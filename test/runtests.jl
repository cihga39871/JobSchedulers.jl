
using JobSchedulers
using Base.Threads
using Test

scheduler_balance_check(title::String) = @testset "Balance check after $title" begin
	@info "scheduler_balance_check: wait_queue: $title"
	wait_queue()
	@test scheduler_status() === RUNNING
	
	@test JobSchedulers.RESOURCE.njob == 0
	@test length(JobSchedulers.THREAD_POOL[].data) == length(JobSchedulers.TIDS)
	@test Set(JobSchedulers.THREAD_POOL[].data) == Set(JobSchedulers.TIDS)
end

@testset "JobSchedulers" begin

	include("test_linked_job_list.jl")

	@testset "Basic" begin

		jq = JobSchedulers.JobQueue()
		@test JobSchedulers.destroy_unnamed_jobs_when_done(true)

		@test JobSchedulers.check_need_redirect(nothing, nothing) == false
		@test JobSchedulers.check_need_redirect("", nothing) == false
		@test JobSchedulers.check_need_redirect("abc", nothing)
		@test JobSchedulers.check_need_redirect(IOBuffer())
		@test_broken JobSchedulers.check_need_redirect(5)
		@test !JobSchedulers.check_need_redirect(nothing)
		@test JobSchedulers.convert_dependency_element(DONE => 1) == (DONE => 1)
		@test JobSchedulers.convert_dependency_element(DONE => Int32(1)) == (DONE => Int64(1))
		@test JobSchedulers.convert_dependency_element(Int32(1)) == (DONE => Int64(1))

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
		JobSchedulers.unsafe_update_state!(command_job)
		submit!(task_job)
		submit!(function_job)
		@test scheduler_status() === :running
		wait_queue()
		@test scheduler_status() === :running

		job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)
		display(job)
		submit!(job)
		fetch(job)

		@test !isqueuing(job)
		@test !isrunning(job)
		@test isdone(job)
		@test !iscancelled(job)
		@test !isfailed(job)
		@test ispast(job)
		@test JobSchedulers.get_thread_id(job) <= 0
		@test JobSchedulers.get_priority(job) == 0

		solve_optimized_ncpu(5)


		scheduler_balance_check("job submission")

		@test scheduler_status() === :running


		j2 = job_query_by_id(job.id)
		j3 = job_query_by_id(job)
		j3 = JobSchedulers.job_query_by_id_no_lock(job)
		@test j2 === job
		@test j3 === job

		job2 = Job(@task(begin; sleep(0.5); println("lowpriority"); end), name="low_priority", priority = 20)
		submit!(job2)
		job = Job(@task(begin; sleep(0.5); println("highpriority"); end), name="high_priority", priority = 0)
		submit!(job)
		job = Job(@task(begin; sleep(0.5); println("midpriority"); end), name="mid_priority", priority = 15)
		submit!(job)
		@test_throws Exception submit!(job) # cannot resubmit

		for i in 1:15
			local job = Job(@task(begin; sleep(0.5); println(i); end), name="batch: $i", priority = 20+i)
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
		end), name="to_cancel2", priority = 20)
		
		@info "submit!(job2)"
		submit!(job2)
		@info "cancel!(job2)"
		cancel!(job2)

		@test_throws Exception submit!(job2) # cannot resubmit
		@test_throws Exception submit!(job) # cannot resubmit

		j = Job(@task 1+1)
		j.task = nothing
		@test_throws Exception submit!(j)
		@test JobSchedulers.unsafe_run!(j) == JobSchedulers.FAIL
		@test JobSchedulers.unsafe_cancel!(j) == CANCELLED

		jobx2 = Job(@task(begin; sleep(20); println("run_success"); end), name="to_cancel", priority = 20, stdout=IOBuffer())
		jobx3 = Job(() -> (begin; sleep(20); println("run_success"); end), name="to_cancel", priority = 20, stdout=IOBuffer())
		jobx4 = Job(`sleep 1`, name="to_cancel", priority = 20, stdout=IOBuffer())


		fetch(job)
		@test JobSchedulers.unsafe_cancel!(job) == :done

		scheduler_balance_check("job cancellation")

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

		io = IOBuffer()
		close_in_future(io, job_with_dep)
		close_in_future(io, [job_with_dep2, job_with_dep3])

		wait_queue()
	end

	@testset "Backup" begin
		### set backup

		tmp1 = tempname()
		tmp2 = tempname()
		
		rm(tmp1, force=true)
		rm(tmp2, force=true)
		set_scheduler_backup(tmp1)

		set_scheduler_backup(tmp1, migrate=true) # do nothing because file not exist

		backup()
		njobs = length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)

		deleteat!(JobSchedulers.JOB_QUEUE.done, 1:3:length(JobSchedulers.JOB_QUEUE.done))
		deleteat!(JobSchedulers.JOB_QUEUE.failed, 1:3:length(JobSchedulers.JOB_QUEUE.failed))
		deleteat!(JobSchedulers.JOB_QUEUE.cancelled, 1:3:length(JobSchedulers.JOB_QUEUE.cancelled))

		# set_scheduler_max_cpu(2)
		set_scheduler_backup(tmp1)
		@test njobs == length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)

		deleteat!(JobSchedulers.JOB_QUEUE.done, 1:3:length(JobSchedulers.JOB_QUEUE.done))
		deleteat!(JobSchedulers.JOB_QUEUE.failed, 1:3:length(JobSchedulers.JOB_QUEUE.failed))
		deleteat!(JobSchedulers.JOB_QUEUE.cancelled, 1:3:length(JobSchedulers.JOB_QUEUE.cancelled))

		set_scheduler_backup(tmp1)

		@test njobs == length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)

		set_scheduler_backup(tmp2, migrate=true)
		backup()

		deleteat!(JobSchedulers.JOB_QUEUE.done, 2:3:length(JobSchedulers.JOB_QUEUE.done))
		deleteat!(JobSchedulers.JOB_QUEUE.failed, 2:3:length(JobSchedulers.JOB_QUEUE.failed))
		deleteat!(JobSchedulers.JOB_QUEUE.cancelled, 2:3:length(JobSchedulers.JOB_QUEUE.cancelled))
		
		set_scheduler_backup(tmp1)
		@test njobs == length(JobSchedulers.JOB_QUEUE.done) + length(JobSchedulers.JOB_QUEUE.failed) + length(JobSchedulers.JOB_QUEUE.cancelled)

		set_scheduler_backup(tmp2, migrate=true, delete_old=true)

		@test !isfile(tmp1)
		@test isfile(tmp2)

		set_scheduler_backup("", delete_old=true)
		@test !isfile(tmp2)
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
		cmdprog_job2 = Job(echo, inputs, Dict(), touch_run_id_file=false)
		cmdprog_job3 = Job(echo; INPUT1 = "H", INPUT2 = "P", touch_run_id_file=false)
		@test_throws ErrorException Job(echo, touch_run_id_file=false)

		submit!(cmdprog_job)
		submit!(cmdprog_job2)
		submit!(cmdprog_job3)
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

	if !JobSchedulers.SINGLE_THREAD_MODE[]
		include("test_thread_id.jl")
	else
		@warn "`JobSchedulers.SINGLE_THREAD_MODE[]` during testing. It will not test multi-thread related codes."
	end

	scheduler_balance_check("thread ID test")

	@testset "Terming" begin
		include("terming.jl")
	end

	scheduler_balance_check("terminal tests")

	@testset "Recur" begin
		include("recur.jl")
	end

	scheduler_balance_check("recur job tests")

	@testset "Macro" begin
		include("test_macro.jl")
	end

	scheduler_balance_check("macro @submit tests")

	@testset "Scoped Values" begin
		include("scoped_values.jl")
	end

	scheduler_balance_check("scoped value tests")
	
	default_mem()
	default_ncpu()
	set_scheduler_max_mem(0.85)
	@test_warn "between 0 and 1" set_scheduler_max_mem(1.85)
	@test set_scheduler_update_second(1) == 1.0
	set_scheduler()
end
