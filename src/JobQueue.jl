
"""
    JobQueue(; max_done::Int = 10000, max_cancelled::Int = 10000)
    mutable struct JobQueue
        const queuing::SortedDict{Int,MutableLinkedList{Job},Base.Order.ForwardOrdering}  # priority => Job List
        const queuing_0cpu::Vector{Job}              # ncpu = 0, can run immediately
        const future::Vector{Job}                    # all jobs with schedule_time > now()
        const running::Vector{Job}
        const done::Vector{Job}
        const failed::Vector{Job}
        const cancelled::Vector{Job}
        max_done::Int
        max_cancelled::Int
        const lock_queuing::ReentrantLock
        const lock_running::ReentrantLock
        const lock_past::ReentrantLock
    end
"""
mutable struct JobQueue
    const queuing::SortedDict{Int,MutableLinkedList{Job},Base.Order.ForwardOrdering}  # priority => Job List
    const queuing_0cpu::Vector{Job}              # ncpu = 0, can run immediately
    const future::Vector{Job}                    # all jobs with schedule_time > now()
    const running::Vector{Job}
    const done::Vector{Job}
    const failed::Vector{Job}
    const cancelled::Vector{Job}
    max_done::Int
    max_cancelled::Int
    const lock_queuing::ReentrantLock
    const lock_running::ReentrantLock
    const lock_past::ReentrantLock
end

function JobQueue(; max_done::Int = 10000, max_cancelled::Int = 10000)
    JobQueue(
        SortedDict{Int,MutableLinkedList{Job}}(20 => MutableLinkedList{Job}()),
        Vector{Job}(),
        Vector{Job}(),
        Vector{Job}(),
        Vector{Job}(),
        Vector{Job}(),
        Vector{Job}(),
        max_done,
        max_cancelled,
        ReentrantLock(),
        ReentrantLock(),
        ReentrantLock()
    )
end

DESTROY_UNNAMED_JOBS_WHEN_DONE::Bool = true

"""
    JobSchedulers.destroy_unnamed_jobs_when_done(b::Bool)

!!! compat "New in v0.10"

    Before v0.10, all jobs will be saved to queue. However, from v0.10, unnamed jobs (`job.name == ""`) will not be saved if it **successfully** ran. If you want to save unnamed jobs, you can set using `JobSchedulers.destroy_unnamed_jobs_when_done(false)`.
"""
function destroy_unnamed_jobs_when_done(b::Bool)
    global DESTROY_UNNAMED_JOBS_WHEN_DONE = b
end

function push_queuing!(queue::SortedDict{Int,MutableLinkedList{Job}}, job::Job)
    if haskey(queue, job.priority)
        push!(queue[job.priority], job)
    else
        queue[job.priority] = MutableLinkedList{Job}(job)
    end
    nothing
end
function push_running!(job::Job)
    # @debug "push_running! lock_running"
    lock(JOB_QUEUE.lock_running) do 
        push!(JOB_QUEUE.running, job)
    end
    # @debug "push_running! lock_running ok"
end
function push_failed!(job::Job)
    # @debug "push_failed! lock_past"
    lock(JOB_QUEUE.lock_past) do 
        push!(JOB_QUEUE.failed, job)
    end
    # @debug "push_failed! lock_past ok"
end
function push_done!(job::Job)
    global DESTROY_UNNAMED_JOBS_WHEN_DONE
    if DESTROY_UNNAMED_JOBS_WHEN_DONE && isempty(job.name)
        #no push
    else
        # @debug "push_done! lock_past"
        lock(JOB_QUEUE.lock_past) do 
            push!(JOB_QUEUE.done, job)
        end
        # @debug "push_done! lock_past ok"
    end
    try_push_next_recur!(job)
end
function push_cancelled!(job::Job)
    # @debug "push_cancelled! lock_past"
    lock(JOB_QUEUE.lock_past) do 
        push!(JOB_QUEUE.cancelled, job)
    end
    # @debug "push_cancelled! lock_past ok"
end


"""
    try_push_next_recur!(job::Job)

This need to be done only when `job.state === DONE`.
"""
function try_push_next_recur!(job::Job)
    next_job = next_recur_job(job)
    isnothing(next_job) && return

    # @debug "try_push_next_recur! lock_queuing"
    lock(JOB_QUEUE.lock_queuing) do
        push!(JOB_QUEUE.future, next_job)
    end
    # @debug "try_push_next_recur! lock_queuing ok"
    return
end

function n_job_remaining()
    n = 0
    # @debug "n_job_remaining lock_queuing"
    lock(JOB_QUEUE.lock_queuing) do
        for jobs in values(JOB_QUEUE.queuing)
            n += length(jobs)
        end
        n += length(JOB_QUEUE.queuing_0cpu) 
        n += length(JOB_QUEUE.future) 
    end
    # @debug "n_job_remaining lock_queuing ok"
    n += length(JOB_QUEUE.running)
    n
end

