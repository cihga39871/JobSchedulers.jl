# JobSchedulers.jl

*A Julia-based job scheduler and workload manager inspired by Slurm and PBS.*

## Package Features

- Job and task scheduler.
- Local workload manager.
- Support CPU, memory, run time management.
- Support running a job at specific time, or a period after creating (schedule).
- Support deferring a job until specific jobs reach specific states (dependency).
- Support automatic backup and reload.

## Future development

- Support command-line scheduler by using DaemonMode.jl.
- Use Documenter.jl for documentation.

## Installation

JobSchedulers.jl can be installed using the Julia package manager. From the Julia REPL, type ] to enter the Pkg REPL mode and run

```julia
pkg> add JobSchedulers
```

To use the package, type

```julia
using JobSchedulers
```

## Quick start

If you need to run multiple heavy Julia tasks, it is recommended to [start Julia with multi-threads](https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads).

```julia
using JobSchedulers, Dates
```

### Scheduler Controls

```julia
scheduler_start()
# [ Info: Scheduler starts.

scheduler_status()
# ┌ Info: Scheduler is running.
# │   SCHEDULER_MAX_CPU = 32
# │   SCHEDULER_MAX_MEM = 121278191616
# │   SCHEDULER_UPDATE_SECOND = 5.0
# │   JOB_QUEUE_MAX_LENGTH = 10000
# └   SCHEDULER_TASK = Task (runnable) @0x00007fe205052e60

# scheduler_stop()  # NO RUN
```

### Scheduler Settings

Set the **maximum CPU** that the scheduler can use. If starting Julia with multi-threads, the maximum CPU is `nthreads() - 1`.

```julia
set_scheduler_max_cpu()     # use all available CPUs
set_scheduler_max_cpu(4)    # use 4 CPUs
set_scheduler_max_cpu(0.5)  # use 50% of CPUs
```

Set the **maximum RAM** the scheduler can use:

```julia
set_scheduler_max_mem()             # use 80% of total memory

set_scheduler_max_mem(4GB)          # use 4GB memory
set_scheduler_max_mem(4096MB)
set_scheduler_max_mem(4194304KB)
set_scheduler_max_mem(4294967296B)

set_scheduler_max_mem(0.5)          # use 50% of total memory
```

Set the update interval of job queue:

```julia
set_scheduler_update_second(0.3)  # update job queue every 0.3 seconds
```

Set the maximum number of finished jobs:

```julia
set_scheduler_max_job(10000)  # If number of finished jobs > 10000, the oldest ones will be removed.
                              # It does not affect queuing or running jobs.
```

### Job Controls

A `Job` is the wrapper of `AbstractCmd` or `Task`:

```julia
command_job = Job(
    `echo command job done`    # AbstractCmd to run
)

task_job = Job(
    @task(println("task job done"))  # Task to run
)

function_job = Job() do  # the function should have no arguments
    println("function job done")
end

job_with_args = Job(
    @task(println("job_with_args done")); # Task to run
    name = "job with args",               # job name.
    user = "me",                # Job owner.
    ncpu = 1,                   # Number of CPU required.
    mem = 1KB,                  # Number of memory required (unit: TB, GB, MB, KB, B).
    schedule_time = Second(3),  # Run after 3 seconds; can be ::DateTime or ::Period.
    wall_time = Hour(1),        # The maximum time to run the job. (Cancel job after reaching wall time.)
    priority = 20,              # Lower number = higher priority.
    dependency = [              # Defer job until some jobs reach some states.
        DONE => command_job,
        DONE => task_job.id
    ]
)
```

> `dependency` argument in `Job(...)` controls when to start a job.
>
> It is a vector with element `STATE => job` or `STATE => job.id`.
>
> STATE is one of `DONE`, `FAILED`, `CANCELLED`, `QUEUING`, `RUNNING`, `PAST`.  
> The first 5 states are real job states.  
> `PAST` is the super set of `DONE`, `FAILED`, `CANCELLED`, which means the job will not run in the future.

Submit a job to queue:

```julia
submit!(command_job)
submit!(task_job)
submit!(job_with_args)
```

Cancel or interrupt a job:

```julia
cancel!(command_job)
```

Get the returned result:

```julia
result(job_with_args)
```

### Queue

