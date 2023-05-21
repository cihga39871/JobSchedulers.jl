# API

## Scheduler Control
```@docs
scheduler_status
scheduler_start
scheduler_stop
```

## Scheduler Settings
```@docs
set_scheduler
set_scheduler_max_cpu
set_scheduler_max_mem
set_scheduler_update_second
set_scheduler_max_job
```

## Job
```@docs
Job
submit!
cancel!
result
```

## Cron: Job Recur/Repeat
```@docs
Cron
JobSchedulers.cron_value_parse
Dates.tonext(::DateTime, ::Cron)
JobSchedulers.date_based_on
```

## Queue
```@docs
queue
all_queue
job_query
```

## Wait For Jobs
```@docs
wait_queue
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

## Progress Meter

!!! note
    To display a progress meter, please use [`wait_queue(show_progress = true)`](@ref).

```@docs
JobSchedulers.JobGroup
JobSchedulers.fingerprint
JobSchedulers.get_group
JobSchedulers.progress_bar
JobSchedulers.queue_progress
JobSchedulers.view_update
```