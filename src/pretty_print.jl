
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
    jobs = Vector{Job}()

    @debug "queue lock_running"
    lock(JOB_QUEUE.lock_running) do
        append!(jobs, JOB_QUEUE.running)
    end
    @debug "queue lock_running ok"

    @debug "queue lock_queuing"
    lock(JOB_QUEUE.lock_queuing) do
        append!(jobs, JOB_QUEUE.queuing_0cpu)
        for js in values(JOB_QUEUE.queuing)
            append!(jobs, js)
        end
        append!(jobs, JOB_QUEUE.future)
    end
    @debug "queue lock_queuing ok"


    if all
        @debug "queue lock_past"
        lock(JOB_QUEUE.lock_past) do 
            append!(jobs, JOB_QUEUE.failed)
            append!(jobs, JOB_QUEUE.cancelled)
            append!(jobs, JOB_QUEUE.done)
        end
        @debug "queue lock_past ok"
    end
    jobs
end

function queue(state::Symbol)
    if state === :all
        return queue(all=true)
    end
    
    jobs = Vector{Job}()
    if state === QUEUING
        @debug "queue lock_queuing"
        lock(JOB_QUEUE.lock_queuing) do
            append!(jobs, JOB_QUEUE.queuing_0cpu)
            for js in values(JOB_QUEUE.queuing)
                append!(jobs, js)
            end
            append!(jobs, JOB_QUEUE.future)
        end
        @debug "queue lock_queuing ok"
    elseif state === RUNNING
        @debug "queue lock_running"
        lock(JOB_QUEUE.lock_running) do
            append!(jobs, JOB_QUEUE.running)
        end
        @debug "queue lock_running ok"
    elseif state === DONE
        @debug "queue lock_past"
        lock(JOB_QUEUE.lock_past) do 
            append!(jobs, JOB_QUEUE.done)
        end
        @debug "queue lock_past ok"
    elseif state === FAILED
        @debug "queue lock_past"
        lock(JOB_QUEUE.lock_past) do 
            append!(jobs, JOB_QUEUE.failed)
        end
        @debug "queue lock_past ok"
    elseif state === CANCELLED
        @debug "queue lock_past"
        lock(JOB_QUEUE.lock_past) do 
            append!(jobs, JOB_QUEUE.cancelled)
        end
        @debug "queue lock_past ok"
    elseif state === PAST
        @debug "queue lock_past"
        lock(JOB_QUEUE.lock_past) do 
            append!(jobs, JOB_QUEUE.failed)
            append!(jobs, JOB_QUEUE.cancelled)
            append!(jobs, JOB_QUEUE.done)
        end
        @debug "queue lock_past ok"
    else
        @warn "state::Symbol is omitted because it is not one of QUEUING, RUNNING, DONE, FAILED, CANCELLED, or :all."
        return queue(all=true)
    end

    return jobs
end


function queue(needle::Union{AbstractString,AbstractPattern,AbstractChar})
    global JOB_QUEUE
    jobs = queue(all=true)
    filter!(r -> occursin(needle, r.name) || occursin(needle, r.user), jobs)
end

function queue(state::Symbol, needle::Union{AbstractString,AbstractPattern,AbstractChar})
    jobs = queue(state)
    filter!(r -> occursin(needle, r.name) || occursin(needle, r.user), jobs)
end
function queue(needle::Union{AbstractString,AbstractPattern,AbstractChar}, state::Symbol)
    queue(state, needle)
end

queue(id::Int) = job_query(id)

"""
    all_queue()
    all_queue(id::Int)
    all_queue(state::Symbol)
    all_queue(needle::Union{AbstractString,AbstractPattern,AbstractChar})

- `state::Symbol`: get jobs with a specific state, including `:all`, `QUEUING`, `RUNNING`, `DONE`, `FAILED`, `CANCELLED`, `PAST`.

  > `PAST` is the superset of `DONE`, `FAILED`, `CANCELLED`.

- `needle::Union{AbstractString,AbstractPattern,AbstractChar}`: get jobs if they contain `needle` in their name or user.

- `id::Int`: get the job with the specific `id`.
"""
all_queue() = queue(;all=true)
all_queue(id::Int) = job_query(id)

all_queue(state::Symbol) = queue(state)
all_queue(needle::Union{AbstractString,AbstractPattern,AbstractChar}) = queue(:all, needle)

