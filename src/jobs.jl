
const JOB_ID = Ref{Int64}()
const JOB_ID_INCREMENT_LOCK = ReentrantLock()

"""
    generate_id() :: Int64

Generate an unique ID.
"""
function generate_id()
    lock(JOB_ID_INCREMENT_LOCK) do
        JOB_ID[] += rand(20000:40000)  # hard to predict ID using rand increment, in case some apps may allow users query job ID. In addition, the best practice for app developers is not directly expose job IDs, or use additional methods to constrain queries.
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
- `mem::Integer = 0`: number of memory this job is about to use (supports TB, GB, MB, KB, B=1).
- `schedule_time::Union{DateTime,Period} = DateTime(0)`: The expected time to run.
- `dependency`: defer job until specified jobs reach specified state (QUEUING, RUNNING, DONE, FAILED, CANCELLED, PAST). PAST is the super set of DONE, FAILED, CANCELLED, which means the job will not run in the future. Eg: `DONE => job`, `[DONE => job1; PAST => job2]`.

!!! info "Dependency"
    The default state is DONE, so `DONE => job` can be simplified to `job`.  
    To be compatible with old versions, you can also use job id (Int): `[DONE => job.id]`.

- `wall_time::Period = Year(1)`: wall clock time limit. Jobs will be terminated after running for this period.
- `priority::Int = 20`: lower means higher priority.

- `cron::Cron = Cron(:none)`: job recurring at specfic date and time. See more at [`Cron`](@ref).
- `until::Union{DateTime,Period} = DateTime(9999,1,1)`: stop job recurring `until` date and time.

!!! info "Thread-safe redirection is supported from v0.12.0"
    - `stdout=nothing`: redirect stdout to the file.
    - `stderr=nothing`: redirect stderr to the file.
    - `append::Bool=false`: append the stdout or stderr or not.

See also [`submit!`](@ref), [`@submit`](@ref), [`Cron`](@ref)
"""
mutable struct Job
    id::Int64
    name::String
    user::String
    ncpu::Float64
    mem::Int64
    schedule_time::DateTime
    submit_time::DateTime
    start_time::DateTime
    stop_time::DateTime
    wall_time::Period
    cron::Cron
    until::DateTime
    state::Symbol
    priority::Int
    dependency::Vector{Pair{Symbol,Union{Int64, Job}}}
    task::Union{Task,Nothing}
    stdout::Union{IO,AbstractString,Nothing}
    stderr::Union{IO,AbstractString,Nothing}
    _thread_id::Int
    _func::Union{Function,Nothing}
    _flags::UInt8  # details in _flags(j::Job)
    _group::String
    _group_state::Symbol
    _dep_check_id::Int
    _prev::Union{Job,Nothing}            # one-by-one mutable linked list
    _next::Union{Job,Nothing}            # one-by-one mutable linked list
    _parent::Union{Job,Nothing}          # the job is submitted by _parent job

    function Job(::UndefInitializer)
        j = new()
        j._prev = j
        j._next = j
        return j
    end
    function Job(id::Integer, name::String, user::String, ncpu::Real, mem::Integer, schedule_time::ST, submit_time::DateTime, start_time::DateTime, stop_time::DateTime, wall_time::Period, cron::Cron, until::ST2, state::Symbol, priority::Int, dependency, task::Union{Task,Nothing}, stdout::Union{IO,AbstractString,Nothing}, stderr::Union{IO,AbstractString,Nothing}, _thread_id::Int, _func::Union{Function,Nothing}, _need_redirect::Bool = check_need_redirect(stdout, stderr), _group::AbstractString = "") where {ST<:Union{DateTime,Period}, ST2<:Union{DateTime,Period}}
        check_ncpu_mem(ncpu, mem)
        check_priority(priority)
        dep = convert_dependency(dependency)
        check_dep(dep)
        _parent = current_job() # the job is submitted by _parent job, or nothing

        # flags
        _flags = 0x00
        if _need_redirect
            _flags |= 0x01  # set _need_redirect flag
        end

        j = new(Int64(id), name, user, Float64(ncpu), Int64(mem), period2datetime(schedule_time), submit_time, start_time, stop_time, wall_time, cron, period2datetime(until), state, priority, dep, task, stdout, stderr, _thread_id, _func, _flags, _group, :nothing, 1, nothing, nothing, _parent)

        j._prev = j
        j._next = j
        j
    end
end

"""
    const _flags = (:_need_redirect, :_recyclable,)

Description of flags of the job.

See also: getter `get\$(flag)` and setter `set\$(flag)!`.
"""
const _flags = (:_need_redirect, :_recyclable,)

# generate getter and setter for each flag
for (ibit, internal_func) in enumerate(_flags)
    getter = Symbol("get", internal_func)
    setter = Symbol("set", internal_func, "!")

    @eval function $(getter)(j::Job)
        return (j._flags & $(0x01 << (ibit-1))) != 0
    end

    getter_help = """
        $getter(j::Job) :: Bool
    
    Get the `$(internal_func)` flag of the job. This flag is stored in `j._flags` at bit position $ibit.
    """
    @eval @doc $getter_help $getter

    @eval function $(setter)(j::Job, val::Bool) 
        if val
            j._flags |= $(0x01 << (ibit-1))
        else
            j._flags &= $(~(0x01 << (ibit-1)))
        end
    end

    setter_help = """
        $setter(j::Job, val::Bool)

    Set the `$(internal_func)` flag of the job. This flag is stored in `j._flags` at bit position $ibit.
    """
    @eval @doc $setter_help $setter
end

"""
    # define lots of local variables first
    @gen_job_task scope_current::Bool ex::Expr

