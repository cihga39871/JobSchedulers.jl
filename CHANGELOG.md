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
