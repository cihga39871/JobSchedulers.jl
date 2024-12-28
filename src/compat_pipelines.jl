# using Pipelines

function julia_program_warn(::JuliaProgram)
    if nthreads() == 1
        @warn "Submitting a JuliaProgram with 1-threaded Julia session is not recommended because it might block schedulers and parallel jobs. Starting Julia with multi-threads is suggested. Help: https://docs.julialang.org/en/v1/manual/multi-threading/#Starting-Julia-with-multiple-threads" maxlog=1
    end
end
julia_program_warn(::CmdProgram) = nothing

"""
    Job(p::Program; kwargs...)
    Job(p::Program, inputs; kwargs...)
    Job(p::Program, inputs, outputs; kwargs...)

Create `Job` by using `Program` from Pipelines.jl package.
The 3 methods are wrappers around `run(::Program, ...)` defined in Pipelines.jl.

`kwargs...` include keyword arguments of `Job(::BaseAbstractCmd, ...)` and `run(::Program, ...)`.

See also: [`run`](@ref)
"""
function Job(p::Program;
    name::AbstractString = p.name,
    user::AbstractString = "",
    ncpu::Real = 1.0,
    mem::Int = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Year(1),
    cron::Cron = Cron(:none),
    until::Union{DateTime,Period} = DateTime(9999),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Union{Int,Job}}}(),
    stdout = nothing,
    stderr = nothing,
    dir::AbstractString = "",
    _warn::Bool = true,
    kwargs...
)
    if _warn
        julia_program_warn(p)
    end

    inputs, outputs, kws = Pipelines.parse_program_args(p; kwargs...)
    inputs, outputs = Pipelines.xxputs_completion_and_check(p, inputs, outputs)

    if !isempty(p.arg_forward)
        for pair in p.arg_forward
            val = if haskey(inputs, pair.first)
                inputs[pair.first]
            else
                outputs[pair.first]
            end
            if pair.second == :name
                if name == p.name
                    name = string(val)
                end
            elseif pair.second == :user
                if user == ""
                    user = string(val)
                end
            elseif pair.second == :ncpu
                if ncpu == 1
                    ncpu = val isa Number ? Float64(val) : parse(Float64, val)
                end
            elseif pair.second == :mem
                if mem == 0
                    mem = val isa Number ? Int(val) : parse(Int, val)
                end
            end
        end
    end

    f() = run(p; 
        _do_parse_program_args=false, 
        _do_xxputs_completion_and_check=false,
        inputs=inputs, outputs=outputs, stdout=stdout, stderr=stderr, dir=abspath(dir), 
        kws...
    )
    job = Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, cron, until, QUEUING, priority, dependency, nothing, stdout, stderr, 0, f, false)

    task = @task begin
        try
            res = f()
            if res isa Pipelines.StackTraceVector
                unsafe_update_as_failed!(job)
            else
                unsafe_update_as_done!(job)
            end
            res
        catch e
            unsafe_update_as_failed!(job)
            rethrow(e)
        finally
            scheduler_need_action()
        end
    end

    job.task = task
    job
end

function Job(p::Program, inputs; kwargs...)
    Job(p::Program; inputs=inputs, kwargs...)
end

function Job(p::Program, inputs, outputs; kwargs...)
    Job(p::Program; inputs=inputs, outputs=outputs, kwargs...)
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
    close_in_future(io::IO, job::Job; kwargs...)
    close_in_future(io::IO, jobs::Vector{Job}; kwargs...)

Close `io` after `job` is in PAST status (either DONE/FAILED/CANCELLED). It is userful if jobs uses `::IO` as `stdout` or `stderr`, because the program will not close `::IO` manually!

`kwargs...` include keyword arguments of `Job(::BaseAbstractCmd, ...)` and `run(::Program, ...)`.

"""
function close_in_future(io::IO, job::Job; kwargs...)
    close_job = Job(program_close_io, "io" => io, kwargs..., touch_run_id_file=false, dependency = [PAST => job])
    submit!(close_job)
    close_job
end
function close_in_future(io::IO, jobs::Vector{Job}; kwargs...)
    deps = [PAST => x for x in jobs]
    close_job = Job(program_close_io, "io" => io, kwargs..., touch_run_id_file=false, dependency = deps)
    submit!(close_job)
    close_job
end