Internal use only! If you use the macro, you are wrong.
"""
macro gen_job_task(scope_current, ex)
    return esc(:(
        if need_redirect
            @task ScopedStreams.redirect_stream(stdout, stderr; mode = append ? "a+" : "w+") do
                @gen_job_task_try_block $scope_current $ex
            end
        else
            @task begin
                @gen_job_task_try_block $scope_current $ex
            end
        end
    ))
end

"""
    # define lots of local variables first
    @gen_job_task_try_block scope_current::Bool ex::Expr

Internal use only! If you use the macro, you are wrong.
"""
macro gen_job_task_try_block(scope_current, ex)
    if scope_current
        ex = :( @with CURRENT_JOB=>job $ex )
    end
    return esc(:(
        try
            res = $ex
            unsafe_update_as_done!(job)
            res
        catch e
            if e isa InterruptException
                unsafe_update_as_cancelled!(job)
            else
                unsafe_update_as_failed!(job)
            end
            rethrow(e)
        finally
            scheduler_need_action()
        end
    ))
end


### Job

function Job(task::Task;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Real = 1.0,
    mem::Integer = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Year(1),
    cron::Cron = cron_none,
    until::Union{DateTime,Period} = DateTime(9999),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Union{Int64, Job}}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    if ncpu > 1.001
        @warn "ncpu > 1 for Job(task::Task) is not fully supported if the task uses multi-threads (except for running threaded commands), it is recommended to split it into different jobs. Job: $name." maxlog=1
    end
    
    need_redirect = check_need_redirect(stdout, stderr)

    job = Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, cron, until, QUEUING, priority, dependency, nothing, stdout, stderr, 0, task.code, need_redirect)

    job.task = @gen_job_task true task.code()
    job
end

function Job(f::Function;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Real = 1.0,
    mem::Integer = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Year(1),
    cron::Cron = cron_none,
    until::Union{DateTime,Period} = DateTime(9999),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Union{Int64, Job}}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    if ncpu > 1.001
        @warn "ncpu > 1 for Job(f::Function) is not fully supported if the function uses multi-threads (except for running threaded commands), it is recommended to split it into different jobs. Job: $name." maxlog=1
    end

    need_redirect = check_need_redirect(stdout, stderr)
    
    job = Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, cron, until, QUEUING, priority, dependency, nothing, stdout, stderr, 0, f, need_redirect)

    job.task = @gen_job_task true f()

    job
end

function Job(command::Base.AbstractCmd;
    name::AbstractString = "",
    user::AbstractString = "",
    ncpu::Real = 1.0,
    mem::Integer = 0,
    schedule_time::Union{DateTime,Period} = DateTime(0),
    wall_time::Period = Year(1),
    cron::Cron = cron_none,
    until::Union{DateTime,Period} = DateTime(9999),
    priority::Int = 20,
    dependency = Vector{Pair{Symbol,Union{Int64, Job}}}(),
    stdout=nothing, stderr=nothing, append::Bool=false
)
    f() = run(command)

    need_redirect = check_need_redirect(stdout, stderr)

    job = Job(generate_id(), name, user, ncpu, mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), wall_time, cron, until, QUEUING, priority, dependency, nothing, stdout, stderr, 0, f, need_redirect)

    job.task = @gen_job_task false f()
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

function check_ncpu_mem(ncpu::Real, mem::Integer)
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

function check_dep(dependency::Vector{Pair{Symbol,Union{Int64, Job}}})
    length(dependency) == 0 && (return)
    for p in dependency
        if !(p.first in [QUEUING, RUNNING, DONE, FAILED, CANCELLED, PAST])
            error("invalid job state (:$(p.first)) found in Job's dependency ($(p.first) => $(p.second)). Possible Job states are QUEUING, RUNNING, DONE, FAILED, CANCELLED, PAST")
        end
    end
end

check_need_redirect(stdout::Nothing, stderr::Nothing) = false
check_need_redirect(stdout, stderr) = check_need_redirect(stdout) | check_need_redirect(stderr)

check_need_redirect(file::AbstractString) = file != ""
check_need_redirect(io::IO) = true
check_need_redirect(x::Nothing) = false
check_need_redirect(x::Any) = error("$x is not valid for redirecting IO: not IO, file_path::AbstractString, or nothing.")

convert_dependency(dependency::Vector{Pair{Symbol,Union{Int64, Job}}}) = dependency
convert_dependency(dependency::Vector) = Pair{Symbol,Union{Int64, Job}}[convert_dependency_element(d) for d in dependency]
convert_dependency(dependency) = Pair{Symbol,Union{Int64, Job}}[convert_dependency_element(dependency)]

convert_dependency_element(p::Pair{Symbol,Job}) = p
convert_dependency_element(p::Pair{Symbol,Int64}) = p
convert_dependency_element(p::Pair{Symbol,<:Integer}) = p.first => Int64(p.second)
convert_dependency_element(p::Pair) = Symbol(p.first) => (p.second isa Job ? p.second : Int64(p.second))
convert_dependency_element(job::Job) = DONE => job
convert_dependency_element(job::Integer) = DONE => Int64(job)

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
    # @gen_job_task needs arguments as follows
    need_redirect = get_need_redirect(j)
    stdout = j.stdout
    stderr = j.stderr
    append = true

    job = Job(generate_id(), j.name, j.user, j.ncpu, j.mem, schedule_time, DateTime(0), DateTime(0), DateTime(0), j.wall_time, j.cron, j.until, QUEUING, j.priority, j.dependency, nothing, stdout, stderr, 0, j._func, need_redirect, j._group)

    job.task = @gen_job_task true Base.invokelatest(job._func)
    job
end
