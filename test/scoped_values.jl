@testset "Scoped Values" begin

    @test current_job() === nothing
    j = Job(name="j") do 
        @info "running j"
        job = current_job()
        @show job._thread_id
        @test job !== nothing
        global j2 = submit!(name="j2") do
            @info "running j2"
            j2 = current_job()
            @test j2 !== nothing
            @show j2._thread_id job._thread_id 
        end
        @yield_current begin
            @info "yield j"
            @test job.ncpu == 0
            j3 = submit!(name="j3") do
                @info "running j3"
                j3 = current_job()
                @test j3 !== nothing
            end
            wait(j3)
        end
        @test job.ncpu == 1
        j2, j3
    end
    submit!(j)
    j2, j3 = fetch(j)
    @test j2.name == "j2"
    @test j3.name == "j3"
    @test current_job() === nothing


    ## race condition test for taking threads
    yield_wait = Ref(true)
    yield_release = Ref(true)

    jparent = Job(name="parent", ncpu=1) do
        @info "running parent"
        job = current_job()
        @test job !== nothing
        @test job.ncpu == 1
        @test job._thread_id >= 0

        children = Job[]  # store child jobs

        @yield_current begin
            @info "yield parent"
            @test job.ncpu == 0

            @info "yield waiting..."
            while yield_wait[]
                sleep(0.1)
            end

            for i in 1:10
                child = Job(name="child: $i", ncpu=1) do
                    @info "running child: $i"
                end
                push!(children, submit!(child))
            end

            for child in children
                wait(child)
            end
            yield_release[] = false
        end

        @test job.ncpu == 1
        return children
    end
    submit!(jparent)

    # block all tids
    ntids = length(JobSchedulers.TIDS)
    for i in 1:ntids
        jblock = Job(name="blocker: $i", ncpu=1) do
            while yield_release[]
                sleep(0.1)
            end
        end
        submit!(jblock)
    end
    yield_wait[] = false
    children = fetch(jparent)

    @test !JobSchedulers.is_tid_occupied(j)
    @test !JobSchedulers.is_tid_ready_to_occupy(j)

    j._thread_id = 5
    @test !JobSchedulers.is_tid_occupied(j)
    @test !JobSchedulers.is_tid_ready_to_occupy(j)
    j.ncpu = 0
    @test JobSchedulers.is_tid_ready_to_occupy(j)


    @test JobSchedulers.unsafe_occupy_tid!(j) == 5
    @test j._thread_id == (5 | JobSchedulers.OCCUPIED_MARK)

    @test JobSchedulers.is_tid_occupied(j)
    @test !JobSchedulers.is_tid_ready_to_occupy(j)

    @test JobSchedulers.unsafe_original_tid(j) == 5
    @test JobSchedulers.unsafe_unoccupy_tid!(j) == 5

end