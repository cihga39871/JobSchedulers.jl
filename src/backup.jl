
"""
    set_scheduler_backup(
        filepath::AbstractString = "";
        migrate::Bool = false,
        delete_old::Bool = false,
        recover_settings::Bool = true,
        recover_queue::Bool = true
    )

Set the backup file of job scheduler.

If `filepath` was set to `""`, stop backup at exit.

If `filepath` was set to an existing file, `recover_settings` or `recover_queue` from `filepath` immediately.

If `filepath` was set to a new file, the backup file will be created at exit.

If `migrate=true` and the old `JobSchedulers.SCHEDULER_BACKUP_FILE` exists, the old backup file will be recovered before recovering from `filepath`.

"""
function set_scheduler_backup(
    filepath::AbstractString = "";
    migrate::Bool = false,
    delete_old::Bool = false,
    recover_settings::Bool = true,
    recover_queue::Bool = true
)
    global SCHEDULER_BACKUP_FILE
    if filepath == ""
        @info "Stop scheduler backup."
        delete_old && isfile(SCHEDULER_BACKUP_FILE) && rm(SCHEDULER_BACKUP_FILE, force=true)
        SCHEDULER_BACKUP_FILE = ""
        return SCHEDULER_BACKUP_FILE
    end

    filepath = abspath(filepath)

    if isdir(filepath) || isdirpath(filepath)
        @error "The file path is a directory." filepath
        return SCHEDULER_BACKUP_FILE
    end

    try
        mkpath(dirname(filepath))
    catch
        @error "Cannot set backup file: cannot create directory."
        return SCHEDULER_BACKUP_FILE
    end

    if migrate
        if isfile(SCHEDULER_BACKUP_FILE) # old one
            recover_backup(SCHEDULER_BACKUP_FILE; recover_settings = recover_settings, recover_queue = recover_queue)
        end
    end

    if isfile(filepath)
        recover_backup(filepath; recover_settings = recover_settings, recover_queue = recover_queue)
    end

    delete_old && isfile(SCHEDULER_BACKUP_FILE) && rm(SCHEDULER_BACKUP_FILE, force=true)
    SCHEDULER_BACKUP_FILE = filepath
    return SCHEDULER_BACKUP_FILE
end

"""
    backup()

Manually backup job scheduler settings and queues. The function is automatically triggered at exit.
"""
function backup()
    global SCHEDULER_BACKUP_FILE
    global SCHEDULER_MAX_CPU
    global SCHEDULER_MAX_MEM
    global JOB_QUEUE

    # no backup when file is not exist
    SCHEDULER_BACKUP_FILE == "" && return

    scheduler_max_cpu = SCHEDULER_MAX_CPU
    scheduler_max_mem = SCHEDULER_MAX_MEM

    # update running: update state, cancel jobs reaching wall time, moving finished from running to others, add next recur of successfully finished job to future queue, and compute current usage.
    update_running!(now())

    q_cancelled = Vector{Job}()
    q_done = Vector{Job}()
    q_failed = Vector{Job}()
    lock(JOB_QUEUE.lock_queuing) do 
        for jobs in values(JOB_QUEUE.queuing)
            for j in jobs
                backup_job!(q_cancelled, q_done, q_failed, j)
            end
        end
        for j in JOB_QUEUE.queuing_0cpu
            backup_job!(q_cancelled, q_done, q_failed, j)
        end
        for j in JOB_QUEUE.future
            backup_job!(q_cancelled, q_done, q_failed, j)
        end
    end

    lock(JOB_QUEUE.lock_running) do
        for j in JOB_QUEUE.running
            backup_job!(q_cancelled, q_done, q_failed, j)
        end
    end

    lock(JOB_QUEUE.lock_past) do
        for j in JOB_QUEUE.done
            backup_job!(q_done, j)
        end
        for j in JOB_QUEUE.failed
            backup_job!(q_failed, j)
        end
        for j in JOB_QUEUE.cancelled
            backup_job!(q_cancelled, j)
        end
    end

    max_done = JOB_QUEUE.max_done
    max_cancelled = JOB_QUEUE.max_cancelled

    # clean old file
    rm(SCHEDULER_BACKUP_FILE, force=true)
    @save SCHEDULER_BACKUP_FILE scheduler_max_cpu scheduler_max_mem max_done max_cancelled q_cancelled q_done q_failed
    @info Pipelines.timestamp() * "Scheduler backup done: $SCHEDULER_BACKUP_FILE"

