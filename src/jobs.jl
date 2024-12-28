
const JOB_ID = Ref{Int}()
const JOB_ID_INCREMENT_LOCK = ReentrantLock()
"""
    generate_id() :: Int

Generate an unique ID.
"""
function generate_id()
    lock(JOB_ID_INCREMENT_LOCK) do
        JOB_ID[] += 1
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
- `ncpu::Real = 1.0`: number of CPU this job is about to use (can be `Float64`, eg: `1.5` will use 150% CPU).
- `mem::Int = 0`: number of memory this job is about to use (supports TB, GB, MB, KB, B=1).
- `schedule_time::Union{DateTime,Period} = DateTime(0)`: The expected time to run.
- `dependency`: defer job until specified jobs reach specified state (QUEUING, RUNNING, DONE, FAILED, CANCELLED, PAST). PAST is the super set of DONE, FAILED, CANCELLED, which means the job will not run in the future. Eg: `DONE => job`, `[DONE => job1; PAST => job2]`.

!!! info "Dependency"
    The default state is DONE, so `DONE => job` can be simplified to `job`.  
    To be compatible with old versions, you can also use job id (Int): `[DONE => job.id]`.  
    JobSchedulers will remove jobs that reached their states in the dependency list.

- `wall_time::Period = Year(1)`: wall clock time limit. Jobs will be terminated after running for this period.
- `priority::Int = 20`: lower means higher priority.

- `cron::Cron = Cron(:none)`: job recurring at specfic date and time. See more at [`Cron`](@ref).
- `until::Union{DateTime,Period} = DateTime(9999,1,1)`: stop job recurring `until` date and time.

# Experimental Keyword Arguments - Output Redirection:

- `stdout=nothing`: redirect stdout to the file.
- `stderr=nothing`: redirect stderr to the file.
- `append::Bool=false`: append the stdout or stderr or not.

!!! note
    Redirecting in Julia are not thread safe, so unexpected redirection might be happen if you are running programs in different `Tasks` simultaneously (multi-threading).

See also [`submit!`](@ref), [`@submit`](@ref), [`Cron`](@ref)
"""
mutable struct Job
    id::Int
    name::String
    user::String
    ncpu::Float64
    mem::Int
    schedule_time::DateTime
    submit_time::DateTime
    start_time::DateTime
    stop_time::DateTime
    wall_time::Period
    cron::Cron
    until::DateTime
    state::Symbol
    priority::Int
    dependency::Vector{Pair{Symbol,Union{Int, Job}}}
    task::Union{Task,Nothing}
    stdout::Union{IO,AbstractString,Nothing}
    stderr::Union{IO,AbstractString,Nothing}
    _thread_id::Int
    _func::Union{Function,Nothing}
    _need_redirect::Bool
    _group::String
    _group_state::Symbol

    function Job(id::Int, name::String, user::String, ncpu::Real, mem::Int, schedule_time::ST, submit_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, cron::Cron, until::ST2, state::Symbol, priority::Int, dependency, task::Union{Task,Nothing}, stdout::Union{IO,AbstractString,Nothing}, stderr::Union{IO,AbstractString,Nothing}, _thread_id::Int, _func::Union{Function,Nothing}, _need_redirect::Bool = check_need_redirect(stdout, stderr), _group::AbstractString = "") where {ST<:Union{DateTime,Period}, ST2<:Union{DateTime,Period}}
        check_ncpu_mem(ncpu, mem)
        check_priority(priority)
        new(id, name, user, Float64(ncpu), mem, period2datetime(schedule_time), submit_time, start_time, stop_time, wall_time, cron, period2datetime(until), state, priority, convert_dependency(dependency), task, stdout, stderr, _thread_id, _func, _need_redirect, _group, :nothing)
    end
end


### Job

function Job(task::Task;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Real = 1.0,
    mem::Int = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Year(1),
    cron::Cron = cron_none,
    until::Union{DateTime,Period} = DateTime(9999),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Int}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    if ncpu > 1.001
        @warn "ncpu > 1 for Job(task::Task) is not fully supported if the task uses multi-threads (except for running threaded commands), it is recommended to split it into different jobs. Job: $name." maxlog=1
    end
    
    need_redirect = check_need_redirect(stdout, stderr)

    job = Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, cron, until, QUEUING, priority, dependency, nothing, stdout, stderr, 0, task.code, need_redirect)

    if need_redirect
        task2 = @task Pipelines.redirect_to_files(stdout, stderr; mode = append ? "a+" : "w+") do
            try
                res = task.code()
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    else
        task2 = @task begin
            try
                res = task.code()
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    end

    job.task = task2
    job
end

function Job(f::Function;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Real = 1.0,
    mem::Int = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Year(1),
    cron::Cron = cron_none,
    until::Union{DateTime,Period} = DateTime(9999),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Int}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    if ncpu > 1.001
        @warn "ncpu > 1 for Job(f::Function) is not fully supported if the function uses multi-threads (except for running threaded commands), it is recommended to split it into different jobs. Job: $name." maxlog=1
    end

    need_redirect = check_need_redirect(stdout, stderr)
    
    job = Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, cron, until, QUEUING, priority, dependency, nothing, "", "", 0, f, need_redirect)

    if need_redirect
        task2 = @task Pipelines.redirect_to_files(stdout, stderr; mode = append ? "a+" : "w+") do
            try
                res = f()
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    else
        task2 = @task begin
            try
                res = f()
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    end
    job.task = task2
    job
end

function Job(command::Base.AbstractCmd;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Real = 1.0,
    mem::Int = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Year(1),
    cron::Cron = cron_none,
    until::Union{DateTime,Period} = DateTime(9999),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Int}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    f() = run(command)

    need_redirect = check_need_redirect(stdout, stderr)

    job = Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, cron, until, QUEUING, priority, dependency, task2, stdout, stderr, 0, f, need_redirect)

    if need_redirect
        task2 = @task Pipelines.redirect_to_files(stdout, stderr; mode = append ? "a+" : "w+") do
            try
                res = f()
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    else
        task2 = @task begin
            try
                res = f()
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    end
    job.task = task2
    job
end

"""
    fetch(x::Job)

