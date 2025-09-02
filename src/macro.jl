
"""
    @submit [option=value]... expr

Submit a job from `expr`. If a `Job` is **explicitly** shown in `expr`, `DONE => job` will be automatically added to the dependency list. 

- `expr`: any type of `Expr`ession is supported. 

- `option = value`: kwargs of [`Job`](@ref). If `expr` is parsed to be a `Pipelines.Program`, `option`s also include its inputs, outputs and run kwargs.

See also [`Job`](@ref), [`submit!`](@ref)

## Example

```julia
j = @submit 1+1
wait(j)
@assert result(j) == 2

# you can use any keyword arguments that `Job` supports, such as `name`, `ncpu`:
j_2sec = @submit name = "run after 2 sec" begin sleep(2); 32 end

# because `j_2sec isa Job`, `DONE => j_2sec` is pushed to `j2.dependency`.
j2 = @submit mem=2KB begin
    1 + result(j_2sec)
end

wait(j2)
@assert result(j2) == 1 + 32

# you can also manually add dependencies not in the `expr`:
j3 = @submit dependency = [PAST => j] println("j3 finished. result of j2 = ", result(j2))

# Note: j3.dependency might be empty after submit, because JobScheduler will remove jobs that reached their states in the dependency list.
```


!!! warning "Only explicit jobs can be automatically added to dependency"
    `@submit` cannot know the elements in a container, so it is unable to walk through and add Job dependencies in a container.
    ```julia
    jobs = Job[]  # the job container
    for i in 1:2
        push!(jobs, @submit begin sleep(30);i end) # 10 jobs will be added to `jobs`
    end

    x = 0
    j_something_wrong = @submit for j in jobs
        # have to use global x
        global x += result(j)
    end
    # ┌ Warning: Getting result from a running job: returned value might be unexpected.
    # └ @ JobSchedulers ~/projects/JobSchedulers.jl/src/jobs.jl:318

    result(j_something_wrong)
    # MethodError(+, (nothing, nothing), 0x0000000000007b16)
    ```
    
    To avoid it, we can 
         (1) use `submit!`, or
         (2) explicitly add `dependency = jobs` to `@submit`.
    
    ```julia
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
    j_ok_too = @submit dependency = jobs for j in jobs
        # have to use global x
        global x += result(j)
    end
    wait(j_ok_too)
    @assert x == 155
    ```
"""
macro submit(args...)
    local opts = args[1:end-1]
    local expr = args[end]
    
    # construct Job(...)
    local params = opt2parameters(opts)

    # construct new_deps = [], and add deps in new_deps
    local possible_deps = sym_list(expr)  # Symbol[all symbols]
    local dep_struct = Expr(:ref, :Any, possible_deps...) # Any[possible_deps...]

    # if expr is only a Symbol: it could be a Program
    local expr_is_a_symbol = expr isa Symbol

    return quote
        local job
        if $expr_is_a_symbol  # could be a program
            local evaluated = $(esc(expr))
            if evaluated isa Program
                job = Job($(esc(params)), evaluated)
                @goto submit
            else
                @goto normal
            end
        else
            @label normal
            local deps = $(esc(dep_struct))
            filter!(isajob, deps)
            job = Job($(esc(params)), () -> $(esc(expr)))

            if !isempty(deps)
                for dep in deps
                    push!(job.dependency, :done => dep)
                end
            end
            @label submit
            submit!(job)
        end
    end
end

macro yield_current(ex)
    return quote
        local res
        local job = current_job()
        if job === nothing || job.ncpu == 0
            res = $(esc(ex))
        else
            local ncpu = job.ncpu
            job.ncpu = 0.0

            res = $(esc(ex))  # no need to try catch. the job will be marked as failed if error happens so ncpu does not need to be restored.
            job.ncpu = ncpu
        end
        res
    end
end
@inline function yield_current(f::Function)
    @yield_current f()
end

@inline isajob(x::Job) = true
@inline isajob(x) = false
@inline isnotajob(x::Job) = false
@inline isnotajob(x) = true

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

Extract var (symbols) in expression/symbol.
"""
function sym_list(x)
    v = Vector{Symbol}()
    just_defined = Set()
    _sym_list!(v, just_defined, x)
    unique!(v)
    filter!(v) do x
        !(x in just_defined)
    end
    v
end

function _sym_list!(v::Vector, just_defined::Set, expr::Expr)
    if expr.head == :(=) && length(expr.args) == 2
        push!(just_defined, expr.args[1])
        # skip first arg
        _sym_list!(v, just_defined, expr.args[2])
    else
        _sym_list!(v, just_defined, expr.args)
    end
    expr
end
_sym_list!(v::Vector, just_defined::Set, sym::Symbol) = push!(v, sym)
_sym_list!(v::Vector, just_defined::Set, x) = nothing

function _sym_list!(v::Vector, just_defined::Set, args::Vector)
    for arg in args
        _sym_list!(v::Vector, just_defined, arg)
    end
end