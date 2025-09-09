
"""
    @submit [option=value]... expr

Submit a job from `expr`. If a `Job` is **explicitly** shown in `expr`, `DONE => job` will be automatically added to the dependency list. 

- `expr`: any type of `Expr`ession. Eg: `1+2`, `length(ARGS)`, `begin ... end`

- `option = value`: kwargs of [`Job`](@ref). If `expr` is parsed to be a `Pipelines.Program`, `option`s also include its inputs, outputs and run kwargs.

See also [`Job`](@ref), and [`submit!`](@ref) for detailed kwargs.

If using `Pipelines`, see also `JuliaProgram`, `CmdProgram`, and `run` for their kwargs.

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

    if expr_is_a_symbol  # could be a program
        return quote
            local evaluated = $(esc(expr))
            if evaluated isa Program
                local job = Job($(esc(params)), evaluated)
                return submit!(job)
            end

            # same as if not expr_is_a_symbol
            local deps = $(esc(dep_struct))
            filter!(isajob, deps)
            local job = Job($(esc(params)), () -> $(esc(expr)))

            if !isempty(deps)
                for dep in deps
                    push!(job.dependency, :done => dep)
                end
            end
            submit!(job)
        end
    else
        return quote
            local deps = $(esc(dep_struct))
            filter!(isajob, deps)
            local job = Job($(esc(params)), () -> $(esc(expr)))

            if !isempty(deps)
                for dep in deps
                    push!(job.dependency, :done => dep)
                end
            end
            submit!(job)
        end
    end
end

"""
    @yield_current expr

Used to prevent wasting threads and even blocking JobScheduler when submitting jobs within jobs.

If `@yield_current` is not called within a job's scope, `expr` will be evaluated as it is.

If `@yield_current` is called within a `Job`'s scope, this `Job` is considered as the [`current_job`](@ref).

And within the `expr` block, the current job's `ncpu` is temporarily set to `0`, and the thread of the current job can be occupied by any child jobs (including **grand-child** jobs). 

Once leaving the `expr` block, the current job's `ncpu` is resumed, and its thread is not able to be occupied.

Therefore, the child jobs need to be submitted and **waited** within the `expr` block. 

Example:

```julia
using JobSchedulers

parent_job = Job(ncpu=1) do
    # imagine preparing A and B takes lots of time
    A = 0
    B = 0

    # compute A and B in parallel (imagine they take lots of time)
    @yield_current begin
        child_job_A = @submit A += 100
        child_job_B = @submit B += 1000
        wait(child_job_A)
        wait(child_job_B)
    end

    # do computation based on results of child jobs 
    return A + B
end

submit!(parent_job)
res = fetch(parent_job)
# 1100
```

If not using `@yield_current`, the thread taken by the current job is wasted when waiting. 

In an extreme condition, the JobScheduler can be **blocked** if all threads are taken by parent jobs, and if their child jobs do not have any threads to run.

To experience the blockage, you can start Julia with `julia -t 1,1`, and run the example code without `@yield_current`. You may kill the julia session by pressing Ctrl+C 10 times.

!!! compat
    `@yield_current` is available from v0.11.11.
"""
macro yield_current(ex)
    return quote
        local res  # COV_EXCL_LINE
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

"""
    yield_current(f::Function) = @yield_current f()

The function version of [`@yield_current`](@ref). 

Prevent wasting threads and even blocking JobScheduler when submitting jobs within jobs.

!!! compat
    `yield_current` is available from v0.11.11.

See details at [`@yield_current`](@ref).
"""
@inline function yield_current(f::Function)
    @yield_current f()
end

@inline isajob(x::Job) = true      # COV_EXCL_LINE
@inline isajob(x) = false          # COV_EXCL_LINE
@inline isnotajob(x::Job) = false  # COV_EXCL_LINE
@inline isnotajob(x) = true        # COV_EXCL_LINE

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
_sym_list!(v::Vector, just_defined::Set, x) = nothing  # COV_EXCL_LINE

function _sym_list!(v::Vector, just_defined::Set, args::Vector)
    for arg in args
        _sym_list!(v::Vector, just_defined, arg)
    end
end