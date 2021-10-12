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
"""
function Job(p::Program;
    name::AbstractString = p.name,
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Int64}}(),
    stdout=nothing,
    stderr=nothing,
    kwargs...
)
    julia_program_warn(p)
    task = @task run(p; stdout=stdout, stderr=stderr, kwargs...)
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
    dependency = Vector{Pair{Symbol,Int64}}(),
    stdout=nothing,
    stderr=nothing,
    kwargs...
)
    julia_program_warn(p)
    task = @task run(p, inputs; stdout=stdout, stderr=stderr, kwargs...)
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
    dependency = Vector{Pair{Symbol,Int64}}(),
    stdout=nothing,
    stderr=nothing,
    kwargs...
)
    julia_program_warn(p)
    task = @task run(p, inputs, outputs; stdout=stdout, stderr=stderr, kwargs...)
    stdout_file = format_stdxxx_file(stdout)
    stderr_file = format_stdxxx_file(stderr)

    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, stdout_file, stderr_file)
end

program_close_io = JuliaProgram(
    name = "Close Julia IO",
    id_file = ".close-julia-io",
    inputs = "io" => IO,
    main = (inputs, outputs) -> begin
        close(inputs["io"])
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
