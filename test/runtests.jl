include("../src/JobSchedulers.jl")

using .JobSchedulers
using Base.Threads
using Dates
using Test

scheduler_start()
scheduler_status()

scheduler_stop()
scheduler_status()

scheduler_start()
sleep(2)
scheduler_status()


job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)
display(job)
submit!(job)

j2 = job_query_by_id(job.id)
@test j2 === job

job2 = Job(@task(begin; sleep(2); println("lowpriority"); end), name="low_priority", priority = 20)
submit!(job2)
job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)
submit!(job)
job = Job(@task(begin; sleep(2); println("midpriority"); end), name="mid_priority", priority = 15)
submit!(job)
for i in 1:20
    local job = Job(@task(begin; sleep(2); println(i); end), name="$i", priority = 20)
    submit!(job)
end


jobx = Job(@task(begin; sleep(20); println("run_success"); end), name="to_cancel", priority = 20)
submit!(jobx)
cancel!(jobx)



job2 = Job(@task(begin
    while true
        println(now())
        sleep(1)
    end
end), name="to_cancel", priority = 20)
submit!(job2)
cancel!(job2)

@test_logs (:error,) submit!(job2) # cannot resubmit
@test_throws Exception submit!(job) # cannot resubmit
@test_logs (:error,) submit!(job2)


### dependency
dep1 = Job(@task(begin
    sleep(2)
    println("dep1 ok")
end), name="dep1", priority = 20)

dep2 = Job(@task(begin
    sleep(3)
    println("dep2 ok")
end), name="dep2", priority = 20)

job_with_dep = Job(@task(begin
    println("job with dep1 and dep2 ok")
end), name="job_with_dep", priority = 20,
dependency = [DONE => dep1.id, DONE => dep2])

job_with_dep2 = Job(@task(begin
    println("job with dep2 ok")
end), name="job_with_dep", priority = 20,
dependency = DONE => dep2)

submit!(dep1)
submit!(dep2)
submit!(job_with_dep)
submit!(job_with_dep2)

while JobSchedulers.DataFrames.nrow(queue()) > 0 && scheduler_status(verbose=false) === RUNNING
    sleep(2)
end

### set backup
rm("/tmp/jl_job_scheduler_backup", force=true)
rm("/tmp/jl_job_scheduler_backup2", force=true)
set_scheduler_backup("/tmp/jl_job_scheduler_backup")

set_scheduler_backup("/tmp/jl_job_scheduler_backup", migrate=true) # do nothing because file not exist

backup()
njobs = JobSchedulers.JOB_QUEUE_OK |> length

deleteat!(JobSchedulers.JOB_QUEUE_OK, 1:3:njobs)

set_scheduler_max_cpu(2)
set_scheduler_backup("/tmp/jl_job_scheduler_backup")
@test njobs == JobSchedulers.JOB_QUEUE_OK |> length
@test JobSchedulers.SCHEDULER_MAX_CPU == (Base.Threads.nthreads() > 1 ? Base.Threads.nthreads()-1 : Sys.CPU_THREADS)

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


### Compat Pipelines.jl
using Pipelines
echo = CmdProgram(
    inputs = ["INPUT1", "INPUT2"],
    cmd = `echo INPUT1 INPUT2`
)
inputs = Dict(
    "INPUT1" => "Hello,",
    "INPUT2" => `Pipeline.jl`
)
cmdprog_job = Job(echo, inputs, touch_run_id_file=false)
cmdprog_job2 = Job(echo, inputs=inputs, touch_run_id_file=false)
cmdprog_job3 = Job(echo, touch_run_id_file=false)

submit!(cmdprog_job)
submit!(cmdprog_job2)
submit!(cmdprog_job3)

while cmdprog_job3.state in (QUEUING, RUNNING) && scheduler_status(verbose=false) === RUNNING
	sleep(1)
end
@test cmdprog_job3.state == :failed

if Base.Threads.nthreads() > 1
    include("test_thread_id.jl")
end

### Compat Pipeline v0.5.0
# Extend `Base.istaskfailed` to fit Pipelines and JobSchedulers packages, which will return a `StackTraceVector` in `t.result`, while Base considered it as `:done`. The function will check and modify the situation and then return the real task status.

p_error = JuliaProgram(
	name = "Julia Program with Errors",
	id_file = "id_file",
	inputs = [
		:a => 10.6 => Float64,
		:b =>  5 => Int
	],
	main = (inputs, outputs) -> begin
		inputs["b"] + "ed"
	end
)

j_error = Job(p_error, touch_run_id_file=false);
submit!(j_error)
while j_error.state in (QUEUING, RUNNING) && scheduler_status(verbose=false) === RUNNING
	sleep(1)
end
@test j_error.state === :failed

## v0.6.7 @Job
jp = JuliaProgram(
	name = "Echo",
	id_file = "id_file",
	inputs = [
		"input",
		"input2" => Int,
		"optional_arg" => 5,
		"optional_arg2" => 0.5 => Number
	],
	outputs = [
		"output" => "<input>.output"
	],
	main = (x,y) -> begin
		@show x
		@show y
		y
	end
)

i = "iout"
kk = :xxx
b = false
commonargs = (touch_run_id_file = b, verbose = :min)
job = @Job jp input=kk input2=22 optional_arg=:sym output=i priority=10 commonargs...
@test job.priority == 10

submit!(job)
while job.state in (QUEUING, RUNNING) && scheduler_status(verbose=false) === RUNNING
	sleep(1)
end
@test result(job) == (true, Dict{String, Any}("output" => "iout"))

@test scheduler_status() === RUNNING

@info "Test finished."
