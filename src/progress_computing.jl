using DisplayStructure
using Terming
using Term
using Logging
using Printf

const DS = DisplayStructure
const T = Terming

const BLOCKS = ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
const BAR_LEFT = "▕"
const BAR_RIGHT = "▎"
const BLOCK = "█"

mutable struct JobGroup
    total::Int
    queuing::Int
    running::Int
    done::Int
    failed::Int
    cancelled::Int
    group_name::String
    job_names::Vector{String}
    elapsed_times::Vector{Millisecond}
    #failed
    eta::Millisecond
    function JobGroup(group_name)
        new(0,0,0,0,0,0,group_name, String[], Millisecond[], Millisecond(0))
    end
end

ALL_JOB_GROUP = JobGroup("ALL JOBS")
JOB_GROUPS = OrderedDict{String, JobGroup}()
OTHER_JOB_GROUP = JobGroup("OTHER JOBS")

function clear_job_group!(g::JobGroup)
    g.total = 0
    g.queuing = 0
    g.running = 0
    g.done = 0
    g.failed = 0
    g.cancelled = 0
    empty!(g.job_names)
    empty!(g.elapsed_times)
    g.eta = Millisecond(0)
end

function clear_job_groups!(; delete::Bool = false)
    if delete
        empty!(JOB_GROUPS)
        clear_job_group!(ALL_JOB_GROUP)
        clear_job_group!(OTHER_JOB_GROUP)
    else
        for g in values(JOB_GROUPS)
            clear_job_group!(g)
        end
    end
end

"""
get_groups(job::Job, group_seperator = r": *")

Return `nested_group_names::Vector{String}`. 

Eg: If `job.name` is `"A: B: 1232"`, return `["A", "A: B", "A: B: 1232"]`
"""
function get_groups(job::Job, group_seperator = r": *")
    gs = String.(split(job.name, group_seperator))
    current_name = gs[end]
    if length(gs) == 1
        return gs
    end
    for i in 2:length(gs)
        gs[i] = gs[i - 1] * ": " * gs[i]
    end
    return gs
end

function add_job_to_group!(g::JobGroup, j::Job)
    g.total += 1
    if j.state === DONE
        g.done += 1
    elseif j.state === QUEUING
        g.queuing += 1
    elseif j.state === RUNNING
        g.running += 1
    elseif j.state === FAILED
        g.failed += 1
    elseif j.state === CANCELLED
        g.cancelled += 1
    end
    push!(g.job_names, j.name)
    if year(j.stop_time) != 0 # stoped
        elapsed_time = j.stop_time - j.start_time
        push!(g.elapsed_times, elapsed_time)
    end
end

function compute_other_job_group!()
    OTHER_JOB_GROUP.total = ALL_JOB_GROUP.total
    OTHER_JOB_GROUP.queuing = ALL_JOB_GROUP.queuing
    OTHER_JOB_GROUP.running = ALL_JOB_GROUP.running
    OTHER_JOB_GROUP.done = ALL_JOB_GROUP.done
    OTHER_JOB_GROUP.failed = ALL_JOB_GROUP.failed
    OTHER_JOB_GROUP.cancelled = ALL_JOB_GROUP.cancelled
    for g in values(JOB_GROUPS)
        if g.total == 1
            continue
        end
        OTHER_JOB_GROUP.total -= g.total
        OTHER_JOB_GROUP.queuing -= g.queuing
        OTHER_JOB_GROUP.running -= g.running
        OTHER_JOB_GROUP.done -= g.done
        OTHER_JOB_GROUP.failed -= g.failed
        OTHER_JOB_GROUP.cancelled -= g.cancelled
    end
    OTHER_JOB_GROUP
end

function queue_summary(;group_seperator = r": *")
    wait_for_lock()
    try
        clear_job_groups!()
        cpu_running = 0
        mem_running = 0

        for job_queue in [JobSchedulers.JOB_QUEUE_OK, JobSchedulers.JOB_QUEUE]
            for j in job_queue
                group_names = get_groups(j, group_seperator)
                for group_name in group_names
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
                    cpu_running += j.ncpu
                    mem_running+= j.mem
                end
            end
        end
        compute_other_job_group!()
    catch
        rethrow()
    finally
        release_lock()
    end
    return cpu_running, mem_running
end