const JOB_PUBLIC_NAMES = tuple(filter!(x -> string(x)[1] != '_', collect(fieldnames(Job)))...)
function Base.propertynames(j::Job, private::Bool=false)
    if private
        fieldnames(Job)
    else
        JOB_PUBLIC_NAMES
    end
end

@eval function Base.show(io::IO, ::MIME"text/plain", job::Job)
    fs = JOB_PUBLIC_NAMES
    fs_string = $(map(string, JOB_PUBLIC_NAMES))
    max_byte = $(maximum(length, map(string, JOB_PUBLIC_NAMES)))
    result = "Job:\n"
    for (i,f) in enumerate(fs)
        result *= string("  ", f, " " ^ (max_byte - length(fs_string[i])) * " → ")
        if f === :mem
            result *= simplify_memory(getfield(job, f), true) * "\n"
        else
            result *= simplify(getfield(job, f), true) * "\n"
        end
    end
    print(io, result)
end

function Base.show(io::IO, job::Job)
    print(io, "Job $(job.id) ($(job.state)): $(job.name)")
end

function Base.show(io::IO, ::MIME"text/plain", job_queue::Vector{Job};
    allrows::Bool = !get(io, :limit, false),
    allcols::Bool = !get(io, :limit, false)
)
    field_order = [:state, :id, :name, :user, :ncpu, :mem, :priority, :dependency, :start_time, :stop_time, :schedule_time, :submit_time, :wall_time, :cron, :until]
    mat = [JobSchedulers.simplify(getfield(j,f)) for j in job_queue, f in field_order]
    mat = hcat(
        [JobSchedulers.simplify(getfield(j, :state)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :id)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :name)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :user)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :ncpu)) for j in job_queue],
        [JobSchedulers.simplify_memory(getfield(j, :mem)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :priority)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :dependency)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :start_time)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :stop_time)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :schedule_time)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :submit_time)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :wall_time)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :cron)) for j in job_queue],
        [JobSchedulers.simplify(getfield(j, :until)) for j in job_queue],
    )

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



simplify(x::Symbol, detail::Bool = false) = ":$x"
simplify(x::Int, detail::Bool = false) = string(x)
simplify(x::AbstractString, detail::Bool = false) = "\"$x\""
simplify(x::Float64, detail::Bool = false) = string(round(x, digits=1))
function simplify(x::DateTime, detail::Bool = false)
    if Date(x) == today()
        Dates.format(x, dateformat"HH:MM:SS")
    elseif x == DateTime(0)
        "na"
    elseif Year(x) == Year(9999)
        "forever"
    else
        Dates.format(x, dateformat"yyyy-mm-dd HH:MM:SS")
    end
end
function simplify(deps::Vector{Pair{Symbol,Union{Int, Job}}}, detail::Bool = false)
    n_dep = length(deps)
    if n_dep == 0
        "[]"
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
simplify(x::Task, detail::Bool = false) = "Task"
function simplify(c::Cron, detail::Bool = false)
    date_based = date_based_on(c)
    if date_based === :none
        return detail ? "Cron(:none)" : ""
    end
    if !detail
        return "Defined"
    end
    time_str = get_time_description(c)
    date_str = get_date_description(c)
    if length(date_str) == 0
        return "Cron($time_str)"
    else
        return "Cron($time_str $date_str)"
    end
end
simplify(x, detail::Bool = false) = string(x)

@eval function simplify_memory(mem::Int, detail::Bool = false)
    if mem < 1024
        "$mem B"
    elseif mem < $(1024^2)
        mem_unit = simplify(mem / 1024)
        "$mem_unit KB"
    elseif mem < $(1024^3)
        mem_unit = simplify(mem / $(1024^2))
        "$mem_unit MB"
    elseif mem < $(1024^4)
        mem_unit = simplify(mem / $(1024^3))
        "$mem_unit GB"
    else
        mem_unit = simplify(mem / $(1024^4))
        "$mem_unit TB"
    end
end

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
    {"id":$(job.id),"state":"$(job.state)","name":"$(job.name)","user":"$(job.user)","ncpu":$(job.ncpu),"submit_time":"$(job.submit_time)","start_time":"$(job.start_time)","stop_time":"$(job.stop_time)","wall_time":"$(job.wall_time)","priority":$(job.priority),"stdout":"$(job.stdout)","stdout":"$(job.stdout)"}"""
end

function json_queue(;all=false)
    q = queue(all=all)
    res = "["
    if !isempty(q)
        res *= join(json.(q), ",")
    end
    res *= "]"
    return res
end
