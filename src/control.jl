
# TODO atexit(f) to store the job history.
const SCHEDULER_TASK = Base.RefValue{Task}()
const SCHEDULER_REACTIVATION_TASK = Base.RefValue{Task}()

function new_scheduler_task()
    global SCHEDULER_TASK
    SCHEDULER_TASK[] = @task scheduler()
    @static if :sticky in fieldnames(Task)
        # make the scheduler task sticky to threadid == 1
        if !SINGLE_THREAD_MODE[]
            # sticky: disallow task migration which was introduced in 1.7
            @static if VERSION >= v"1.7-"
                SCHEDULER_TASK[].sticky = true
            else
                SCHEDULER_TASK[].sticky = false
            end    
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), SCHEDULER_TASK[], 0)
        end
    end
    SCHEDULER_TASK[]
end
function new_scheduler_reactivation_task()
    global SCHEDULER_REACTIVATION_TASK
    SCHEDULER_REACTIVATION_TASK[] = @task scheduler_reactivation()
    @static if :sticky in fieldnames(Task)
        # make the scheduler task sticky to threadid == 1
        if !SINGLE_THREAD_MODE[]
            # sticky: disallow task migration which was introduced in 1.7
            @static if VERSION >= v"1.7-"
                SCHEDULER_REACTIVATION_TASK[].sticky = true
            else
                SCHEDULER_REACTIVATION_TASK[].sticky = false
            end    
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), SCHEDULER_REACTIVATION_TASK[], 0)
        end
    end
    SCHEDULER_REACTIVATION_TASK[]
end

"""
    scheduler_start()

Start the job scheduler.
"""
function scheduler_start(; verbose=true)
    global SCHEDULER_TASK
    global SCHEDULER_REACTIVATION_TASK

    if !isassigned(SCHEDULER_TASK)
        new_scheduler_task()
    end
    if !isassigned(SCHEDULER_REACTIVATION_TASK)
        new_scheduler_reactivation_task()
    end

    set_scheduler_while_loop(true) # scheduler task won't stop

    for (task, name) in [SCHEDULER_TASK => "Scheduler task", SCHEDULER_REACTIVATION_TASK => "Scheduler reactivation task"]
        if Base.istaskfailed(task[]) || istaskdone(task[])
            verbose && @warn "$name was interrupted or done. Restart."
            task === SCHEDULER_TASK ? new_scheduler_task() : new_scheduler_reactivation_task()
            schedule(task[])
            while !istaskstarted(task[])
                sleep(0.05)
            end
        elseif istaskstarted(task[]) # if done, started is also true
            verbose && @info "$name is running."
        else
            verbose && @info "$name starts."
            schedule(task[])
            while !istaskstarted(task[])
                sleep(0.05)
            end
        end
    end
end

"""
    scheduler_stop()

Stop the job scheduler.
"""
function scheduler_stop(; verbose=true)
    global SCHEDULER_TASK
    global SCHEDULER_REACTIVATION_TASK

    for (task, name) in [SCHEDULER_TASK => "Scheduler task", SCHEDULER_REACTIVATION_TASK => "Scheduler reactivation task"]
        if !isassigned(task)
            verbose && @warn "$name is not running."
        elseif Base.istaskfailed(task[]) || istaskdone(task[])
            verbose && @warn "$name is not running."
        elseif istaskstarted(task[]) # if done, started is also true
            set_scheduler_while_loop(false) # scheduler task stop after the next loop
            scheduler_need_action()
            while !(Base.istaskfailed(task[]) || istaskdone(task[]))
                sleep(0.2)
                scheduler_need_action()
            end
            verbose && @info "$name stops."
        else
            verbose && @warn "$name is not running."
        end
    end
end

