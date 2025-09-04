
# Manual

JobSchedulers.jl can used to glue commands in a pipeline/workflow, and can also be used to schedule small Julia tasks thanks to its very low overhead (1~2 µs/job). 

!!! info "Multi-threading"
    It is recommended to [start Julia with multi-threads](https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads) when using JobSchedulers.jl.


```julia
using JobSchedulers
```

## Create a Job

A [`Job`](@ref) is the wrapper of `AbstractCmd`, `Function` or `Task`:

```julia
command_job = Job(
    `echo command job done`    # AbstractCmd to run
)

function_job = Job() do  # the function should have no arguments
    println("function job done")
end

task_job = Job(
    @task(println("task job done"))  # Task to run
)

job_with_args = Job(
    @task(println("job_with_args done")); # Task to run
    name = "job with args",     # Job name.
    user = "me",                # Job owner.
    ncpu = 1,                   # Number of CPU required (Int/Float).
    mem = 1KB,                  # Number of memory required (unit: TB, GB, MB, KB, B).
    schedule_time = Second(3),  # Run after 3 seconds; can be ::DateTime or ::Period.
    wall_time = Hour(1),        # The maximum time to run the job.
    priority = 20,              # Lower number = higher priority.
    cron = Cron(:none),         # Job recurring: Cron defines repeat date and time.
    until = DateTime(9999,1,1), #                When to stop job recurring.
    dependency = [              # Defer job until some jobs reach some states.
        command_job,
        DONE => task_job
    ],
    stdout = nothing,           # stdout redirection to file
    stderr = nothing,           # stderr redirection to file
    append = false              # whether append to existing files
)
# Job:
#   id            → 9385239735019930
#   name          → "job with args"
#   user          → "me"
#   ncpu          → 1.0
#   mem           → 1.0 KB
#   schedule_time → 11:58:15
#   submit_time   → na
#   start_time    → na
#   stop_time     → na
#   wall_time     → 1 hour
#   cron          → Cron(:none)
#   until         → forever
#   state         → :queuing
#   priority      → 20
#   dependency    → 2 jobs
#   stdout        → nothing
#   stderr        → nothing
#   task          → Task (runnable) @0x00007625b8d26720
```

> `dependency` argument in [`Job`](@ref) controls when to start a job.
>
> It is a vector with element `STATE => job` or `STATE => job.id`.
>
> STATE is one of `DONE`, `FAILED`, `CANCELLED`, `QUEUING`, `RUNNING`, `PAST`.  
> The first 5 states are real job states.  
> `PAST` is the super set of `DONE`, `FAILED`, `CANCELLED`, which means the job will not run in the future.
>
> `DONE => job` can be simplified to `job` from v0.8.

## Submit a Job

Submit a job to queue:

```julia
submit!(command_job)
submit!(task_job)
submit!(job_with_args)
```

> Details: [`submit!`](@ref)

## Create and submit a Job

`submit!(Job(...))` can be simplified to `submit!(...)` from v0.8.

```julia
job = submit!(@task(println("job")), priority = 0)
```

Macro `@submit [args...] expression` is available from v0.10.2. It will automatically add **explictly referred** `Job` dependencies by walking through the symbols in the `expression`.

```julia
job = @submit ncpu=1 1+1

job_auto_dependency = @submit 1 + result(job)
# equivalent to submit!(() -> 1 + result(job); dependency=job)
```

[`@submit`](@ref) supports any type of `Expr`ession, including a code block:

```julia
x = 5
job_block = @submit begin
    y = x + 1
    y^2
end
@assert fetch(job_block) == (5+1)^2
```

## Get a Job's Result

Get the returned [`result`](@ref) imediately. If job is not finished, show a warning message and return nothing:

```julia
result(job)
# "result"
```

You can also use [`fetch`](@ref) to wait for job to finish and return its result from JobSchedulers v0.10.2.

```julia
fetch(job)
```

## Cancel a Job

Interrupt or [`cancel!`](@ref) a job:

```julia
cancel!(job)
```

## Recurring/repetitive Job

Recurring jobs can be defined using two arguments of `Job`: `Job(..., cron::Cron, until::Union{DateTime,Period})`.

