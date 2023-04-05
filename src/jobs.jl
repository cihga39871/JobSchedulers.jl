"""
    generate_id() :: Int64

Generate ID. It is unique in most instances.
"""
function generate_id()
    time_value = (now().instant.periods.value - 63749462400000) << 16
    rand_value = rand(UInt16)
    time_value + rand_value
end

format_stdxxx_file(::Nothing) = ""
format_stdxxx_file(x::String) = x
format_stdxxx_file(x::AbstractString) = convert(String, x)
format_stdxxx_file(x::IOStream) = x.name[7:end-1]
format_stdxxx_file(x) = ""

function check_ncpu_mem(ncpu::Int64, mem::Int64)
    if ncpu < 1
        error("ncpu < 1 is not supported for Job")
    end
    if mem < 0
        error("mem < 1 is not supported for Job")
    end
end

"""
    Job(command::Base.AbstractCmd; stdout=nothing, stderr=nothing, append::Bool=false, kwargs...)
    Job(f::Function; kwargs...)
    Job(task::Task; kwargs...)

# Arguments

- `command::Base.AbstractCmd`: the command to run.
- `f::Function`: the function to run without any arguments, like `f()`.
- `task::Task`: the task to run. Eg: `@task(1+1)`.

# Common Keyword Arguments (kwargs...)

 - `name::String = ""`: job name.
 - `user::String = ""`: user that job belongs to.
 - `ncpu::Int64 = 1`: number of CPU this job is about to use.
 - `mem::Int64 = 0`: number of memory this job is about to use (supports TB, GB, MB, KB, B=1).
 - `schedule_time::Union{DateTime,Period} = DateTime(0)`: The expected time to run.
 - `dependency`: defer job until specified jobs reach specified state (QUEUING, RUNNING, DONE, FAILED, CANCELLED, PAST). PAST is the super set of DONE, FAILED, CANCELLED, which means the job will not run in the future. Eg: `DONE => job`, `[DONE => job1; PAST => job2]`.

 > To be compatible with old versions, you can also use job id (Int): `[DONE => job.id]`.

 - `wall_time::Period = Week(1)`: wall clock time limit.
 - `priority::Int = 20`: lower means higher priority.

# Experimental Keyword Arguments - Output Redirection:

 - `stdout=nothing`: redirect stdout to the file.
 - `stderr=nothing`: redirect stderr to the file.
 - `append::Bool=false`: append the stdout or stderr or not.

!!! note
    Redirecting in Julia are not thread safe, so unexpected redirection might be happen if you are running programs in different `Tasks` simultaneously (multi-threading).
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
    dependency::Vector{Pair{Symbol,Union{Int64, Job}}}
    task::Union{Task,Nothing}
    stdout_file::String
    stderr_file::String
    _thread_id::Int

    # original
    function Job(id::Int64, name::String, user::String, ncpu::Int64, mem::Int64, schedule_time::DateTime, create_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, state::Symbol, priority::Int, dependency::Vector, task::Union{Task,Nothing}, stdout_file::String, stderr_file::String)
        if !(typeof(wall_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.wall_time is not one of Union{Millisecond,Second,Minute,Hour,Day,Week}")
        end
        check_ncpu_mem(ncpu, mem)
        dependency = convert(Vector{Pair{Symbol,Union{Int64, Job}}}, dependency)
        new(id, name, user, ncpu, mem, schedule_time, create_time, start_time, stop_time, wall_time, state, priority, dependency, task, stdout_file, stderr_file, 0)
    end

    # schedule_time::Period
    function Job(id::Int64, name::String, user::String, ncpu::Int64, mem::Int64, schedule_time::Period, create_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, state::Symbol, priority::Int, dependency::Vector, task::Union{Task,Nothing}, stdout_file::String, stderr_file::String)
        if !(typeof(wall_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.wall_time is not one of Union{Millisecond,Second,Minute,Hour,Day,Week}")
        end
        if !(typeof(schedule_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.schedule_time is not one of Union{DateTime,Millisecond,Second,Minute,Hour,Day,Week}")
        end
        check_ncpu_mem(ncpu, mem)
        dependency = convert(Vector{Pair{Symbol,Union{Int64, Job}}}, dependency)
        new(id, name, user, ncpu, mem, now() + schedule_time, create_time, start_time, stop_time, wall_time, state, priority, dependency, task, stdout_file, stderr_file, 0)
    end

    # dependency::Pair{Symbol,Int64}
    function Job(id::Int64, name::String, user::String, ncpu::Int64, mem::Int64, schedule_time::DateTime, create_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, state::Symbol, priority::Int, dependency::Pair{Symbol,T}, task::Union{Task,Nothing}, stdout_file::String, stderr_file::String) where T
        if !(typeof(wall_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.wall_time is not one of Union{Millisecond,Second,Minute,Hour,Day,Week}")
        end
        check_ncpu_mem(ncpu, mem)
        dependency = Pair{Symbol,Union{Int64, Job}}[dependency]
        new(id, name, user, ncpu, mem, schedule_time, create_time, start_time, stop_time, wall_time, state, priority, dependency, task, stdout_file, stderr_file, 0)
    end

    # schedule_time::Period
    # dependency::Pair{Symbol,Int64}
    function Job(id::Int64, name::String, user::String, ncpu::Int64, mem::Int64, schedule_time::Period, create_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, state::Symbol, priority::Int, dependency::Pair{Symbol,T}, task::Union{Task,Nothing}, stdout_file::String, stderr_file::String) where T
        if !(typeof(wall_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.wall_time is not one of Union{Millisecond,Second,Minute,Hour,Day,Week}")
        end
        if !(typeof(schedule_time) <: Union{Millisecond,Second,Minute,Hour,Day,Week})
            error("Job.schedule_time is not one of Union{DateTime,Millisecond,Second,Minute,Hour,Day,Week}")
        end
        check_ncpu_mem(ncpu, mem)
        dependency = Pair{Symbol,Union{Int64, Job}}[dependency]
        new(id, name, user, ncpu, mem, now() + schedule_time, create_time, start_time, stop_time, wall_time, state, priority, dependency, task, stdout_file, stderr_file, 0)
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
    dependency = Vector{Pair{Symbol,Int64}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    if ncpu > 1
        @warn "ncpu != 1 for Job(task::Task) is not fully supported by JobScheduler. If a task uses multi-threads, it is recommended to split it into different jobs. Job: $name." maxlog=1
    end
    task2 = @task Pipelines.redirect_to_files(stdout, stderr; mode = append ? "a+" : "w+") do
        task.code()
    end
    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task2, "", "")
end

function Job(f::Function;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Int64}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    if ncpu != 1
        @warn "ncpu != 1 for Job(task::Task) is not fully supported by JobScheduler. If a task uses multi-threads, it is recommended to split it into different jobs. Job: $name." maxlog=1
    end
    task2 = @task Pipelines.redirect_to_files(stdout, stderr; mode = append ? "a+" : "w+") do
        f()
    end
    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task2, "", "")
end

function Job(command::Base.AbstractCmd;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Int64 = 1,
    mem::Int64 = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Week(1),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Int64}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    task = @task Pipelines.redirect_to_files(stdout, stderr; mode = append ? "a+" : "w+") do
        run(command)
    end
    stdout_file = format_stdxxx_file(stdout)
    stderr_file = format_stdxxx_file(stderr)
    Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, QUEUING, priority, dependency, task, stdout_file, stderr_file)
end

"""
    result(job::Job)

