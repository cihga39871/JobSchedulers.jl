# Changelog

v0.10.7

- Fix: crash when showing progress meter after all jobs finished while stdout/sterr are redirected to files. Remove call to legacy `queue_summary`, which was replaced a while ago. 

v0.10.6

- Fix: `is_dependency_ok(job)`: capture `job.state` in variable to avoid changing when running the function, which might lead to error.
- Performance: job: when user's function is done, change the state to done or failed within `job.task`, and `update_queue!()` can capture this change now. In previous versions, if a job is done, the flag might not updated to done, which cause significant delay in some situations.
- Change: `scheduler_reactivation` interval changed to  0.1s from 0.5s.

v0.10.5

- Fix: when showing progress meter, changing `JobGroup.x` was not thread safe. 
- Fix: when showing progress meter, now CPU and MEM was not computed again from JobGroup, but just fetch from a global variable `RESOURCE(cpu, mem)::Resource`. `RESOURCE` is computed when `update_queue!()`

v0.10.4

- Optimize: remove extra `scheduler_status` check in `queue_progress(...)`.
- Optimize: `wait_queue(show_progress=false)` no longer took 100% CPU. Now it computes exit condition only when scheduler updates.
- Change: explicit error when calling the second `wait_queue(...)`. Only one is allowed each time. 
- Compat: JLD2 0.5.

v0.10.3

- Fix: error when calling `wait_queue(;show_progress=true)` and no job has been submitted.

v0.10.2

- Feat: new macro `@submit` to create a job using an expression. It will automatically add explictly referred `Job` dependencies by walking through the symbols in the expression.
- Feat: new method `fetch`.

v0.10.1

- Fix: `job` not defined if Job failed.

v0.10.0

- **Feat/Optimize: Rewriting scheduler for 200~400X speed up. Scheduling 100,000 small tasks in 0.2 seconds using 24 threads.**
- Deprecate: `SCHEDULER_UPDATE_SECOND` and `set_scheduler_update_second()` are no longer required. Changing them will have no effect on the scheduler.
- Feat: Now, the scheduler updates when needed, and every 0.5 second. When specific events happen, `scheduler_need_action()` is used to trigger update of the scheduler. `SCHEDULER_REACTIVATION_TASK[]` is used to trigger `scheduler_need_action()` every 0.5 second because a regular check is needed for future jobs (defined by `j::Job.schedule_time`).
- Change: `Job`'s fields `stdout_file::String` and `stderr_file::String` is changed to `stdout::Union{IO,AbstractString,Nothing}` and `stderr::Union{IO,AbstractString,Nothing}`.
- Change: remove function `format_stdxxx_file(x)`.
- Optimize: check whether a job needs IO redirection before wrapping in task. Also, avoid unecessary stack when wrapping a new job, avoiding recurring job's stack overflow due to creating new jobs.
- Feat: Now people can `set_group_seperator(group_seperator::Regex=r": *")`. A group name will be given to `Job`. It is useful when showing progress meters.
- Feat: New `wait(j::Job)` and `wait(js::Vector{Job})`.
- Optimize: progress bar now does not blink: now we do not clear lines before printing. Instead, printing a "erase from cursor to end of line" characters.
- Optimize: rewrite progress computing for much faster speed.

v0.9.0

- Change: `ncpu` now also accepts `Float64`, but if `0 < ncpu < 1`, job still binds to one thread and other jobs cannot use binded threads.
- Change: `Job`'s field name `:create_time` is changed to `:submit_time`.
- Change: check duplicate job when submitting: check `submit_time == DateTime(0)`, rather than recursively check existing jobs in `JOB_QUEUE`.
- Feat: showing `queue()` is better.

v0.8.4

- Update: remove print-to-stdout statements during precompilation.

v0.8.3

- Compat: fix precompilation runs forever in Julia v1.10.

v0.8.2

