"""
    generate_id() :: Int64

Generate ID. It is unique in most instances.
"""
function generate_id()
    time_value = (now().instant.periods.value - 63749462400000) << 16
    rand_value = rand(UInt16)
    time_value + rand_value
end

"""
    Job(command::Base.AbstractCmd; stdout=nothing, stderr=nothing, append::Bool=false, kwargs...)
    Job(task::Task; kwargs...)

# Special Arguments of `Job(::Base.AbstractCmd; ...)`

- `command::Base.AbstractCmd`: it should not redirect to stdout or stderr. Define stdout and stderr in this function.
- `stdout=nothing`: redirect stdout to the file.
- `stderr=nothing`: redirect stderr to the file.
- `append::Bool=false`: append the stdout or stderr or not.
- `kwargs...`: the keyword arguments listed in the following method.

# Common Keyword Arguments (kwargs...)

 - `name::String = ""`: job name.
 - `user::String = ""`: user that job belongs to.
 - `ncpu::Int64 = 1`: number of CPU this job is about to use.
 - `mem::Int64 = 0`: number of memory this job is about to use (supports TB, GB, MB, KB, B=1).
 - `schedule_time::Union{DateTime,Period} = DateTime(0)`: The expected time to run.
 - `wall_time::Period = Week(1)`: wall clock time limit.
 - `priority::Int = 20`: lower means higher priority.
 - `dependency::Vector{Pair{Symbol,Int64}}`: defer job until specified jobs reach specified state (QUEUING, RUNNING, DONE, FAILED, CANCELLED).
"""
mutable struct Job
    id::Int64
    name::String
    user::String
    ncpu::Int64
    mem::Int64
    schedule_time::DateTime
    create_time::DateTime
    start_time::DateTime
    stop_time::DateTime
    wall_time::Period
    state::Symbol
    priority::Int
    dependency::Vector{Pair{Symbol,Int64}}
    task::Union{Task,Nothing}
    stdout_file::String
    stderr_file::String

    function Job(id::Int64, name::String, user::String, ncpu::Int64, mem::Int64, schedule_time::DateTime, create_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, state::Symbol, priority::Int, dependency::Vector{Pair{Symbol,Int64}}, task::Union{Task,Nothing}, stdout_file::String, stderr_file::String)
        if !(typeof(wall_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.wall_time is not one of Union{Millisecond,Second,Minute,Hour,Day,Week}")
        end
        new(id, name, user, ncpu, mem, schedule_time, create_time, start_time, stop_time, wall_time, state, priority, dependency, task, stdout_file, stderr_file)
    end

    function Job(id::Int64, name::String, user::String, ncpu::Int64, mem::Int64, schedule_time::Period, create_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, state::Symbol, priority::Int, dependency::Vector{Pair{Symbol,Int64}}, task::Union{Task,Nothing}, stdout_file::String, stderr_file::String)
        if !(typeof(wall_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.wall_time is not one of Union{Millisecond,Second,Minute,Hour,Day,Week}")
        end
        if !(typeof(schedule_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.schedule_time is not one of Union{DateTime,Millisecond,Second,Minute,Hour,Day,Week}")
        end
        new(id, name, user, ncpu, mem, now() + schedule_time, create_time, start_time, stop_time, wall_time, state, priority, dependency, task, stdout_file, stderr_file)
    end
end


### Job

function Job(task::Task;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency::Vector{Pair{Symbol,Int64}} = Vector{Pair{Symbol,Int64}}()
)
    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, "", "")
end

function Job(command::Base.AbstractCmd;
    stdout=nothing, stderr=nothing, append::Bool=false,
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency::Vector{Pair{Symbol,Int64}} = Vector{Pair{Symbol,Int64}}()
)
    task = @task run(pipeline(command, stdout=stdout, stderr=stderr, append=append))
    stdout_file = isnothing(stdout) ? "" : stdout
    stderr_file = isnothing(stderr) ? "" : stderr
    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, stdout_file, stderr_file)
end

function result(job::Job)
    if job.state !== DONE
        @warn "Getting result from a $(job.state) job: returned value might be unexpected."
    end
    job.task.result
end