Return the result of `job`. If the job is not done, a warning message will also show.
"""
function result(job::Job)
    if job.state !== DONE
        @warn "Getting result from a $(job.state) job: returned value might be unexpected."
    end
    job.task.result
end

get_thread_id(job::Job) = job._thread_id
get_priority(job::Job) = job.priority

"""
    solve_optimized_ncpu(default::Int; 
        ncpu_range::UnitRange{Int64} = 1:total_cpu, 
        njob::Int = 1, 
        total_cpu::Int = JobSchedulers.SCHEDULER_MAX_CPU, 
        side_jobs_cpu::Int = 0)

Find the optimized number of CPU for a job.

- `default`: default ncpu of the job.
- `ncpu_range`: the possible ncpu range of the job.
- `njob`: number of the same job.
- `total_cpu`: the total CPU that can be used by JobSchedulers.
- `side_jobs_cpu`: some small jobs that might be run when the job is running, so the job won't use up all of the resources and stop small tasks.
"""
function solve_optimized_ncpu(default::Int; njob::Int = 1, total_cpu::Int = JobSchedulers.SCHEDULER_MAX_CPU, ncpu_range::UnitRange{Int64} = 1:total_cpu, side_jobs_cpu::Int = 0)
    mincpu = max(ncpu_range.start, 1)
    maxcpu = ncpu_range.stop
    if !(mincpu <= maxcpu <= total_cpu)
        return max(1, default)
    end

    if default > maxcpu
        default = maxcpu
    elseif default < mincpu
        default = mincpu
    end

    if njob == 1
        n1 = (total_cpu - side_jobs_cpu)
        return min(max(n1, default, mincpu), maxcpu)
    elseif njob > 1
        njob_batch = round(Int, total_cpu / default)
        njob_batch = min(njob, njob_batch)
        n1 = (total_cpu - side_jobs_cpu) ÷ njob_batch
        return min(max(n1, mincpu), maxcpu)
    else
        return max(1, default)
    end
end
