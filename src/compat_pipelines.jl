# using Pipelines
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
    task = @task run(p, inputs, outputs; stdout=stdout, stderr=stderr, kwargs...)
    stdout_file = format_stdxxx_file(stdout)
    stderr_file = format_stdxxx_file(stderr)

    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, stdout_file, stderr_file)
end
