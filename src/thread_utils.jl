
const THREAD_POOL = Base.RefValue{Channel{Int}}()  # defined in __init__(); the thread 1 is reserved for JobScheduler, when nthreads > 2

function schedule_thread(j::Job)
    @static if :sticky in fieldnames(Task)
        if nthreads() > 1
            # sticky: disallow task migration which was introduced in 1.7
            @static if VERSION >= v"1.7"
                j.task.sticky = true
            else
                j.task.sticky = false
            end
            # take the next free thread... Will block/wait until a thread becomes free
            j._thread_id = take!(THREAD_POOL[])
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), j.task, j._thread_id-1)
        end
    end
    schedule(j.task)
end

"""
    free_thread(j::Job)

Make thread available again after work is done!
"""
function free_thread(j::Job)
    j._thread_id <= 0 && return # do nothing. 0 means (1) nthreads = 1 (2) job is not started;
    # <0 means the thread was freed.
    put!(THREAD_POOL[], j._thread_id)
    j._thread_id = - j._thread_id
    return
end