Wait for a `Job` to finish, then return its result value. If the task fails with an exception, a `TaskFailedException` (which wraps the failed task) is thrown.

!!! compat
    `fetch(x::Job)` is available from JobSchedulers v0.10.2.
"""
function Base.fetch(x::Job)
    fetch(x.task)
end

period2datetime(t::DateTime) = t
period2datetime(t::Period) = now() + t

function check_ncpu_mem(ncpu::Real, mem::Int)
    if ncpu < 0
        error("ncpu < 0 is not supported for Job.")
    elseif 0.001 <= ncpu <= 0.999
        @warn "Job with 0 < ncpu < 1. This job will also bind to one available thread. Other jobs cannot use binded threads." maxlog=1
    end
    if mem < 0
        error("mem < 0 is not supported for Job")
    end
end

function check_priority(priority::Int)
    if priority < -9999 || priority > 9999
        error("abs(priority) > 9999 is not supported for Job")
    end
end

check_need_redirect(stdout::Nothing, stderr::Nothing) = false
check_need_redirect(stdout, stderr) = check_need_redirect(stdout) && check_need_redirect(stderr)

check_need_redirect(file::AbstractString) = file != ""
check_need_redirect(io::IO) = true
check_need_redirect(x::Nothing) = false
check_need_redirect(x::Any) = error("$x is not valid for redirecting IO: not IO, file_path::AbstractString, or nothing.")

function convert_dependency(dependency::Vector{Pair{Symbol,Union{Int, Job}}})
    dependency
end
function convert_dependency(dependency::Vector)
    Pair{Symbol,Union{Int, Job}}[convert_dependency_element(d) for d in dependency]
end
function convert_dependency(dependency)
    Pair{Symbol,Union{Int, Job}}[convert_dependency_element(dependency)]
end
function convert_dependency_element(p::Pair{Symbol,T}) where T  # do not specify T's type!!!
    p
end
function convert_dependency_element(job::T) where T <: Union{Int, Job}
    DONE => job
end

"""
    isqueuing(j::Job) :: Bool
"""
@inline isqueuing(j::Job) = j.state === QUEUING

"""
    isrunning(j::Job) :: Bool
"""
@inline isrunning(j::Job) = j.state === RUNNING

"""
    isdone(j::Job) :: Bool
"""
@inline isdone(j::Job) = j.state === DONE

"""
    iscancelled(j::Job) :: Bool
"""
@inline iscancelled(j::Job) = j.state === CANCELLED

"""
    isfailed(j::Job) :: Bool
"""
@inline isfailed(j::Job) = j.state === FAILED

"""
    ispast(j::Job) :: Bool = j.state === DONE || j.state === CANCELLED || j.state === FAILED
"""
@inline ispast(j::Job) = j.state === DONE || j.state === CANCELLED || j.state === FAILED


"""
    result(job::Job)

Return the result of `job`. If the job is not done, a warning message will also show.
"""
function result(job::Job)
    if !istaskdone(job.task)
        @warn "Getting result from a $(job.state) job: returned value might be unexpected."
    end
    job.task.result
end

"""
    get_thread_id(job::Job) = job._thread_id
"""
get_thread_id(job::Job) = job._thread_id

"""
    get_priority(job::Job) = job.priority
"""
get_priority(job::Job) = job.priority

"""
    solve_optimized_ncpu(default::Int; 
        ncpu_range::UnitRange{Int} = 1:total_cpu, 
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
function solve_optimized_ncpu(default::Int; njob::Int = 1, total_cpu::Int = JobSchedulers.SCHEDULER_MAX_CPU, ncpu_range::UnitRange{Int} = 1:total_cpu, side_jobs_cpu::Int = 0)
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

"""
    next_recur_job(j::Job) -> Union{Job, Nothing}

Based on `j.cron` and `j.until`, return a new recurring `Job` or `nothing`.
"""
function next_recur_job(j::Job)
    schedule_time = tonext(j.stop_time, j.cron)
    if isnothing(schedule_time) || schedule_time > j.until
        return nothing
    end
    # This job needs to be submitted using push!(new_job, JOB_QUEUE), cannot be submitted by submit!(new_job)

    job = Job(generate_id(), j.name, j.user, j.ncpu, j.mem, schedule_time, now(), DateTime(0), DateTime(0), j.wall_time, j.cron, j.until, QUEUING, j.priority, j.dependency, nothing, j.stdout, j.stderr, 0, j._func, j._need_redirect, j._group)

    if job._need_redirect
        task2 = @task Pipelines.redirect_to_files(stdout, stderr; mode = append ? "a+" : "w+") do
            try
                res = Base.invokelatest(job._func)
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    else
        task2 = @task begin
            try
                res = Base.invokelatest(job._func)
                unsafe_update_as_done!(job)
                res
            catch e
                unsafe_update_as_failed!(job)
                rethrow(e)
            finally
                scheduler_need_action()
            end
        end
    end

    job.task = task2
    job
end