"""
    scheduler_status() :: Symbol

Print the settings and status of job scheduler. Return `:not_running` or `:running`.
"""
function scheduler_status(; verbose=true)
    global SCHEDULER_TASK
    global SCHEDULER_REACTIVATION_TASK
    global SCHEDULER_MAX_CPU
    global SCHEDULER_MAX_MEM
    if !isassigned(SCHEDULER_TASK) || !isassigned(SCHEDULER_REACTIVATION_TASK)
        verbose && @warn "Scheduler is not running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM = simplify_memory(SCHEDULER_MAX_MEM) JOB_QUEUE.max_done JOB_QUEUE.max_cancelled
        :not_running
    elseif Base.istaskfailed(SCHEDULER_TASK[]) || istaskdone(SCHEDULER_TASK[]) || Base.istaskfailed(SCHEDULER_REACTIVATION_TASK[]) || istaskdone(SCHEDULER_REACTIVATION_TASK[]) 
        verbose && @info "Scheduler is not running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM = simplify_memory(SCHEDULER_MAX_MEM) JOB_QUEUE.max_done JOB_QUEUE.max_cancelled SCHEDULER_TASK[] SCHEDULER_REACTIVATION_TASK[]
        :not_running
    elseif istaskstarted(SCHEDULER_TASK[]) || istaskstarted(SCHEDULER_REACTIVATION_TASK[])
        verbose && @info "Scheduler is running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM = simplify_memory(SCHEDULER_MAX_MEM) JOB_QUEUE.max_done JOB_QUEUE.max_cancelled SCHEDULER_TASK[] SCHEDULER_REACTIVATION_TASK[]
        :running
    else
        verbose && @info "Scheduler is not running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM = simplify_memory(SCHEDULER_MAX_MEM) JOB_QUEUE.max_done JOB_QUEUE.max_cancelled SCHEDULER_TASK[] SCHEDULER_REACTIVATION_TASK[]
        :not_running
    end
end

"""
    set_scheduler_update_second(s::AbstractFloat = 0.6)

Set the update interval of scheduler.
"""
function set_scheduler_update_second(s::AbstractFloat = 0.6)
    @warn "set_scheduler_update_second(s) is no longer required. The Job's scheduler updates when needed automatically." maxlog=1
    s <= 0.001 && error("schedular update interval cannot be less than 0.001.")
    global SCHEDULER_UPDATE_SECOND = Float64(s)
end
set_scheduler_update_second(s) = set_scheduler_update_second(convert(Float64, s))


function default_ncpu()
    global TIDS
    if isempty(TIDS)
        Sys.CPU_THREADS
    else
        length(TIDS)
    end
end

"""
    set_scheduler_max_cpu(ncpu::Int = default_ncpu())
    set_scheduler_max_cpu(percent::Float64)

Set the maximum CPU (thread) the scheduler can use. If starting Julia with multiple threads in the default thread pool, the maximum CPU is the number of tids in the default thread pool not equal to 1.

# Example
    set_scheduler_max_cpu()     # use all available CPUs
    set_scheduler_max_cpu(4)    # use 4 CPUs
    set_scheduler_max_cpu(0.5)  # use 50% of CPUs
"""
function set_scheduler_max_cpu(ncpu::Int = default_ncpu())
    global TIDS
    ncpu < 1 && error("number of CPU cannot be less than 1.")
    
    if SINGLE_THREAD_MODE[]
        if ncpu > Sys.CPU_THREADS
            @warn "Assigning number of CPU > total CPU."
        end
    else
        if ncpu > length(TIDS)
            @warn "Assigning number of CPU > default_ncpu() is not allowed. Set to `default_ncpu()`. Thread tid==1 is reserved for schedulers, and JobSchedulers use the rest threads of default thread pool. To use more threads, try to start Julia with sufficient threads. Help: https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads"
            ncpu = length(TIDS)
        elseif ncpu < 1
            error("Assigning number of CPU < 1 is not allowed in multi-threaded Julia.")
        end
    end

    global SCHEDULER_MAX_CPU = ncpu
end
function set_scheduler_max_cpu(percent::Float64)
    if 0.0 < percent <= 1.0
        ncpu = round(Int, Sys.CPU_THREADS * percent)
        if ncpu > default_ncpu()
            @warn "Assigning number of CPU > default_ncpu() is not allowed. Set to `default_ncpu()`. Thread tid==1 is reserved for schedulers, and JobSchedulers use the rest threads of default thread pool. To use more threads, try to start Julia with sufficient threads. Help: https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads"
            ncpu = default_ncpu()
        end
        set_scheduler_max_cpu(ncpu)
    else
        @error "Percent::Float64 should be between 0 and 1. Are you looking for set_scheduler_max_cpu(ncpu::Int) ?"
    end
end

default_mem() = round(Int64, Sys.total_memory() * 0.8)
"""
    set_scheduler_max_mem(mem::Integer = default_mem())
    set_scheduler_max_mem(percent::AbstractFloat)

Set the maximum RAM the scheduler can use.

# Example
    set_scheduler_max_mem()             # use 80% of total memory

    set_scheduler_max_mem(4GB)          # use 4GB memory
    set_scheduler_max_mem(4096MB)
    set_scheduler_max_mem(4194304KB)
    set_scheduler_max_mem(4294967296B)

    set_scheduler_max_mem(0.5)          # use 50% of total memory
"""
function set_scheduler_max_mem(mem::Integer = default_mem())
    mem < 1 && error("number of memory cannot be less than 1.")
    if mem > Sys.total_memory() * 0.9 + 1
        @warn "Assigning memory > 90% of total memory."
    end
    global SCHEDULER_MAX_MEM = mem
