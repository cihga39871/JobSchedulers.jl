
@testset "Recur basic" begin

    @test JobSchedulers.bitfindnext(0x0000000000000001, 0) == 0
    @test JobSchedulers.bitfindnext(0x0000000000000001, 1) === nothing
    @test JobSchedulers.bitfindnext(0x0000000000000001, 64) === nothing
    @test_throws Exception JobSchedulers.bitfindnext(0x0000000000000001, -1)
    @test_throws Exception Cron(:abc)

    @test !JobSchedulers.first_is_asterisk(1)
    @test !JobSchedulers.first_is_asterisk([1])
    @test JobSchedulers.first_is_asterisk([*])

    dt = DateTime("2023-04-21T10:25:09.719")

    @test_throws Exception JobSchedulers.cron_value_parse(64)
    @test_throws Exception JobSchedulers.cron_value_parse(+)
    @test_throws Exception JobSchedulers.cron_value_parse("abc")
    @test_throws Exception JobSchedulers.cron_value_parse('a')
    

    @test JobSchedulers.cron_value_parse(0x0000000000000001) == 0x0000000000000001
    @test JobSchedulers.cron_value_parse([1,3,5,7,9]) == 0x00000000000002aa
    @test JobSchedulers.cron_value_parse("1,3,5,7,9") == 0x00000000000002aa
    @test JobSchedulers.cron_value_parse("1-9/2") == 0x00000000000002aa
    @test JobSchedulers.cron_value_parse("*/4") == 0x1111111111111111
    @test JobSchedulers.cron_value_parse("*/3") == 0x9249249249249249
    @test JobSchedulers.cron_value_parse("*/2") == 0x5555555555555555
    @test JobSchedulers.cron_value_parse("*/1") == 0xffffffffffffffff
    @test JobSchedulers.cron_value_parse("*") == 0xffffffffffffffff
    @test JobSchedulers.cron_value_parse("1-5,7,7,4") == 0x00000000000000be
    @test JobSchedulers.cron_value_parse("1-5,7,7,4/2") == 0x55555555555555fe
    @test JobSchedulers.cron_value_parse("0-5,7,7,4") == 0x00000000000000bf
    @test JobSchedulers.cron_value_parse("5/2") == 0xaaaaaaaaaaaaaaa0
    @test JobSchedulers.cron_value_parse('*') == 0xffffffffffffffff
    @test JobSchedulers.cron_value_parse('2') == 0x0000000000000004
    @test JobSchedulers.cron_value_parse([1,3,5, "7,9"]) == 0x00000000000002aa
    @test JobSchedulers.cron_value_parse([1,3,5, "*"]) == 0xffffffffffffffff

    c = Cron()
    show(stdout, MIME("text/plain"), c)
    @test JobSchedulers.tonext(Time(23,59,59), c) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(23,59,55), c) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(0,0,0), c) == Time(0,1,0)
    @test JobSchedulers.tonext(Time(0,0,0), c, same=true) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(0,59,00), c) == Time(1,0,0)

    c1 = Cron(:hourly)
    show(stdout, MIME("text/plain"), c1)
    @test JobSchedulers.tonext(Time(23,59,59), c1) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(23,59,00), c1) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(23,00,00), c1, same=true) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,00,00), c1) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,00,01), c1) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,00,01), c1, same=true) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,01,01), c1, same=true) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,01,01), c1) == Time(23,00,0)


    for c2 in (Cron(:yearly), Cron(0,0,0,1,1,0))
    show(stdout, MIME("text/plain"), c2)
    @test JobSchedulers.date_based_on(c2) == :day_of_month
    @test JobSchedulers.tonext(Date(2023,1,2), c2) == Date(2024,1,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c2) == Date(2024,1,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c2, same=true) == Date(2023,1,1)
    end

    for c3 in (Cron(:monthly), Cron(0,0,0,1,*,0))
    show(stdout, MIME("text/plain"), c3)
    @test JobSchedulers.date_based_on(c3) == :day_of_month
    @test JobSchedulers.tonext(Date(2023,1,2), c3) == Date(2023,2,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c3) == Date(2023,2,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c3, same=true) == Date(2023,1,1)
    @test JobSchedulers.tonext(Date(2023,12,1), c3, same=true) == Date(2023,12,1)
    @test JobSchedulers.tonext(Date(2023,12,1), c3) == Date(2024,1,1)
    end

    for c4 in (Cron(:weekly), Cron(0,0,0,0,*,1))
    show(stdout, MIME("text/plain"), c4)
    @test JobSchedulers.date_based_on(c4) == :day_of_week
    @test JobSchedulers.tonext(Date(2023,1,2), c4) == Date(2023,1,9)
    @test JobSchedulers.tonext(Date(2023,1,2), c4, same=true) == Date(2023,1,2)
    @test JobSchedulers.tonext(Date(2023,1,1), c4, same=true) == Date(2023,1,2)
    @test JobSchedulers.tonext(Date(2023,1,1), c4) == Date(2023,1,2)
    @test JobSchedulers.tonext(Date(2023,1,3), c4) == Date(2023,1,9)
    @test JobSchedulers.tonext(Date(2023,1,4), c4) == Date(2023,1,9)
    @test JobSchedulers.tonext(Date(2023,1,5), c4) == Date(2023,1,9)
    @test JobSchedulers.tonext(Date(2023,1,6), c4) == Date(2023,1,9)
    @test JobSchedulers.tonext(Date(2023,1,7), c4) == Date(2023,1,9)
    @test JobSchedulers.tonext(Date(2023,1,8), c4) == Date(2023,1,9)
    end

    c5 = Cron(:daily)
    show(stdout, MIME("text/plain"), c5)
    @test JobSchedulers.date_based_on(c5) == :everyday
    @test JobSchedulers.tonext(Date(2023,1,2), c5) == Date(2023,1,3)
    @test JobSchedulers.tonext(Date(2023,1,2), c5, same=true) == Date(2023,1,2)

    c6 = Cron(30, 45, 20, "*/2", *, *)
    show(stdout, MIME("text/plain"), c6)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c6) == DateTime(2023,1,2,20,45,30)
    @test JobSchedulers.tonext(DateTime(2023,1,2,20,45,00), c6) == DateTime(2023,1,2,20,45,30)
    @test JobSchedulers.tonext(DateTime(2023,1,2,20,46,00), c6) == DateTime(2023,1,4,20,45,30)

    c_never = Cron(*,*,*,0,0,0)
    @test JobSchedulers.tonext(DateTime(2023,1,2,20,46,00), c_never) === nothing
    @test_throws Exception submit!(now, cron=c_never)

    c7 = Cron(0,0,0,0,0,0)
    show(stdout, MIME("text/plain"), c7)
    @test JobSchedulers.date_based_on(c7) == :none
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c7) === nothing

    c8 = Cron("*/10", *,*,*,*,*)
    show(stdout, MIME("text/plain"), c8)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c8) == DateTime(2023,1,2,12,30,10)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c8, same=true) == DateTime(2023,1,2,12,30,00)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,50), c8, same=false) == DateTime(2023,1,2,12,31,00)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,55), c8, same=false) == DateTime(2023,1,2,12,31,00)


    # 24 0 1-31/10 1 */2
    c9 = Cron(0,24, 0, "1-31/10", 1, "*/2")
    show(stdout, MIME("text/plain"), c9)
    dt = DateTime(2025,1,1,0,12,0)
    dt = JobSchedulers.tonext(dt, c9)
    @test dt == DateTime(2025,1,11,0,24,0)
    dt = JobSchedulers.tonext(dt, c9)
    @test dt == DateTime(2025,1,21,0,24,0)
    dt = JobSchedulers.tonext(dt, c9)
    @test dt == DateTime(2026,1,1,0,24,0)
    dt = JobSchedulers.tonext(dt, c9)
    @test dt == DateTime(2026,1,31,0,24,0)

    JobSchedulers.get_time_description(c9)
    JobSchedulers.get_time_description(Cron(*,*,4,1,1,1))
    JobSchedulers.get_time_description(Cron(*,3,4,1,1,1))
    JobSchedulers.date_based_on(Cron(*,3,4,1,1,1))
    JobSchedulers.get_date_description(Cron(*,3,4,1,1,1))
    JobSchedulers.get_date_description(Cron(:none))
    
    JobSchedulers.get_second_description([1,4,7]) 
    JobSchedulers.get_second_description([1,4]) 
    JobSchedulers.get_second_description(Int[]) 
    JobSchedulers.get_second_description([1]) 
    JobSchedulers.get_minute_description([1,4,7])
    JobSchedulers.get_minute_description([1,4])
    JobSchedulers.get_minute_description([1])
    JobSchedulers.get_hour_description([1,4,7])
    JobSchedulers.get_hour_description([1,4])
    JobSchedulers.get_hour_description([1])
    JobSchedulers.get_date_description(c9)
    JobSchedulers.get_date_description(Cron(:none))
    JobSchedulers.get_dow_description(c9)
    JobSchedulers.get_dow_description(Cron(:none))
    JobSchedulers.get_month_description(c9)
    JobSchedulers.get_month_description(Cron(:none))
    JobSchedulers.get_dom_description(c9)
    JobSchedulers.get_monthday_description(Cron("*/10", *,*,*,*,*))
    JobSchedulers.get_monthday_description(Cron("*/10", *,*,"1/2",*,*))
    

    JobSchedulers.is_valid_day(now(), c9)
