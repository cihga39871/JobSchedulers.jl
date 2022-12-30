
# TODO atexit(f) to store the job history.


function new_scheduler_task()
    global SCHEDULER_TASK
    SCHEDULER_TASK = @task scheduler()
    @static if :sticky in fieldnames(Task)
        # make the scheduler task sticky to threadid == 1
        if nthreads() > 1
            # sticky: disallow task migration which was introduced in 1.7
            @static if VERSION >= v"1.7"
                SCHEDULER_TASK.sticky = true
            else
                SCHEDULER_TASK.sticky = false
            end    
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), SCHEDULER_TASK, 0)
        end
    end
    SCHEDULER_TASK
end

"""
    scheduler_start()

Start the job scheduler.
"""
function scheduler_start(; verbose=true)
    global SCHEDULER_TASK

    if !isdefined(@__MODULE__, :SCHEDULER_TASK)
        new_scheduler_task()
    end

    set_scheduler_while_loop(true) # scheduler task won't stop

    if istaskfailed(SCHEDULER_TASK) || istaskdone(SCHEDULER_TASK)
        verbose && @warn "Scheduler was interrupted or done. Restart."
        new_scheduler_task()
        schedule(SCHEDULER_TASK)
        while !istaskstarted(SCHEDULER_TASK)
    		sleep(0.05)
    	end
    elseif istaskstarted(SCHEDULER_TASK) # if done, started is also true
        verbose && @warn "Scheduler is running."
    else
        verbose && @info "Scheduler starts."
        schedule(SCHEDULER_TASK)
        while !istaskstarted(SCHEDULER_TASK)
    		sleep(0.05)
    	end
    end
end

"""
    scheduler_stop()

Stop the job scheduler.
"""
function scheduler_stop(; verbose=true)
    global SCHEDULER_TASK

    if !isdefined(@__MODULE__, :SCHEDULER_TASK)
        verbose && @warn "Scheduler is not running."
    elseif istaskfailed(SCHEDULER_TASK) || istaskdone(SCHEDULER_TASK)
        verbose && @warn "Scheduler is not running."
    elseif istaskstarted(SCHEDULER_TASK) # if done, started is also true
        set_scheduler_while_loop(false) # scheduler task stop after the next loop
        while !(istaskfailed(SCHEDULER_TASK) || istaskdone(SCHEDULER_TASK))
            sleep(0.2)
        end
        verbose && @info "Scheduler stops."
    else
        verbose && @warn "Scheduler is not running."
    end
end

"""
    scheduler_status() :: Symbol

Print the settings and status of job scheduler. Return `:not_running` or `:running`.
"""
function scheduler_status(; verbose=true)
    global SCHEDULER_TASK
    global SCHEDULER_MAX_CPU
    global SCHEDULER_MAX_MEM
    global SCHEDULER_UPDATE_SECOND
    global JOB_QUEUE_MAX_LENGTH
    global SCHEDULER_TASK
    if !isdefined(@__MODULE__, :SCHEDULER_TASK)
        verbose && @warn "Scheduler is not running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM SCHEDULER_UPDATE_SECOND JOB_QUEUE_MAX_LENGTH
        :not_running
    elseif istaskfailed(SCHEDULER_TASK) || istaskdone(SCHEDULER_TASK)
        verbose && @info "Scheduler is not running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM SCHEDULER_UPDATE_SECOND JOB_QUEUE_MAX_LENGTH SCHEDULER_TASK
        :not_running
    elseif istaskstarted(SCHEDULER_TASK)
        verbose && @info "Scheduler is running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM SCHEDULER_UPDATE_SECOND JOB_QUEUE_MAX_LENGTH SCHEDULER_TASK
        :running
    else
        verbose && @info "Scheduler is not running." SCHEDULER_MAX_CPU SCHEDULER_MAX_MEM SCHEDULER_UPDATE_SECOND JOB_QUEUE_MAX_LENGTH SCHEDULER_TASK
        :not_running
    end
end

"""
    set_scheduler_update_second(s::Float64 = 0.6)

Set the update interval of scheduler.
"""
function set_scheduler_update_second(s::Float64 = 0.6)
    s <= 0.001 && error("schedular update interval cannot be less than 0.001.")
    global SCHEDULER_UPDATE_SECOND = s
end
set_scheduler_update_second(s) = set_scheduler_update_second(convert(Float64, s))


default_ncpu() = ifelse(nthreads() > 1, nthreads()-1, Sys.CPU_THREADS)

