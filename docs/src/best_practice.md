# Best Practice (Please Read)

In the following sections, we briefly go through a few techniques that can help you understand tricks when using JobSchedulers.

## Multi-threaded or single-threaded Julia session

It is recommended to use JobSchedulers in multi-threaded Julia sessions. 

`Job`s are controlled using a main scheduler task (`JobSchedulers.SCHEDULER_TASK[]`). This task always binds to thread ID (tid) 1 and does not migrate to other threads. During initiation, JobSchedulers.jl checks available tids in the **default** thread pool. If the default thread pool is empty after excluding tid 1, JobSchedulers.jl will use a single-thread mode (`JobSchedulers.SINGLE_THREAD_MODE[]`). Otherwise, JobSchedulers.jl will use a multi-thread mode.

### Single-thread Mode

The maximum number of CPU is default to the system CPU (`Sys.CPU_THREADS`). 

All `Job`s are migratable, and they might yield to other tasks. 

### Multi-thread Mode

The maximum number of CPU is default to

- number of threads in the default thread pool, if you use any interactive threads. (ie. starting julia with `-t 10,1`.)

- number of threads in the default thread pool **minus 1**, if you do not use interactive threads. (ie. starting julia with `-t 10`.)

The tids that JobScheduler.jl can use are stored in a Channel `JobSchedulers.THREAD_POOL[]`. 

If you submit a job assigning `ncpu > 0`, 

- **the job does not migrate to other threads.** 
- Also, if you only use JobSchedulers to schedule tasks, **your tasks will not be blocked by other tasks at any time**. It is important when your tasks need quick response (like a web API server). Therefore, you can ignore the existance of interactive threads when using JobSchedulers.jl.

  !!! info
      JobSchedulers.jl even solves the issue of interactive tasks prior to the official Julia introducing task migration (partially solved) and the interactive/default thread pools.

If you set `ncpu = 0` to your job,

- the job is migratable and does not take any tid from `JobSchedulers.THREAD_POOL[]`.

  !!! tip
      Use `ncpu = 0` only when a job is very small, or a job that spawns and waits for other jobs:
      ```julia
      using JobSchedulers

      small_job = Job(ncpu = 0) do
          # within the small job,
          # submit 100 big jobs
          big_jobs = map(1:100) do _
              @submit ncpu=1 sum(rand(9999999))
          end
          # post-process of big jobs
          total = 0.0
          for j in big_jobs
              total += fetch(j)
          end
          total
      end
      submit!(small_job)
      total = fetch(small_job)
      # 4.999998913757924e8
      ```


## Avoid simultaneous use of `Job` and other multi-threaded methods using the `:default` thread pool

Since a normal `Job` binds to a tid in the default thread pool and does not migrate, it is better not to simultaneously use `Job` and other threaded methods, such as `Threads.@spawn` and `Threads.@threads`. 

Also, JobScheduers.jl has very low extra computational costs (scheduling 10,000 jobs within 0.01 second), so normal threaded methods can be replaced with `Job`.

If you really want to use both `Job` and other threaded methods, it is better to make sure to run them at different time. You may use `wait_queue()`, `scheduler_stop()`, and `scheduler_start()` in this situation.
