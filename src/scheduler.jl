const B = 1
const KB = 1024
const MB = 1024KB
const GB = 1024MB
const TB = 1024GB

SCHEDULER_MAX_CPU = nthreads() > 1 ? nthreads()-1 : Sys.CPU_THREADS
SCHEDULER_MAX_MEM = round(Int, Sys.total_memory() * 0.9)
SCHEDULER_UPDATE_SECOND = 0.6

const JOB_QUEUE = Vector{Job}()
JOB_QUEUE_LOCK = SpinLock()
const JOB_QUEUE_OK = Vector{Job}()  # jobs not queuing
JOB_QUEUE_MAX_LENGTH = 10000

SCHEDULER_BACKUP_FILE = ""

SCHEDULER_WHILE_LOOP = true
"""
    set_scheduler_while_loop(b::Bool)

if set to false, the scheduler will stop.
"""
function set_scheduler_while_loop(b::Bool)
    global SCHEDULER_WHILE_LOOP = b
end

const QUEUING = :queuing
const RUNNING = :running
const DONE = :done
const FAILED = :failed
const CANCELLED = :cancelled

const PAST = :past # super set of DONE, FAILED, CANCELLED

function release_lock()
    global JOB_QUEUE_LOCK
    @debug "               release_lock() start"
    unlock(JOB_QUEUE_LOCK)
    @debug "               release_lock() end"
end

SLEEP_HANDELED_TIME = 10
function wait_for_lock()
    global JOB_QUEUE_LOCK
    global SLEEP_HANDELED_TIME
    @debug "wait_for_lock() start"
    while !trylock(JOB_QUEUE_LOCK)
        try
            sleep(0.05)
        catch ex
            SLEEP_HANDELED_TIME -= 1
            if SLEEP_HANDELED_TIME < 0
                rethrow(ex)
            else
                @warn "JobScheduler: sleep() failed but handelled. Max time to handle: $SLEEP_HANDELED_TIME" exception=ex
            end
        end
    end
    @debug "wait_for_lock() end"
end

"""
    istaskfailed(t::Task)

Extend `Base.istaskfailed` to fit Pipelines and JobSchedulers packages, which will return a `StackTraceVector` in `t.result`, while Base considered it as `:done`. The function checks the situation and modifies the real task status and other properties.
"""
function Base.istaskfailed(t::Task)
    @static if hasfield(Task, :_state)
        if t._state === 0x02 # Base.task_state_failed
            return true
        end
    elseif hasfield(Task, :state)
        # TODO: this field name should be deprecated in 2.0
        if t.state === :failed
            return true
        end
    end
    if getproperty(t, :result) isa Pipelines.StackTraceVector
        # it is failed, but task is showing done, so we make it failed manually.
        @static if hasfield(Task, :_state)
            t._state = 0x02 # Base.task_state_failed
        end
        @static if hasfield(Task, :_isexception)
            t._isexception = true
        end
        @static if hasfield(Task, :state)
            # TODO: this field name should be deprecated in 2.0
            t.state = :failed
        end
        @static if hasfield(Task, :exception)
            # TODO: this field name should be deprecated in 2.0
            t.exception = t.result
        end
        @static if hasfield(Task, :backtrace)
            # TODO: this field name should be deprecated in 2.0
            t.backtrace = t.result[end][2]
        end
        return true
    end
    return false
end