end


@testset "Recur jobs" begin
    jname = "recur print date time: $(rand(UInt))"
    j = Job(
        name = jname,
        cron = Cron("*/1", *,*,*,*,*),
        until = Second(3)
    ) do 
        println("--- Recur Job Start at $(now())")
    end
    submit!(j)

    sleep(3)

    n_retry = 10
    while n_retry > 0
        jqs = queue(QUEUING, jname)
        if length(jqs) >= 1
            cancel!.(jqs)
            sleep(0.1)
        else
            n_retry -= 1
        end
    end

    js = queue("recur print")
    display(js)

    @test length(js) > 1
    if length(js) >= 2
        @test js[1].id != js[2].id && js[1].name == js[2].name
    else
        error("Recur job not submitted!")
    end
    @info "Waiting recur jobs to finish"
    
    jsdone = queue("recur print", DONE)
    wait(jsdone)

    outfile = tempname()
    open(outfile, "w+") do outio
        j2name = "recur print date time: $(rand(UInt))"
        j2 = Job(
            name = j2name,
            cron = Cron("*/1", *,*,*,*,*),
            stdout = outio,
            until = Second(3)
        ) do 
            @show stdout
            println("--- Recur Job Start at $(now())")
        end
        submit!(j2)
        sleep(2)

        n_retry = 10
        while n_retry > 0
            jqs = queue(QUEUING, j2name)
            if length(jqs) >= 1
                cancel!.(jqs)
                sleep(0.1)
            else
                n_retry -= 1
            end
        end
    end
    lines = readlines(outfile)
    rm(outfile, force=true)
    @test length(lines) >= 2
end