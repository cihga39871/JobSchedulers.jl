const B = 1
const KB = 1024
const MB = 1024KB
const GB = 1024MB
const TB = 1024GB

SCHEDULER_MAX_CPU = Sys.CPU_THREADS
SCHEDULER_MAX_MEM = round(Int, Sys.total_memory() * 0.9)
SCHEDULER_UPDATE_SECOND = 5.0

const JOB_QUEUE = Vector{Job}()
JOB_QUEUE_LOCK = false
const JOB_QUEUE_OK = Vector{Job}()  # jobs not queueing
JOB_QUEUE_MAX_LENGTH = 10000

SCHEDULER_BACKUP_FILE = ""

const QUEUEING = :queueing
const RUNNING = :running
const DONE = :done
const FAILED = :failed
const CANCELLED = :cancelled

function force_free_lock()
    global JOB_QUEUE_LOCK = false
end

function wait_for_job_queue()
    global JOB_QUEUE_LOCK
    while JOB_QUEUE_LOCK
        sleep(0.05)
    end
    while JOB_QUEUE_LOCK
        sleep(0.05)
    end
end

"""
    submit!(job::Job)

Submit the job. If `job.create_time == 0000-01-01T00:00:00 (default)`, it will change to the time of submission.
"""
function submit!(job::Job)
    global JOB_QUEUE
    global JOB_QUEUE_LOCK
    global QUEUEING

    if scheduler_status(verbose=false) == :not_running
        @error "Scheduler is not running. Please start scheduler by using scheduler_start()"
        return job
    end

    # check task state
    if istaskstarted(job.task) || job.state !== QUEUEING
        @error "Cannot submit running/done/failed/canceled job!" job
        return job
    end

    # job.state = QUEUEING
    if job.create_time == DateTime(0)
        job.create_time = now()
    end
    wait_for_job_queue()
    @debug "submit start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
        push!(JOB_QUEUE, job)
    JOB_QUEUE_LOCK = false
    @debug "submit end" JOB_QUEUE_LOCK

    return job
end

"""
    unsafe_run!(job::Job) :: Bool

Jump the queue and run `job` immediately, no matter what other jobs are running or waiting. If successful initiating to run, return `true`, else `false`.
"""
function unsafe_run!(job::Job) :: Bool
    global RUNNING
    global FAILED
    global DONE
    global CANCELLED
    if istaskfailed(job.task)
        if job.state !== CANCELLED
            job.state = FAILED
        end
        false
    elseif istaskdone(job.task)
        job.state = DONE
        false
    elseif istaskstarted(job.task)
        job.state = RUNNING
        false
    else
        schedule(job.task)
        job.start_time = now()
        job.state = RUNNING
        true
    end
end

"""
    cancel!(job::Job)

Cancel `job`, stop queueing or running.
"""
function cancel!(job::Job)
    global JOB_QUEUE_LOCK
    wait_for_job_queue()
    @debug "cancel start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
    try
        res = unsafe_cancel!(job)
        JOB_QUEUE_LOCK = false
        @debug "cancel end" JOB_QUEUE_LOCK
        return res
    catch e
        rethrow(e)
        JOB_QUEUE_LOCK = false
        @debug "cancel end" JOB_QUEUE_LOCK
    end
end

"""
    unsafe_cancel!(job::Job)

Caution: it is unsafe and should only be called within lock. Do not call from other module.
"""
function unsafe_cancel!(job::Job)
    global CANCELLED
    global RUNNING
    try
        schedule(job.task, InterruptException(), error=true)
        job.stop_time = now()
        job.state = CANCELLED
    catch e
        unsafe_update_state!(job)
        if job.state === RUNNING
            @error "unsafe_cancel!(job): cannot cancel a job." job
        end
        job.state
    end
end


### Scheduler main

function scheduler()
    global SCHEDULER_UPDATE_SECOND
    while true
        update_queue!()
        sleep(SCHEDULER_UPDATE_SECOND)
    end
end

function update_queue!()
    global SCHEDULER_MAX_CPU
    # step 0: cancel jobs if run time > wall time
    cancel_jobs_reaching_wall_time!()
    # step 1: update running jobs' states
    update_state!()
    # step 2: migrate finished jobs to JOB_QUEUE_OK from JOB_QUEUE
    migrate_finished_jobs!()
    # step 3: compute current CPU/MEM usage
    used_ncpu, used_mem = current_usage()
    ncpu_available = SCHEDULER_MAX_CPU - used_ncpu
    mem_available = SCHEDULER_MAX_MEM - used_mem
    # step 4: sort by priority
    update_queue_priority!()
    # step 5: run queueing jobs
    run_queueing_jobs(ncpu_available, mem_available)
