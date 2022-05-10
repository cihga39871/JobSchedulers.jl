# using Pipelines

function julia_program_warn(p::JuliaProgram)
    if nthreads() == 1
        @warn "Submitting a JuliaProgram with 1-threaded Julia session is not recommended because it might block schedulers. Starting Julia with multi-threads is suggested. Help: https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads" maxlog=1
    end
end
julia_program_warn(p::CmdProgram) = nothing

"""
    Job(p::Program; kwargs...)
    Job(p::Program, inputs; kwargs...)
    Job(p::Program, inputs, outputs; kwargs...)

Create `Job` by using `Program` from Pipelines.jl package.
The 3 methods are a wrapper around `run(::Program, ...)`.

`kwargs...` include keyword arguments of `Job(::BaseAbstractCmd, ...)` and `run(::Program, ...)`.

See also [`@Job`](@ref), [`run`](@ref), [`@run`](@ref), [`@vars`](@ref)

"""
function Job(p::Program;
    name::AbstractString = p.name,
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Union{Int64,Job}}}(),
    stdout = nothing,
    stderr = nothing,
    dir::AbstractString = "",
    kwargs...
)
    julia_program_warn(p)
    task = @task run(p; stdout=stdout, stderr=stderr, dir=abspath(dir), kwargs...)
    stdout_file = format_stdxxx_file(stdout)
    stderr_file = format_stdxxx_file(stderr)

    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, stdout_file, stderr_file)
end

function Job(p::Program, inputs;
    name::AbstractString = p.name,
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Union{Int64, Job}}}(),
    stdout = nothing,
    stderr = nothing,
    dir::AbstractString = "",
    kwargs...
)
    julia_program_warn(p)
    task = @task run(p, inputs; stdout=stdout, stderr=stderr, dir=abspath(dir), kwargs...)
    stdout_file = format_stdxxx_file(stdout)
    stderr_file = format_stdxxx_file(stderr)

    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, stdout_file, stderr_file)
end

function Job(p::Program, inputs, outputs;
    name::AbstractString = p.name,
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Union{Int64, Job}}}(),
    stdout = nothing,
    stderr = nothing,
    dir::AbstractString = "",
    kwargs...
)
    julia_program_warn(p)
    task = @task run(p, inputs, outputs; stdout=stdout, stderr=stderr, dir=abspath(dir), kwargs...)
    stdout_file = format_stdxxx_file(stdout)
    stderr_file = format_stdxxx_file(stderr)

    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, stdout_file, stderr_file)
end

"""
    @Job program::Program key_value_args... Job_args...

Run `program` without creating `inputs::Dict` and `outputs::Dict`.

- `key_value_args`: the inputs and outputs are provided in the form of `key = value`, rather than `Dict`.

- `Job_args`: the keyword arguments pass to `Job(p::Program, inputs, outputs, Job_args...)`.

See also [`Job`](@ref), [`run`](@ref), [`@run`](@ref), [`@vars`](@ref)

### Example
```julia
jp = JuliaProgram(
	name = "Echo",
	id_file = "id_file",
	inputs = [
		"input",
		"input2" => Int,
		"optional_arg" => 5,
		"optional_arg2" => 0.5 => Number
	],
	outputs = [
		"output" => "<input>.output"
	],
	main = (x,y) -> begin
		@show x
		@show y
		y
	end
)

i = "iout"
kk = :xxx
b = false
commonargs = (touch_run_id_file = b, verbose = :min)
job = @Job jp input=kk input2=22 optional_arg=:sym output=i commonargs...
submit!(job)
result(job)
# (true, Dict{String, Any}("output" => "iout"))
```
"""
macro Job(program, args...)
    return quote
        local p = $(esc(program))
        if !(p isa Program)
            error("The first argument of @Job should be a ::Program")
        end
        local inputs = Dict{String,Any}()
        local outputs = Dict{String,Any}()
        local args = [($args)...]
        local narg = length(args)
        local kw_args = Vector{Any}()  # keyword parameters of other functions, such as run, Job.
        local i = 1
        while i <= narg
            local arg = args[i]
            if arg.head === :(=)
                local key = string(arg.args[1])
                local val = arg.args[2]

                if key in p.inputs
                    setindex!(inputs, Core.eval(@__MODULE__, val), key)
                elseif key in p.outputs
                    setindex!(outputs, Core.eval(@__MODULE__, val), key)
                else  # may be keyword parameters of other functions, such as run, Job.
                    arg.head = :kw  # keyword head is :kw, rather than :(=)
                    if !(val isa QuoteNode) # QuoteNode: such as :(:sym)
                        arg.args[2] = Core.eval(@__MODULE__, val)
                    end
                    push!(kw_args, arg)
                end
            elseif arg.head == :(...)  # common_args...
                local extra_args = Core.eval(@__MODULE__, arg.args[1])
                local extra_args_keys = keys(extra_args)
                local extra_args_vals = values(extra_args)
                local nextra = length(extra_args_keys)
                for m in 1:nextra
                    local k = extra_args_keys[m]
                    local v = extra_args_vals[m]
                    if v isa Symbol
                        v = QuoteNode(v)  # no interpolation of Symbol
                    end
                    push!(args, Expr(:(=), k, v))
                end
                narg = length(args)
            else
                error("SyntaxError: args only support `key = value` form: $arg")
            end
            i += 1
        end

        local ex_kw = Expr(:parameters, kw_args...)
        local ex = :(Job($p, $inputs, $outputs))
        insert!(ex.args, 2, ex_kw)  # insert keyword arguments to ex
        eval(ex)
    end
end

program_close_io = JuliaProgram(
    name = "Close Julia IO",
    id_file = ".close-julia-io",
    inputs = "io" => IO,
    main = (inputs, outputs) -> begin
        close(inputs["io"])
        if inputs["io"] == Base.stdout
            Pipelines.restore_stdout()
        end
        if inputs["io"] == Base.stderr
            Pipelines.restore_stderr()
        end
        Dict{String,Any}()
    end
)

"""
    close_in_future(io::IO, job::Job)
    close_in_future(io::IO, jobs::Vector{Job})

Close `io` after `job` is in PAST status (either DONE/FAILED/CANCELLED). It is userful if jobs uses `::IO` as `stdout` or `stderr`, because the program will not close `::IO` manually!
"""
function close_in_future(io::IO, job::Job)
    close_job = Job(program_close_io, "io" => io, touch_run_id_file=false, dependency = [PAST => job.id])
    submit!(close_job)
    close_job
end
function close_in_future(io::IO, jobs::Vector{Job})
    deps = [PAST => x.id for x in jobs]
    close_job = Job(program_close_io, "io" => io, touch_run_id_file=false, dependency = deps)
    submit!(close_job)
    close_job
end