- `cron::Cron` use a similar syntax of Linux's **Crontab**. It accepts a [`Cron`](@ref) object. It extends Linux's crontab and allows repeat every XX seconds. You can use your favorate `*`, `-`, `,` syntax just like crontab. Other features please see [`Cron`](@ref).

- `until::Union{DateTime,Period})`: stop job recurring until date and time.

Construction:

```julia
Cron(second, minute, hour, day_of_month, month, day_of_week)
```

Examples:

```julia
Cron()
# Cron(every minute at 0 second past every hour everyday)

Cron(0,0,0,1,1,0)
Cron(:yearly)
Cron(:annually)
# Cron(at 00:00:00 on day-of-month 1 in Jan)

Cron(0,0,0,1,*,*)
Cron(:monthly)
# Cron(at 00:00:00 on day-of-month 1)

Cron(0,0,0,*,*,1)
Cron(:weekly)
# Cron(at 00:00:00 on Mon)

Cron(0,0,0,*,'*',"*") # * is equivalent to '*', and "*" in Cron.
Cron(:daily)
Cron(:midnight)
# Cron(at 00:00:00 everyday)

Cron(0,0,*,*,*,*)
Cron(:hourly)
# Cron(at 0 minute, 0 second past every hour everyday)

Cron(0,0,0,0,0,0) # never repeat
Cron(:none)       # never repeat
# Cron(:none)

Cron(0,0,0,*,*,"*/2")
# Cron(at 00:00:00 on Tue, Thu and Sat)

Cron(0,0,0,*,*,"1-7/2")
# Cron(at 00:00:00 on Mon, Wed, Fri and Sun)

Cron(0,0,0,1,"1-12/3",*)
# Cron(at 00:00:00 on day-of-month 1 in Jan, Apr, Jul and Oct)

Cron(30,4,"1,3-5",1,*,*)
# Cron(at 4 minute, 30 second past 1, 3, 4 and 5 hours on day-of-month 1)

# repeatly print time every 5 seconds, until current time plus 20 seconds
recurring_job = submit!(cron = Cron("*/5", *, *, *, *, *), until = Second(20)) do
    println(now())
end
# 2025-03-04T22:26:00.176
# 2025-03-04T22:26:05.077
# 2025-03-04T22:26:10.089
# 2025-03-04T22:26:15.051
```

> Details: [`Cron`](@ref)

## Queue

Show all jobs:

```julia
queue(:all)      # or:
queue(all=true)  # or:
all_queue()
# 1-element Vector{Job}:
# ┌─────┬───────┬──────────────────┬─────────────────┬──────┬──────┬─────────
# │ Row │ state │               id │            name │ user │ ncpu │    mem ⋯
# ├─────┼───────┼──────────────────┼─────────────────┼──────┼──────┼─────────
# │   1 │ :done │ 6407186212753787 │ "job with args" │ "me" │  1.0 │ 1.0 KB ⋯
# └─────┴───────┴──────────────────┴─────────────────┴──────┴──────┴─────────
#                                                           9 columns omitted
```

!!! compat "Changes from v0.10"

    Before v0.10, all jobs will be saved to queue. However, from v0.10, unnamed jobs (`job.name == ""`) will not be saved if they **successfully** ran. If you want to save unnamed jobs, you can set using `JobSchedulers.destroy_unnamed_jobs_when_done(false)`.

Show queue (running and queuing jobs only):

```julia
queue()
# 0-element Vector{Job}:
# ┌─────┬───────┬────┬──────┬──────┬──────┬─────┬──────────┬────────────┬────
# │ Row │ state │ id │ name │ user │ ncpu │ mem │ priority │ dependency │ s ⋯
# └─────┴───────┴────┴──────┴──────┴──────┴─────┴──────────┴────────────┴────
#                                                           7 columns omitted
```

Show queue using a job state (`QUEUING`, `RUNNING`, `DONE`, `FAILED`, `CANCELLED`, or `PAST`):

```julia
queue(DONE)
# 1-element Vector{Job}:
# ┌─────┬───────┬──────────────────┬─────────────────┬──────┬──────┬─────────
# │ Row │ state │               id │            name │ user │ ncpu │    mem ⋯
# ├─────┼───────┼──────────────────┼─────────────────┼──────┼──────┼─────────
# │   1 │ :done │ 6407186212753787 │ "job with args" │ "me" │  1.0 │ 1.0 KB ⋯
# └─────┴───────┴──────────────────┴─────────────────┴──────┴──────┴─────────
#                                                           9 columns omitted
```

