include("../src/JobSchedulers.jl")

using .JobSchedulers
using Test

scheduler_start()
scheduler_status()

scheduler_stop()
scheduler_status()

scheduler_start()
sleep(2)
scheduler_status()


job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)
submit!(job)
job2 = Job(@task(begin; sleep(2); println("lowpriority"); end), name="low_priority", priority = 20)
submit!(job2)
job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)
submit!(job)
job = Job(@task(begin; sleep(2); println("midpriority"); end), name="mid_priority", priority = 15)
submit!(job)
for i in 1:20
    job = Job(@task(begin; sleep(2); println(i); end), name="$i", priority = 20)
    submit!(job)
end


jobx = Job(@task(begin; sleep(20); println("run_success"); end), name="to_cancel", priority = 20)
submit!(jobx)
cancel!(jobx)


using Dates
job2 = Job(@task(begin
    t = now()
    while true
        if (now() - t).value > 1000
            println(t)
            t = now()
        end
    end
end), name="to_cancel", priority = 20)
submit!(job2)
cancel!(job2)

submit!(job2) # cannot resubmit
# submit!(job)
submit!(job2)


# set backup
rm("/tmp/jl_job_scheduler_backup", force=true)
rm("/tmp/jl_job_scheduler_backup2", force=true)
set_scheduler_backup("/tmp/jl_job_scheduler_backup")

set_scheduler_backup("/tmp/jl_job_scheduler_backup", migrate=true) # do nothing because file not exist

backup()
njobs = JobSchedulers.JOB_QUEUE_OK |> length

deleteat!(JobSchedulers.JOB_QUEUE_OK, 1:3:njobs)

set_scheduler_max_cpu(1)
set_scheduler_backup("/tmp/jl_job_scheduler_backup")
@test njobs == JobSchedulers.JOB_QUEUE_OK |> length
@test JobSchedulers.SCHEDULER_MAX_CPU == Sys.CPU_THREADS

job_queue_backup = deepcopy(JobSchedulers.JOB_QUEUE_OK)

deleteat!(JobSchedulers.JOB_QUEUE_OK, 1:3:njobs)
set_scheduler_backup("/tmp/jl_job_scheduler_backup")

@test njobs == JobSchedulers.JOB_QUEUE_OK |> length

set_scheduler_backup("/tmp/jl_job_scheduler_backup2", migrate=true)
backup()


deleteat!(JobSchedulers.JOB_QUEUE_OK, 2:3:njobs)
set_scheduler_backup("/tmp/jl_job_scheduler_backup")
@test njobs == JobSchedulers.JOB_QUEUE_OK |> length
set_scheduler_backup("/tmp/jl_job_scheduler_backup2", migrate=true, delete_old=true)

@test !isfile("/tmp/jl_job_scheduler_backup")
@test isfile("/tmp/jl_job_scheduler_backup2")

set_scheduler_backup("", delete_old=true)
@test !isfile("/tmp/jl_job_scheduler_backup2")
