# all are running with 24 threads

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
    wait_queue()
    x
end
@time experiments_jobschedulers(1, 10) 

@time experiments_jobschedulers(1, 10000)  
# speed up 330X
# v0.10   0.014750 seconds (145.62 k allocations: 12.526 MiB)
# v0.9    4.871162 seconds (296.27 k allocations: 16.973 MiB)

@time experiments_jobschedulers(1, 100000) 
# speed up 216X
# v0.10   0.240398 seconds (1.46 M allocations: 125.250 MiB, 15.57% gc time)
# v0.9   52.003475 seconds (2.97 M allocations: 355.336 MiB, 0.20% gc time)

