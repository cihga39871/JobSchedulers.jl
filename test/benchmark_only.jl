# all are running with 24 threads

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
# speed up 469X
# v0.10   0.010370 seconds (125.72 k allocations: 10.086 MiB)
# v0.9    4.871162 seconds (296.27 k allocations: 16.973 MiB)

@time experiments_jobschedulers(1, 100000) 
# speed up 210X
# v0.10   0.247005 seconds (1.26 M allocations: 100.839 MiB, 21.43% gc time)
# v0.9   52.003475 seconds (2.97 M allocations: 355.336 MiB, 0.20% gc time)

function experiments_jobschedulers2(a, K=10000)
    x = 0
    for i in 1:K
        @submit! x += a
    end
    wait_queue()
    x
end

@time experiments_jobschedulers2(1, 10) 

@time experiments_jobschedulers2(1, 10000)

@time experiments_jobschedulers2(1, 100000) 