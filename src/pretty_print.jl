
@eval function DataFrames.DataFrame(job_queue::Vector{Job})
    fs = $(fieldnames(Job))
    d = DataFrame()
    wait_for_lock()
    try
        for f in fs
            d[!, f] = getfield.(job_queue, f)
        end
    catch e
        rethrow(e)
    finally
        release_lock()
    end
    select!(d, :state, :id, :name, :user, :ncpu, :mem, :start_time, :stop_time)
end

"""
```julia
queue(; all::Bool = false)
queue(state)
queue(needle)
queue(state, needle)
queue(needle, state)
queue(id)
```
"""
function queue(;all::Bool=false)
    global JOB_QUEUE
    global JOB_QUEUE_OK
    if all
        DataFrame([JOB_QUEUE; JOB_QUEUE_OK])
    else
        DataFrame(JOB_QUEUE)
    end
end

function queue(state::Symbol)
    if state == :all
        queue(all=true)
    elseif state in [QUEUING, RUNNING, DONE, FAILED, CANCELLED]
        q = queue(all=true)
        q[q.state .== state, :]
    elseif state == PAST
        DataFrame(JOB_QUEUE_OK)
    else
        queue(all=true)
        @warn "state::Symbol is omitted because it is not one of QUEUING, RUNNING, DONE, FAILED, CANCELLED, or :all."
    end
end


function queue(needle::Union{AbstractString,AbstractPattern,AbstractChar})
    global JOB_QUEUE
    global JOB_QUEUE_OK
    dt = DataFrame([JOB_QUEUE; JOB_QUEUE_OK])
    filter!(r -> occursin(needle, r.name) || occursin(needle, r.user), dt)
end

function queue(state::Symbol, needle::Union{AbstractString,AbstractPattern,AbstractChar})
    if state == :all
        dt = queue(needle)
    elseif state in [QUEUING, RUNNING, DONE, FAILED, CANCELLED]
        dt = queue(all=true)
        filter!(:state => x -> x == state, dt)
    elseif state == PAST
        dt = DataFrame(JOB_QUEUE_OK)
    else
        dt = queue(all=true)
        @warn "state::Symbol is omitted because it is not one of QUEUING, RUNNING, DONE, FAILED, CANCELLED, or :all."
    end
    filter!(r -> occursin(needle, r.name) || occursin(needle, r.user), dt)
end
function queue(needle::Union{AbstractString,AbstractPattern,AbstractChar}, state::Symbol)
    queue(state, needle)
end

queue(id::Int64) = job_query(id)
all_queue(id::Int64) = job_query(id)

all_queue(state::Symbol) = queue(state)
all_queue(needle::Union{AbstractString,AbstractPattern,AbstractChar}) = queue(:all, needle)


@eval function Base.display(job::Job)
    fs = $(fieldnames(Job))
    fs_string = $(map(string, fieldnames(Job)))
    max_byte = $(maximum(length, map(string, fieldnames(Job))))
    println("Job:")
    for (i,f) in enumerate(fs)
        print("  ", f, " " ^ (max_byte - length(fs_string[i])), " → ")
        display(getfield(job, f))
    end
end

@eval function Base.Dict(job::Job)
    fs = $(fieldnames(Job))
    d = Dict{Symbol, Any}()
    for f in fs
        f === :task && continue
        d[f] = getfield(job, f)
    end
    d
end

#TODO: update new fields. Check compatibility with existing programs
function JSON.Writer.json(job::Job)
    """
    {"id":$(job.id),"state":"$(job.state)","name":"$(job.name)","user":"$(job.user)","ncpu":$(job.ncpu),"create_time":"$(job.create_time)","start_time":"$(job.start_time)","stop_time":"$(job.stop_time)","wall_time":"$(job.wall_time)","priority":$(job.priority),"stdout_file":"$(job.stdout_file)","stderr_file":"$(job.stderr_file)"}"""
end

function json_queue(;all=false)
    global JOB_QUEUE
    global JOB_QUEUE_OK
    res = "["
    if all
        if !isempty(JOB_QUEUE)
            res *= join(JOB_QUEUE .|> json, ",")
        end
        if !isempty(JOB_QUEUE_OK)
            if res[end] == '}'
                res *= ","
            end
            res *= join(JOB_QUEUE_OK .|> json, ",")
        end
    else
        if !isempty(JOB_QUEUE)
            res *= join(JOB_QUEUE .|> json, ",")
        end
    end
    res *= "]"
    return res
end