"""
    submit!(job::Job)

Submit the job. If `job.create_time == 0000-01-01T00:00:00 (default)`, it will change to the time of submission.
"""
function submit!(job::Job)
    global JOB_QUEUE
    global QUEUING

    if scheduler_status(verbose=false) == :not_running
        @error "Scheduler is not running. Please start scheduler by using scheduler_start()"
        return job
    end

    # cannot run a task recovered from backup, since task is nothing.
    if isnothing(job.task)
        if job.state in (RUNNING, QUEUING)
            job.state = CANCELLED
        end
        @error "Cannot submit a job recovered from backup!" job
        return job
    end

    # check task state
    if istaskstarted(job.task) || job.state !== QUEUING
        @error "Cannot submit running/done/failed/canceled job!" job
        return job
    end

    @debug "submit!(job::Job) id=$(job.id) name=$(job.name)"
    wait_for_lock()
    try
        # check duplicate submission (queuing)
        for existing_job in JOB_QUEUE
            if existing_job === job
                error("Cannot re-submit the same job! Job ID: $(job.id)")
            end
        end

        # job.state = QUEUING
        if job.create_time == DateTime(0)
            job.create_time = now()
        end

        push!(JOB_QUEUE, job)
    catch e
        rethrow(e)
    finally
        release_lock()
    end

    return job
end

"""
    unsafe_run!(job::Job) :: Bool

Jump the queue and run `job` immediately, no matter what other jobs are running or waiting. If successful initiating to run, return `true`, else `false`.
"""
function unsafe_run!(job::Job) :: Bool
    global QUEUING
    global RUNNING
    global FAILED
    global DONE
    global CANCELLED

    # cannot run a backup task
    if isnothing(job.task)
        @error "Cannot run a job recovered from backup!" job
        if job.state in (RUNNING, QUEUING)
            job.state = CANCELLED
        end
        return false
    end

    try
        # set_non_sticky!(job)
        # schedule(job.task)
        schedule_thread(job)
        job.start_time = now()
        job.state = RUNNING
        true
    catch e
        # check status when fail
        if Pipelines.istaskfailed(job.task)
            if job.state !== CANCELLED
                job.state = FAILED
                @error "A job has failed: $(job.id)" exception=job.task.result
            end
            false
        elseif istaskdone(job.task)
            job.state = DONE
            false
        elseif istaskstarted(job.task)
            job.state = RUNNING
            false
        else
            rethrow(e)
            false
        end
    end
end

"""
    cancel!(job::Job)

Cancel `job`, stop queuing or running.
"""
function cancel!(job::Job)
    @debug "cancel!(job::Job) id=$(job.id) name=$(job.name)"
    wait_for_lock()
    res = try
        unsafe_cancel!(job)
    catch e
        rethrow(e)
    finally
        release_lock()
    end
    res
end

"""
    unsafe_cancel!(job::Job)

Caution: it is unsafe and should only be called within lock. Do not call from other module.
"""
function unsafe_cancel!(job::Job)
    global CANCELLED
    global RUNNING

    # cannot cancel a backup task (can never be run)
    if isnothing(job.task)
        if job.state in (RUNNING, QUEUING)
            job.state = CANCELLED
        end
        return job.state
    end

    # no need to cancel finished ones
    if Pipelines.istaskfailed(job.task)
        if job.state !== CANCELLED
            job.state = FAILED
            # job.task.result isa Exception, notify errors
            @error "A job has failed: $(job.id)" exception=job.task.result
        end
        free_thread(job)
        return job.state
    elseif istaskdone(job.task)
        if job.state !== DONE
            job.state = DONE
        end
        free_thread(job)
        return job.state
    end

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
    finally
        free_thread(job)
        return job.state
    end
end


### Scheduler main

function scheduler()
    global SCHEDULER_UPDATE_SECOND
    global SCHEDULER_WHILE_LOOP
    while SCHEDULER_WHILE_LOOP
        @debug "scheduler() new loop"
        update_queue!()
        try # if someone sends ctrl + C to sleep, scheduler wont stop.
            sleep(SCHEDULER_UPDATE_SECOND)
        catch ex
            @warn "JobScheduler: sleep() failed but handelled." exception=ex
        end
    end
    @debug "scheduler() end"
    nothing
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
    # step 5: run queuing jobs
    run_queuing_jobs(ncpu_available, mem_available)
end

