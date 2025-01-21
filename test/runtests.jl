
using JobSchedulers
using Base.Threads
using Test

@testset "JobSchedulers" begin

	@testset "Basic" begin

		scheduler_start()
		scheduler_status()

		scheduler_stop()
		scheduler_status()

		scheduler_start()
		@test scheduler_status() === :running

		# simple jobs
		command_job = Job(`sleep 1`; name="command job")
		task_job = Job(@task(sleep(1)); name="task job")
		function_job = Job(;name="function job") do
		    sleep(1)
		end
		submit!(command_job)
		submit!(task_job)
		submit!(function_job)
		wait_queue()
		@test scheduler_status() === :running

		job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)
		display(job)
		submit!(job)

		wait_queue()

		@test scheduler_status() === :running


		j2 = job_query_by_id(job.id)
		@test j2 === job

		job2 = Job(@task(begin; sleep(2); println("lowpriority"); end), name="low_priority", priority = 20)
		submit!(job2)
		job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)
		submit!(job)
		job = Job(@task(begin; sleep(2); println("midpriority"); end), name="mid_priority", priority = 15)
		submit!(job)
		for i in 1:10
			local job = Job(@task(begin; sleep(2); println(i); end), name="batch: $i", priority = 20)
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
		
		@info "submit!(job2)"
		submit!(job2)
		@info "cancel!(job2)"
		cancel!(job2)

		@test_throws Exception submit!(job2) # cannot resubmit
		@test_throws Exception submit!(job) # cannot resubmit
	end

	@testset "Dependency" begin
		### dependency
		# sleep(1)
		dep1 = Job(@task(begin
			sleep(2)
			println("dep1 ok")
		end), name="dep: 1", priority = 20)
		# sleep(1)

		dep2 = Job(@task(begin
			sleep(3)
			println("dep2 ok")
		end), name="dep: 2", priority = 20)

		job_with_dep = Job(@task(begin
			println("job with dep1 and dep2 ok")
		end), name="dep: job_with_dep", priority = 20,
		dependency = [DONE => dep1.id, DONE => dep2])

		job_with_dep2 = Job(@task(begin
			println("job with dep2 ok")
		end), name="dep: job_with_dep", priority = 20,
		dependency = DONE => dep2)

		job_with_dep3 = Job(@task(begin
			println("job with dep3 ok")
		end), name="dep: job_with_dep", priority = 20,
		dependency = dep2)


		submit!(dep1)
		submit!(dep2)
		submit!(job_with_dep)
		submit!(job_with_dep2)
		submit!(job_with_dep3)
		submit!(@task(begin
			println("job_no_cpu ok")
		end), name="dep: job_with_dep", priority = 20, ncpu = 0)

		job_with_args = Job(
			@task(begin println("job_with_args done"); "result" end); # Task to run
			name = "job with args",               # job name.
			user = "me",                # Job owner.
			ncpu = 1.6,                 # Number of CPU required.
			mem = 1KB,                  # Number of memory required (unit: TB, GB, MB, KB, B).
			schedule_time = Second(3),  # Run after 3 seconds; can be ::DateTime or ::Period.
			wall_time = Hour(1),        # The maximum time to run the job. (Cancel job after reaching wall time.)
			priority = 20,              # Lower number = higher priority.
			dependency = [              # Defer job until some jobs reach some states.
				dep2,
				DONE => job_with_dep2
			]
		)

		wait_queue()
	end

	@testset "Backup" begin
		### set backup
		rm("/tmp/jl_job_scheduler_backup", force=true)
		rm("/tmp/jl_job_scheduler_backup2", force=true)
		set_scheduler_backup("/tmp/jl_job_scheduler_backup")

		set_scheduler_backup("/tmp/jl_job_scheduler_backup", migrate=true) # do nothing because file not exist

		backup()
		njobs = length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)

		deleteat!(JobSchedulers.JOB_QUEUE.done, 1:3:length(JobSchedulers.JOB_QUEUE.done))
		deleteat!(JobSchedulers.JOB_QUEUE.failed, 1:3:length(JobSchedulers.JOB_QUEUE.failed))
		deleteat!(JobSchedulers.JOB_QUEUE.cancelled, 1:3:length(JobSchedulers.JOB_QUEUE.cancelled))

		set_scheduler_max_cpu(2)
		set_scheduler_backup("/tmp/jl_job_scheduler_backup")
		@test njobs == length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)
		@test JobSchedulers.SCHEDULER_MAX_CPU == (Base.Threads.nthreads() > 1 ? Base.Threads.nthreads()-1 : Sys.CPU_THREADS)

		deleteat!(JobSchedulers.JOB_QUEUE.done, 1:3:length(JobSchedulers.JOB_QUEUE.done))
		deleteat!(JobSchedulers.JOB_QUEUE.failed, 1:3:length(JobSchedulers.JOB_QUEUE.failed))
		deleteat!(JobSchedulers.JOB_QUEUE.cancelled, 1:3:length(JobSchedulers.JOB_QUEUE.cancelled))

		set_scheduler_backup("/tmp/jl_job_scheduler_backup")

		@test njobs == length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)

		set_scheduler_backup("/tmp/jl_job_scheduler_backup2", migrate=true)
		backup()

		deleteat!(JobSchedulers.JOB_QUEUE.done, 2:3:length(JobSchedulers.JOB_QUEUE.done))
		deleteat!(JobSchedulers.JOB_QUEUE.failed, 2:3:length(JobSchedulers.JOB_QUEUE.failed))
		deleteat!(JobSchedulers.JOB_QUEUE.cancelled, 2:3:length(JobSchedulers.JOB_QUEUE.cancelled))
		
		set_scheduler_backup("/tmp/jl_job_scheduler_backup")
		@test njobs == length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)

		set_scheduler_backup("/tmp/jl_job_scheduler_backup2", migrate=true, delete_old=true)

		@test !isfile("/tmp/jl_job_scheduler_backup")
		@test isfile("/tmp/jl_job_scheduler_backup2")

		set_scheduler_backup("", delete_old=true)
		@test !isfile("/tmp/jl_job_scheduler_backup2")
	end

	@testset "Compat Pipelines.jl" begin
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
		@test_throws ErrorException cmdprog_job3 = Job(echo, touch_run_id_file=false)

		submit!(cmdprog_job)
		submit!(cmdprog_job2)
	end

	### Compat Pipeline v0.5.0
	# Extend `Base.istaskfailed` to fit Pipelines and JobSchedulers packages, which will return a `StackTraceVector` in `t.result`, while Base considered it as `:done`. The function will check and modify the situation and then return the real task status.
	@testset "Compat Pipelines v0.5" begin
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
		@warn "The following will show method error of +"
		j_error = Job(p_error, touch_run_id_file=false);
		submit!(j_error)
		while j_error.state in (QUEUING, RUNNING) && scheduler_status(verbose=false) === RUNNING
			sleep(1)
		end
		@test j_error.state === :failed
	end


	## Compat Pipelines v0.8
	@testset "Compat Pipelines v0.8" begin
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
		job = Job(jp; input=kk, input2=22, optional_arg=:sym, output=i, priority=10, commonargs...)
		@test job.priority == 10

		submit!(job)
		while job.state in (QUEUING, RUNNING) && scheduler_status(verbose=false) === RUNNING
			sleep(1)
		end
		@test result(job) == (true, Dict{String, Any}("output" => "iout"))

	end


	@testset "Compat Pipelines v0.8.5" begin
		jp = JuliaProgram(
			name = "Echo",
			id_file = "id_file",
			inputs = [
				"NAME", "USER", :NCPU, :MEM
			],
			main = quote
				@show NAME
				@show USER
				@show NCPU
				@show MEM
			end,
			arg_forward = [
				"NAME" => :name,
				:USER => "user",
				"NCPU" => "ncpu",
				:MEM => :mem
			]
		)
		commonargs = (touch_run_id_file = false, verbose = :min)
		job = Job(jp; NAME = "cihga39871", USER = "CJC", NCPU=3, MEM=666, priority=10, commonargs...)
		@test job.priority == 10
		@test job.name == "cihga39871"
		@test job.user == "CJC"
		@test job.ncpu == 3
		@test job.mem == 666

		job.ncpu = 0.5
		submit!(job)
		while job.state in (QUEUING, RUNNING) && scheduler_status(verbose=false) === RUNNING
			sleep(1)
		end
		@test result(job) == (true, Dict{String, Any}())

	end

	if Base.Threads.nthreads() > 1
		include("test_thread_id.jl")
	else
		@warn "Threads.nthreads() == 1 during testing is not recommended. Please run Julia in multi-threads to test JobSchedulers."
	end

	@testset "Terming" begin
		include("terming.jl")
	end
	@testset "Recur" begin
		include("recur.jl")
	end

	@testset "Macro" begin
		include("test_macro.jl")
	end


	@test scheduler_status() === RUNNING
end
