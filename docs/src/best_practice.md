# Best Practice (Please Read)

In the following sections, we briefly go through a few techniques that can help you understand tricks when using JobSchedulers.

## Multi-threaded or single-threaded Julia session

It is recommended to use JobSchedulers in multi-threaded Julia sessions. 

`Job`s are controlled using a main scheduler task (`JobSchedulers.SCHEDULER_TASK[]`). This task always binds to thread ID (tid) 1 and does not migrate to other threads. During initiation, JobSchedulers checks available tids in the **default** thread pool. 

If the default thread pool is empty after excluding tid 1, JobSchedulers will use a single-thread mode (`JobSchedulers.SINGLE_THREAD_MODE[]::Bool`). Otherwise, JobSchedulers will use a multi-thread mode.

### Single-thread Mode

The maximum number of CPU is default to the system CPU (`Sys.CPU_THREADS`). 

All `Job`s are migratable, and they might yield to other tasks. 

### Multi-thread Mode

The maximum number of CPU is default to

- number of threads in the default thread pool, if you use any interactive threads. (ie. starting julia with `-t 10,1`.)

- number of threads in the default thread pool **minus 1**, if you do not use interactive threads. (ie. starting julia with `-t 10`.)

The tids that JobScheduler.jl can use are stored in a Channel `JobSchedulers.THREAD_POOL[]`. 

If you submit a job assigning `ncpu > 0`,

- the job takes a thread from `THREAD_POOL`;
- **the job does not migrate to other threads;** 
- also, if you only use JobSchedulers to schedule tasks, **your tasks will not be blocked by other tasks at any time**. It is important when your tasks need quick response (like a web API server). Therefore, you can ignore the existance of interactive threads when using JobSchedulers.jl.

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

#### [Submitting child jobs within a parent job](@id submit-child-jobs)

Submitting jobs within jobs is allowed in JobSchedulers, but it might waste threads and even block the scheduler.

To prevent the side effects, it is always recommended to use [`@yield_current`](@ref) to wrap the code that creats and waits for child jobs.

Why and when do the side effects happen?

Each job with `ncpu > 0` takes a unique thread ID when started, and if a parent job submits and waits for a child job during its execution, the thread taken by the parent is wasted when waiting. In a worse senario, if there is no avaiable thread, the child job won't start, resulting a scheduler blockage. 

!!! details "An example to demonstrate the blockage"
    Start Julia with 1 interactive and 1 default thread: `julia -t 1,1`, and run the following code:

    ```julia
    using JobSchedulers
    
    @assert length(JobSchedulers.TIDS) == 1 "Please run the code with `julia -t 1,1`"

    parent_job = submit!(@task begin
        println("Parent job running on thread ", Threads.threadid())

        println("Avaiable threads in the thread pool: ", JobSchedulers.THREAD_POOL[].data)

        child_job1 = Job(@task begin
            println("Child job 1 running on thread ", Threads.threadid())
        end; name="child 1")
        child_job2 = Job(@task begin
            println("Child job 2 running on thread ", Threads.threadid())
        end; name="child 1")
        
        submit!(child_job1)
        submit!(child_job2)
        
        wait(child_job1)
        wait(child_job2)
    end; name="parent");
    # Parent job running on thread 2
    # Avaiable threads in the thread pool: Int64[]

    sleep(1)
    queue()
    # ┌─────┬──────────┬──────────────────┬───────────┬──────┬──────┬─────┬──────────┬───
    # │ Row │    state │               id │      name │ user │ ncpu │ mem │ priority │  ⋯
    # ├─────┼──────────┼──────────────────┼───────────┼──────┼──────┼─────┼──────────┼───
    # │   1 │ :running │ 9386485380519246 │  "parent" │   "" │  1.0 │ 0 B │       20 │  ⋯
    # │   2 │ :queuing │ 9386485380548364 │ "child 1" │   "" │  1.0 │ 0 B │       20 │  ⋯
    # │   3 │ :queuing │ 9386485380578205 │ "child 1" │   "" │  1.0 │ 0 B │       20 │  ⋯
    # └─────┴──────────┴──────────────────┴───────────┴──────┴──────┴─────┴──────────┴───
    fetch(parent_job)
    ```

    As it shows, the two child jobs is queuing because no avaiable thread in the thread pool. The scheduler is blocked forever until you kill the parent job (or the Julia session, of course).

    If you do not wait for child jobs, the program will not block, but what if you need the results of child jobs in the parent?

To solve it, you can simply wrap child jobs within [`@yield_current`](@ref) block, like the following example.

Start Julia with 1 interactive and 1 default thread: `julia -t 1,1`, and run the following code:

```julia
using JobSchedulers

@assert length(JobSchedulers.TIDS) == 1 "Please run the code with `julia -t 1,1`"
@assert length(queue()) == 0 "Please start a new Julia session: `julia -t 1,1`"

parent_job = submit!(@task begin
    println("Parent job running on thread ", Threads.threadid())

    println("Avaiable threads in the thread pool: ", JobSchedulers.THREAD_POOL[].data)

    @yield_current begin
        child_job1 = Job(@task begin
            println("Child job 1 running on thread ", Threads.threadid())
        end; name="child 1")
        child_job2 = Job(@task begin
            println("Child job 2 running on thread ", Threads.threadid())
        end; name="child 1")
        
        submit!(child_job1)
        submit!(child_job2)
        
        wait(child_job1)
        wait(child_job2)
    end
end; name="parent");
# Parent job running on thread 2
# Avaiable threads in the thread pool: Int64[]
# Child job 1 running on thread 2
# Child job 2 running on thread 2

fetch(parent_job)
```

With [`@yield_current`](@ref), the child jobs run successfully with the same thread as its parent, because the parent was yielding to the children.

More details in [`@yield_current`](@ref).

## Avoid simultaneous use of `Job` and other multi-threaded methods using the `:default` thread pool

Since a normal `Job` binds to a tid in the default thread pool and does not migrate, it is better not to simultaneously use `Job` and other threaded methods, such as `Threads.@spawn` and `Threads.@threads`. 

Also, JobScheduers has very low computational costs (1~2 us/job from creation to destroy), so normal threaded methods can be replaced with `Job`.

If you really want to use both `Job` and other threaded methods, it is better to make sure to run them at different time. You may use `wait_queue()`, `scheduler_stop()`, and `scheduler_start()` in this situation.
