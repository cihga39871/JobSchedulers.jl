

@testset "macro @submit" begin
    j = @submit name = "abc" dependency = [] 1+1
    wait(j)
    @test result(j) == 2
    @test j.name == "abc"

    a = 3242
    j = @submit a + 5
    wait(j)
    @test result(j) == 3242 + 5

    j_long = @submit name = "abc" dependency = j begin sleep(2); 32 end

    j2 = @submit mem = 2KB begin 1 + result(j) + result(j_long) end
    @test length(j2.dependency) > 0
    sleep(1)
    @test j2.state === QUEUING
    wait(j2)
    @test result(j2) === 1 + 3247 + 32

    p = JobSchedulers.Pipelines.JuliaProgram()
    @submit touch_run_id_file=false p

    @test (yield_current(now) isa Dates.DateTime)
    @test JobSchedulers.isajob(j)
    @test !JobSchedulers.isajob(p)
    @test !JobSchedulers.isajob(1)
    @test !JobSchedulers.isajob("")

    @test !JobSchedulers.isnotajob(j)
    @test JobSchedulers.isnotajob(p)
    @test JobSchedulers.isnotajob(1)
    @test JobSchedulers.isnotajob("")

    @test JobSchedulers._sym_list!([], Set(), 5) === nothing


    function experiments_jobschedulers2(a, K=10000)
        x = 0
        for i in 1:K
            @submit x += a
        end
        wait_queue()
        x
    end
    experiments_jobschedulers2(1, 10)

    function test_sequential(a, K=10)
        x = 0
        y = [a:a+K...]
        js = Job[]
        
        for _ in 1:K
            j1 = @submit sum(y)/length(y)
            for i in y
                j2 = @submit (i - result(j1))^2
                push!(js, j2)
            end
        end
        jsum = @submit dependency=js for j in js
            x += result(j)
        end
        wait(jsum)
        x/K
    end
    @test test_sequential(4,50) == 11050
end