function cancel_jobs_reaching_wall_time!()
    global JOB_QUEUE
    global RUNNING
    @debug "cancel_jobs_reaching_wall_time!()"
    wait_for_lock()
    try
        for job in JOB_QUEUE
            if job.state === RUNNING
                elapsed_time =  now() - job.start_time
                remaining_time = Millisecond(job.wall_time) - elapsed_time
                if remaining_time.value < 0
                    unsafe_cancel!(job)  # cannot call cancel! because lock is on
                end
            end
        end
    catch e
        rethrow(e)
    finally
        release_lock()
    end
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
            free_thread(job)
            job.state = DONE
        elseif task_state === FAILED
            job.stop_time = now()
            free_thread(job)
            @error "A job has failed: $(job.id): $(job.name)" exception=job.task.result
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
    @debug "update_state!()"
    wait_for_lock()
    try
        foreach(unsafe_update_state!, JOB_QUEUE)
    catch e
        rethrow(e)
    finally
        release_lock()
    end
    return
end

function migrate_finished_jobs!()
    global JOB_QUEUE
    global JOB_QUEUE_OK
    global JOB_QUEUE_MAX_LENGTH
    @debug "migrate_finished_jobs!()"
    wait_for_lock()
    try
        finished_indices = map(j -> !(j.state === QUEUING || j.state === RUNNING), JOB_QUEUE)
        append!(JOB_QUEUE_OK, JOB_QUEUE[finished_indices])
        deleteat!(JOB_QUEUE, finished_indices)
    catch e
        rethrow(e)
    finally
        release_lock()
    end

    # delete JOB_QUEUE_OK if too many
    n_delete = length(JOB_QUEUE_OK) - JOB_QUEUE_MAX_LENGTH
    n_delete > 0 && deleteat!(JOB_QUEUE_OK, 1:n_delete)
    return
end

function current_usage()
    global JOB_QUEUE
    global RUNNING
    cpu_usage = 0
    mem_usage = 0
    @debug "current_usage()"
    wait_for_lock()
    try
        for job in JOB_QUEUE
            if job.state === RUNNING
                cpu_usage += job.ncpu
                mem_usage += job.mem
            end
        end
    catch e
        rethrow(e)
    finally
        release_lock()
    end
    return cpu_usage, mem_usage
end

function update_queue_priority!()
    global JOB_QUEUE
    @debug "update_queue_priority!()"
    wait_for_lock()
    try
        sort!(JOB_QUEUE, by=get_priority)
    catch e
        rethrow(e)
    finally
        release_lock()
    end
    return
end
get_priority(job::Job) = job.priority


function run_queuing_jobs(ncpu_available::Int, mem_available::Int)
    global JOB_QUEUE
    global QUEUING
    @debug "run_queuing_jobs($ncpu_available::Int, $mem_available::Int)"
    wait_for_lock()
    try
        for job in JOB_QUEUE
            ncpu_available < 1 && break
            mem_available  < 1 && break
            if job.state === QUEUING && job.schedule_time < now() && job.ncpu <= ncpu_available && job.mem <= mem_available && is_dependency_ok(job)
                if unsafe_run!(job)
                    ncpu_available -= job.ncpu
                    mem_available  -= job.mem
                end
            end
        end
    catch e
        rethrow(e)
    finally
        release_lock()
    end
    return ncpu_available, mem_available
end

"""
Caution: run it within lock only.
"""
function is_dependency_ok(job::Job)
    for dep in job.dependency
        state = dep.first
        dep_id = dep.second
        dep_job = job_query_by_id_no_lock(dep_id)

        if isnothing(dep_job)
            return false
        end

        state == dep_job.state && continue

        state == PAST &&
            dep_job.state in (FAILED, CANCELLED, DONE) && continue

        if dep_job.state in (FAILED, CANCELLED)
            # change job state to cancelled
            @warn "Cancel job ($(job.id)) because one of its dependency ($(dep_job.id)) is failed or cancelled."
            job.state = CANCELLED
            return false
        elseif dep_job.state == DONE
            # change job state to cancelled
            @warn "Cancel job ($(job.id)) because one of its dependency ($(dep_job.id)) is done, but the required state is $(state)."
            job.state = CANCELLED
            return false
        end

        return false
    end
    return true
end
