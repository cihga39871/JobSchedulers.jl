@compile_workload begin
    using Pipelines
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
    Job(jp; _warn = false, input=kk, input2=22, optional_arg=:sym, output=i, priority=10, commonargs...)
    
    # scheduler_start(verbose=false)

    job = Job(@task(begin; sleep(2); println("highpriority"); end), name="high_priority", priority = 0)

    dep1 = Job(() -> println("jobwithdep"), name="dep1", 
        dependency = job, schedule_time = Second(1), cron = Cron(second = *), until = Second(3)
    )
    
    show(devnull, MIME("text/plain"), job)
    show(devnull, MIME("text/plain"), [job; dep1])
    
    show(devnull, job)
    show(devnull, [job; dep1])

    j_stdout = Job(ncpu = 1) do 
        for i = 1:3
            println("stdout $i")
            sleep(0.4)
        end
    end
    
    j_stderr = Job(ncpu = 1) do 
        for i = 1:3
            println(stderr, "ERROR: test stderr color $i")
            sleep(0.3)
        end
    end
    
    j_stdlog = Job(ncpu = 1) do 
        for i = 1:3
            @info("log $i")
            sleep(0.2)
        end
    end

    # cron
    JobSchedulers.cron_value_parse(0x0000000000000001) == 0x0000000000000001
    JobSchedulers.cron_value_parse("1,3,5,7,9") == 0x00000000000002aa
    JobSchedulers.cron_value_parse("*/3") == 0x9249249249249249
    JobSchedulers.cron_value_parse("1-9/2") == 0x00000000000002aa
    JobSchedulers.cron_value_parse([1,3,5, "7,9"]) == 0x00000000000002aa
    JobSchedulers.cron_value_parse([1,3,5, "*"]) == 0xffffffffffffffff
    
    c = Cron()
    JobSchedulers.tonext(Time(23,59,55), c) == Time(0,0,0)
    JobSchedulers.tonext(Time(0,0,0), c, same=true) == Time(0,0,0)
    JobSchedulers.tonext(Time(0,59,00), c) == Time(1,0,0)

    c4 = Cron(:weekly)
    JobSchedulers.tonext(Date(2023,1,3), c4) == Date(2023,1,9)

    c5 = Cron(:daily)
    JobSchedulers.tonext(Date(2023,1,2), c5) == Date(2023,1,3)
    
    c6 = Cron(30, 45, 20, "*/2", *, *)
    JobSchedulers.tonext(DateTime(2023,1,2,20,45,00), c6) == DateTime(2023,1,2,20,45,30)

    # wait_queue()
    # scheduler_stop(verbose=false)
    nothing
end