"""
    set_scheduler_max_cpu(ncpu::Int = default_ncpu())
    set_scheduler_max_cpu(percent::Float64)

Set the maximum CPU (thread) the scheduler can use. If starting Julia with multi-threads, the maximum CPU is `nthreads() - 1`.

# Example
    set_scheduler_max_cpu()     # use all available CPUs
    set_scheduler_max_cpu(4)    # use 4 CPUs
    set_scheduler_max_cpu(0.5)  # use 50% of CPUs
"""
function set_scheduler_max_cpu(ncpu::Int = default_ncpu())
    ncpu < 1 && error("number of CPU cannot be less than 1.")
    if ncpu > Sys.CPU_THREADS
        @warn "Assigning number of CPU > total CPU."
    end
    # nthreads == 1 will not triger schedule at different jobs.
    if nthreads() > 1
        if ncpu > nthreads()-1
            error("Assigning number of CPU > total threads available - 1. Thread one is reserved for schedulers. Try to start Julia with sufficient threads. Help: https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads")
        elseif ncpu < 2
            error("Assigning number of CPU < 2 is not allowed in multi-threaded Julia. Thread one is reserved for schedulers.")
        end
    end
    global SCHEDULER_MAX_CPU = ncpu
end
function set_scheduler_max_cpu(percent::Float64)
    if 0.0 < percent <= 1.0
        ncpu = round(Int, Sys.CPU_THREADS * percent)
        if ncpu > default_ncpu()
            @warn "Assigning number of CPU > default_ncpu() is not allowed. Set to default_ncpu(). Thread one is reserved for schedulers if Threads.nthreads() > 1. To use more threads, try to start Julia with sufficient threads. Help: https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads"
            ncpu = default_ncpu()
        end
        set_scheduler_max_cpu(ncpu)
    else
        @error "Percent::Float64 should be between 0 and 1. Are you looking for set_scheduler_max_cpu(ncpu::Int) ?"
    end
end

default_mem() = round(Int, Sys.total_memory() * 0.8)
"""
    set_scheduler_max_mem(mem::Int = default_mem())
    set_scheduler_max_mem(percent::Float64)

Set the maximum RAM the scheduler can use.

# Example
    set_scheduler_max_mem()             # use 80% of total memory

    set_scheduler_max_mem(4GB)          # use 4GB memory
    set_scheduler_max_mem(4096MB)
    set_scheduler_max_mem(4194304KB)
    set_scheduler_max_mem(4294967296B)

    set_scheduler_max_mem(0.5)          # use 50% of total memory
"""
function set_scheduler_max_mem(mem::Int = default_mem())
    mem < 1 && error("number of memory cannot be less than 1.")
    if mem > Sys.total_memory() * 0.9
        @warn "Assigning memory > 90% of total memory."
    end
    global SCHEDULER_MAX_MEM = mem
end
function set_scheduler_max_mem(percent::Float64)
    if 0.0 < percent < 1.0
        set_scheduler_max_mem(round(Int, Sys.total_memory() * percent))
    else
        @error "Percent::Float64 should be between 0 and 1. Are you looking for set_scheduler_max_mem(mem::Int) ?"
    end
end

"""
    set_scheduler_max_job(n_finished_jobs::Int = 10000)

Set the number of finished jobs.
"""
function set_scheduler_max_job(n_finished_jobs::Int = 10000)
    if n_finished_jobs < 10
        @error "Cannot set number of finished jobs < 10"
    else
        global JOB_QUEUE_MAX_LENGTH = n_finished_jobs
    end
end

"""
    set_scheduler(;
        max_cpu::Union{Int,Float64} = JobSchedulers.SCHEDULER_MAX_CPU,
        max_mem::Union{Int,Float64} = JobSchedulers.SCHEDULER_MAX_MEM,
        max_job::Int = JobSchedulers.JOB_QUEUE_MAX_LENGTH,
        update_second = JobSchedulers.SCHEDULER_UPDATE_SECOND
    )

See details:
[`set_scheduler_max_cpu`](@ref), 
[`set_scheduler_max_mem`](@ref), 
[`set_scheduler_max_job`](@ref), 
[`set_scheduler_update_second`](@ref) 
"""
function set_scheduler(;
    max_cpu::Union{Int,Float64} = SCHEDULER_MAX_CPU,
    max_mem::Union{Int,Float64} = SCHEDULER_MAX_MEM,
    max_job::Int = JOB_QUEUE_MAX_LENGTH,
    update_second = SCHEDULER_UPDATE_SECOND
)
    set_scheduler_max_cpu(max_cpu)
    set_scheduler_max_mem(max_mem)
    set_scheduler_max_job(max_job)
    set_scheduler_update_second(update_second)

    scheduler_status()
end

"""
    wait_queue(;show_progress = false)

Wait for all jobs in `queue()` become finished.

- `show_progress = true`, job progress will show.

See also: [`queue_progress`](@ref).
"""
function wait_queue(;show_progress::Bool = false)
    if show_progress
        queue_progress()
    else
        while length(JOB_QUEUE) > 0 && scheduler_status(verbose=false) === RUNNING
            sleep(SCHEDULER_UPDATE_SECOND)
        end
        if scheduler_status(verbose=false) != RUNNING
            @error "Scheduler was not running. Jump out from wait_queue()"
        end
    end
    nothing
end