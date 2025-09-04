# Overhead Test of Scheduling Systems

To test the overhead of scheduling systems, I compared `Base.Threads`, `Dagger`, and `JobSchedulers` using tiny tasks (`x::Int += y::Int`).

!!! warning
    `x += y` is not thread-safe, and it is for overhead test only.
    BenchmarkTools.jl cannot be used in this case because it competes scheduling systems.

## System information

- Julia v1.11.6 with `-t 24,1` (24 threads in the default thread pool, and 1 interactive thread).
- Each script run on seperate Julia sessions.
- JobSchedulers.jl v0.11.11; Dagger v0.19.1.
- System: Ubuntu 22.04.5.
- CPU: AMD® Ryzen threadripper pro 7985wx 64-cores × 128-threads.
- Memory: 512GB: 8 × 64GB DDR5 5600MHz ECC RDIMM.

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
begin
    @time experiments_threads(1, 10000);
    @time experiments_threads(1, 10000);
    @time experiments_threads(1, 10000);
    #   0.000719 seconds (9.61 k allocations: 160.906 KiB)
    #   0.000392 seconds (6.85 k allocations: 117.750 KiB)
    #   0.000320 seconds (8.88 k allocations: 149.500 KiB)

    @time experiments_threads(1, 100000);
    @time experiments_threads(1, 100000);
    @time experiments_threads(1, 100000);
    #   0.001833 seconds (99.61 k allocations: 1.530 MiB)
    #   0.001633 seconds (99.61 k allocations: 1.530 MiB)
    #   0.001375 seconds (99.26 k allocations: 1.525 MiB)
end
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
begin
    @time experiments_jobschedulers(1, 10000);
    @time experiments_jobschedulers(1, 10000);
    @time experiments_jobschedulers(1, 10000);
    #   0.022963 seconds (211.94 k allocations: 11.988 MiB, 27.13% gc time, 34 lock conflicts)
    #   0.013618 seconds (204.64 k allocations: 11.854 MiB, 58 lock conflicts)
    #   0.014744 seconds (204.29 k allocations: 11.848 MiB, 48 lock conflicts)

    @time experiments_jobschedulers(1, 100000);
    @time experiments_jobschedulers(1, 100000);
    @time experiments_jobschedulers(1, 100000);
    #   0.200437 seconds (2.05 M allocations: 118.630 MiB, 24.80% gc time, 530 lock conflicts)
    #   0.270190 seconds (2.06 M allocations: 118.689 MiB, 41.37% gc time, 503 lock conflicts)
    #   0.242404 seconds (2.05 M allocations: 118.601 MiB, 29.48% gc time, 311 lock conflicts)
end
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
begin
    @time experiments_dagger(1, 10000);
    @time experiments_dagger(1, 10000);
    @time experiments_dagger(1, 10000);
    #   0.927116 seconds (8.34 M allocations: 371.282 MiB, 10.42% gc time, 13889 lock conflicts, 37.67% compilation time: 59% of which was recompilation)
    #   0.849340 seconds (8.72 M allocations: 390.953 MiB, 21.63% gc time, 18758 lock conflicts, 0.78% compilation time)
    #   0.766911 seconds (8.17 M allocations: 367.719 MiB, 20.11% gc time, 8553 lock conflicts, 0.03% compilation time)

    @time experiments_dagger(1, 100000);
    @time experiments_dagger(1, 100000);
    @time experiments_dagger(1, 100000);
    #   9.019336 seconds (82.94 M allocations: 3.871 GiB, 15.10% gc time, 88065 lock conflicts, 0.03% compilation time)
    #   9.968372 seconds (87.17 M allocations: 4.119 GiB, 15.35% gc time, 84407 lock conflicts, 0.02% compilation time)
    #  10.134259 seconds (86.53 M allocations: 3.928 GiB, 18.11% gc time, 79525 lock conflicts, 0.02% compilation time)
end
```

## Results

Table. Benchmark of average elapsed time to schedule 10,000 and 100,000 tasks using different scheduling systems.

| Modules       | 10,000 Tasks | 100,000 Tasks |
| :------------ | -----------: | ------------: |
| Base.Threads  | 0.000477 s   |  0.001613 s   |
| JobSchedulers | 0.017108 s   |  0.237677 s   |
| Dagger        | 0.847789 s   |  9.707322 s   |

- JobSchedulers.jl can schedule 10,000 tasks within 0.02 second, which is 50X faster than Dagger.

- JobSchedulers.jl is robust, and able to achive a decent speed when scaling up to 100,000 tasks.

## Conclusions

- JobSchedulers.jl has a very little overhead (1~2 µs/job) and provides many great features than Base.Threads.

- The low overhead of JobSchedulers.jl makes it interchangable with Base.Threads.
