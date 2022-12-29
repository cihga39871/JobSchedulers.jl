# Test for Progress Summary of Job Queues
#=

using JobSchedulers
using Base.Threads
using Test
scheduler_start()

=#

println(Pipelines.stdout_origin, JobSchedulers.progress_bar(0.0, 3))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(0.4, 3))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(1.0, 3))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(0.0, 10))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(1.0, 10))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(1.1, 10))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(-0.8, 20))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(0.985, 20))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(0.05, 20))
println(Pipelines.stdout_origin, JobSchedulers.progress_bar(0.199, 20))

