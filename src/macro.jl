"""
    @submit! [option=value]... expr

Submit the job. Options are kwargs of [`Job`](@ref). If a `Job` is in `expr`, `DONE => job` will be automatically added to the dependency list, and this job in expr will be replaced by `result(job)`  

> `submit!(Job(...))` can be simplified to `submit!(...)`. They are equivalent.

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
    1 + j_2sec
end

wait(j2)
@assert result(j2) == 1 + 32

# you can also manually add dependencies that not in the `expr`:
j3 = @submit! dependency = [j2, PAST => j] println("j3 finished")

# Note: j3.dependency might be empty after submit, because JobScheduler will remove jobs that reached their states in the dependency list
```
"""
macro submit!(args...)
    local opts = args[1:end-1]
    local expr = args[end]
    
    # construct Job(...)
    local params = opt2parameters(opts) # can esc
    local new_expr = result_if_job!(expr)
    local job_expr = Expr(:call, 
        :(JobSchedulers.Job),
        params,
        Expr(:(->),
            :(()),
            new_expr
        )
    )

    # construct new_deps = [], and add deps in new_deps
    local possible_deps = sym_list(new_expr)
    unique!(possible_deps)
    local new_dep_expr = quote
        local new_deps = JobSchedulers.Job[]
        for dep_sym in $possible_deps
            dep = try
                eval(dep_sym)
            catch
                @error :dep not found
                nothing
            end
            if dep isa JobSchedulers.Job
                push!(new_deps, dep)
            end
        end
        new_deps
    end

    return quote
        local job = $(esc(job_expr))
        local new_deps = $(esc(new_dep_expr))

        for dep in new_deps
            push!(job.dependency, DONE => dep)
        end
        submit!(job)
    end
end

function opt2parameters(opts::NTuple{N, Expr}) where N
    for opt in opts
        if opt.head === :(=)
            opt.head = :kw
        end
    end
    Expr(:parameters, opts...)
end

"""
    result_if_job!(x)

Scan `x` (an expression), if found any Symbol in args, replace the symbol with

```julia
@static if sym isa Job
    result(sym)
else
    sym
end
```
"""
function result_if_job!(sym::Symbol)
    :(@static if $sym isa JobSchedulers.Job
        JobSchedulers.result($sym)
    else
        $sym
    end)
end
function result_if_job!(expr::Expr)
    expr.args = result_if_job!(expr.args)
    expr
end
function result_if_job!(args::Vector)
    for (i, val) in enumerate(args)
        args[i] = result_if_job!(val)
    end
    args
end
result_if_job!(x) = x

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
sym_list!(v::Vector, x) = nothing
sym_list!(v::Vector, sym::Symbol) = nothing

function sym_list!(v::Vector, args::Vector)
    if length(args) == 3 && args[1] === :isa && args[2] isa Symbol && args[3] == :(JobSchedulers.Job)
        push!(v, args[2])
    else
        for arg in args
            sym_list!(v::Vector, arg)
        end
    end
end
