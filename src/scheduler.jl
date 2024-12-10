const B = 1
const KB = 1024
const MB = 1024KB
const GB = 1024MB
const TB = 1024GB

SCHEDULER_MAX_CPU::Int = nthreads() > 1 ? nthreads()-1 : Sys.CPU_THREADS
SCHEDULER_MAX_MEM::Int = round(Int, Sys.total_memory() * 0.9)
SCHEDULER_UPDATE_SECOND::Float64 = 0.05

JOB_QUEUE_MAX_LENGTH::Int = 10000

const JOB_QUEUE = JobQueue(; max_done = JOB_QUEUE_MAX_LENGTH,  max_cancelled = max_done = JOB_QUEUE_MAX_LENGTH)

SCHEDULER_BACKUP_FILE::String = ""

SCHEDULER_WHILE_LOOP::Bool = true

"Bool. Showing progress meter? Related to progress computation and display. true when wait_queue(show_progress=true)"
PROGRESS_METER::Bool = false

"Bool. Should only be used when PROGRESS_METER == false because both PROGRESS_METER and PROGRESS_WAIT compete SCHEDULER_PROGRESS_ACTION[]. true when wait_queue(show_progress=false)"
PROGRESS_WAIT::Bool = false

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

SLEEP_HANDELED_TIME::Int = 10

"""
    istaskfailed2(t::Task)

Extend `Base.istaskfailed` to fit Pipelines and JobSchedulers packages, which will return a `StackTraceVector` in `t.result`, while Base considered it as `:done`. The function checks the situation and modifies the real task status and other properties.
"""
function istaskfailed2(t::Task)
    if Base.istaskfailed(t)
        return true
    end
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
    submit!(args_of_Job...; kwargs_of_Job...)

Submit the job to queue. 

> `submit!(Job(...))` can be simplified to `submit!(...)`. They are equivalent.

See also [`Job`](@ref), [`@submit`](@ref)
"""
function submit!(job::Job)
    global JOB_QUEUE
    global QUEUING

    # cannot run a task recovered from backup, since task is nothing.
    @boundscheck begin
        if isnothing(job.task)
            if job.state in (RUNNING, QUEUING)
                job.state = CANCELLED
            end
            error("Cannot submit a job recovered from backup! Job ID: $(job.id). Name: $(job.name)")
        end

        # check task state
        if job.state !== QUEUING || istaskstarted(job.task)
            error("Cannot submit running/done/failed/cancelled job! Job ID: $(job.id). Name: $(job.name)")
        end
    end

    current = now()
    # job.state = QUEUING
    if job.submit_time == DateTime(0)
        job.submit_time = current
    else
        # duplicate submission
        error("Cannot re-submit the same job! Job ID: $(job.id). Name: $(job.name)")
    end

    # if recur need to be set
    if job.schedule_time == DateTime(0) && !isempty(job.cron)
        next_time = tonext(job.submit_time, job.cron)
        if isnothing(next_time)
            error("Cannot submit the job: no date and time matching its $(job.cron)")
        else
            job.schedule_time = next_time
        end
    end

    @debug "submit!(job::Job) id=$(job.id) name=$(job.name) lock_queuing"
    lock(JOB_QUEUE.lock_queuing) do 
        if job.schedule_time > current  # run in future
            push!(JOB_QUEUE.future, job)
        elseif job.ncpu == 0
            push!(JOB_QUEUE.queuing_0cpu, job)
        else
            push_queuing!(JOB_QUEUE.queuing, job)
        end

        if PROGRESS_METER
            update_group_state!(job)
        end
    end
    @debug "submit!(job::Job) id=$(job.id) name=$(job.name) lock_queuing ok"
    scheduler_need_action()

    return job
end

function submit!(args...; kwargs...)
    submit!(Job(args...; kwargs...))
end

"""
    unsafe_run!(job::Job, current::DateTime=now()) :: Bool

Jump the queue and run `job` immediately, no matter what other jobs are running or waiting. If successful initiating to run, return `true`, else `false`. 