- Feat: not replace `Base.istaskfailed`. Use `istaskfailed2` instead.
- Feat: recurring job: job does not immediately after submit, except manually set `Job(..., schedule_time)`. (#8)
- Feat: no double printing stacktrace when a job failed. 
- Feat: progress bar: dim job count == 0. (#9)

v0.8.1

- Fix: scheduler() handles errors and InteruptExceptions more wisely. (Thanks to @fivegrant, #7)

v0.8.0

- Feat: `ncpu == 0` can set to a `Job`, but a warning message shows.
- Feat: `dependency = DONE => job_A`: to be simplified to `dependency = job_A` or `dependency = job_A.id`.
- Feat: Simplify `Job()` methods.
- Feat: `submit!(Job(...))`: to be simplified to `submit!(...)`.
- Feat: schedule repetitive jobs using `Cron` until a specific date and time: `Job(cron = Cron(0,0,*,*,*,*), until = Year(1))`. It is  inspired by Linux-based crontab.
- Change: `Job()`: default wall time value increase to `Year(1)` from `Week(1)`.
- Change: `SCHEDULER_TASK` is now a `Base.RefValue{Task}` rather than undefined or `Task`.

v0.7.12

- Compat: Pipelines v0.9, 0.10 (new), 1 (not published).
- Docs: Use Documenter.jl.

v0.7.11

- Update: Term to v2.
- Feat: Set a lower loop interval of nthreads > 2.
- Feat: Move `scheduler_start()` in `__init__()`.

v0.7.10

- Feature: Better progress bar for visualization.

v0.7.9

- Fix: `solve_optimized_ncpu()`: devision by 0 if njob == 0.

v0.7.8

- Feature: `solve_optimized_ncpu()`: Find the optimized number of CPU for a job.

v0.7.7

- Fix: `style_line()`: index error for special UTF characters.

v0.7.6

- Fix: if original stdout is a file, not contaminating stdout using `wait_queue(show_progress = true)`.

v0.7.5

- Change: remove extra blank lines after `wait_queue(show_progress = true)`.

- Fix a benign error (task switch error for `sleep()`).

v0.7.4

- Feature: Progress meter: `wait_queue(show_progress = true)`.

v0.7.3

- Compat: Pipelines v0.9: significant improvement on decision of re-run: considering file change.
- Fix: pretty print of Job and Vector{Job}.

v0.7.2

- Fix: unexpected output of `scheduler_status()` when SCHEDULER_TASK is not defined.

v0.7.1

- Compat: PrettyTables = "0.12 - 2" to satisfy DataFrames v1.3.5 which needs PrettyTables v1 but not v2.

v0.7.0

- Remove dependency DataFrames and change to PrettyTables. The loading time of DataFrames is high.

- Feature: now a Job is sticky to one thread (>1). JobSchedulers allocates and manuages it. The SCHEDULER_TASK is sticky to thread 1.

- Feature: `queue(...)` is rewritten.

- Feature: Better pretty print of Job and queue().

- Feature: New function: `wait_queue()` waits for all jobs in `queue()` become finished.

- Feature: New function: `set_scheduler()`

- Fix: `set_scheduler_max_cpu(percent::Float64)`: use default_ncpu() if error.

- Change: SCHEDULER_UPDATE_SECOND to 0.05 from 0.6

v0.6.12

- Feature: Enchance compatibility with Pipelines v0.8.5: Program has a new field called arg_forward that is used to forward user-defined inputs/outputs to specific keyword arguments of JobSchedulers.Job(::Program, ...), including name::String, user::String, ncpu::Int, mem::Int.

v0.6.11

- Fix: running `queue()` when updating queue: use lock within `DataFrames.DataFrame(job_queue::Vector{Job})`.

v0.6.10

- Update documents.

v0.6.9

- Support Pipelines.jl v0.8.

v0.6.8

- Feature: Replace `@Job` with `Job` to run `program` without creating `inputs::Dict` and `outputs::Dict`. Remove `@Job`.

v0.6.7

- Feature: Run `program` without creating `inputs::Dict` and `outputs::Dict`: `@Job program::Program key_value_args... Job_args...`. See also `@run` in Pipelines.jl.

v0.6.6

- Optimize: `job.dependency` now accepts `DONE => job`, `[DONE => job1.id; PAST => job2]`.

- Optimize: `is_dependency_ok(job::Job)::Bool` is rewritten: for loop when found a dep not ok, and delete previous ok deps. If dep is provided as Int, query Int for job and then replace Int with the job.

v0.6.5

- Fix: If an app is built, SCHEDULER_MAX_CPU and SCHEDULER_MAX_MEM will be fixed to the building computer: fix by re-defining `SCHEDULER_MAX_CPU` and `SCHEDULER_MAX_MEM` in `__init__()`.

- Debug: add debug outputs.

v0.6.4

- Fix: `scheduler_stop()` cannot stop because v0.6.1 update. Now `scheduler_stop` does not send ^C to `SCHEDULER_TASK`, but a new global variable `SCHEDULER_WHILE_LOOP::Bool` is added to control the while loop in `scheduler()`.

- Optimize: the package now can be precompiled: global Task cannot be precompiled, so we do not define `SCHEDULER_TASK::Task` when loading the package. Define it only when needed.

v0.6.3

- Fix: `scheduler_start()` now wait until `SCHEDULER_TASK` is actually started. Previously, it returns after `schedule(SCHEDULER_TASK)`.

v0.6.2

- Compat Pipelines v0.7.0.

v0.6.1

- Robustness: scheduler() and wait_for_lock(): wrap sleep() within a try-catch block. If someone sends ctrl + C to sleep, scheduler wont stop.

v0.6.0

- Compatibility: Pipelines v0.5.0: Job(...; dir=dir).

v0.5.1

- Fix: program_close_io: If the current stdout/stderr is IO, restore to default stdout/stderr.

v0.5.0

- Compatibility: Pipelines v0.5.0: fixed redirection error and optimized stack trace display. Extend `Base.istaskfailed` to fit Pipelines and JobSchedulers packages, which will return a `StackTraceVector` in `t.result`, while Base considered it as `:done`. The fix checks the situation and modifies the real task status and other properties.

v0.4.1

- Export `PAST`. PAST is the super set of DONE, FAILED, CANCELLED, which means the job will not run in the future.

v0.4.0

- If running with multi-threads Julia, `SCHEDULER_TASK` runs in thread 1, and other jobs spawn at other threads. Thread assignment was achieved by JobScheduler. Besides, `SCHEDULER_MAX_CPU = nthreads() > 1 ? nthreads()-1 : Sys.CPU_THREADS`.

- New feature: `queue(job_state::Symbol)`.

- Use try-finally for all locks.

v0.3.0

- Tasks run on different threads, if Julia version supports and `nthreads() > 1`.

- Use `SpinLock`.

- Fix typo "queuing" from "queueing".

- Notify when a job is failed.
