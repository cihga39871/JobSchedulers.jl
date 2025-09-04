# Test for Progress Summary of Job Queues
#=

using JobSchedulers
using Base.Threads
using Test
scheduler_start()

=#

io_from = open(joinpath(@__DIR__, "log.log"), "r")
@test_nowarn JobSchedulers.print_rest_lines(Base.stdout, io_from, 0)
close(io_from)

@test JobSchedulers.progress_bar(NaN, 1; is_in_terminal=false) == "100.00% ▕████████████████████▎"
@test JobSchedulers.progress_bar(NaN, 1; is_in_terminal=true) == "▕\e[32m█\e[39m▎"
@test JobSchedulers.progress_bar(0.9, 20; is_in_terminal=false) == " 90.00% ▕██████████████████  ▎"
@test JobSchedulers.progress_bar(0.3333, 20; is_in_terminal=false) == " 33.33% ▕██████▋             ▎"



println(stdout, JobSchedulers.progress_bar(0.0, 3))
println(stdout, JobSchedulers.progress_bar(0.4, 3))
println(stdout, JobSchedulers.progress_bar(1.0, 3))
println(stdout, JobSchedulers.progress_bar(0.0, 10))
println(stdout, JobSchedulers.progress_bar(1.0, 10))
println(stdout, JobSchedulers.progress_bar(1.1, 10))
println(stdout, JobSchedulers.progress_bar(-0.8, 20))
println(stdout, JobSchedulers.progress_bar(0.985, 20))
println(stdout, JobSchedulers.progress_bar(0.05, 20))
println(stdout, JobSchedulers.progress_bar(0.199, 20))

j_stdout = Job(ncpu = 1, name = "terming: 1") do 
    for i = 1:10
        println("stdout $i")
        sleep(0.4)
    end
end

j_stderr = Job(ncpu = 1, name = "terming: 2") do 
    for i = 1:10
        println(stderr, "ERROR: test stderr color $i")
        sleep(0.3)
    end
end

j_stdlog = Job(ncpu = 1, name = "terming: 3") do 
    for i = 1:10
        @info("log $i")
        sleep(0.5)
    end
end

submit!(j_stdout)
submit!(j_stderr)
submit!(j_stdlog)

tmp_file = tempname()
tmpbuffer = open(tmp_file, "w+")
try
    JobSchedulers.queue_progress(tmpbuffer, tmpbuffer)
finally
    close(tmpbuffer)
    rm(tmp_file; force=true)
end
wait_queue(show_progress = true)
JobSchedulers.normal_print_queue_progress()

queue(:all)
queue()
show(stdout, "text/plain", queue(PAST))


## Job group
JobSchedulers.set_group_seperator(r": *")
JobSchedulers.JobGroup("group name")

## line style
@test JobSchedulers.style_line("", :nothing) == ("", :nothing)
JobSchedulers.style_line("ERROR: abc", :nothing)
JobSchedulers.style_line(" @ trackback:12345", :nothing)
@test JobSchedulers.style_line("[ Info: info", :nothing)[2] == :info
@test JobSchedulers.style_line("[ Debug: debug", :nothing)[2] == :debug
@test JobSchedulers.style_line("[ Warning: warn", :nothing)[2] == :warning
@test JobSchedulers.style_line("[ Error: error", :nothing)[2] == :error
JobSchedulers.style_line("│ x = 5", :info)
JobSchedulers.style_line("│ x = 5", :debug)
JobSchedulers.style_line("│ x = 5", :warning)
@test JobSchedulers.style_line("└ end", :warning)[2] == :nothing

@test_nowarn JobSchedulers.init_group_state!()

@test_nowarn JobSchedulers.compute_other_job_group!([JobSchedulers.JOB_GROUPS["terming"]])
@test JobSchedulers.get_group(j_stdlog) == "terming"

queue(QUEUING)
queue(RUNNING)
queue(DONE)
queue(FAILED)
queue(CANCELLED)
js = queue(PAST)
queue(" ", DONE)
queue(j_stdout.id)
@test_logs (:warn,) queue(:abc)
all_queue()
all_queue(j_stdout.id)
all_queue(DONE)
all_queue("1")

Base.propertynames(j_stdout, true)
Base.propertynames(j_stdout, false)
@test JobSchedulers.trygetfield(j_stdout, :sym) == "#undef"
show(stdout, MIME("text/plain"), j_stdout)
show(stdout, MIME("text/plain"), Job(undef))
show(stdout, j_stdout)
show(stdout, Job(undef))
j_stdout.task = nothing
show(stdout, MIME("text/plain"), j_stdout)
show(stdout, j_stdout)
j_stdout.name = ""
show(stdout, j_stdout)


show(stdout, MIME("text/plain"), js; allrows=true)
show(stdout, MIME("text/plain"), js; allcols=true)
show(stdout, MIME("text/plain"), js; allcols=true, allrows=true)
show(stdout, MIME("text/plain"), js; allcols=false, allrows=false)

@test JobSchedulers.simplify(DateTime(0)) == "na"
@test JobSchedulers.simplify(DateTime(9999,1,2,3,4,5)) == "forever"
@test JobSchedulers.simplify(DateTime(2023,1,2,3,4,5)) == "2023-01-02 03:04:05"

@test JobSchedulers.simplify(Pair{Symbol,Union{Int, Job}}[], false) == "[]"
@test JobSchedulers.simplify(Pair{Symbol,Union{Int, Job}}[DONE => 123456]) == "[:done => 123456]"
@test JobSchedulers.simplify(Pair{Symbol,Union{Int, Job}}[DONE => j_stdout])[1:10] == "[:done => "
@test JobSchedulers.simplify(Pair{Symbol,Union{Int, Job}}[DONE => j_stdout, DONE => j_stderr]) == "2 jobs"

t = @task 1+1
@test JobSchedulers.simplify(t) == "Task"

@test JobSchedulers.simplify_memory(parse(Int64, "1024")) == "1.0 KB"
@test JobSchedulers.simplify_memory(parse(Int64, "1048576")) == "1.0 MB"
@test JobSchedulers.simplify_memory(parse(Int64, "1073741824")) == "1.0 GB"
@test JobSchedulers.simplify_memory(parse(Int64, "1099511627776")) == "1.0 TB"
@test JobSchedulers.simplify_memory(parse(Int64, "15995116277765")) == "14.5 TB"

@test Base.Dict(j_stdout) isa Dict{Symbol, Any}
@test JobSchedulers.JSON.Writer.json(j_stdout) isa String
@test JobSchedulers.json_queue(all=true) isa String 

@test set_scheduler_update_second(1) == 1.0