Caution: it will not trigger `scheduler_need_action()`.
"""
function unsafe_run!(job::Job, current::DateTime=now()) :: Bool
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
        schedule_thread(job)
        job.start_time = current
        job.state = RUNNING
        true
    catch e
        # check status when fail
        if istaskfailed2(job.task)
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
    @debug "cancel!(job::Job) id=$(job.id) name=$(job.name) lock_queuing"
    lock(JOB_QUEUE.lock_queuing) do
    #     @debug "cancel!(job::Job) id=$(job.id) name=$(job.name) lock_running"
    #     lock(JOB_QUEUE.lock_running) do
            unsafe_cancel!(job)
    #     end
    #     @debug "cancel!(job::Job) id=$(job.id) name=$(job.name) lock_running ok"
    end
    @debug "cancel!(job::Job) id=$(job.id) name=$(job.name) lock_queuing ok"
end

"""
    unsafe_cancel!(job::Job, current::DateTime=now())

Caution: it is unsafe and should only be called within lock. Do not call from other module.

Caution: it will not trigger `scheduler_need_action()`.
"""
function unsafe_cancel!(job::Job, current::DateTime=now())
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
    if istaskfailed2(job.task)
        if job.state !== CANCELLED
            job.state = FAILED
            # job.task.result isa Exception, notify errors
            @error "A job has failed: $(job.id)" exception=job.task.result
        end
        # free_thread(job)
        return job.state
    elseif istaskdone(job.task)
        if job.state !== DONE
            job.state = DONE
        end
        # free_thread(job)J
        return job.state
    end

    try
        schedule(job.task, InterruptException(), error=true)
        job.stop_time = current
        job.state = CANCELLED
    catch e
        unsafe_update_state!(job)
        if job.state === RUNNING
            @error "unsafe_cancel!(job): cannot cancel a job." job
        end
        job.state
    finally
        # TODO: what if InterruptException did not stop the job?
        # free_thread(job)
        return job.state
    end
end


### Scheduler main
const SCHEDULER_ACTION = Base.RefValue{Channel{Int}}()  # defined in __init__()
const SCHEDULER_ACTION_LOCK = ReentrantLock()

const SCHEDULER_PROGRESS_ACTION = Base.RefValue{Channel{Int}}()  # defined in __init__()

function scheduler_need_action()
    global SCHEDULER_ACTION
    global SCHEDULER_ACTION_LOCK

    # isready(SCHEDULER_ACTION[]) && return  # isready means already ready for action


    @debug "scheduler_need_action SCHEDULER_ACTION_LOCK"

    # SCHEDULER_ACTION is not thread safe
    lock(SCHEDULER_ACTION_LOCK) do 
        # if !isready(SCHEDULER_ACTION[]) # will take action, no need to repeat
            @time "--------------- scheduler_need_action put" put!(SCHEDULER_ACTION[], 1)
        # end
        if (PROGRESS_METER || PROGRESS_WAIT) && !isready(SCHEDULER_PROGRESS_ACTION[]) 
            put!(SCHEDULER_PROGRESS_ACTION[], 1)
        end
    end
    @debug "scheduler_need_action SCHEDULER_ACTION_LOCK ok"
    nothing
end

function scheduler_reactivation()
    global SCHEDULER_WHILE_LOOP
    global SLEEP_HANDELED_TIME

    while SCHEDULER_WHILE_LOOP
        try
            scheduler_need_action()
            sleep(0.5)
        catch ex
            if isa(ex, InterruptException) && isinteractive()  # if someone sends ctrl + C to sleep, scheduler wont stop in interactive mode
                SLEEP_HANDELED_TIME -= 1
                if SLEEP_HANDELED_TIME < 0
                    set_scheduler_while_loop(false)
                    rethrow(ex)
                else
                    @warn "JobScheduler.scheduler() catched a InterruptException during wait. Max time to catch: $SLEEP_HANDELED_TIME. To stop the scheduler, please use JobSchedulers.set_scheduler_while_loop(false), or send InterruptException $SLEEP_HANDELED_TIME more times." exception=ex
                end
            else
                set_scheduler_while_loop(false)
                throw(ex)
            end
        end
        
    end
end


"""
    scheduler()

