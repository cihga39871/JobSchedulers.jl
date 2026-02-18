
"""
    JOB_CEMETERY = Ref{Channel{Job}}()

A channel to store recyclable jobs, with a buffer size of 2000. Init in `__init__` function of `JobSchedulers.jl`. 

See also: [`recyclable!`](@ref).
"""
const JOB_CEMETERY = Ref{Channel{Job}}()

"""
    recyclable!(job::Job)

After a job reaches a `done` state, it can be marked as recyclable **only if it can be destoried by GC**. This is particularly beneficial in scenarios where many jobs are created and destroyed frequently, as it can reduce memory fragmentation and improve performance.

Specifically, when a job is marked as recyclable, it means that, after the job reaches a `done` state, it **won't be accessed and queried by any user's code anymore**, including job dependency, `queue`, `job_query`, `fetch`, `result`, `wait`, etc. In other words, the job can be destroyed by GC. 
"""
function recyclable!(job::Job)
    set_recyclable!(job, true)
end

