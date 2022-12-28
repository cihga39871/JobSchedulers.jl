# Test for Progress Summary of Job Queues
#=

using JobSchedulers
using Base.Threads
using Test
scheduler_start()

=#

j_std = Job() do 
    while true
        @info "$(now())"
        println("[$(now())] default std")
        println(Base.stdout, "[$(now())] Base.stdout")
        println(Base.stderr, "[$(now())] Base.stderr")
        sleep(10)
    end
end
submit!(j_std)

using Terming

function main()
    # set term size and clear
    Terming.displaysize(20, 75); Terming.clear()

    # enable raw mode
    Terming.raw!(true)
    event = nothing
    while event != Terming.KeyPressedEvent(Terming.ESC)
        # read in_stream
        sequence = Terming.read_stream()
        # parse in_stream sequence to event
        event = Terming.parse_sequence(sequence)
        @show event
    end
    # disable raw mode
    Terming.raw!(false)

    return
end



main()

println(Pipelines.stdout_origin, progress_bar(0.0, 3))
println(Pipelines.stdout_origin, progress_bar(0.4, 3))
println(Pipelines.stdout_origin, progress_bar(1.0, 3))
println(Pipelines.stdout_origin, progress_bar(0.0, 10))
println(Pipelines.stdout_origin, progress_bar(1.0, 10))
println(Pipelines.stdout_origin, progress_bar(1.1, 10))
println(Pipelines.stdout_origin, progress_bar(-0.8, 20))
println(Pipelines.stdout_origin, progress_bar(0.985, 20))
println(Pipelines.stdout_origin, progress_bar(0.05, 20))
println(Pipelines.stdout_origin, progress_bar(0.199, 20))
