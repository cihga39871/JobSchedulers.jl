"""
    @submit! [option=value]... expr
"""
macro submit!(args...)
    local opts = args[1:end-1]
    local expr = args[end]
    local params = opt2parameters(opts) # can esc
    local new_expr = result_if_job!(expr)
    local possible_deps = sym_list(new_expr)
 
    unique!(possible_deps)

    local add_deps = quote
        if length($possible_deps) > 0
            for dep in $possible_deps
                @show dep
                if dep isa Job
                    push!(job.dependency, DONE => dep2)
                end
            end
        end
    end

    return quote
        local job
        let e = $(esc(new_expr))
        local job = Job($(esc(params)), @task e)
        end
        $add_deps
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
    esc(:(@static if $sym isa Job
        result($sym)
    else
        $sym
    end))
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
function result_if_job!(x)
    x
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

function sym_list!(v::Vector, sym::Symbol)
end
function sym_list!(v::Vector, expr::Expr)
    sym_list!(v, expr.args)
end
function sym_list!(v::Vector, args::Vector)
    if length(args) == 3 && args[1] === :isa && args[3] === :Job && args[2] isa Symbol
        push!(v, args[2])
    else
        for arg in args
            sym_list!(v::Vector, arg)
        end
    end
end
function sym_list!(v::Vector, x)
end