end

atexit(backup)

function backup_job!(q_cancelled::Vector{Job}, q_done::Vector{Job}, q_failed::Vector{Job}, j::Job)
    job = deepcopy(j)
    job.task = nothing
    job._func = nothing
    if job.state === DONE
        push!(q_done, job)
    elseif job.state === FAILED
        push!(q_failed, job)
    else
        job.state = CANCELLED
        push!(q_cancelled, job)
    end
end
function backup_job!(q::Vector{Job}, j::Job)
    job = deepcopy(j)
    job.task = nothing
    job._func = nothing
    push!(q, job)
end

"""
    recover_backup(filepath::AbstractString; recover_settings = true, recover_queue = true)

Recover job scheduler settings or job queues from file.
"""
function recover_backup(filepath::AbstractString; recover_settings::Bool = true, recover_queue::Bool = true)
    global SCHEDULER_BACKUP_FILE
    global SCHEDULER_MAX_CPU
    global SCHEDULER_MAX_MEM
    global JOB_QUEUE

    if !(recover_settings || recover_queue)
        return
    end

    if !is_valid_backup_file(filepath)
        @error "Cannot recover backup from an invalid file: $(filepath)"
        return
    end

    data = JLD2.load(filepath)
    
    # validate data
    for key in ["scheduler_max_cpu", "scheduler_max_mem", "max_done", "max_cancelled", "q_cancelled", "q_done", "q_failed"]
        if !haskey(data, key)
            @error "Cannot recover backup: JobSchedulers version incompatible: $filepath"
            return
        end
    end

    if recover_settings
        @info "Settings recovered from the backup file ($filepath)"
        set_scheduler_max_cpu(data["scheduler_max_cpu"])
        set_scheduler_max_mem(data["scheduler_max_mem"])
        set_scheduler_max_job(data["max_done"], data["max_cancelled"])
    end

    if recover_queue
        @debug "recover_backup($filepath; recover_settings = $recover_settings, recover_queue = $recover_queue)"

        # get the current jobs, to avoid copying existing jobs
        current_job_ids = Set{Int}()
        lock(JOB_QUEUE.lock_queuing) do 
            for jobs in values(JOB_QUEUE.queuing)
                for job in jobs
                    push!(current_job_ids, job.id)
                end
            end
            for job in JOB_QUEUE.queuing_0cpu
                push!(current_job_ids, job.id)
            end
            for job in JOB_QUEUE.future
                push!(current_job_ids, job.id)
            end
        end
        lock(JOB_QUEUE.lock_running) do 
            for job in JOB_QUEUE.running
                push!(current_job_ids, job.id)
            end
        end
        lock(JOB_QUEUE.lock_past) do 
            for job in JOB_QUEUE.done
                push!(current_job_ids, job.id)
            end
            for job in JOB_QUEUE.failed
                push!(current_job_ids, job.id)
            end
            for job in JOB_QUEUE.cancelled
                push!(current_job_ids, job.id)
            end
        end


        # starting copying from data
        filter!(data["q_cancelled"]) do job
            !(job.id in current_job_ids)
        end
        filter!(data["q_done"]) do job
            !(job.id in current_job_ids)
        end
        filter!(data["q_failed"]) do job
            !(job.id in current_job_ids)
        end
        lock(JOB_QUEUE.lock_past) do 
            pushfirst!(JOB_QUEUE.cancelled, data["q_cancelled"]...)
            pushfirst!(JOB_QUEUE.done, data["q_done"]...)
            pushfirst!(JOB_QUEUE.failed, data["q_failed"]...)
        end
    end

    nothing
end

function is_valid_backup_file(filepath::AbstractString)
    REQUIRED_FILE_HEADER = "HDF5-based Julia Data Format, version "
    io = open(filepath, "r")
    headermsg = String(read!(io, Vector{UInt8}(undef, length(REQUIRED_FILE_HEADER))))
    headermsg == REQUIRED_FILE_HEADER
end
