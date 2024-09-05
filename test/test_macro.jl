

@testset "@submit!" begin
    j = @submit! name = "abc" dependency = [] 1+1
    wait(j)
    @test result(j) == 2
    @test j.name == "abc"

    j_long = @submit! name = "abc" dependency = $j begin sleep(2); 32 end

    j2 = @submit! mem = 2KB begin println(1+j); 1+$j+$j_long end
    @test length(j2.dependency) > 0
    sleep(1)
    @test j2.state === QUEUING
    wait(j2)
    @test result(j2) === 1 + 2 + 32
end
