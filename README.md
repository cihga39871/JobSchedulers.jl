# JobSchedulers.jl

*A Julia-based job scheduler and workload manager inspired by Slurm and PBS.*

| **Documentation**                                                               |
|:-------------------------------------------------------------------------------:|
| [![](https://img.shields.io/badge/docs-stable-blue.svg)](https://cihga39871.github.io/JobSchedulers.jl/stable) [![](https://img.shields.io/badge/docs-dev-blue.svg)](https://cihga39871.github.io/JobSchedulers.jl/dev) |

## Package Features

- Job and task scheduler.
- Local workload manager.
- Support CPU, memory, run time management.
- Support running a job at specific time, or a period after creating (schedule).
- Support deferring a job until specific jobs reach specific states (dependency).
- Support automatic backup and reload.

## Installation

JobSchedulers.jl can be installed using the Julia package manager. From the Julia REPL, type ] to enter the Pkg REPL mode and run

```julia
pkg> add JobSchedulers
# If it fails, use
pkg> add https://github.com/cihga39871/JobSchedulers.jl.git
```

To use the package, type

```julia
using JobSchedulers
```

## Quick start

```julia
using JobSchedulers, Dates
```

### Scheduler Controls

```julia
scheduler_start()
# [ Info: Scheduler starts.

scheduler_status()
# ┌ Info: Scheduler is running.
# │   SCHEDULER_MAX_CPU = 16
# │   SCHEDULER_MAX_MEM = 14900915405
# │   SCHEDULER_UPDATE_SECOND = 5.0
# └   JOB_QUEUE_MAX_LENGTH = 10000

# scheduler_stop()  # NO RUN
```

### Job Controls

A `Job` is the wrapper of `AbstractCmd` or `Cmd`:

```julia
command_job = Job(
    `echo command job done`    # AbstractCmd to run
)

task_job = Job(
    @task(println("task job done"))  # Task to run
)

job_with_args = Job(
    @task(println("job_with_args done")); # Task to run
    name = "job_with_args",               # job name.
    user = "me",                # Job owner.
    ncpu = 1,                   # Number of CPU required.
    mem = 1KB,                  # Number of memory required (unit: TB, GB, MB, KB, B).
    schedule_time = Second(3),  # Run after 3 seconds, can be DateTime or Period.
    wall_time = Hour(1),        # The maximum wall time to run the job.
    priority = 20,              # Lower = higher priority.
    dependency = [              # Defer job until some jobs reach some states.
        DONE => command_job.id,   # Left can be DONE, FAILED, CANCELLED, or even
        DONE => task_job.id       # QUEUEING, RUNNING.
    ]                             # Right is the job id.
)
```

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

### Queue

Show queue (all jobs):
```julia
all_queue()
queue(all=true)
# 3×16 DataFrame. Omitted printing of 10 columns
# │ Row │ id              │ name          │ user   │ ncpu  │ mem   │ schedule_time           │
# │     │ Int64           │ String        │ String │ Int64 │ Int64 │ DateTime                │
# ├─────┼─────────────────┼───────────────┼────────┼───────┼───────┼─────────────────────────┤
# │ 1   │ 314268209759432 │               │        │ 1     │ 0     │ 0000-01-01T00:00:00     │
# │ 2   │ 314268298112225 │               │        │ 1     │ 0     │ 0000-01-01T00:00:00     │
# │ 3   │ 314268353241057 │ job_with_args │ me     │ 1     │ 1024  │ 2021-04-16T12:02:37.511 │
```

Show queue (running and queueing jobs only):

```julia
queue()
# 0×16 DataFrame
```

### Job Query

```julia
job_query(314268353241057)
job_query_by_id(314268353241057)
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

Stop backup and `delete_old` backup:

```julia
set_scheduler_backup(delete_old=true)
```

## Documentation


- [**STABLE**](https://cihga39871.github.io/JobSchedulers.jl/stable) &mdash; **documentation of the most recently tagged version.**
- [**DEVEL**](https://cihga39871.github.io/JobSchedulers.jl/dev) &mdash; *documentation of the in-development version.*