Show queue using a `String` or `Regex` to match job name or user:

```julia
queue("me")
queue("with args")
queue(r"job.*")
# 1-element Vector{Job}:
# ┌─────┬───────┬──────────────────┬─────────────────┬──────┬──────┬─────────
# │ Row │ state │               id │            name │ user │ ncpu │    mem ⋯
# ├─────┼───────┼──────────────────┼─────────────────┼──────┼──────┼─────────
# │   1 │ :done │ 6407186212753787 │ "job with args" │ "me" │  1.0 │ 1.0 KB ⋯
# └─────┴───────┴──────────────────┴─────────────────┴──────┴──────┴─────────
#                                                           9 columns omitted
```

> See more at [`queue`](@ref), and [`all_queue`](@ref).

## Job query

Get `Job` object by providing job ID, or access the index of queue:

```julia
job_query(6407186212753787)  # or:
queue(6407186212753787)
queue(:all)[1]
# Job:
#   id            → 6407186212753787
#   name          → "job with args"
#   user          → "me"
#   ncpu          → 1.0
#   mem           → 1.0 KB
#   schedule_time → 13:11:45
#   submit_time   → 13:12:46
#   start_time    → 13:12:46
#   stop_time     → 13:12:46
#   wall_time     → 1 hour
#   cron          → Cron(:none)
#   until         → forever
#   state         → :done
#   priority      → 20
#   dependency    → 2 jobs
#   task          → Task
#   stdout        → nothing
#   stderr        → nothing
```

> See more at [`job_query`](@ref), and [`queue`](@ref).


## Wait for jobs and progress meter

[`wait`](@ref) for a specific job(s):

```julia
wait(j::Job)
wait(js::Vector{Job})
```

Wait for jobs finished using [`wait_queue`](@ref).


```julia
wait_queue()
# no output

# If `show_progress = true`, a fancy progress meter will display.
wait_queue(show_progress = true)

# stop waiting when <= 2 jobs are queuing or running.
wait_queue(show_progress = true, exit_num_jobs = 2)
```
![progress meter](assets/progress_meter.png)

## Scheduler control

Scheduler is automatically started after v0.7.11.

```julia
scheduler_stop()
# [ Info: Scheduler task stops.
# ┌ Warning: Scheduler reactivation task is not running.
# └ @ JobSchedulers ~/projects/JobSchedulers.jl/src/control.jl:92

scheduler_start()
# ┌ Warning: Scheduler task was interrupted or done. Restart.
# └ @ JobSchedulers ~/projects/JobSchedulers.jl/src/control.jl:61
# ┌ Warning: Scheduler reactivation task was interrupted or done. Restart.
# └ @ JobSchedulers ~/projects/JobSchedulers.jl/src/control.jl:61

scheduler_status()
# ┌ Info: Scheduler is running.
# │   SCHEDULER_MAX_CPU = 23
# │   SCHEDULER_MAX_MEM = "169.7 GB"
# │   JOB_QUEUE.max_done = 10000
# │   JOB_QUEUE.max_cancelled = 10000
# │   SCHEDULER_TASK[] = Task (runnable) @0x00007d4160031dc0
# └   SCHEDULER_REACTIVATION_TASK[] = Task (runnable) @0x00007d4160031f50
# :running
```

!!! info "Number of CPU Optimization"
    JobSchedulers.jl also provide a function to find optimized `ncpu` that a Job can use, based on current cpu usage. See more at [`solve_optimized_ncpu`](@ref).

## Compatibility with Pipelines.jl

