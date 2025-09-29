# API

## Const/Variables

```julia
const B = 1
const KB = 1024
const MB = 1024KB
const GB = 1024MB
const TB = 1024GB

const QUEUING = :queuing
const RUNNING = :running
const DONE = :done
const FAILED = :failed
const CANCELLED = :cancelled
const PAST = :past # super set of DONE, FAILED, CANCELLED

const cron_none = Cron(:none)

const SCHEDULER_TASK = Base.RefValue{Task}()
const SCHEDULER_REACTIVATION_TASK = Base.RefValue{Task}()
```

## Job
```@docs
Job
submit!
@submit
cancel!
result
fetch(::Job)
isqueuing
isrunning
isdone
iscancelled
isfailed
ispast
```

## Submit Job within Job
```@docs
@yield_current
yield_current
current_job
```

## Cron: Job Recur/Repeat
```@docs
Cron
JobSchedulers.cron_value_parse
Dates.tonext(::DateTime, ::Cron)
```

## Queue
```@docs
queue
all_queue
job_query
job_query_by_id
```

## Wait For Jobs
```@docs
wait_queue
wait(::Job)
```

## Scheduler Settings
```@docs
set_scheduler
set_scheduler_max_cpu
set_scheduler_max_mem
set_scheduler_max_job
JobSchedulers.destroy_unnamed_jobs_when_done
JobSchedulers.set_group_seperator
JobSchedulers.GROUP_SEPERATOR
```

## Scheduler Control

Scheduler is automatically started, so it is not necessary to start/stop it.

```@docs
scheduler_status
scheduler_start
scheduler_stop
```

## Optimize CPU Usage
```@docs
solve_optimized_ncpu
```

## Backup
```@docs
set_scheduler_backup
backup
```

## Internal

### Internal - Const/Variable

```@docs
JobSchedulers.THREAD_POOL
JobSchedulers.SINGLE_THREAD_MODE
JobSchedulers.TIDS
JobSchedulers.CURRENT_JOB
JobSchedulers.OCCUPIED_MARK
```

```julia
const SKIP = UInt8(0)
const OK   = UInt8(1)
const FAIL = UInt8(2)

const SCHEDULER_ACTION = Base.RefValue{Channel{Int}}()  # defined in __init__()
const SCHEDULER_PROGRESS_ACTION = Base.RefValue{Channel{Int}}()  # defined in __init__()

SCHEDULER_MAX_CPU::Int = -1              # set in __init__
SCHEDULER_MAX_MEM::Int64 = Int64(-1)     # set in __init__
SCHEDULER_UPDATE_SECOND::Float64 = 0.05  # set in __init__

const JOB_QUEUE = JobQueue(; max_done = JOB_QUEUE_MAX_LENGTH,  max_cancelled = max_done = JOB_QUEUE_MAX_LENGTH)

SCHEDULER_BACKUP_FILE::String = ""

SCHEDULER_WHILE_LOOP::Bool = true

SLEEP_HANDELED_TIME::Int = 10

DESTROY_UNNAMED_JOBS_WHEN_DONE::Bool = true

const ALL_JOB_GROUP = JobGroup("ALL JOBS")
const JOB_GROUPS = OrderedDict{String, JobGroup}()
const OTHER_JOB_GROUP = JobGroup("OTHERS")
```

### Internal - Thread Utils

```@docs
JobSchedulers.schedule_thread
JobSchedulers.free_thread
JobSchedulers.is_tid_ready_to_occupy
JobSchedulers.is_tid_occupied
JobSchedulers.unsafe_occupy_tid!
JobSchedulers.unsafe_unoccupy_tid!
JobSchedulers.unsafe_original_tid
```

### Internal - LinkedJobList

```@docs
JobSchedulers.LinkedJobList
Base.deleteat!(::LinkedJobList, ::Job)
```

### Internal - Scheduling

```@docs
JobSchedulers.JobQueue
JobSchedulers.scheduler()
JobSchedulers.unsafe_run!
JobSchedulers.unsafe_cancel!
JobSchedulers.unsafe_update_state!
JobSchedulers.is_dependency_ok
JobSchedulers.set_scheduler_while_loop
JobSchedulers.get_priority
JobSchedulers.get_thread_id
JobSchedulers.date_based_on
JobSchedulers.next_recur_job
```

### Internal - Progress Meter

!!! note
    To display a progress meter, please use [`wait_queue(show_progress = true)`](@ref).

```@docs
JobSchedulers.JobGroup
JobSchedulers.get_group
JobSchedulers.progress_bar
JobSchedulers.queue_progress
JobSchedulers.view_update
JobSchedulers.PROGRESS_METER
JobSchedulers.update_group_state!
JobSchedulers.init_group_state!()
```