end
function set_scheduler_max_mem(percent::AbstractFloat)
    if 0.0 < percent < 1.0
        set_scheduler_max_mem(round(Int64, Sys.total_memory() * percent))
    else
        @error "Percent::Float64 should be between 0 and 1. Are you looking for set_scheduler_max_mem(mem::Int) ?"
    end
end

"""
    set_scheduler_max_job(max_done::Int = 10000, max_cancelled::Int = max_done)

Set the number of finished jobs. If number of jobs exceed 1.5*NUMBER, old jobs will be delete.
"""
function set_scheduler_max_job(max_done::Int = 10000, max_cancelled::Int = max_done)
    if max_done < 10 || max_cancelled < 10
        @error "Cannot set number of finished jobs < 10"
    else
        JOB_QUEUE.max_done = max_done
        JOB_QUEUE.max_cancelled = max_cancelled
    end
end

"""
    set_scheduler(;
        max_cpu::Real = JobSchedulers.SCHEDULER_MAX_CPU,
        max_mem::Real = JobSchedulers.SCHEDULER_MAX_MEM,
        max_job::Int = JobSchedulers.JOB_QUEUE.max_done,
        max_cancelled_job::Int = JobSchedulers.JOB_QUEUE.max_cancelled_job
    )

- `max_job`: the number of jobs done. If number of jobs exceed 1.5*NUMBER, old jobs will be delete.
- `max_cancelled_job`: the number of cancelled jobs. If number of jobs exceed 1.5*NUMBER, old jobs will be delete.

See details:
[`set_scheduler_max_cpu`](@ref), 
[`set_scheduler_max_mem`](@ref), 
[`set_scheduler_max_job`](@ref)
"""
function set_scheduler(;
    max_cpu::Real = JobSchedulers.SCHEDULER_MAX_CPU,
    max_mem::Real = JobSchedulers.SCHEDULER_MAX_MEM,
    max_job::Int = JobSchedulers.JOB_QUEUE.max_done,
    max_cancelled_job::Int = JobSchedulers.JOB_QUEUE.max_cancelled_job,
    update_second = JobSchedulers.SCHEDULER_UPDATE_SECOND
)
    set_scheduler_max_cpu(max_cpu)
    set_scheduler_max_mem(max_mem)
    set_scheduler_max_job(max_job, max_cancelled_job)
    set_scheduler_update_second(update_second)

    scheduler_status()
end

"""
    wait_queue(;show_progress::Bool = false, exit_num_jobs::Int = 0)

Wait for all jobs in `queue()` become finished.

- `show_progress = true`, job progress will show.

- `exit_num_jobs::Int`: exit when `queue()` has less than `Int` number of jobs. It is useful to ignore some jobs that are always running or recurring.

See also: [`queue_progress`](@ref).
"""
function wait_queue(;show_progress::Bool = false, exit_num_jobs::Int = 0)
    global PROGRESS_WAIT
    global PROGRESS_METER
    if PROGRESS_WAIT || PROGRESS_METER
        error("Another wait_queue(...) is active. It is not allowed to run more than one wait_queue()")
    end
    if show_progress
        progress_task = @task queue_progress(exit_num_jobs = exit_num_jobs)
        @static if :sticky in fieldnames(Task)
            # make the scheduler task sticky to threadid == 1
            if !SINGLE_THREAD_MODE[]
                # sticky: disallow task migration which was introduced in 1.7
                @static if VERSION >= v"1.7-"
                    progress_task.sticky = true
                else
                    progress_task.sticky = false
                end    
                ccall(:jl_set_task_tid, Cvoid, (Any, Cint), progress_task, 0)
            end
        end
        schedule(progress_task)
        wait(progress_task)
    else
        PROGRESS_WAIT = true
        while true
            (@show are_remaining_jobs_more_than(exit_num_jobs)) || break
            if scheduler_status(verbose=false) !== RUNNING
                @error "Scheduler was not running. Jump out from wait_queue()"
                break
            end
            take!(SCHEDULER_PROGRESS_ACTION[])  # wait until further action
        end
        PROGRESS_WAIT = false
    end
    nothing
end

"""
    wait(j::Job)
    wait(js::Vector{Job})

Wait for the job(s) to be finished.
"""
function Base.wait(j::Job)
    wait(j.task)
end

function Base.wait(js::Vector{Job})
    for j in js
        wait(j.task)
    end
end