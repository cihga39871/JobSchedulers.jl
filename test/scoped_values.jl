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