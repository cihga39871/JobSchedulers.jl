
const THREAD_POOL = Base.RefValue{Channel{Int}}()  # defined in __init__(); the thread 1 is reserved for JobScheduler, when nthreads > 2


"""
    set_non_sticky!(t::Task)
    set_non_sticky!(j::Job)

Allow a job run in different threads. Not available in Julia 1.1.
"""
function set_non_sticky!(t::Task)
    @static if :sticky in fieldnames(Task)  # sticky controls wether a job is running in different threads, not found in Julia 1.1, found in julia 1.2 and so on.
        if nthreads() > 1
            t.sticky = false
        end
    end
end

set_non_sticky!(j::Job) = set_non_sticky!(j.task)

function set_thread_id!(t::Task, tid::Int)
    @static if :sticky in fieldnames(Task)  # sticky controls wether a job is running in different threads, not found in Julia 1.1, found in julia 1.2 and so on.
        if nthreads() > 1
            t.sticky = false
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, tid-1)
        end
    end
end

function set_thread_id!(j::Job, tid::Int)
    @static if :sticky in fieldnames(Task)  # sticky controls wether a job is running in different threads, not found in Julia 1.1, found in julia 1.2 and so on.
        if nthreads() > 1
            j.task.sticky = false
            j._thread_id = tid
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), j.task, tid-1)
        end
    end
end

function get_thread_id()

end

function schedule_thread(j::Job)
    @static if :sticky in fieldnames(Task)
        if nthreads() > 1
            j.task.sticky = false
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
    j._thread_id == 0 && return # do nothing. 0 means (1) nthreads = 1 (2) job is not started or the thread was freed.
    put!(THREAD_POOL[], j._thread_id)
    j._thread_id = 0
    return
end
