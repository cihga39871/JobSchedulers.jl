
set_scheduler_update_second(0.05)

scheduler_status()

@time for i in 1:100
    local job = Job() do
        threadid()
    end
    submit!(job)
    if 1 == fetch(job.task)
        error("Test fail. Assigning jobs to thread 1 is not allowed, but observed.")
    end
end