The function of running Job's scheduler. It needs to be called by `scheduler_start()`, rather than calling directly.
"""
function scheduler()
    global SCHEDULER_WHILE_LOOP
    global SCHEDULER_ACTION
    global SCHEDULER_ACTION_LOCK
    global SLEEP_HANDELED_TIME

    while SCHEDULER_WHILE_LOOP
        @debug "scheduler() new loop"
        
        try
            # SCHEDULER_ACTION is not thread safe
            @time "--------------- wait scheduler" wait(SCHEDULER_ACTION[])
            lock(SCHEDULER_ACTION_LOCK) do 
                empty!(SCHEDULER_ACTION[].data)
                @atomic SCHEDULER_ACTION[].n_avail_items = 0
                # take!(SCHEDULER_ACTION[])
            end
            
            update_queue!()
        catch ex
            if isa(ex, InterruptException) && isinteractive()  # if someone sends ctrl + C to sleep, scheduler wont stop in interactive mode
                SLEEP_HANDELED_TIME -= 1
                if SLEEP_HANDELED_TIME < 0
                    rethrow(ex)
                else
                    @warn "JobScheduler.scheduler() catched a InterruptException during wait. Max time to catch: $SLEEP_HANDELED_TIME. To stop the scheduler, please use JobSchedulers.set_scheduler_while_loop(false), or send InterruptException $SLEEP_HANDELED_TIME more times." exception=ex
                end
            else
                set_scheduler_while_loop(false)
                throw(ex)
            end
        end
    end
    @debug "scheduler() end"
    nothing
end

function unsafe_update_as_failed!(job::Job, current::DateTime = now())
    job.stop_time = current
    # free_thread(job)
    # @error "A job failed: $(job.id): $(job.name)" # exception=job.task.result
    job.state = FAILED
end
function unsafe_update_as_done!(job::Job, current::DateTime = now())
    job.stop_time = current
    # free_thread(job)
    job.state = DONE
end

"""
    unsafe_update_state!(job::Job)

Update the state of `job` from `job.task` when `job.state === :running`.

If a repeative job is PAST, submit a new job.

Caution: it is unsafe and should only be called within lock.
"""
function unsafe_update_state!(job::Job)
    global RUNNING
    global DONE
    global FAILED
    if job.state === RUNNING
        task_state = job.task.state
        if istaskfailed2(job.task)
            unsafe_update_as_failed!(job)
        elseif task_state === DONE
            unsafe_update_as_done!(job)
        end
    else
        job.state
    end
end

"""
    is_dependency_ok(job::Job)::Bool

Caution: run it within lock only.

Algorithm: Break for loop when found a dep not ok, and delete previous ok deps.

If dep is provided as Int, query Int for job and then replace Int with the job.
"""
function is_dependency_ok(job::Job)
    if length(job.dependency) == 0
        return true
    end
    deps_to_delete = 0
    res = true
    # break for loop when found dep not ok, and delete previous ok deps
    for (i, dep) in enumerate(job.dependency)
        state = dep.first
        if dep.second isa Int
            dep_job = job_query_by_id_no_lock(dep.second)

            if isnothing(dep_job)
                res = false
                break
            end
            job.dependency[i] = state => dep_job
        else
            dep_job = dep.second
        end


        if (state == dep_job.state) ||
        (state == PAST && dep_job.state in (FAILED, CANCELLED, DONE))
            deps_to_delete = i
            continue
        end

        if dep_job.state in (FAILED, CANCELLED)
            # change job state to cancelled
            @warn "Cancel job ($(job.id)) because one of its dependency ($(dep_job.id)) is failed or cancelled."
            job.state = CANCELLED
            res = false
            break
        elseif dep_job.state == DONE
            # change job state to cancelled
            @warn "Cancel job ($(job.id)) because one of its dependency ($(dep_job.id)) is done, but the required state is $(state)."
            job.state = CANCELLED
            res = false
            break
        end

        res = false
        break
    end
    if deps_to_delete > 0
        deleteat!(job.dependency, 1:deps_to_delete)
    end
    return res
end
