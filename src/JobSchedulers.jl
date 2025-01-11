
module JobSchedulers

using Revise

using Reexport
using Base.Threads
@reexport using Dates
using JSON
using PrettyTables
using JLD2
using Pipelines
using DataStructures

using PrecompileTools

include("bit.jl")
include("job_recur.jl")
export Cron

include("jobs.jl")
export Job, result, solve_optimized_ncpu,
isqueuing, isrunning, isdone, iscancelled, isfailed, ispast



include("thread_utils.jl")

include("JobQueue.jl")


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
set_scheduler,
set_scheduler_max_cpu,
set_scheduler_max_mem,
set_scheduler_max_job,
default_ncpu,
default_mem,
wait_queue


include("backup.jl")
export set_scheduler_backup, backup

include("compat_pipelines.jl")
export close_in_future


include("progress_computing.jl")
include("progress_view.jl")
export queue_progress

include("macro.jl")
export @submit

function __init__()
    # Fixing precompilation hangs due to open tasks or IO
    # https://docs.julialang.org/en/v1/devdocs/precompile_hang/
    ccall(:jl_generating_output, Cint, ()) == 1 && return nothing

    # initiating THREAD_POOL
    c = Channel{Int}(nthreads() - 1)
    THREAD_POOL[] = c
    foreach(i -> put!(c, i), 2:nthreads())  # the thread 1 is reserved for JobScheduler, when nthreads > 2

    # initiating scheduler action Channel.
    SCHEDULER_ACTION[] = Channel{Int}(1)
    SCHEDULER_PROGRESS_ACTION[] = Channel{Int}(1)

    # initiating JOB ID
    JOB_ID[] = (now().instant.periods.value - 63749462400000) << 16

    # SCHEDULER_MAX_CPU must be the same as THREAD_POOL (if nthreads > 1), or the scheduler will stop.
    global SCHEDULER_MAX_CPU = default_ncpu()
    global SCHEDULER_MAX_MEM = round(Int, Sys.total_memory() * 0.9)
    global SCHEDULER_UPDATE_SECOND = ifelse(nthreads() > 1, 0.01, 0.05)
    scheduler_start(verbose=false)
end

if Base.VERSION >= v"1.8"
    include("precompile_workload.jl")
end

end
