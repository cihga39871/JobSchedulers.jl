# Overhead Test of Scheduling Systems

To test the overhead of scheduling systems, I compared `Base.Threads`, `Dagger.jl`, and `JobSchedulers` using tiny tasks (`x::Int += y::Int`).

!!! warning
    `x += y` is not thread-safe, and it is for overhead test only.
    BenchmarkTools.jl cannot be used in this case because it competes scheduling systems.

## System information

- Julia v1.11.3 with `-t 24,1` (24 threads in the default thread pool, and 1 interactive thread).
- Each script run on seperate Julia sessions.
- JobSchedulers.jl v0.11.6; Dagger v0.18.14.
- Ubuntu 22.04 system.
- CPU: i9-13900K.
- Memory: 196GB DDR5 4800 MT/s.

## Scripts

The following scripts are used to test overhead of scheduling systems.

### overhead-baseline.jl

```julia
using .Threads
function experiments_threads(a, K=10000)
    x = 0
    Threads.@threads for i in 1:K
        x += a
    end
    x
end

# compile
experiments_threads(1, 10)

# test
@time experiments_threads(1, 10000);
@time experiments_threads(1, 10000);
@time experiments_threads(1, 10000);
#   0.000267 seconds (9.61 k allocations: 160.906 KiB)
#   0.000244 seconds (8.87 k allocations: 149.297 KiB)
#   0.000186 seconds (9.35 k allocations: 156.750 KiB)

@time experiments_threads(1, 100000);
@time experiments_threads(1, 100000);
@time experiments_threads(1, 100000);
#   0.001288 seconds (98.01 k allocations: 1.506 MiB)
#   0.001620 seconds (99.14 k allocations: 1.523 MiB)
#   0.001470 seconds (99.61 k allocations: 1.530 MiB)
```

### overhead-jobschedulers.jl

```julia
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

# compile
experiments_jobschedulers(1, 10)

# test
@time experiments_jobschedulers(1, 10000);
@time experiments_jobschedulers(1, 10000);
@time experiments_jobschedulers(1, 10000);
#  0.007719 seconds (170.36 k allocations: 10.767 MiB, 197 lock conflicts)
#  0.007741 seconds (159.35 k allocations: 10.566 MiB, 198 lock conflicts)
#  0.010097 seconds (157.05 k allocations: 10.524 MiB, 14.18% gc time, 70 lock conflicts)

@time experiments_jobschedulers(1, 100000);
@time experiments_jobschedulers(1, 100000);
@time experiments_jobschedulers(1, 100000);
#  0.119578 seconds (1.57 M allocations: 105.162 MiB, 30.19% gc time, 2344 lock conflicts)
#  0.122050 seconds (1.56 M allocations: 105.044 MiB, 37.64% gc time, 2216 lock conflicts)
#  0.113245 seconds (1.56 M allocations: 105.055 MiB, 33.09% gc time, 2205 lock conflicts)
```

### overhead-dagger.jl

```julia
using Dagger
function experiments_dagger(a, K=10000)
    x = 0
    f() = x += a
    @sync for i in 1:K
        Dagger.@spawn f()
    end
    x
end

# compile
experiments_dagger(1, 10)

# test
@time experiments_dagger(1, 10000);
@time experiments_dagger(1, 10000);
@time experiments_dagger(1, 10000);
#   1.097989 seconds (31.55 M allocations: 2.315 GiB, 33.66% gc time, 761375 lock conflicts)
#   1.314606 seconds (27.20 M allocations: 1.944 GiB, 33.19% gc time, 622269 lock conflicts)
#   1.121939 seconds (30.54 M allocations: 2.227 GiB, 32.63% gc time, 738192 lock conflicts)

@time experiments_dagger(1, 100000);
@time experiments_dagger(1, 100000);
@time experiments_dagger(1, 100000);
#  11.078450 seconds (305.29 M allocations: 22.357 GiB, 36.32% gc time, 7429201 lock conflicts)
#  12.931351 seconds (316.35 M allocations: 23.249 GiB, 35.22% gc time, 7587318 lock conflicts)
#  11.318478 seconds (121.07 M allocations: 7.953 GiB, 22.46% gc time, 1476778 lock conflicts, 0.04% compilation time)
```

## Results

Table. Benchmark of average elapsed time to schedule 10,000 and 100,000 tasks using different scheduling systems.

| Modules       | 10,000 Tasks | 100,000 Tasks |
| :------------ | -----------: | ------------: |
| Base.Threads  | 0.000232 s   |  0.001459 s   |
| JobSchedulers | 0.008519 s   |  0.118291 s   |
| Dagger        | 1.178178 s   | 11.776093 s   |

- JobSchedulers.jl can schedule 10,000 tasks within 0.01 second, which is 150X faster than Dagger.

- JobSchedulers.jl is robust, and able to achive a decent speed when scaling up to 100,000 tasks.

## Conclusions

JobSchedulers.jl has very little overhead when comparing with Base.Threads, but provides strong extensive features than Base.Threads.

The low overhead of JobSchedulers.jl makes it interchangable with Base.Threads.
