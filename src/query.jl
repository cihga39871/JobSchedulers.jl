"""
    job_query_by_id(id::Int64)

Search job by `job.id` in the queue.

Return `job::Job` if found, `nothing` if not found.
"""
function job_query_by_id(id::Int64)
    res = nothing
    wait_for_lock()
    try
        for job in JOB_QUEUE
            if job.id == id
                res = job
                break
            end
        end
        if isnothing(res)
            for job in JOB_QUEUE_OK
                if job.id == id
                    res = job
                    break
                end
            end
        end
    catch e
        rethrow(e)
    finally
        release_lock()
    end
    return res
end # function

job_query = job_query_by_id

function job_query_by_id_no_lock(id::Int64)
    for job in JOB_QUEUE
        if job.id == id
            return job
        end
    end
    for job in JOB_QUEUE_OK
        if job.id == id
            return job
        end
    end
    return nothing # not found
end # function

job_query = job_query_by_id
