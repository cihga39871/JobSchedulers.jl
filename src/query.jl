"""
    job_query_by_id(id::Int)

Search job by `job.id` in the queue.

Return `job::Job` if found, `nothing` if not found.
"""
function job_query_by_id(id::Int)
    res = nothing
    @debug "job_query_by_id($id)"

    @debug "job_query_by_id lock_running"
    j = lock(JOB_QUEUE.lock_running) do
        for j in JOB_QUEUE.running
            j.id == id && return j
        end
    end
    @debug "job_query_by_id lock_running ok"

    j isa Job && return j

    @debug "job_query_by_id lock_queuing"
    j = lock(JOB_QUEUE.lock_queuing) do
        for j in JOB_QUEUE.queuing_0cpu
            j.id == id && return j
        end

        for js in values(JOB_QUEUE.queuing)
            for j in js
                j.id == id && return j
            end
        end

        for j in JOB_QUEUE.future
            j.id == id && return j
        end
    end
    @debug "job_query_by_id lock_queuing ok"

    j isa Job && return j

    @debug "job_query_by_id lock_past"
    j = lock(JOB_QUEUE.lock_past) do 
        for j in JOB_QUEUE.failed
            j.id == id && return j
        end
        for j in JOB_QUEUE.cancelled
            j.id == id && return j
        end
        for j in JOB_QUEUE.done
            j.id == id && return j
        end
    end
    @debug "job_query_by_id lock_past ok"
    return j  # Nothing or Job
end # function
job_query_by_id(job::Job) = job

job_query = job_query_by_id

function job_query_by_id_no_lock(id::Int)
    for j in JOB_QUEUE.running
        j.id == id && return j
    end
    for j in JOB_QUEUE.queuing_0cpu
        j.id == id && return j
    end

    for js in values(JOB_QUEUE.queuing)
        for j in js
            j.id == id && return j
        end
    end

    for j in JOB_QUEUE.future
        j.id == id && return j
    end
    for j in JOB_QUEUE.failed
        j.id == id && return j
    end
    for j in JOB_QUEUE.cancelled
        j.id == id && return j
    end
    for j in JOB_QUEUE.done
        j.id == id && return j
    end

    return nothing # not found
end # function
job_query_by_id_no_lock(job::Job) = job
