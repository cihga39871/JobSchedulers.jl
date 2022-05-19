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
