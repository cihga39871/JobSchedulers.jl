
"""
    Job(command::Base.AbstractCmd; stdout=nothing, stderr=nothing, append::Bool=false, kwargs...)

## Arguments

- `command::Base.AbstractCmd`: it should not redirect to stdout or stderr. Define stdout and stderr in this function.
- `stdout=nothing`: redirect stdout to the file.
- `stderr=nothing`: redirect stderr to the file.
- `append::Bool=false`: append the stdout or stderr or not.
- `kwargs...`: the keyword arguments listed in the following method.

---------------

    Job(task::Task;
        id::Int = now().instant.periods.value,
        name::AbstractString = "",
        user::AbstractString = "",
        ncpu::Int64 = 1,
        create_time::DateTime = DateTime(0),
        start_time::DateTime = DateTime(0),
        stop_time::DateTime = DateTime(0),
        wall_time::Period = Week(1),
        state::Symbol = :queueing,
        priority::Int = 20
    )

---------------

## Fields of type `Job`
 - `id::Int`
 - `name::String`
 - `user::String`
 - `ncpu::Int64`
 - `create_time::DateTime`
 - `start_time::DateTime`
 - `stop_time::DateTime`
 - `wall_time::Period`: the type is one of `Union{Millisecond,Second,Minute,Hour,Day,Week}`
 - `state::Symbol`: one of `:queueing`, `:running`, `:done`, `:failed`, `:cancelled`
 - `priority::Int`: lower means higher priority, default is 20.
 - `task::Task`
 - `stdout_file::String`: only valid when call from Job(::Base.AbstractCmd; stdout="outfile", kwargs...)
 - `stderr_file::String`: only valid when call from Job(::Base.AbstractCmd; stderr="errfile", kwargs...)
"""
mutable struct Job
    id::Int
    name::String
    user::String
    ncpu::Int64
    create_time::DateTime
    start_time::DateTime
    stop_time::DateTime
    wall_time::Period
    state::Symbol
    priority::Int
    task::Task
    stdout_file::String
    stderr_file::String

    function Job(id::Int, name::String, user::String, ncpu::Int64, create_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, state::Symbol, priority::Int, task::Task, stdout_file::String, stderr_file::String)
        if !(typeof(wall_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.wall_time is not one of Union{Millisecond,Second,Minute,Hour,Day,Week}")
        end
        new(id, name, user, ncpu, create_time, start_time, stop_time, wall_time, state, priority, task, stdout_file, stderr_file)
    end
end


### Job

function Job(task::Task;
    id::Int = now().instant.periods.value,
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Int64 = 1,
    create_time::DateTime = DateTime(0),
    start_time::DateTime = DateTime(0),
    stop_time::DateTime = DateTime(0),
    wall_time::Period = Week(1),
    state::Symbol = QUEUEING,
    priority::Int = 20,
    stdout_file = "",
    stderr_file = ""
)
    Job(id, name, user, ncpu, create_time, start_time, stop_time, wall_time, state, priority, task, stdout_file, stderr_file)
end
function Job(command::Base.AbstractCmd;
    stdout=nothing, stderr=nothing, append::Bool=false,
    id::Int = now().instant.periods.value,
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Int64 = 1,
    create_time::DateTime = DateTime(0),
    start_time::DateTime = DateTime(0),
    stop_time::DateTime = DateTime(0),
    wall_time::Period = Week(1),
    state::Symbol = QUEUEING,
    priority::Int = 20
)
    task = @task run(pipeline(command, stdout=stdout, stderr=stderr, append=append))
    stdout_file = isnothing(stdout) ? "" : stdout
    stderr_file = isnothing(stderr) ? "" : stderr
    Job(task; stdout_file=stdout_file, stderr_file=stderr_file, id=id, name=name, user=user, ncpu=ncpu, create_time=create_time, start_time=start_time, stop_time=stop_time, wall_time=wall_time, state=state, priority=priority)
end
