
# TODO atexit(f) to store the job history.


SCHEDULER_TASK = @task scheduler()


function new_scheduler_task()
    global SCHEDULER_TASK
    SCHEDULER_TASK = @task scheduler()
end

"""
    scheduler_start()

Start the job scheduler.
"""
function scheduler_start(; verbose=true)
    global SCHEDULER_TASK

    if istaskfailed(SCHEDULER_TASK) || istaskdone(SCHEDULER_TASK)
        verbose && @warn "Scheduler was interrupted or done. Restart."
        new_scheduler_task()
        schedule(SCHEDULER_TASK)
        while !istaskstarted(SCHEDULER_TASK)
    		sleep(0.2)
    	end
    elseif istaskstarted(SCHEDULER_TASK) # if done, started is also true
        verbose && @warn "Scheduler is running."
    else
        verbose && @info "Scheduler starts."
        schedule(SCHEDULER_TASK)
        while !istaskstarted(SCHEDULER_TASK)
    		sleep(0.2)
    	end
    end
end

"""
    scheduler_stop()

Stop the job scheduler.
"""
function scheduler_stop(; verbose=true)
    global SCHEDULER_TASK
    if istaskfailed(SCHEDULER_TASK) || istaskdone(SCHEDULER_TASK)
        verbose && @warn "Scheduler is not running."
    elseif istaskstarted(SCHEDULER_TASK) # if done, started is also true
        wait_for_lock()
            schedule(SCHEDULER_TASK, InterruptException; error=true)
        release_lock()
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
    if istaskfailed(SCHEDULER_TASK) || istaskdone(SCHEDULER_TASK)
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

"""
    set_scheduler_max_cpu(ncpu::Int = nthreads()>1 ? nthreads()-1 : Sys.CPU_THREADS)
    set_scheduler_max_cpu(percent::Float64)

Set the maximum CPU (thread) the scheduler can use. If starting Julia with multi-threads, the maximum CPU is `nthreads() - 1`.

# Example
    set_scheduler_max_cpu()     # use all available CPUs
    set_scheduler_max_cpu(4)    # use 4 CPUs
    set_scheduler_max_cpu(0.5)  # use 50% of CPUs
"""
function set_scheduler_max_cpu(ncpu::Int = nthreads() > 1 ? nthreads()-1 : Sys.CPU_THREADS)
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
        if ncpu > nthreads() - 1
            @warn "Assigning number of CPU > total threads available - 1 is not allowed. Set to total threads available - 1. Thread one is reserved for schedulers. To use more threads, try to start Julia with sufficient threads. Help: https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads"
            ncpu = nthreads() - 1
        end
        set_scheduler_max_cpu(ncpu)
    else
        @error "Percent::Float64 should be between 0 and 1. Are you looking for set_scheduler_max_cpu(ncpu::Int) ?"
    end
end

"""
    set_scheduler_max_mem(mem::Int = round(Int, Sys.total_memory() * 0.8))
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
function set_scheduler_max_mem(mem::Int = round(Int, Sys.total_memory() * 0.8))
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
