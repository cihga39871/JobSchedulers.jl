
set_scheduler_update_second(0.05)

if scheduler_status() != :running
    scheduler_start()
end

jobs = Job[]
@time for i in 1:100
    local job = Job() do
        sleep(rand())
        x = Threads.threadid()
        sleep(rand())
        y = Threads.threadid()
        return (x, y)
    end
    c = JobSchedulers.THREAD_POOL[]
    JobSchedulers.schedule_thread(job)
    if nthreads() > 1
        put!(JobSchedulers.THREAD_POOL[], 2)
    end
    push!(jobs, job)
end

if nthreads() > 1
    for job in jobs
        x, y = fetch(job.task)
        # @show job._thread_id, x, y
        if (x == 1 || y == 1)
            error("Test fail. Assigning jobs to thread 1 is not allowed, but observed.")
        end
        if x != y
            error("Test fail. Job migrating is observed but should be disallowed in JobSchedulers.")
        end
        if x != job._thread_id
            error("Test fail. Job migrating is observed but should be disallowed in JobSchedulers.")
        end
    end
end