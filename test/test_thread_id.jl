@testset "Sticky test for multiple threads" begin
    # set_scheduler_update_second(0.05)

    if scheduler_status() != :running
        scheduler_start()
    end

    jobs = Job[]
    @time for i in 1:100
        local job = submit!() do
            x = Threads.threadid()
            sleep(rand())
            sleep(rand())
            y = Threads.threadid()
            return (x, y)
        end
        # c = JobSchedulers.THREAD_POOL[]
        # JobSchedulers.schedule_thread(job)
        # if nthreads() > 1
        #     put!(JobSchedulers.THREAD_POOL[], 2)
        # end
        push!(jobs, job)
    end

    if nthreads() > 1
        for (i, job) in enumerate(jobs)
            @info "Sticky test for multiple threads: fetching job $i"
            x, y = fetch(job.task)
            # @show job._thread_id, x, y
            if (x == 1 || y == 1)
                @show job._thread_id, x, y
                error("Test fail. Assigning jobs to thread 1 is not allowed, but observed.")
            end
            if x != y
                @show job._thread_id, x, y
                error("Test fail. Job migrating is observed but should be disallowed in JobSchedulers.")
            end
            if x != abs(job._thread_id)
                # the job is not freed, so job._thread_id will not become -job._thread_id
                @show job._thread_id, x, y
                error("Test fail. Job migrating is observed but should be disallowed in JobSchedulers.")
            end
        end
    end
end