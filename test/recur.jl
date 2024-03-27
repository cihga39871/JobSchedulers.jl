
@testset "Recur basic" begin
        
    dt = DateTime("2023-04-21T10:25:09.719")

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
    @test JobSchedulers.cron_value_parse("1-5,7,7,4/2") == 0x00000000000000aa
    @test JobSchedulers.cron_value_parse("0-5,7,7,4") == 0x00000000000000bf
    @test JobSchedulers.cron_value_parse('*') == 0xffffffffffffffff
    @test JobSchedulers.cron_value_parse([1,3,5, "7,9"]) == 0x00000000000002aa
    @test JobSchedulers.cron_value_parse([1,3,5, "*"]) == 0xffffffffffffffff

    c = Cron()
    @test JobSchedulers.tonext(Time(23,59,59), c) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(23,59,55), c) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(0,0,0), c) == Time(0,1,0)
    @test JobSchedulers.tonext(Time(0,0,0), c, same=true) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(0,59,00), c) == Time(1,0,0)

    c1 = Cron(:hourly)
    @test JobSchedulers.tonext(Time(23,59,59), c1) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(23,59,00), c1) == Time(0,0,0)
    @test JobSchedulers.tonext(Time(23,00,00), c1, same=true) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,00,00), c1) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,00,01), c1) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,00,01), c1, same=true) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,01,01), c1, same=true) == Time(23,00,0)
    @test JobSchedulers.tonext(Time(22,01,01), c1) == Time(23,00,0)


    for c2 in (Cron(:yearly), Cron(0,0,0,1,1,0))
    @test JobSchedulers.date_based_on(c2) == :monthday
    @test JobSchedulers.tonext(Date(2023,1,2), c2) == Date(2024,1,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c2) == Date(2024,1,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c2, same=true) == Date(2023,1,1)
    end

    for c3 in (Cron(:monthly), Cron(0,0,0,1,*,0))
    @test JobSchedulers.date_based_on(c3) == :monthday
    @test JobSchedulers.tonext(Date(2023,1,2), c3) == Date(2023,2,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c3) == Date(2023,2,1)
    @test JobSchedulers.tonext(Date(2023,1,1), c3, same=true) == Date(2023,1,1)
    @test JobSchedulers.tonext(Date(2023,12,1), c3, same=true) == Date(2023,12,1)
    @test JobSchedulers.tonext(Date(2023,12,1), c3) == Date(2024,1,1)
    end

    for c4 in (Cron(:weekly), Cron(0,0,0,0,0,1))
    @test JobSchedulers.date_based_on(c4) == :dayofweek
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
    @test JobSchedulers.date_based_on(c5) == :everyday
    @test JobSchedulers.tonext(Date(2023,1,2), c5) == Date(2023,1,3)
    @test JobSchedulers.tonext(Date(2023,1,2), c5, same=true) == Date(2023,1,2)

    c6 = Cron(30, 45, 20, "*/2", *, *)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c6) == DateTime(2023,1,2,20,45,30)
    @test JobSchedulers.tonext(DateTime(2023,1,2,20,45,00), c6) == DateTime(2023,1,2,20,45,30)
    @test JobSchedulers.tonext(DateTime(2023,1,2,20,46,00), c6) == DateTime(2023,1,4,20,45,30)

    c7 = Cron(0,0,0,0,0,0)
    @test JobSchedulers.date_based_on(c7) == :none
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c7) === nothing

    c8 = Cron("*/10", *,*,*,*,*)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c8) == DateTime(2023,1,2,12,30,10)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,00), c8, same=true) == DateTime(2023,1,2,12,30,00)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,50), c8, same=false) == DateTime(2023,1,2,12,31,00)
    @test JobSchedulers.tonext(DateTime(2023,1,2,12,30,55), c8, same=false) == DateTime(2023,1,2,12,31,00)
end


@testset "Recur jobs" begin
    j = Job(
        name = "recur print date time $(rand(UInt))",
        cron = Cron("*/2", *,*,*,*,*)
    ) do 
        println("--- Recur Job Start at $(now())")
        return now()
    end
    submit!(j)

    sleep(4)
    j_new = queue(:done)[end]
    @test j.id != j_new.id && j.name == j_new.name
    JobSchedulers.wait_for_lock()
    try
        JobSchedulers.unsafe_cancel!.(queue(QUEUING, "recur print date time"))
    catch e
        rethrow(e)
    finally
        JobSchedulers.release_lock()
    end
end