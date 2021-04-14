include("../src/JobSchedulers.jl")

using .JobSchedulers

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
submit!(job2)

submit!(job) # it is ok to submit task :done
submit!(job2)
