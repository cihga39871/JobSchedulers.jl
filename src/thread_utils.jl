
"""
    const THREAD_POOL = Base.RefValue{Channel{Int}}()

Defined in `__init__()`.

If version > 1.9, `THREAD_POOL` contains only tids in `Threads.threadpooltids(:default)`.

Also, the thread 1 is reserved for JobScheduler.
"""
const THREAD_POOL = Base.RefValue{Channel{Int}}()

"""
    const SINGLE_THREAD_MODE = Base.RefValue{Bool}()

Defined in `__init__()`. Whether `Threads.threadpooltids(:default)` are empty or `== [1]`.
"""
const SINGLE_THREAD_MODE = Base.RefValue{Bool}()

"""
    const TIDS = Vector{Int}()

Defined in `__init__()`. All tids in the default thread pool, excluding tid 1.
"""
const TIDS = Vector{Int}()

"""
    const CURRENT_JOB = ScopedValue{Union{Job, Nothing}}(nothing)

The `Job` that is running in the current scope, `nothing` if the current scope is not within a job.

See also [`current_job`](@ref).
"""
const CURRENT_JOB = ScopedValue{Union{Job, Nothing}}(nothing)

"""
    current_job() :: Union{Job, Nothing}

Return the `Job` that is running in the current scope, `nothing` if the current scope is not within a job.
"""
@inline current_job() = CURRENT_JOB[]

"""
    const OCCUPIED_MARK = 1<<30

A large number added to `job._thread_id` to mark the thread is yielded.
"""
const OCCUPIED_MARK = 1<<30

"""
    unsafe_occupy_tid!(j::Job) :: Int

Return the `j._thread_id` before changing, and mark the tid as occupied by adding `OCCUPIED_MARK` to `j._thread_id`.

Unsafe when:
- If `j._thread_id <= 0` or `j` is occupied, `j._thread_id` will not be changed, and return `j._thread_id`.
"""
@inline function unsafe_occupy_tid!(j::Job)
    tid = j._thread_id
    j._thread_id |= OCCUPIED_MARK
    return tid
end

"""
    unsafe_unoccupy_tid!(j::Job) :: Bool

Remove `OCCUPIED_MARK` from `j._thread_id` to mark the tid is ready to yield. Please ensure the tid is occupied (`is_tid_occupied(j)`) before calling this function.

Unsafe when:
- If `j._thread_id < 0`, the tid will be changed to a very small negative number, which does not make sense.
- If `j._thread_id == 0`, the tid will remain 0.
- If `j` is not occupied, the tid will remain unchanged.
"""
@inline unsafe_unoccupy_tid!(j::Job) = j._thread_id &= ~OCCUPIED_MARK

"""
    @inline unsafe_original_tid(j::Job) = j._thread_id & ~OCCUPIED_MARK

Only useful when `j._thread_id > 0`.
Used to get the original tid of a job, without `OCCUPIED_MARK`. 
"""
@inline unsafe_original_tid(j::Job) = j._thread_id & ~OCCUPIED_MARK

"""
    is_tid_ready_to_occupy(j::Job) :: Bool

Return Bool. `true` means job is able to occupy (`j.ncpu == 0 && j._thread_id > 0`) and not occupied (`j._thread_id & OCCUPIED_MARK == 0`).
"""
@inline function is_tid_ready_to_occupy(j::Job)
    # j.ncpu == 0 && j._thread_id > 0 && (j._thread_id & OCCUPIED_MARK == 0)
    j.ncpu == 0 && (0 < j._thread_id < OCCUPIED_MARK)  # optimized version
end

"""
    is_tid_occupied(j::Job) :: Bool

Return Bool. `false` means job not occupied (`j._thread_id & OCCUPIED_MARK != 0`) or not able to occupy (`j._thread_id <= 0`).
"""
@inline function is_tid_occupied(j::Job)
    # j._thread_id > 0 && (j._thread_id & OCCUPIED_MARK != 0)
    j._thread_id > OCCUPIED_MARK  # optimized version
end

const SKIP = UInt8(0)
const OK   = UInt8(1)
const FAIL = UInt8(2)

"""
    schedule_thread(j::Job) :: UInt8

Internal: assign TID to and run the job.
"""
function schedule_thread(j::Job) :: UInt8
    if j.ncpu > 0
        @static if :sticky in fieldnames(Task)
            if !SINGLE_THREAD_MODE[]
                # sticky: disallow task migration which was introduced in 1.7
                @static if VERSION >= v"1.7-"
                    j.task.sticky = true
                else
                    j.task.sticky = false
                end

                # if any parent job's tid is not occupied by one of its child tasks, then give the thread to this child.
                parent = j._parent
                while parent !== nothing # isa Job
                    # if parent don't yield (ncpu != 0), cannot give it to child tasks.
                    if is_tid_ready_to_occupy(parent)
                        j._thread_id = unsafe_occupy_tid!(parent)
                        if j._thread_id > 0  # just in case if race condition happens and parent job's tid is occupied by another child task. Even it is unlikely to happen because the function should be only be called within the main scheduler task.
                            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), j.task, j._thread_id-1)
                        end
                        @goto schedule_task
                    end
                    parent = parent._parent
                end
                
                # take the next free thread... Will block/wait until a thread becomes free

                if isready(THREAD_POOL[])
                    j._thread_id = take!(THREAD_POOL[])
                    ccall(:jl_set_task_tid, Cvoid, (Any, Cint), j.task, j._thread_id-1)
                else
                    # no free thread, skip this time
                    return SKIP
                end
                
            end
        end
    # else  # ncpu == 0
        # allow task migration which was introduced in 1.7
    end
    @label schedule_task
    try
        schedule(j.task)
        return OK
    catch e
        @error "Error scheduling job. Skip. id=$(j.id) name=$(j.name)" exception=(e, catch_backtrace())
        return FAIL
    end
end

"""
    free_thread(j::Job)

Make thread available again after job is finished.
"""
function free_thread(j::Job)
    if j._thread_id <= 0
        # do nothing. 
        # 0 means (1) nthreads = 1 or j.ncpu = 0 (2) job is not started; 
        # <0 means the thread was freed before.
        return 
    end

    # if j is the parent job and is occupied, then do not free the thread to the pool, but mark the tid as done.
    if is_tid_occupied(j)
        j._thread_id = - unsafe_original_tid(j)
        return
    end

    # if j has any parent jobs, and one of them is occupying the same thread,
    # then do not free the thread to the pool, 
    # but mark that parent job's tid as not occupied, and mark j's tid as done.
    parent = j._parent
    while parent !== nothing # not nothing
        if unsafe_original_tid(parent) == j._thread_id  # it is ok to use unsafe_original_tid if j._thread_id < 0 because it won't be equal.
            is_tid_occupied(parent) && unsafe_unoccupy_tid!(parent)
            j._thread_id = - j._thread_id
            return
        end
        parent = parent._parent
    end
    
    # if j does not have a parent job, or its parent job is not occupying the same thread, then free the thread to the pool.
    put!(THREAD_POOL[], j._thread_id)
    j._thread_id = - j._thread_id
    return
end
