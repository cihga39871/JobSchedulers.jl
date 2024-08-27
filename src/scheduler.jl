const B = 1
const KB = 1024
const MB = 1024KB
const GB = 1024MB
const TB = 1024GB

SCHEDULER_MAX_CPU::Int = nthreads() > 1 ? nthreads()-1 : Sys.CPU_THREADS
SCHEDULER_MAX_MEM::Int = round(Int, Sys.total_memory() * 0.9)
SCHEDULER_UPDATE_SECOND::Float64 = 0.05

const JOB_QUEUE = Vector{Job}()
const JOB_QUEUE_LOCK = ReentrantLock()
const JOB_QUEUE_OK = Vector{Job}()  # jobs not queuing
JOB_QUEUE_MAX_LENGTH::Int = 10000

SCHEDULER_BACKUP_FILE::String = ""

SCHEDULER_WHILE_LOOP::Bool = true

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
    @debug "               release_lock() start  $JOB_QUEUE_LOCK"
    unlock(JOB_QUEUE_LOCK)
    @debug "               release_lock() end    $JOB_QUEUE_LOCK"
end

SLEEP_HANDELED_TIME::Int = 10
function wait_for_lock()
    global JOB_QUEUE_LOCK
    global SLEEP_HANDELED_TIME
    @debug "               wait_for_lock() start $JOB_QUEUE_LOCK"
    while !trylock(JOB_QUEUE_LOCK)
        try
            sleep(0)
        catch ex
            SLEEP_HANDELED_TIME -= 1
            if SLEEP_HANDELED_TIME < 0
                rethrow(ex)
            else
                @warn "JobScheduler: sleep() failed but handelled. Max time to handle: $SLEEP_HANDELED_TIME" exception=ex
            end
        end
    end
    @debug "               wait_for_lock() end   $JOB_QUEUE_LOCK"
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

Submit the job. If `job.submit_time == 0000-01-01T00:00:00 (default)`, it will change to the time of submission.

> `submit!(Job(...))` can be simplified to `submit!(...)`. They are equivalent.

See also [`Job`](@ref)
"""
function submit!(job::Job)
    global JOB_QUEUE
    global QUEUING

    if scheduler_status(verbose=false) != :running
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
        # job.state = QUEUING
        if job.submit_time == DateTime(0)
            job.submit_time = now()
        else
            # duplicate submission
            error("Cannot re-submit the same job! Job ID: $(job.id). Name: $(job.name)")
        end
        
        # job recur: set schedule_time
        if job.schedule_time == DateTime(0) && date_based_on(job.cron) !== :none
            next_time = tonext(now(), job.cron)
            if isnothing(next_time)
                error("Cannot submit the job: no date and time matching its $(job.cron)")
            else
                job.schedule_time = next_time
            end
        end

        push!(JOB_QUEUE, job)
    finally
        release_lock()
        scheduler_need_action()
    end

    return job
end

function submit!(args...; kwargs...)
    submit!(Job(args...; kwargs...))
end

"""
    unsafe_run!(job::Job) :: Bool

Jump the queue and run `job` immediately, no matter what other jobs are running or waiting. If successful initiating to run, return `true`, else `false`. 

Caution: it will not trigger `scheduler_need_action()`.
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
    @debug "cancel!(job::Job) id=$(job.id) name=$(job.name)"
    wait_for_lock()
    res = try
        unsafe_cancel!(job)
    catch e
        rethrow(e)
    finally
        release_lock()
        scheduler_need_action()
    end
    res
end

