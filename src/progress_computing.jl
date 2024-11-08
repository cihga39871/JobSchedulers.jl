using Terming
using Term
using Logging
using Printf

const T = Terming

const BLOCKS = ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
const BAR_LEFT = "▕"
const BAR_RIGHT = "▎"
const BLOCK = "█"

mutable struct Resource
    cpu::Float64
    mem::Int
end
const RESOURCE = Resource(0,0)

function update_resource(cpu::Real, mem::Int)
    global RESOURCE
    RESOURCE.cpu = cpu
    RESOURCE.mem = mem
end

"""
    GROUP_SEPERATOR::Regex = r": *"

Group seperator is used to group the names of Jobs. Used when display the progress meter using `wait_queue(show_progress=true)`

To set it, use `set_group_seperator(group_seperator::Regex)`.
"""
GROUP_SEPERATOR::Regex = r": *"

"""
    set_group_seperator(group_seperator::Regex) = global GROUP_SEPERATOR = group_seperator

Set the group seperator. Group seperator is used to group the names of Jobs. Used when display the progress meter using `wait_queue(show_progress=true)`

Default is `r": *"`.
"""
function set_group_seperator(group_seperator::Regex)
    global GROUP_SEPERATOR = group_seperator
end


"""
    mutable struct JobGroup
        name::String
        total::Int
        queuing::Int
        running::Int
        done::Int
        failed::Int
        cancelled::Int
    end

`JobGroup` is computed when displaying a progress meter.
"""
mutable struct JobGroup
    name::String
    @atomic total::Int
    @atomic queuing::Int
    @atomic running::Int
    @atomic done::Int
    @atomic failed::Int
    @atomic cancelled::Int
    jobs::Set{Job}  # running jobs only
    lock_jobs::ReentrantLock  # lock when updating/query jobs
end

function JobGroup(group_name::AbstractString)
    JobGroup(group_name, 0, 0, 0, 0, 0, 0, Set{Job}(), ReentrantLock())
end

const ALL_JOB_GROUP = JobGroup("ALL JOBS")
const JOB_GROUPS = OrderedDict{String, JobGroup}()
const JOB_GROUPS_LOCK = ReentrantLock()
const OTHER_JOB_GROUP = JobGroup("OTHERS")

"""
    update_group_state!(job::Job)

This should only be called if `JobSchedulers.PROGRESS_METER == true`. Update the job's group state, which will be used in Progress Meter.
"""
function update_group_state!(job::Job)
    job._group_state === job.state && return

    if job._group_state === :nothing
        # initial job
        job._group = get_group(job.name)

        jg = lock(JOB_GROUPS_LOCK) do
            if haskey(JOB_GROUPS, job._group)
                jg = JOB_GROUPS[job._group]
            else
                jg = JobGroup(job._group)
                JOB_GROUPS[job._group] = jg
            end
        end

        @atomic jg.total += 1
        @atomic ALL_JOB_GROUP.total += 1
    else
        jg = lock(JOB_GROUPS_LOCK) do
            JOB_GROUPS[job._group]
        end
        # group state before updating
        modifyfield!(jg, job._group_state, -, 1, :sequentially_consistent)
        modifyfield!(ALL_JOB_GROUP, job._group_state, -, 1, :sequentially_consistent)
    end

    # group state before updating
    if job._group_state === RUNNING  # previous running, not current
        try
            lock(jg.lock_jobs) do
                pop!(jg.jobs, job)
            end
        catch
        end
    end

    # updated group state
    job._group_state = job.state
    modifyfield!(jg, job._group_state, +, 1, :sequentially_consistent)
    modifyfield!(ALL_JOB_GROUP, job._group_state, +, 1, :sequentially_consistent)

    if job._group_state === RUNNING  # current running
        lock(jg.lock_jobs) do
            push!(jg.jobs, job)
        end
    end

    nothing
end

"""
    init_group_state!()

Prepare group state for existing jobs 
"""
function init_group_state!()
    clear_job_group!(ALL_JOB_GROUP)
    lock(JOB_GROUPS_LOCK) do
        empty!(JOB_GROUPS)
    end
    # clear_job_group!(OTHER_JOB_GROUP)  # no need to init, will compute later anyway

    lock(JOB_QUEUE.lock_queuing) do 
        init_group_state!.(JOB_QUEUE.future)
        init_group_state!.(JOB_QUEUE.queuing_0cpu)
        for jobs in values(JOB_QUEUE.queuing)
            init_group_state!.(jobs)
        end
    end
    lock(JOB_QUEUE.lock_running) do 
        init_group_state!.(JOB_QUEUE.running)
    end
    lock(JOB_QUEUE.lock_past) do 
        init_group_state!.(JOB_QUEUE.done)
        init_group_state!.(JOB_QUEUE.failed)
        init_group_state!.(JOB_QUEUE.cancelled)
    end
    nothing
end

function init_group_state!(job::Job)
    job._group_state = :nothing
    update_group_state!(job)
end

function clear_job_group!(g::JobGroup)
    @atomic g.total = 0
    @atomic g.queuing = 0
    @atomic g.running = 0
    @atomic g.done = 0
    @atomic g.failed = 0
    @atomic g.cancelled = 0
    lock(g.lock_jobs) do 
        empty!(g.jobs)
    end
end

"""
    get_group(job::Job, group_seperator = GROUP_SEPERATOR)
    get_group(name::AbstractString, group_seperator = GROUP_SEPERATOR)

Return `nested_group_names::Vector{String}`. 

Eg: If `job.name` is `"A: B: 1232"`, return `["A", "A: B", "A: B: 1232"]`
"""
function get_group(job::Job, group_seperator = GROUP_SEPERATOR)
    get_group(job.name, group_seperator)
end
function get_group(name::AbstractString, group_seperator = GROUP_SEPERATOR)
    isempty(name) && (return "") 
    String(split(name, group_seperator; limit = 2)[1])
end

function compute_other_job_group!(groups_shown::Vector{JobGroup})
    @atomic OTHER_JOB_GROUP.total = ALL_JOB_GROUP.total
    @atomic OTHER_JOB_GROUP.queuing = ALL_JOB_GROUP.queuing
    @atomic OTHER_JOB_GROUP.running = ALL_JOB_GROUP.running
    @atomic OTHER_JOB_GROUP.done = ALL_JOB_GROUP.done
    @atomic OTHER_JOB_GROUP.failed = ALL_JOB_GROUP.failed
    @atomic OTHER_JOB_GROUP.cancelled = ALL_JOB_GROUP.cancelled
    lock(OTHER_JOB_GROUP.lock_jobs) do
        empty!(OTHER_JOB_GROUP.jobs)
    end
    for g in groups_shown
        @atomic OTHER_JOB_GROUP.total -= g.total
        @atomic OTHER_JOB_GROUP.queuing -= g.queuing
        @atomic OTHER_JOB_GROUP.running -= g.running
        @atomic OTHER_JOB_GROUP.done -= g.done
        @atomic OTHER_JOB_GROUP.failed -= g.failed
        @atomic OTHER_JOB_GROUP.cancelled -= g.cancelled
    end
    if OTHER_JOB_GROUP.running > 0
        # find one that is running
        shown_group_names = Set([g.name for g in groups_shown])
        lock(JOB_QUEUE.lock_running) do 
            for job in JOB_QUEUE.running
                if job._group in shown_group_names
                    continue
                end
                lock(OTHER_JOB_GROUP.lock_jobs) do
                    push!(OTHER_JOB_GROUP.jobs, job)
                end
                break
            end
        end
    end
    OTHER_JOB_GROUP
end
