
module JobSchedulers

using Base.Threads
using Dates, DataFrames, JSON
using JLD2
using Pipelines
using OrderedCollections

include("jobs.jl")
export Job, result

include("thread_utils.jl")


include("scheduler.jl")
export B, KB, MB, GB, TB
export submit!, cancel!
export QUEUING, RUNNING, DONE, FAILED, CANCELLED, PAST

include("pretty_print.jl")
export queue, all_queue, json_queue

include("query.jl")
export job_query_by_id, job_query

include("control.jl")
export scheduler_start, scheduler_stop, scheduler_status
export set_scheduler_update_second,
set_scheduler_max_cpu,
set_scheduler_max_mem,
set_scheduler_max_job

include("backup.jl")
export set_scheduler_backup, backup

include("compat_pipelines.jl")
export close_in_future, @Job

local SCHEDULER_TASK


function __init__()
    # initiating THREAD_POOL
    c = Channel{Int}(nthreads() - 1)
    THREAD_POOL[] = c
    foreach(i -> put!(c, i), 2:nthreads())  # the thread 1 is reserved for JobScheduler, when nthreads > 2

    # SCHEDULER_MAX_CPU must be the same as THREAD_POOL (if nthreads > 1), or the scheduler will stop.
    global SCHEDULER_MAX_CPU = nthreads() > 1 ? nthreads()-1 : Sys.CPU_THREADS
    global SCHEDULER_MAX_MEM = round(Int, Sys.total_memory() * 0.9)
end

end
