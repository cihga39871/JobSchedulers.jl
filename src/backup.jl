
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
            recover_backup(SCHEDULER_BACKUP_FILE; recover_settings = recover_settings, recover_queue = recover_settings)
        end
    end

    if isfile(filepath)
        recover_backup(filepath; recover_settings = recover_settings, recover_queue = recover_settings)
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
    global SCHEDULER_UPDATE_SECOND
    global JOB_QUEUE_MAX_LENGTH
    global JOB_QUEUE
    global JOB_QUEUE_OK
    global QUEUING
    global RUNNING
    global CANCELLED

    # no backup when file is not exist
    SCHEDULER_BACKUP_FILE == "" && return

    scheduler_max_cpu = SCHEDULER_MAX_CPU
    scheduler_max_mem = SCHEDULER_MAX_MEM
    scheduler_update_second = SCHEDULER_UPDATE_SECOND
    job_queue_max_length = JOB_QUEUE_MAX_LENGTH

    @debug "backup()"
    wait_for_lock()
    try
        # update state of jobs for the last time
        foreach(unsafe_update_state!, JOB_QUEUE)

        # job queue: set to cancelled
        job_queue = deepcopy(JOB_QUEUE)
        for job in job_queue
            job.task = nothing
            if job.state in (QUEUING, RUNNING)
                job.state = CANCELLED
            end
        end

        job_queue_ok = deepcopy(JOB_QUEUE_OK)
        for job in job_queue_ok
            job.task = nothing
        end
        append!(job_queue_ok, job_queue)
        # clean old file
        rm(SCHEDULER_BACKUP_FILE, force=true)
        @save SCHEDULER_BACKUP_FILE scheduler_max_cpu scheduler_max_mem scheduler_update_second job_queue_max_length job_queue_ok
        @info "Scheduler backup: $SCHEDULER_BACKUP_FILE"
    finally
        release_lock()
    end
end

atexit(backup)

"""
    recover_backup(filepath::AbstractString; recover_settings = true, recover_queue = true)

Recover job scheduler settings or job queues from file.
"""
function recover_backup(filepath::AbstractString; recover_settings::Bool = true, recover_queue::Bool = true)
    global SCHEDULER_BACKUP_FILE
    global SCHEDULER_MAX_CPU
    global SCHEDULER_MAX_MEM
    global SCHEDULER_UPDATE_SECOND
    global JOB_QUEUE_MAX_LENGTH
    global JOB_QUEUE
    global JOB_QUEUE_OK

    if !(recover_settings || recover_queue)
        return
    end

    if !is_valid_backup_file(filepath)
        @error "Cannot recover backup from an invalid file: $(filepath)"
        return
    end

    @load filepath scheduler_max_cpu scheduler_max_mem scheduler_update_second job_queue_max_length job_queue_ok

    if recover_settings
        @info "Settings recovered from the backup file ($filepath)"
        set_scheduler_max_cpu(scheduler_max_cpu)
        set_scheduler_max_mem(scheduler_max_mem)
        set_scheduler_update_second(scheduler_update_second)
        set_scheduler_max_job(job_queue_max_length)
    end

    if recover_queue
        @debug "recover_backup($filepath; recover_settings = $recover_settings, recover_queue = $recover_queue)"
        wait_for_lock()
            current_jobs = Dict{Int64, Vector{Job}}()
            append_jobs_dict!(current_jobs, JOB_QUEUE)
            append_jobs_dict!(current_jobs, JOB_QUEUE_OK)

            job_indices_to_copy = Int[]

            for (ind, job) in enumerate(job_queue_ok)
                if !has_job_in(current_jobs, job)
                    push!(job_indices_to_copy, ind)
                end
            end
            @info "$(length(job_indices_to_copy)) jobs recovered from the backup file ($filepath)."
            pushfirst!(JOB_QUEUE_OK, view(job_queue_ok, job_indices_to_copy)...)
        release_lock()
    end

    nothing
end

function append_jobs_dict!(jobs_dict::Dict{Int64, Vector{Job}}, job_queue::Vector{Job})
    for job in job_queue
        job_vec = get(jobs_dict, job.id, nothing)
        if isnothing(job_vec)  # no key, create
            jobs_dict[job.id] = [job]
        elseif has_job_in(job_vec, job)  # has same job, skip
            continue
        else  # push
            push!(job_vec, job)
        end
    end
end

function is_same_job(a::Job, b::Job)
    a.id == b.id &&
    a.schedule_time == b.schedule_time &&
    a.create_time == b.create_time &&
    a.start_time == b.start_time &&
    a.stop_time == b.stop_time &&
    a.name == b.name &&
    a.user == b.user &&
    a.ncpu == b.ncpu &&
    a.mem == b.mem &&
    a.wall_time == b.wall_time &&
    a.priority == b.priority
end

function has_job_in(vec::Vector{Job}, job::Job)
    for j in vec
        if is_same_job(j, job)
            return true
        end
    end
    false
end

function has_job_in(jobs_dict::Dict{Int64, Vector{Job}}, job)
    job_vec = get(jobs_dict, job.id, nothing)
    if isnothing(job_vec)  # no key
        false
    elseif has_job_in(job_vec, job)  # has same job
        true
    else
        false
    end
end

function is_valid_backup_file(filepath::AbstractString)
    REQUIRED_FILE_HEADER = "HDF5-based Julia Data Format, version "
    io = open(filepath, "r")
    headermsg = String(read!(io, Vector{UInt8}(undef, length(REQUIRED_FILE_HEADER))))
    headermsg == REQUIRED_FILE_HEADER
end
