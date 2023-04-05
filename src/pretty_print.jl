
"""
```julia
queue(; all::Bool = false)    -> Vector{Job}
queue(state::Symbol )         -> Vector{Job}
queue(needle)                 -> Vector{Job}
queue(state::Symbol , needle) -> Vector{Job}
queue(needle, state::Symbol ) -> Vector{Job}
queue(id::Int)                -> Job
```

- `all::Bool`: if true, get all jobs. if false, get only running and queuing jobs.

- `state::Symbol`: get jobs with a specific state, including `:all`, `QUEUING`, `RUNNING`, `DONE`, `FAILED`, `CANCELLED`, `PAST`.

  > `PAST` is the superset of `DONE`, `FAILED`, `CANCELLED`.

- `needle::Union{AbstractString,AbstractPattern,AbstractChar}`: get jobs if they contain `needle` in their name or user.

- `id::Int`: get the job with the specific `id`.
"""
function queue(;all::Bool=false)
    global JOB_QUEUE
    global JOB_QUEUE_OK
    if all
        [JOB_QUEUE; JOB_QUEUE_OK]
    else
        copy(JOB_QUEUE)
    end
end

function queue(state::Symbol)
    if state == :all
        queue(all=true)
    elseif state in [QUEUING, RUNNING, DONE, FAILED, CANCELLED]
        q = queue(all=true)
        filter!(job -> job.state == state, q)
    elseif state == PAST
        copy(JOB_QUEUE_OK)
    else
        queue(all=true)
        @warn "state::Symbol is omitted because it is not one of QUEUING, RUNNING, DONE, FAILED, CANCELLED, or :all."
    end
end


function queue(needle::Union{AbstractString,AbstractPattern,AbstractChar})
    global JOB_QUEUE
    global JOB_QUEUE_OK
    dt = [JOB_QUEUE; JOB_QUEUE_OK]
    filter!(r -> occursin(needle, r.name) || occursin(needle, r.user), dt)
end

function queue(state::Symbol, needle::Union{AbstractString,AbstractPattern,AbstractChar})
    if state == :all
        dt = queue(needle)
    elseif state in [QUEUING, RUNNING, DONE, FAILED, CANCELLED]
        dt = queue(all=true)
        filter!(x -> x.state == state, dt)
    elseif state == PAST
        dt = copy(JOB_QUEUE_OK)
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

"""
    all_queue()
    all_queue(id::Int64)
    all_queue(state::Symbol)
    all_queue(needle::Union{AbstractString,AbstractPattern,AbstractChar})

- `state::Symbol`: get jobs with a specific state, including `:all`, `QUEUING`, `RUNNING`, `DONE`, `FAILED`, `CANCELLED`, `PAST`.

  > `PAST` is the superset of `DONE`, `FAILED`, `CANCELLED`.

- `needle::Union{AbstractString,AbstractPattern,AbstractChar}`: get jobs if they contain `needle` in their name or user.

- `id::Int`: get the job with the specific `id`.
"""
all_queue() = queue(;all=true)
all_queue(id::Int64) = job_query(id)

all_queue(state::Symbol) = queue(state)
all_queue(needle::Union{AbstractString,AbstractPattern,AbstractChar}) = queue(:all, needle)


@eval function Base.show(io::IO, ::MIME"text/plain", job::Job)
    fs = $(fieldnames(Job))
    fs_string = $(map(string, fieldnames(Job)))
    max_byte = $(maximum(length, map(string, fieldnames(Job))))
    println(io, "Job:")
    for (i,f) in enumerate(fs)
        print(io, "  ", f, " " ^ (max_byte - length(fs_string[i])), " → ")
        print(io, simplify(getfield(job, f)))
        println(io)
    end
end

function Base.show(io::IO, job::Job)
    print(io, "Job $(job.id) ($(job.state)): $(job.name)")
end

function Base.show(io::IO, ::MIME"text/plain", job_queue::Vector{Job};
    allrows::Bool = !get(io, :limit, false),
    allcols::Bool = !get(io, :limit, false)
)
    field_order = [:state, :id, :name, :user, :ncpu, :mem, :start_time, :stop_time, :schedule_time, :create_time, :wall_time, :priority, :dependency, :stdout_file, :stderr_file, :task, :_thread_id]
    mat = [JobSchedulers.simplify(getfield(j,f)) for j in job_queue, f in field_order]

    if allcols && allrows
        crop = :none
    elseif allcols
        crop = :vertical
    elseif allrows
        crop = :horizontal
    else
        crop = :both
    end
    println(io, "$(length(job_queue))-element Vector{Job}:")
    JobSchedulers.pretty_table(io, mat; header = field_order, crop = crop, maximum_columns_width = 20, vcrop_mode = :middle, show_row_number = true)
end



simplify(x::Symbol) = ":$x"
simplify(x::Int) = string(x)
simplify(x::AbstractString) = "\"$x\""
simplify(x::DateTime) = Dates.format(x, dateformat"yyyy-mm-dd HH:MM:SS")
function simplify(deps::Vector{Pair{Symbol,Union{Int64, Job}}})
    n_dep = length(deps)
    if n_dep == 0
        :([])
    elseif n_dep == 1
        dep = deps[1]
        id = if dep.second isa Int
            dep.second
        else
            dep.second.id
        end
        "[:$(dep.first) => $(id)]"
    else
        "$n_dep jobs"
    end
end
simplify(x::Task) = "Task"
simplify(x) = string(x)

#### JSON conversion
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
