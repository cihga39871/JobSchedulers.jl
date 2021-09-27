"""
    job_query_by_id(id::Int64)

Search job by `job.id` in the queue.

Return `job::Job` if found, `nothing` if not found.
"""
function job_query_by_id(id::Int64)
    wait_for_lock()
        for job in JOB_QUEUE
            if job.id == id
                release_lock()
                return job
            end
        end
        for job in JOB_QUEUE_OK
            if job.id == id
                release_lock()
                return job
            end
        end
    release_lock()
    return nothing # not found
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