[Pipelines.jl](https://cihga39871.github.io/Pipelines.jl/dev/): A lightweight Julia package for computational pipelines and workflows.

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

### Example

```julia
using Pipelines, JobSchedulers

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
#   cmd_dependencies → <empty>
#   arg_inputs       → IN1 :: Any (required)
#                      IN2 :: Any (required)
#   validate_inputs  → do_nothing
#   prerequisites    → do_nothing
#   cmd              → `echo inputs are: IN1 and IN2` & `echo outputs are: OUT`
#   infer_outputs    → do_nothing
#   arg_outputs      → OUT :: Any (required)
#   validate_outputs → do_nothing
#   wrap_up          → do_nothing
#   arg_forward      → <empty>

### native Pipelines.jl method to run the program
run(p, IN1 = `in1`, IN2 = 2, OUT = "out", touch_run_id_file = false) 
# touch_run_id_file = false means do not create a file which indicates 
# the job is done and avoids re-run.

# ┌ Info: 2025-03-04 22:31:11 Started: Command Program
# │   command_template = `echo inputs are: IN1 and IN2` & `echo outputs are: OUT`
# │   run_id = Base.UUID("c30eed71-69ff-544b-a175-b6077dcd0931")
# │   inputs =
# │    Dict{String, Any} with 2 entries:
# │      "IN2" => 2
# │      "IN1" => `in1`
# │   outputs =
# │    Dict{String, Any} with 1 entry:
# └      "OUT" => "out"
# inputs are: in1 and 2
# outputs are: out
# ┌ Info: 2025-03-04 22:31:12 Finished: Command Program
# │   command_running = `echo inputs are: in1 and 2` & `echo outputs are: out`
# │   run_id = Base.UUID("c30eed71-69ff-544b-a175-b6077dcd0931")
# │   inputs =
# │    Dict{String, Any} with 2 entries:
# │      "IN2" => 2
# │      "IN1" => `in1`
# │   outputs =
# │    Dict{String, Any} with 1 entry:
# └      "OUT" => "out"
# (true, Dict{String, Any}("OUT" => "out"))

### run the program by submitting to JobSchedulers.jl
program_job = submit!(p, IN1 = `in1`, IN2 = 2, OUT = "out", touch_run_id_file = false)
# same results as `run`

# get the returned result
result(program_job)
# (true, Dict{String, Any}("OUT" => "out"))
```

[`@submit`](@ref) also works with `Program`s:

```julia
program_job2 = @submit IN1=`in1` IN2=2 OUT="out" touch_run_id_file=false p
```

## Scheduler settings

Check the current status of scheduler:

```julia
scheduler_status()
# ┌ Info: Scheduler is running.
# │   SCHEDULER_MAX_CPU = 32
# │   SCHEDULER_MAX_MEM = "169.6 GB"
# │   JOB_QUEUE.max_done = 10000
# │   JOB_QUEUE.max_cancelled = 10000
# │   SCHEDULER_TASK[] = Task (runnable) @0x00007fe205052e60
# └   SCHEDULER_REACTIVATION_TASK[] = Task (runnable) @0x00007d4160031f50
# :running
```

Set the **maximum CPU** that the scheduler can use. If starting Julia with multi-threads, the maximum CPU is the number of default thread pool, excluding thread ID 1.

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
# 101166391296
```

Set the maximum number of finished jobs:

```julia
set_scheduler_max_job(max_done::Int = 10000, max_cancelled::Int = max_done)

set_scheduler_max_job(10000)  # If number of finished jobs > 10000, 
                              #    the oldest ones will be removed.
# 10000                       # It does not affect queuing, running, or failed jobs.
```

Set the previous setting in one function:

```julia
set_scheduler(;
    max_cpu = JobSchedulers.SCHEDULER_MAX_CPU,
    max_mem = JobSchedulers.SCHEDULER_MAX_MEM,
    max_job = JobSchedulers.JOB_QUEUE.max_done,
    max_cancelled_job = JobSchedulers.JOB_QUEUE.max_cancelled_job,
    update_second = JobSchedulers.SCHEDULER_UPDATE_SECOND
)
# ┌ Info: Scheduler is running.
# │   SCHEDULER_MAX_CPU = 32
# │   SCHEDULER_MAX_MEM = "169.6 GB"
# │   JOB_QUEUE.max_done = 10000
# │   JOB_QUEUE.max_cancelled = 10000
# │   SCHEDULER_TASK[] = Task (runnable) @0x00007fe205052e60
# └   SCHEDULER_REACTIVATION_TASK[] = Task (runnable) @0x00007d4160031f50
# :running
```

## Backup

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