Show queue (all jobs):
```julia
queue(:all)      # or:
queue(all=true)  # or:
all_queue()
# 34×17 DataFrame
#  Row │ state      id                name             user    ncpu   mem     ⋯
#      │ Symbol     Int64             String           String  Int64  Int64   ⋯
# ─────┼───────────────────────────────────────────────────────────────────────
#    1 │ done       1324034831845071  high_priority                1      0   ⋯
#    2 │ cancelled  1324072551328464  to_cancel                    1      0
#    3 │ cancelled  1324072551917525  to_cancel                    1      0
#    4 │ done       1324072550649105  high_priority                1      0
#   ⋮  │     ⋮             ⋮                 ⋮           ⋮       ⋮      ⋮     ⋱
#   31 │ failed     1324073678055463  Command Program              1      0   ⋯
#   32 │ done       1324073675645221  Command Program              1      0
#   33 │ done       1324073677010642  Command Program              1      0
#   34 │ done       1324243247103863                               1      0
#                                                11 columns and 26 rows omitted
```

Show queue (running and queuing jobs only):

```julia
queue()
# 0×16 DataFrame
```

Show queue by given a job state (`QUEUING`, `RUNNING`, `DONE`, `FAILED`, `CANCELLED`, or `PAST`):

```julia
queue(CANCELLED)
# 2×17 DataFrame
#  Row │ state      id                name       user    ncpu   mem    ⋯
#      │ Symbol     Int64             String     String  Int64  Int64  ⋯
# ─────┼────────────────────────────────────────────────────────────────
#    1 │ cancelled  1324072551328464  to_cancel              1      0  ⋯
#    2 │ cancelled  1324072551917525  to_cancel              1      0
#                                                     11 columns omitted
```

### Job Query

Get `Job` object by providing job ID.

```julia
job_query(314268353241057)  # or:
queue(314268353241057)
# Job:
#   id            → 314268353241057
#   name          → "job_with_args"
#   user          → "me"
#   ncpu          → 1
#   mem           → 1024
#   schedule_time → 2021-04-16T12:02:37.511
#   create_time   → 2021-04-16T12:02:40.587
#   start_time    → 2021-04-16T12:02:49.786
#   stop_time     → 2021-04-16T12:02:54.803
#   wall_time     → 1 hour
#   state         → :done
#   priority      → 20
#   dependency    → 2-element Array{Pair{Symbol,Int64},1}:
#  :done => 314268209759432
#  :done => 314268298112225
#   task          → Task (done) @0x00007fe7c027bd00
#   stdout_file   → ""
#   stderr_file   → ""
```

### Backup

Set backup file:

```julia
set_scheduler_backup("/path/to/backup/file")
```
> JobSchedulers writes to the backup file at exit.
> If the file exists, scheduler settings and job queue will be recovered from it automatically.
> Recovered jobs are just for query, not run-able.

Stop backup and `delete_old` backup:

```julia
set_scheduler_backup(delete_old=true)
```

Backup immediately:

```julia
backup()
```

### Compatibility with Pipelines.jl

[Pipelines.jl]: https://cihga39871.github.io/Pipelines.jl/dev/	"Pipelines.jl: A lightweight Julia package for computational pipelines and workflows."

You can also create a `Job` by using `Program` types from Pipelines.jl:

```julia
Job(p::Program; program_kwargs..., run_kwargs..., job_kwargs...)
Job(p::Program, inputs; run_kwargs..., job_kwargs...)
Job(p::Program, inputs, outputs; run_kwargs..., job_kwargs...)
```

- `program_kwargs...` is input and output arguments defined in `p::Program`.
- `run_kwargs...` is keyword arguments of `run(::Program; ...)`
- `job_kwargs...` is keyword arguments of `Job(::Union{Base.AbstractCmd,Task}; ...)`

Details can be found by typing

```julia
julia> using Pipelines, JobSchedulers
julia> ?run
julia> ?Job
```

#### Example

```julia
using Pipelines, JobSchedulers

scheduler_start()

p = CmdProgram(
    inputs = ["IN1", "IN2"],
    outputs = "OUT",
    cmd = pipeline(`echo inputs are: IN1 and IN2` & `echo outputs are: OUT`)
)

### native Pipelines.jl method to run the program
run(p, IN1 = `in1`, IN2 = 2, OUT = "out", touch_run_id_file = false) # touch_run_id_file = false means do not create a file which indicates the job is done and avoids re-run.

# inputs are: in1 and in2
# outputs are: out
# (true, Dict("OUT" => "out"))

### run the program by submitting to JobSchedulers.jl
program_job = Job(p, IN1 = `in1`, IN2 = 2, OUT = "out", touch_run_id_file = false)

submit!(program_job)
# inputs are: in1 and 2
# outputs are: out

# get the returned result
result(program_job)
# (true, Dict("OUT" => "out"))
```
