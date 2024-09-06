"""
    @submit! [option=value]... expr
    @submit [option=value]... expr

Submit a job from `expr`. If a `Job` is **explicitly** shown in `expr`, `DONE => job` will be automatically added to the dependency list. 

- `option = value`: kwargs of [`Job`](@ref).

!!! warn "Only explicit jobs can be automatically added to dependency"
    If a job is in a container, `@submit!` cannot know the elements in the container:
    ```julia
    j = @submit! 666

    jobs = Job[]  # the job container
    for i in 1:10
        push!(jobs, @submit! begin sleep(2);i end) # 10 jobs will be added to `jobs`
    end

    x = 0
    j_something_wrong = @submit! for j in jobs
        # have to use global x
        global x += result(j)
    end
    # ┌ Warning: Getting result from a running job: returned value might be unexpected.
    # └ @ JobSchedulers ~/projects/JobSchedulers.jl/src/jobs.jl:318

    result(j_something_wrong)
    # MethodError(+, (nothing, nothing), 0x0000000000007b16)

    x = 0
    j_ok = submit!(dependency = jobs) do
        for j in jobs
            # have to use global x
            global x += result(j)
        end
    end
    wait(j_ok)
    @assert x == 55

    x = 100
    j_ok_too = @submit! dependency = jobs for j in jobs
        # have to use global x
        global x += result(j)
    end
    wait(j_ok_too)
    @assert x == 155
    ```

See also [`Job`](@ref), [`submit!`](@ref)

## Example

```julia
j = @submit! 1+1
wait(j)
@assert result(j) == 2

# you can use any keyword arguments that `Job` supports, such as `name`, `ncpu`:
j_2sec = @submit! name = "run after 2 sec" begin sleep(2); 32 end

# because `j_2sec isa Job`, `DONE => j_2sec` is pushed to `j2.dependency`, and the `j_2sec` in the begin-end block is converted to `result(j_2sec)`:
j2 = @submit! mem=2KB begin
    1 + result(j_2sec)
end

wait(j2)
@assert result(j2) == 1 + 32

# you can also manually add dependencies that not in the `expr`:
j3 = @submit! dependency = [PAST => j] println("j3 finished. result of j2 = ", result(j2))

# Note: j3.dependency might be empty after submit, because JobScheduler will remove jobs that reached their states in the dependency list.
```
"""
macro submit!(args...)
    local opts = args[1:end-1]
    local expr = args[end]
    
    # construct Job(...)
    local params = opt2parameters(opts) # can esc

    # construct new_deps = [], and add deps in new_deps
    local possible_deps = sym_list(expr)  # Symbol[all symbols]
    unique!(possible_deps)
    local dep_struct = Expr(:ref, :Any, possible_deps...) # Any[possible_deps...]

    return quote
        local job = Job($(esc(params)), () -> $(esc(expr)))
        local deps = $(esc(dep_struct))
        filter!(isajob, deps)

        if !isempty(deps)
            for dep in deps
                push!(job.dependency, :done => dep)
            end            
        end
        @info job.dependency
        submit!(job)
    end
end

isajob(x::Job) = true
isajob(x) = false

function opt2parameters(opts::NTuple{N, Expr}) where N
    for opt in opts
        if opt.head === :(=)
            opt.head = :kw
        end
    end
    Expr(:parameters, opts...)
end

"""
    sym_list(x)

Extract var (symbols) in `var isa Job`.
"""
function sym_list(x)
    v = Vector{Symbol}()
    sym_list!(v, x)
    v
end

sym_list!(v::Vector, expr::Expr) = sym_list!(v, expr.args)
sym_list!(v::Vector, sym::Symbol) = push!(v, sym)
sym_list!(v::Vector, x) = nothing

function sym_list!(v::Vector, args::Vector)
    for arg in args
        sym_list!(v::Vector, arg)
    end
end