"""
    unsafe_cancel!(job::Job)

Caution: it is unsafe and should only be called within lock. Do not call from other module.

Caution: it will not trigger `scheduler_need_action()`.
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
    if istaskfailed2(job.task)
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
        # TODO: what if InterruptException did not stop the job?
        free_thread(job)
        return job.state
    end
end


### Scheduler main
const SCHEDULER_ACTION = Base.RefValue{Channel{Int}}()  # defined in __init__()
const SCHEDULER_ACTION_LOCK = ReentrantLock()
RUNNING_MAX_IDX::Int = 0

function scheduler_need_action()
    global SCHEDULER_ACTION
    global SCHEDULER_ACTION_LOCK

    isready(SCHEDULER_ACTION[]) && return  # isready means already ready for action

    lock(SCHEDULER_ACTION_LOCK) do 
        if !isready(SCHEDULER_ACTION[]) # will take action, no need to repeat
            put!(SCHEDULER_ACTION[], 1)
        end
    end
    nothing
end

function scheduler_reactivation()
    global SCHEDULER_UPDATE_SECOND
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
            wait(SCHEDULER_ACTION[])
            take!(SCHEDULER_ACTION[])
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

function update_queue!()
    global SCHEDULER_MAX_CPU
    global JOB_QUEUE
    global RUNNING
    global RUNNING_MAX_IDX
    # step 0: cancel jobs if run time > wall time
    wait_for_lock()
    try
        for i in 1:RUNNING_MAX_IDX
            job = JOB_QUEUE[i]
            if job.state === RUNNING
                wall_time = job.start_time + job.wall_time
                if wall_time < now()
                    unsafe_cancel!(job)  # cannot call cancel! because lock is on
                end
            end

            # step 1: update running jobs' states
            unsafe_update_state!(job)
        end
    finally
        release_lock()
    end

    # step 2: migrate finished jobs to JOB_QUEUE_OK from JOB_QUEUE
    # and submit finished recurring jobs
    migrate_finished_jobs!()

    # step 3: compute current CPU/MEM usage
    # step 4: sort by (ncpu == 0) + state (RUNNING) + priority
    # step 5: run queuing jobs
    run_queuing_jobs()
end

function unsafe_update_as_failed!(job::Job)
    job.stop_time = now()
    free_thread(job)
    @error "A job failed: $(job.id): $(job.name)" # exception=job.task.result
    job.state = FAILED
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
            job.stop_time = now()
            free_thread(job)
            job.state = DONE
        end
    else
        job.state
    end
end

# only be used in `migrate_finished_jobs!`
const finished_indices = Vector{Int}()

function migrate_finished_jobs!()
    global JOB_QUEUE
    global JOB_QUEUE_OK
    global JOB_QUEUE_MAX_LENGTH
    global finished_indices
    global RUNNING_MAX_IDX
    @debug "migrate_finished_jobs!()"
    wait_for_lock()
    try
        empty!(finished_indices)
        for i in 1:RUNNING_MAX_IDX
            job = JOB_QUEUE[i]
            if job.state === QUEUING || job.state === RUNNING
                continue
            else
                push!(finished_indices, i)
            end
        end

        finished_jobs = @view(JOB_QUEUE[finished_indices])

        for j in finished_jobs
            # only append named or failed jobs
            if !isempty(j.name) || j.state === FAILED
                push!(JOB_QUEUE_OK, j)
            end
            
            # if recurring job is DONE, submit new
            if j.state === DONE
                next_job = next_recur_job(j)
                if isnothing(next_job)
                    continue
                end
                push!(JOB_QUEUE, next_job)
            end
        end

        deleteat!(JOB_QUEUE, finished_indices)

        # delete JOB_QUEUE_OK if too many
        n_delete = length(JOB_QUEUE_OK) - JOB_QUEUE_MAX_LENGTH
        n_delete > 0 && deleteat!(JOB_QUEUE_OK, 1:n_delete)
    finally
        release_lock()
    end
    return
end

function compute_priority_rank(job::Job)
    job.priority + 
    ifelse(job.ncpu == 0 && job.schedule_time < now(), -100000, 0) +   # run this job immediately
    ifelse(job.state == RUNNING, -10000, 0)
end

function run_queuing_jobs()
    global JOB_QUEUE
    global QUEUING
    global RUNNING_MAX_IDX
    @debug "run_queuing_jobs"
    wait_for_lock()
    try
        # current usage
        used_ncpu = 0.0
        used_mem = 0
        for i in 1:min(RUNNING_MAX_IDX, length(JOB_QUEUE))  # RUNNING_MAX_IDX might be less because of migrate_finished_jobs!
            job = JOB_QUEUE[i]
            if job.state === RUNNING
                used_ncpu += job.ncpu
                used_mem += job.mem
            end
        end
        ncpu_available = SCHEDULER_MAX_CPU - used_ncpu
        mem_available = SCHEDULER_MAX_MEM - used_mem

        # update queue priority
        # from now, RUNNING_MAX_IDX cannot be used in `for i in 1:RUNNING_MAX_IDX` and need to update when running a job
        sort!(JOB_QUEUE, by=compute_priority_rank)
        RUNNING_MAX_IDX = 0

        njob = length(JOB_QUEUE)
        i = 1
        while i <= njob
            job = JOB_QUEUE[i]
            if job.ncpu != 0
                break
            end
            # job.ncpu == 0
            if job.state === RUNNING
                RUNNING_MAX_IDX = i
            elseif job.state === QUEUING && job.schedule_time < now() && job.mem <= mem_available && is_dependency_ok(job)
                unsafe_run!(job)
                # ncpu_available -= job.ncpu
                mem_available  -= job.mem
                RUNNING_MAX_IDX = i
            end
            i += 1
        end

        # job.ncpu > 0
        while i <= njob
            ncpu_available < 0.999 && break  # ncpu::Float64, can be inaccurate
            mem_available  < 0 && break

            job = JOB_QUEUE[i]
            if job.state === RUNNING
                RUNNING_MAX_IDX = i
            elseif job.state === QUEUING && job.schedule_time < now() && job.ncpu <= ncpu_available + 0.001 && job.mem <= mem_available && is_dependency_ok(job)  # # ncpu::Float64, can be inaccurate
                unsafe_run!(job)
                ncpu_available -= job.ncpu
                mem_available  -= job.mem
                RUNNING_MAX_IDX = i
            end
            i += 1
        end

    finally
        release_lock()
    end
    nothing
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
