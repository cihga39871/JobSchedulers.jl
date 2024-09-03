using Terming
using Term
using Logging
using Printf

const T = Terming

const BLOCKS = ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
const BAR_LEFT = "▕"
const BAR_RIGHT = "▎"
const BLOCK = "█"

CPU_RUNNING::Int = 0
MEM_RUNNING::Int = 0

GROUP_SEPERATOR::Regex = r": *"

"""
    set_group_seperator(group_seperator::Regex)

Set the group seperator. Group seperator is used to group the names of Jobs.
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
    total::Int
    queuing::Int
    running::Int
    done::Int
    failed::Int
    cancelled::Int
    jobs::Set{Job}  # running jobs only
end

function JobGroup(group_name::AbstractString)
    JobGroup(group_name, 0, 0, 0, 0, 0, 0, Set{Job}())
end

const ALL_JOB_GROUP = JobGroup("ALL JOBS")
const JOB_GROUPS = OrderedDict{String, JobGroup}()
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

        if haskey(JOB_GROUPS, job._group)
            jg = JOB_GROUPS[job._group]
        else
            jg = JobGroup(job._group)
            JOB_GROUPS[job._group] = jg
        end

        jg.total += 1
        ALL_JOB_GROUP.total += 1
    else
        jg = JOB_GROUPS[job._group]
        # group state before updating
        setfield!(jg, job._group_state, getfield(jg, job._group_state) - 1)
        setfield!(ALL_JOB_GROUP, job._group_state, getfield(ALL_JOB_GROUP, job._group_state) - 1)
    end

    # group state before updating
    if job._group_state === RUNNING  # previous running, not current
        try
            pop!(jg.jobs, job)
        catch
        end
    end

    # updated group state
    job._group_state = job.state
    setfield!(jg, job._group_state, getfield(jg, job._group_state) + 1)
    setfield!(ALL_JOB_GROUP, job._group_state, getfield(ALL_JOB_GROUP, job._group_state) + 1)

    if job._group_state === RUNNING  # current running
        push!(jg.jobs, job)
    end

    nothing
end

"""
    init_group_state!()

Prepare group state for existing jobs 
"""
function init_group_state!()
    clear_job_group!(ALL_JOB_GROUP)
    empty!(JOB_GROUPS)
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
    g.total = 0
    g.queuing = 0
    g.running = 0
    g.done = 0
    g.failed = 0
    g.cancelled = 0
    empty!(g.jobs)
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
    OTHER_JOB_GROUP.total = ALL_JOB_GROUP.total
    OTHER_JOB_GROUP.queuing = ALL_JOB_GROUP.queuing
    OTHER_JOB_GROUP.running = ALL_JOB_GROUP.running
    OTHER_JOB_GROUP.done = ALL_JOB_GROUP.done
    OTHER_JOB_GROUP.failed = ALL_JOB_GROUP.failed
    OTHER_JOB_GROUP.cancelled = ALL_JOB_GROUP.cancelled
    empty!(OTHER_JOB_GROUP.jobs)
    for g in groups_shown
        OTHER_JOB_GROUP.total -= g.total
        OTHER_JOB_GROUP.queuing -= g.queuing
        OTHER_JOB_GROUP.running -= g.running
        OTHER_JOB_GROUP.done -= g.done
        OTHER_JOB_GROUP.failed -= g.failed
        OTHER_JOB_GROUP.cancelled -= g.cancelled
    end
    if OTHER_JOB_GROUP.running > 0
        # find one that is running
        shown_group_names = Set([g.group_name for g in groups_shown])
        lock(JOB_QUEUE.lock_running) do 
            for job in JOB_QUEUE.running
                if job._group in shown_group_names
                    continue
                end
                push!(OTHER_JOB_GROUP, job)
                break
            end
        end
    end
    OTHER_JOB_GROUP
end
