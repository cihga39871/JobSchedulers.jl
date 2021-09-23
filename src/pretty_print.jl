
@eval function DataFrames.DataFrame(job_queue::Vector{Job})
    fs = $(fieldnames(Job))
    d = DataFrame()
    for f in fs
        d[!, f] = getfield.(job_queue, f)
    end
    select!(d, :state, :id, :name, :user, :ncpu, :mem, :create_time, :)
end

function queue(;all=false)
    global JOB_QUEUE
    global JOB_QUEUE_OK
    if all
        DataFrame([JOB_QUEUE..., JOB_QUEUE_OK...])
    else
        DataFrame(JOB_QUEUE)
    end
end
all_queue() = queue(all=true)

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