function are_remaining_jobs_more_than(x::Integer)
    n = length(JOB_QUEUE.running)
    n > x && return true

    # @debug "n_job_remaining lock_queuing"
    lock(JOB_QUEUE.lock_queuing) do
        for jobs in values(JOB_QUEUE.queuing)
            n += length(jobs)
            n > x && return
        end
        n += length(JOB_QUEUE.queuing_0cpu)
        n += length(JOB_QUEUE.future)
        n > x && return
    end
    # @debug "n_job_remaining lock_queuing ok"
    n > x
end


const id_delete_in_update_running = Int[]
const id_delete_in_move_future_to_queuing = Int[]
const id_delete_in_run_queuing = Int[]
const priority_delete = Int[]

function update_queue!()
    # @debug "update_queue! start"
    current = now()

    move_future_to_queuing(current)

    # update running: update state, cancel jobs reaching wall time, moving finished from running to others, add next recur of successfully finished job to future queue, and compute current usage.
    used_ncpu, used_mem = update_running!(current)
    update_resource(used_ncpu, used_mem)

    free_ncpu = SCHEDULER_MAX_CPU - used_ncpu
    free_mem = SCHEDULER_MAX_MEM - used_mem
    run_queuing!(current, free_ncpu, free_mem)

    # clean done and cancelled queue if exceed max_done and max_cancelled
    clean_queue!()
    # @debug "update_queue! done"
end

"""
    update_running!(current::DateTime)

update running: update state, cancel jobs reaching wall time, moving finished from running to others
"""
function update_running!(current::DateTime)
    global id_delete_in_update_running
    isempty(JOB_QUEUE.running) && return (0.0, Int64(0))
    
    # @debug "update_running! lock_running"
    used_ncpu, used_mem = lock(JOB_QUEUE.lock_running) do
        empty!(id_delete_in_update_running)
        used_ncpu = 0.0
        used_mem = Int64(0)
        for (i, job) in enumerate(JOB_QUEUE.running)
            
            if job.state === CANCELLED
                push!(id_delete_in_update_running, i)
                free_thread(job)
                push_cancelled!(job)
                PROGRESS_METER && update_group_state!(job)
                continue
            end

            # update state
            if istaskfailed2(job.task)
                unsafe_update_as_failed!(job, current)
                push!(id_delete_in_update_running, i)
                free_thread(job)
                push_failed!(job)
                PROGRESS_METER && update_group_state!(job)
                continue
            elseif job.state === DONE
                push!(id_delete_in_update_running, i)
                free_thread(job)
                push_done!(job)
                PROGRESS_METER && update_group_state!(job)
                continue
            elseif job.task.state === DONE
                unsafe_update_as_done!(job, current)
                push!(id_delete_in_update_running, i)
                free_thread(job)
                push_done!(job)
                PROGRESS_METER && update_group_state!(job)
                continue
            end

            if job.state === RUNNING
                # still running: check reaching wall time
                if job.start_time + job.wall_time < current
                    state = unsafe_cancel!(job, current)
                    if state === CANCELLED
                        push!(id_delete_in_update_running, i)
                        free_thread(job)
                        push_cancelled!(job)
                        PROGRESS_METER && update_group_state!(job)
                        continue
                    elseif state === DONE
                        push!(id_delete_in_update_running, i)
                        free_thread(job)
                        push_done!(job)
                        PROGRESS_METER && update_group_state!(job)
                        continue
                    elseif state === FAILED
                        push!(id_delete_in_update_running, i)
                        free_thread(job)
                        push_failed!(job)
                        PROGRESS_METER && update_group_state!(job)
                        continue
                    end
                end
            end

            # after moving, still running:
            used_ncpu += job.ncpu
            used_mem += job.mem
        end
        deleteat!(JOB_QUEUE.running, id_delete_in_update_running)
        used_ncpu, used_mem
    end
    # @debug "update_running! lock_running ok"
    used_ncpu, used_mem
end


function move_future_to_queuing(current::DateTime)
    global id_delete_in_move_future_to_queuing
    isempty(JOB_QUEUE.future) && return
    
    # @debug "move_future_to_queuing lock_queuing"
    lock(JOB_QUEUE.lock_queuing) do
        empty!(id_delete_in_move_future_to_queuing)
        for (i, job) in enumerate(JOB_QUEUE.future)
            if job.schedule_time <= current
                # move out from future
                if job.ncpu == 0
                    push!(JOB_QUEUE.queuing_0cpu, job)
                else
                    push_queuing!(JOB_QUEUE.queuing, job)
                end
                push!(id_delete_in_move_future_to_queuing, i)
            end
        end
        deleteat!(JOB_QUEUE.future, id_delete_in_move_future_to_queuing)
    end
    # @debug "move_future_to_queuing lock_queuing ok"
end