end

function cancel_jobs_reaching_wall_time!()
    global JOB_QUEUE
    global RUNNING
    global JOB_QUEUE_LOCK
    wait_for_job_queue()
    @debug "cancel_jobs_reaching_wall_time start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
        for job in JOB_QUEUE
            if job.state === RUNNING
                elapsed_time =  now() - job.start_time
                remaining_time = Millisecond(job.wall_time) - elapsed_time
                if remaining_time.value < 0
                    unsafe_cancel!(job)  # cannot call cancel! because JOB_QUEUE_LOCK is on
                end
            end
        end
    JOB_QUEUE_LOCK = false
    @debug "cancel_jobs_reaching_wall_time end" JOB_QUEUE_LOCK
end

"""
    unsafe_update_state!(job::Job)

Update the state of `job` from `job.task` when `job.state === :running`.

Caution: it is unsafe and should only be called within lock.
"""
function unsafe_update_state!(job::Job)
    global RUNNING
    global DONE
    global FAILED
    if job.state === RUNNING
        task_state = job.task.state
        if task_state === DONE
            job.stop_time = now()
            job.state = DONE
        elseif task_state === FAILED
            job.stop_time = now()
            job.state = FAILED
        end
    else
        job.state
    end
end

"""
    update_state!()

Update the state of each `job` in JOB_QUEUE from `job.task` when `job.state === :running`.
"""
function update_state!()
    global JOB_QUEUE
    global JOB_QUEUE_LOCK
    wait_for_job_queue()
    @debug "update_state start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
        foreach(unsafe_update_state!, JOB_QUEUE)
    JOB_QUEUE_LOCK = false
    @debug "update_state end" JOB_QUEUE_LOCK
    return
end

function migrate_finished_jobs!()
    global JOB_QUEUE
    global JOB_QUEUE_LOCK
    global JOB_QUEUE_OK
    global JOB_QUEUE_MAX_LENGTH
    wait_for_job_queue()
    @debug "migrate_finished_jobs start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
        finished_indices = map(j -> !(j.state === QUEUEING || j.state === RUNNING), JOB_QUEUE)
        append!(JOB_QUEUE_OK, JOB_QUEUE[finished_indices])
        deleteat!(JOB_QUEUE, finished_indices)
    JOB_QUEUE_LOCK = false
    @debug "migrate_finished_jobs end" JOB_QUEUE_LOCK

    # delete JOB_QUEUE_OK if too many
    n_delete = length(JOB_QUEUE_OK) - JOB_QUEUE_MAX_LENGTH
    n_delete > 0 && deleteat!(JOB_QUEUE_OK, 1:n_delete)
    return
end

function current_usage()
    global JOB_QUEUE
    global RUNNING
    global JOB_QUEUE_LOCK
    cpu_usage = 0
    mem_usage = 0
    wait_for_job_queue()
    @debug "current_cpu_usage start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
        for job in JOB_QUEUE
            if job.state === RUNNING
                cpu_usage += job.ncpu
                mem_usage += job.mem
            end
        end
    JOB_QUEUE_LOCK = false
    @debug "current_cpu_usage end" JOB_QUEUE_LOCK
    return cpu_usage, mem_usage
end

function update_queue_priority!()
    global JOB_QUEUE
    global JOB_QUEUE_LOCK
    wait_for_job_queue()
    @debug "update_queue_priority start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
        sort!(JOB_QUEUE, by=get_priority)
    JOB_QUEUE_LOCK = false
    @debug "update_queue_priority end" JOB_QUEUE_LOCK
    return
end
get_priority(job::Job) = job.priority


function run_queueing_jobs(ncpu_available::Int, mem_available::Int)
    global JOB_QUEUE
    global QUEUEING
    global JOB_QUEUE_LOCK
    wait_for_job_queue()
    @debug "run_queueing_jobs start" JOB_QUEUE_LOCK
    JOB_QUEUE_LOCK = true
        for job in JOB_QUEUE
            ncpu_available < 1 && break
            mem_available  < 1 && break
            if job.state === QUEUEING && job.schedule_time < now() && job.ncpu <= ncpu_available && job.mem <= mem_available
                if unsafe_run!(job)
                    ncpu_available -= job.ncpu
                    mem_available  -= job.mem
                end
            end
        end
    JOB_QUEUE_LOCK = false
    @debug "run_queueing_jobs end" JOB_QUEUE_LOCK
    return ncpu_available, mem_available
end
