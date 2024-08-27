
using .Threads
function experiments_threads(a, K=10000)
    x = 0
    Threads.@threads for i in 1:K
        x += a
    end
    x
end

@time experiments_threads(1, 10000)  #   0.000176 seconds (9.61 k allocations: 160.891 KiB)
@time experiments_threads(1, 100000) #   0.001873 seconds (99.61 k allocations: 1.530 MiB)

using Dagger
function experiments_dagger(a, K=10000)
    x = 0
    f() = x += a
    @sync for i in 1:K
        Dagger.@spawn f()
    end
    x
end

@time experiments_dagger(1, 10000)  #   0.846881 seconds (26.50 M allocations: 1.828 GiB, 29.06% gc time)
@time experiments_dagger(1, 100000)  # dead


using JobSchedulers

function experiments_jobschedulers(a, K=10000)
    x = 0
    f() = x += a
    for i in 1:K
        submit!(f)
    end
    @info "all submitted"
    wait_queue()   
    x
end
@time experiments_jobschedulers(1, 10) 

@time experiments_jobschedulers(1, 10000)  #     0.023636 seconds (229.87 k allocations: 15.877 MiB)
@time experiments_jobschedulers(1, 100000) #     0.915987 seconds (2.30 M allocations: 158.742 MiB, 6.47% gc time)
