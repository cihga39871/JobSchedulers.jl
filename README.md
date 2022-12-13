# JobSchedulers.jl

*A Julia-based job scheduler and workload manager inspired by Slurm and PBS.*

## Why JobScheduler?

We may find different tasks or programs use different CPU and memory. Some can run simultaneously, but some have to run sequentially. JobScheduler is stable, useful and powerful for task queuing and workload management. 

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
# │   SCHEDULER_UPDATE_SECOND = 0.05
# │   JOB_QUEUE_MAX_LENGTH = 10000
# └   SCHEDULER_TASK = Task (runnable) @0x00007fe205052e60
# :running

# scheduler_stop()  # NO RUN
```

### Scheduler Settings

Set the **maximum CPU** that the scheduler can use. If starting Julia with multi-threads, the maximum CPU is `nthreads() - 1`.

```julia
set_scheduler_max_cpu()     # use all available CPUs
# 32
set_scheduler_max_cpu(4)    # use 4 CPUs
# 4
set_scheduler_max_cpu(0.5)  # use 50% of CPUs
# 16
```

Set the **maximum RAM** the scheduler can use:

```julia
set_scheduler_max_mem()             # use 80% of total memory
# 107792089088

set_scheduler_max_mem(4GB)          # use 4GB memory
set_scheduler_max_mem(4096MB)
set_scheduler_max_mem(4194304KB)
set_scheduler_max_mem(4294967296B)
# 4294967296
set_scheduler_max_mem(0.5)          # use 50% of total memory
# 67370055680
```

Set the update interval of job queue:

```julia
set_scheduler_update_second(0.03)  # update job queue every 0.3 seconds
# 0.03
```

Set the maximum number of finished jobs:

```julia
set_scheduler_max_job(10000)  # If number of finished jobs > 10000, the oldest ones will be removed.
# 10000                       # It does not affect queuing or running jobs.
```

Set the previous setting in one function:

```julia
set_scheduler(
    max_cpu = JobSchedulers.SCHEDULER_MAX_CPU,
    max_mem = JobSchedulers.SCHEDULER_MAX_MEM,
    update_second = JobSchedulers.SCHEDULER_UPDATE_SECOND,
    max_job = JobSchedulers.JOB_QUEUE_MAX_LENGTH
)
# ┌ Info: Scheduler is running.
# │   SCHEDULER_MAX_CPU = 16
# │   SCHEDULER_MAX_MEM = 67370055680
# │   SCHEDULER_UPDATE_SECOND = 0.03
# │   JOB_QUEUE_MAX_LENGTH = 10000
# └   SCHEDULER_TASK = Task (runnable) @0x00007fd239184fe0
# :running
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
    @task(begin println("job_with_args done"); "result" end); # Task to run
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
# Job:
#   id            → 3603962603799412
#   name          → "job with args"
#   user          → "me"
#   ncpu          → 1
#   mem           → 1024
#   schedule_time → 2022-11-18 11:35:08
#   create_time   → 0000-01-01 00:00:00
#   start_time    → 0000-01-01 00:00:00
#   stop_time     → 0000-01-01 00:00:00
#   wall_time     → 1 hour
#   state         → :queuing
#   priority      → 20
#   dependency    → 2 jobs
#   task          → Task
#   stdout_file   → ""
#   stderr_file   → ""
#   _thread_id    → 0
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
# "result"
```

### Queue

Show queue (all jobs):
```julia
queue(:all)      # or:
queue(all=true)  # or:
all_queue()
# 3-element Vector{Job}:
# ┌─────┬───────┬──────────────────┬─────────────────┬──────┬──────┬────────
# │ Row │ state │               id │            name │ user │ ncpu │  mem  ⋯
# ├─────┼───────┼──────────────────┼─────────────────┼──────┼──────┼────────
# │   1 │ :done │ 3603962559801309 │              "" │   "" │    1 │    0  ⋯
# │   2 │ :done │ 3603962563817452 │              "" │   "" │    1 │    0  ⋯
# │   3 │ :done │ 3603962603799412 │ "job with args" │ "me" │    1 │ 1024  ⋯
# └─────┴───────┴──────────────────┴─────────────────┴──────┴──────┴────────
#                                                         11 columns omitted
```

Show queue (running and queuing jobs only):

```julia
queue()
# 0-element Vector{Job}:
```

Show queue using a job state (`QUEUING`, `RUNNING`, `DONE`, `FAILED`, `CANCELLED`, or `PAST`):

```julia
queue(DONE)
# 3-element Vector{Job}:
# ┌─────┬───────┬──────────────────┬─────────────────┬──────┬──────┬────────
# │ Row │ state │               id │            name │ user │ ncpu │  mem  ⋯
# ├─────┼───────┼──────────────────┼─────────────────┼──────┼──────┼────────
# │   1 │ :done │ 3603962559801309 │              "" │   "" │    1 │    0  ⋯
# │   2 │ :done │ 3603962563817452 │              "" │   "" │    1 │    0  ⋯
# │   3 │ :done │ 3603962603799412 │ "job with args" │ "me" │    1 │ 1024  ⋯
# └─────┴───────┴──────────────────┴─────────────────┴──────┴──────┴────────
#                                                         11 columns omitted
```

`queue(...)` and `all_queue()` can also used to filter job name and user. Please find out more by typing `?queue` and `?all_queue` in REPL.

### Job Query

Get `Job` object by providing job ID.

```julia
job_query(3603962563817452)  # or:
queue(3603962563817452)
# Job:
#   id            → 3603962563817452
#   name          → ""
#   user          → ""
#   ncpu          → 1
#   mem           → 0
#   schedule_time → 0000-01-01 00:00:00
#   create_time   → 2022-11-18 11:35:30
#   start_time    → 2022-11-18 11:35:30
#   stop_time     → 2022-11-18 11:35:30
#   wall_time     → 1 week
#   state         → :done
#   priority      → 20
#   dependency    → []
#   task          → Task
#   stdout_file   → ""
#   stderr_file   → ""
#   _thread_id    → 0
```

### Wait for jobs

Wait for all jobs in `queue()` finished:

```julia
wait_queue()
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
# CmdProgram:
#   name             → Command Program
#   id_file          → 
#   info_before      → auto
#   info_after       → auto
#   cmd_dependencies → CmdDependency[]
#   arg_inputs       → IN1 :: Any (required)
#                      IN2 :: Any (required)
#   validate_inputs  → do_nothing
#   prerequisites    → do_nothing
#   cmd              → `echo inputs are: IN1 and IN2` & `echo outputs are: OUT`
#   infer_outputs    → do_nothing
#   arg_outputs      → OUT :: Any (required)
#   validate_outputs → do_nothing
#   wrap_up          → do_nothing
#   arg_forward      → Pair{String, Symbol}[]


### native Pipelines.jl method to run the program
run(p, IN1 = `in1`, IN2 = 2, OUT = "out", touch_run_id_file = false) # touch_run_id_file = false means do not create a file which indicates the job is done and avoids re-run.

# inputs are: in1 and in2
# outputs are: out
# (true, Dict("OUT" => "out"))

### run the program by submitting to JobSchedulers.jl
program_job = Job(p, IN1 = `in1`, IN2 = 2, OUT = "out", touch_run_id_file = false)
# Job:
#   id            → 3603980229784158
#   name          → "Command Program"
#   user          → ""
#   ncpu          → 1
#   mem           → 0
#   schedule_time → 0000-01-01 00:00:00
#   create_time   → 0000-01-01 00:00:00
#   start_time    → 0000-01-01 00:00:00
#   stop_time     → 0000-01-01 00:00:00
#   wall_time     → 1 week
#   state         → :queuing
#   priority      → 20
#   dependency    → []
#   task          → Task
#   stdout_file   → ""
#   stderr_file   → ""
#   _thread_id    → 0

submit!(program_job)
# inputs are: in1 and 2
# outputs are: out

# get the returned result
result(program_job)
# (true, Dict("OUT" => "out"))
```
