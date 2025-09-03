
const B = Int64(1)
const KB = Int64(1024)
const MB = 1024KB
const GB = 1024MB
const TB = 1024GB

const QUEUING = :queuing
const RUNNING = :running
const DONE = :done
const FAILED = :failed
const CANCELLED = :cancelled

const PAST = :past # super set of DONE, FAILED, CANCELLED


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

        @atomic RESOURCE.njob += 1

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
    unsafe_run!(job::Job, current::DateTime=now()) :: UInt8

Jump the queue and run `job` immediately, no matter what other jobs are running or waiting.

Return:
- `OK`: successfully scheduled to run.
- `SKIP`: no thread is available, skip this time.
- `FAIL`: failed to schedule.

Caution: it will not trigger `scheduler_need_action()`.
"""
function unsafe_run!(job::Job, current::DateTime=now()) :: UInt8
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
        return FAIL
    end

    ret = schedule_thread(job)

    if ret == OK
        job.start_time = current
        job.state = RUNNING
        return OK
    elseif ret == SKIP
        return SKIP
    else  # FAIL
        # check status when fail
        if istaskfailed2(job.task)
            if job.state !== CANCELLED
                job.state = FAILED
                @error "A job has failed: $(job.id)" exception=job.task.result
            end
        elseif istaskdone(job.task)
            job.state = DONE
        elseif istaskstarted(job.task)
            job.state = RUNNING
        end
        return FAIL
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
        return job.state
    elseif istaskdone(job.task)
        if job.state !== DONE
            job.state = DONE
        end
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
        return job.state
    end
end


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
            @static if VERSION >= v"1.12-"  # 1.12: t._state is atomic
                @atomic t._state = 0x02  # Base.task_state_failed
            else
                t._state = 0x02  # Base.task_state_failed
            end
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