# all are running with 24 threads

using Statistics
using JobSchedulers

#=
    using .Threads
    function experiments_threads(a, K=10000)
        x = 0
        Threads.@threads for i in 1:K
            x += a
        end
        x
    end

    @time experiments_threads(1, 10000)  #   0.000176 seconds (9.54 k allocations: 159.828 KiB)
    @time experiments_threads(1, 100000) #   0.001873 seconds (99.61 k allocations: 1.530 MiB)

    using Dagger
    function experiments_dagger(a, K=10000)
        x = 0
        f() = x += a
        @sync for i in 1:K
            Dagger.@spawn f()  # cannot use x += a because not a valid expression in Dagger
        end
        x
    end

    @time experiments_dagger(1, 10000)  #   0.846881 seconds (26.50 M allocations: 1.828 GiB, 29.06% gc time)
    @time experiments_dagger(1, 100000)  # dead
=#

function experiments_jobschedulers(a, K=10000)
    x = 0
    f() = x += a
    for i in 1:K
        submit!(f)
    end
    wait_queue()
    x
end

function experiments_jobschedulers2(a, K=10000)
    x = 0
    for i in 1:K
        @submit x += a
    end
    wait_queue()
    x
end

@time experiments_jobschedulers(1, 10)
@time experiments_jobschedulers2(1, 10) 

println("\n=== submit! ===")
for K in (10_000, 100_000)
    times = Float64[]
    for _ in 1:5
        GC.gc()
        t = @elapsed begin
            v = @time experiments_jobschedulers(1, K)
        end
        push!(times, t)
    end
    println("K=", K,
        " | mean=", round(mean(times), digits=6), " s",
        " | median=", round(median(times), digits=6), " s",
        " | min=", round(minimum(times), digits=6), " s",
        " | max=", round(maximum(times), digits=6), " s"
    )
end

println("\n=== @submit ===")
for K in (10_000, 100_000)
    times = Float64[]
    for _ in 1:5
        GC.gc()
        t = @elapsed begin
            v = @time experiments_jobschedulers2(1, K)
        end
        push!(times, t)
    end
    println("K=", K,
        " | mean=", round(mean(times), digits=6), " s",
        " | median=", round(median(times), digits=6), " s",
        " | min=", round(minimum(times), digits=6), " s",
        " | max=", round(maximum(times), digits=6), " s"
    )
end