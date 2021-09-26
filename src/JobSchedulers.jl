__precompile__(false)  # Task cannot be serialized

module JobSchedulers

using Dates, DataFrames, JSON
using JLD2
using Pipelines

include("jobs.jl")
export Job, result

include("scheduler.jl")
export B, KB, MB, GB, TB
export submit!, cancel!
export QUEUING, RUNNING, DONE, FAILED, CANCELLED

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
export close_in_future

end
