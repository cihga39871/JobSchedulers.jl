# JobSchedulers.jl

*A Julia-based job scheduler and workload manager inspired by Slurm and PBS.*

| **Documentation**                                                               |
|:-------------------------------------------------------------------------------:|
| [![](https://img.shields.io/badge/docs-stable-blue.svg)](https://cihga39871.github.io/JobSchedulers.jl/stable) [![](https://img.shields.io/badge/docs-dev-blue.svg)](https://cihga39871.github.io/JobSchedulers.jl/dev) |

## Package Features

- Job and task scheduler.
- Local workload manager.
- Support CPU, memory, run time management.
- Support run a job at specific time, or a period after creating.
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
```

### Job Controls

A `Job` is the wrapper of `AbstractCmd` or `Cmd`:

```julia
command_job = Job(
    `echo command job done`;    # AbstractCmd to run
    name = "echo",              # job name
    user = "me",                # job owner
    ncpu = 1,                   # number of CPU required
    mem = 1KB,                  # number of memory required (unit: TB, GB, MB, KB, B)
    schedule_time = Second(3),  # run after 3 seconds, can be DateTime or Period
    wall_time = Hour(1),        # the maximum wall time to run the job
    priority = 20               # lower = higher priority
)

task_job = Job(
    @task(println("task job done"))  # Task to run
    # Other keyword arguments are the same
)
```

Submit a job to queue:

```julia
submit!(command_job)
submit!(task_job   )
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
# 2×15 DataFrame
#  Row │ id               name    user    ncpu   mem    ⋯
#      │ Int64            String  String  Int64  Int64  ⋯
# ─────┼─────────────────────────────────────────────────
#    1 │ 310796141563261  echo    me          1   1024  ⋯
#    2 │ 310796497191577                      1      0
#                                      10 columns omitted
```

Show queue (running and queueing jobs only):

```julia
queue()
# 0×15 DataFrame
```

### Job Query

```julia
job_query(310796141563261)
job_query_by_id(310796141563261)
# Job:
#   id            → 310796141563261
#   name          → "echo"
#   user          → "me"
#   ncpu          → 1
#   mem           → 1024
#   schedule_time → 2021-04-15T21:19:35.765
#   create_time   → 2021-04-15T21:22:37.828
#   start_time    → 2021-04-15T21:22:39.414
#   stop_time     → 2021-04-15T21:22:42.162
#   wall_time     → 1 hour
#   state         → :done
#   priority      → 20
#   task          → Task (done) @0x00007f6f95ebf0d0
#   stdout_file   → ""
#   stderr_file   → ""
```

### Backup

Set backup file:

```julia
set_scheduler_backup("/path/to/backup/file")
```
> When Julia exits, write to the backup file automatically.
> If the file exists, scheduler settings and job queue will be recovered from it automatically.

Stop backup and delete the old backup file:

```julia
set_scheduler_backup(delete_old=true)
```

## Documentation


- [**STABLE**](https://cihga39871.github.io/JobSchedulers.jl/stable) &mdash; **documentation of the most recently tagged version.**
- [**DEVEL**](https://cihga39871.github.io/JobSchedulers.jl/dev) &mdash; *documentation of the in-development version.*
