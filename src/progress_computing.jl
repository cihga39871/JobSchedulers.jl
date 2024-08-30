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
        total::Int
        queuing::Int
        running::Int
        done::Int
        failed::Int
        cancelled::Int
        eta::Millisecond
        group_name::String
        job_name::String
        failed_job_names::Vector{String}
        elapsed_times::Vector{Millisecond}
        function JobGroup(group_name)
            new(0, 0, 0, 0, 0, 0, Millisecond(0), group_name, "", String[], Millisecond[])
        end
    end

`JobGroup` is computed when displaying a progress meter.
"""
mutable struct JobGroup
    name::String
    jobs::Vector{Job}
    total::Int
    queuing::Int
    running::Int
    done::Int
    failed::Int
    cancelled::Int
    function JobGroup(name)
        new(name, Vector{Job}(), 0, 0, 0, 0, 0, 0)
    end
end

COMPUTING_JOB_GROUP::Bool = false

const ALL_JOB_GROUP = JobGroup("ALL JOBS")
const JOB_GROUPS = OrderedDict{String, JobGroup}()
const OTHER_JOB_GROUP = JobGroup("OTHERS")

function push_job_group!(j::Job)
    
end

"""
    fingerprint(g::JobGroup)
    ALL_JOB_GROUP_FINGERPRINT = fingerprint(ALL_JOB_GROUP)

If `ALL_JOB_GROUP_FINGERPRINT` is different from new fingerprint, update view.
"""
function fingerprint(g::JobGroup)
    return (
        g.total,
        g.queuing,
        g.running,
        g.done,
        g.failed,
        g.cancelled
    )
end
ALL_JOB_GROUP_FINGERPRINT = fingerprint(ALL_JOB_GROUP)



function clear_job_group!(g::JobGroup)
    g.total = 0
    g.queuing = 0
    g.running = 0
    g.done = 0
    g.failed = 0
    g.cancelled = 0
    g.eta = Millisecond(0)
    g.job_name = ""
    empty!(g.failed_job_names)
    empty!(g.elapsed_times)
end

function clear_job_groups!(; delete::Bool = false)
    if delete
        empty!(JOB_GROUPS)
    else
        for g in values(JOB_GROUPS)
            clear_job_group!(g)
        end
    end
    clear_job_group!(ALL_JOB_GROUP)
    clear_job_group!(OTHER_JOB_GROUP)
    global CPU_RUNNING = 0
    global MEM_RUNNING = 0
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

function add_job_to_group!(g::JobGroup, j::Job)
    g.total += 1
    if j.state === DONE
        g.done += 1
    elseif j.state === QUEUING
        g.queuing += 1
    elseif j.state === RUNNING
        g.job_name = j.name
        g.running += 1
    elseif j.state === FAILED
        g.failed += 1
    elseif j.state === CANCELLED
        g.cancelled += 1
    end
    if year(j.stop_time) != 0 # stoped
        elapsed_time = j.stop_time - j.start_time
        push!(g.elapsed_times, elapsed_time)
    end
end

function compute_other_job_group!(groups_shown::Vector{JobGroup})
    OTHER_JOB_GROUP.total = ALL_JOB_GROUP.total
    OTHER_JOB_GROUP.queuing = ALL_JOB_GROUP.queuing
    OTHER_JOB_GROUP.running = ALL_JOB_GROUP.running
    OTHER_JOB_GROUP.done = ALL_JOB_GROUP.done
    OTHER_JOB_GROUP.failed = ALL_JOB_GROUP.failed
    OTHER_JOB_GROUP.cancelled = ALL_JOB_GROUP.cancelled
    OTHER_JOB_GROUP.job_name = ""
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
        for job_group in values(JOB_GROUPS)
            if !(job_group.group_name in shown_group_names)
                job_group.job_name == "" && continue
                OTHER_JOB_GROUP.job_name = job_group.job_name
                break
            end
        end
    end
    OTHER_JOB_GROUP
end

function queue_summary(;group_seperator = GROUP_SEPERATOR)
    queue_update = false
    wait_for_lock()
    try
        clear_job_groups!()

        for job_queue in [JobSchedulers.JOB_QUEUE_OK, JobSchedulers.JOB_QUEUE]
            for j in job_queue
                group_name = get_group(j, group_seperator)
                if group_name != ""
                    group = get(JOB_GROUPS, group_name, nothing)
                    if group === nothing
                        g = JobGroup(group_name)
                        JOB_GROUPS[group_name] = g
                        add_job_to_group!(g, j)
                    else
                        add_job_to_group!(group, j)
                    end
                end
                add_job_to_group!(ALL_JOB_GROUP, j)

                if j.state === RUNNING
                    global CPU_RUNNING += j.ncpu
                    global MEM_RUNNING += j.mem
                end
            end
        end
    catch
        rethrow()
    finally
        release_lock()
    end

    new_fingerprint = fingerprint(ALL_JOB_GROUP)
    if new_fingerprint == ALL_JOB_GROUP_FINGERPRINT
        queue_update = false
    else
        queue_update = true
        global ALL_JOB_GROUP_FINGERPRINT = new_fingerprint
    end
    return queue_update
end