function run_queuing!(current::DateTime, free_ncpu::Real, free_mem::Int64)
    global id_delete_in_run_queuing
    global priority_delete
    # @debug "run_queuing! lock_queuing"
    lock(JOB_QUEUE.lock_queuing)
    try
        empty!(id_delete_in_run_queuing)
        
        # check queuing_0cpu first
        if !isempty(JOB_QUEUE.queuing_0cpu)
            # @debug "run_queuing! lock_queuing - check queuing_0cpu"
            for (i, job) in enumerate(JOB_QUEUE.queuing_0cpu)
                if job.mem <= free_mem && is_dependency_ok(job)
                    is_run_successful = try
                        unsafe_run!(job, current)
                    catch e
                        @error "Cannot run $(job.id) $(job.name). Skip." exception=e
                        false
                    end
                    if is_run_successful
                        free_mem  -= job.mem
                        push!(id_delete_in_run_queuing, i)
                        push_running!(job)
                    else
                        push!(id_delete_in_run_queuing, i)
                        if job.state === CANCELLED
                            push_cancelled!(job)
                        elseif job.state === DONE
                            push_done!(job)
                        elseif job.state === FAILED
                            push_failed!(job)
                        end
                    end
                    PROGRESS_METER && update_group_state!(job)
                end
            end
            deleteat!(JOB_QUEUE.queuing_0cpu, id_delete_in_run_queuing)
        end

        free_ncpu < 0.999 && return
        free_mem <= 0 && return

        # check normal queue: SortedDict{Int,MutableLinkedList{Job}}

        need_clean_empty_priority = length(JOB_QUEUE.queuing) > 10
        if need_clean_empty_priority
            empty!(priority_delete)
        end
        for p in JOB_QUEUE.queuing # lowest priority comes first
            priority, jobs = p
            # @debug "run_queuing! lock_queuing - scan priority = $priority"

            # remove empty priority
            if length(jobs) == 0
                if need_clean_empty_priority && priority != 20
                    push!(priority_delete, priority)  # 20 is default, don't delete
                end
                continue
            end

            # @debug "run_queuing! lock_queuing - scan priority = $priority - try run jobs"
            empty!(id_delete_in_run_queuing)
            for node in NodeIterate(jobs)
                job = node.data
            # for (i, job) in enumerate(jobs)
                if job.state === CANCELLED
                    deleteat!(jobs, node)
                    # push!(id_delete_in_run_queuing, i)
                    push_cancelled!(job)
                    PROGRESS_METER && update_group_state!(job)
                    continue
                end

                if job.ncpu <= free_ncpu + 0.001 && job.mem <= free_mem && is_dependency_ok(job)
                    # @debug "run_queuing! lock_queuing - scan priority = $priority - try run $(job.id) $(job.name)"
                    is_run_successful = try
                        unsafe_run!(job, current)
                    catch e
                        @error "Cannot run $(job.id) $(job.name). Skip." exception=e
                        false
                    end
                    if is_run_successful
                        free_ncpu -= job.ncpu
                        free_mem  -= job.mem
                        deleteat!(jobs, node)
                        # push!(id_delete_in_run_queuing, i)
                        push_running!(job)

                        free_ncpu < 0.999 && break
                        free_mem <= 0 && break
                    else
                        deleteat!(jobs, node)
                        # push!(id_delete_in_run_queuing, i)
                        if job.state === CANCELLED
                            push_cancelled!(job)
                        elseif job.state === DONE
                            push_done!(job)
                        elseif job.state === FAILED
                            push_failed!(job)
                        end
                    end
                    PROGRESS_METER && update_group_state!(job)
                else
                    # TODO 0.11.5-dev
                    # save if the next job's condition is the same, so we can skip.
                end
            end
            # @debug "run_queuing! lock_queuing - scan priority = $priority - delete running jobs"
            # deleteat!(jobs, id_delete_in_run_queuing)

            free_ncpu < 0.999 && break
            free_mem <= 0 && break
        end
        if need_clean_empty_priority
            for priority in priority_delete
                delete!(JOB_QUEUE.queuing, priority)
            end
        end
    catch
        rethrow()
    finally
        unlock(JOB_QUEUE.lock_queuing)
        # @debug "run_queuing! lock_queuing ok"
    end
end

"""
    clean done and cancelled queue if exceed `max_done` and `max_cancelled`
"""
function clean_queue!()
    if length(JOB_QUEUE.done) >= JOB_QUEUE.max_done * 1.5
        # @debug "clean_queue! JOB_QUEUE.lock_past 1"
        lock(JOB_QUEUE.lock_past) do
            n_delete = length(JOB_QUEUE.done) - JOB_QUEUE.max_done
            deleteat!(JOB_QUEUE.done, 1:n_delete)
        end
        # @debug "clean_queue! JOB_QUEUE.lock_past 1 ok"
    end

    if length(JOB_QUEUE.cancelled) >= JOB_QUEUE.max_cancelled * 1.5
        # @debug "clean_queue! JOB_QUEUE.lock_past 2"
        lock(JOB_QUEUE.lock_past) do
            n_delete = length(JOB_QUEUE.cancelled) - JOB_QUEUE.max_cancelled
            deleteat!(JOB_QUEUE.cancelled, 1:n_delete)
        end
        # @debug "clean_queue! JOB_QUEUE.lock_past 2 ok"
    end
end