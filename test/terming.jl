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

j_stdout = Job(ncpu = 1) do 
    for i = 1:10
        println("stdout $i")
        sleep(0.4)
    end
end

j_stderr = Job(ncpu = 1) do 
    for i = 1:10
        println(stderr, "ERROR: test stderr color $i")
        sleep(0.3)
    end
end

j_stdlog = Job(ncpu = 1) do 
    for i = 1:10
        @info("log $i")
        sleep(0.5)
    end
end

submit!(j_stdout)
submit!(j_stderr)
submit!(j_stdlog)
wait_queue(show_progress = true)