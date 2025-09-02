
SCHEDULER_MAX_CPU::Int = -1              # set in __init__
SCHEDULER_MAX_MEM::Int64 = Int64(-1)     # set in __init__
SCHEDULER_UPDATE_SECOND::Float64 = 0.05  # set in __init__

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

SLEEP_HANDELED_TIME::Int = 10

const SCHEDULER_ACTION = Base.RefValue{Channel{Int}}()  # defined in __init__()
const SCHEDULER_PROGRESS_ACTION = Base.RefValue{Channel{Int}}()  # defined in __init__()

function scheduler_need_action()
    global SCHEDULER_ACTION

    isready(SCHEDULER_ACTION[]) && return  # isready means already ready for action

    if !isready(SCHEDULER_ACTION[]) # will take action, no need to repeat
        put!(SCHEDULER_ACTION[], 1)
    end

    # 
    # if (PROGRESS_METER || PROGRESS_WAIT) && !isready(SCHEDULER_PROGRESS_ACTION[]) 
    #     put!(SCHEDULER_PROGRESS_ACTION[], 1)
    # end

    nothing
end

function scheduler_reactivation()
    global SCHEDULER_WHILE_LOOP
    global SLEEP_HANDELED_TIME

    while SCHEDULER_WHILE_LOOP
        try
            scheduler_need_action()
            sleep(0.1)
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
    global SLEEP_HANDELED_TIME

    while SCHEDULER_WHILE_LOOP
        @debug "scheduler() new loop"
        try
            wait(SCHEDULER_ACTION[])
            take!(SCHEDULER_ACTION[])

            update_queue!()  # put!(SCHEDULER_PROGRESS_ACTION[], 1) is in this function.
        catch ex
            if isa(ex, InterruptException) && isinteractive()  # if someone sends ctrl + C to sleep, scheduler wont stop in interactive mode
                SLEEP_HANDELED_TIME -= 1
                if SLEEP_HANDELED_TIME < 0
                    rethrow(ex)
                else
                    @warn "JobScheduler.scheduler() catched a InterruptException during wait. Max time to catch: $SLEEP_HANDELED_TIME. To stop the scheduler, please use JobSchedulers.set_scheduler_while_loop(false), or send InterruptException $SLEEP_HANDELED_TIME more times." exception=ex
                end
            else
                @error "JobScheduler.scheduler() stopped because of an internal error." exception=(ex, catch_backtrace())  # display the error. throw(ex) will not display the error.
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
    job.state = FAILED
end
function unsafe_update_as_done!(job::Job, current::DateTime = now())
    job.stop_time = current
    job.state = DONE
end

"""
    unsafe_update_state!(job::Job)

Update the state of `job` from `job.task` when `job.state === :running`.

If a repeative job is PAST, submit a new job.

Caution: it is unsafe and should only be called within lock.
"""
function unsafe_update_state!(job::Job)
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

Algorithm: Break while loop when found dep not ok, and change `job._dep_check_id` to the current id.

If dep is provided as Integer, query Integer for job and then replace Integer with the job.
"""
function is_dependency_ok(job::Job)
    if length(job.dependency) < job._dep_check_id
        return true
    end
    # break while loop when found dep not ok, and change _dep_check_id to the current id

    # _dep_check_id = 1 when init Job
    n = length(job.dependency)
    while job._dep_check_id <= n
        dep = job.dependency[job._dep_check_id]
        state = dep.first
        if dep.second isa Integer
            dep_job = job_query_by_id_no_lock(dep.second)

            if isnothing(dep_job)
                # considered finished because done job with no name will not be stored.
                job._dep_check_id += 1
                continue
            end
            job.dependency[job._dep_check_id] = state => dep_job
        else
            dep_job = dep.second
        end

        dep_state = dep_job.state  # avoid changing during the following calls, if changing from RUNNING to DONE, might throw error in `elseif dep_state == DONE`

        if (state === dep_state) ||
        (state === PAST && dep_state in (FAILED, CANCELLED, DONE))
            job._dep_check_id += 1
            continue
        end

        if dep_state in (FAILED, CANCELLED)
            # change job state to cancelled
            @warn "Cancel job ($(job.id)) because one of its dependency ($(dep_job.id)) is $(dep_job.state)."
            job.state = CANCELLED
            break
        elseif dep_state == DONE
            # change job state to cancelled
            @warn "Cancel job ($(job.id)) because one of its dependency ($(dep_job.id)) is done, but the required state is $(state)."
            job.state = CANCELLED
            break
        end

        break
    end

    return n < job._dep_check_id
end
