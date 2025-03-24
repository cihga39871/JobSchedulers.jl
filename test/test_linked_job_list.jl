@testset "LinkedJobList" begin

    @testset "empty list" begin
        l1 = LinkedJobList()
        @test LinkedJobList() == LinkedJobList()
        @test iterate(l1) === nothing
        @test isempty(l1)
        @test length(l1) == 0
        @test lastindex(l1) == 0
        @test collect(l1) == Job[]
        @test eltype(l1) == Job
        @test eltype(typeof(l1)) == Job
        @test_throws ArgumentError pop!(l1)
        @test_throws ArgumentError popfirst!(l1)
    end

    do_nothing = JobSchedulers.Pipelines.do_nothing

    function jobnameids(l::T) where T <: Union{Vector{Job}, LinkedJobList}
        Int[parse(Int, j.name) for j in l]
    end

    @testset "core functionality" begin
        n = 10

        @testset "push back / pop back" begin
            l = LinkedJobList()

            @testset "push back" begin
                for i = 1:n
                    I = "$i"
                    push!(l, Job(do_nothing, name=I))
                    @test last(l).name == I
                    if i > 4
                        @test getindex(l, i).name == I
                        @test jobnameids(getindex(l, 1:floor(Int, i/2))) == collect(1:floor(Int, i/2))
                        @test jobnameids(l[1:floor(Int, i/2)]) == collect(1:floor(Int, i/2))
                        setindex!(l, Job(do_nothing, name="0"), i - 2)
                        @test jobnameids(l) == [1:i-3..., 0, i-1:i...]
                        setindex!(l, Job(do_nothing, name="$(i-2)"), i - 2)
                    end
                    @test lastindex(l) == i
                    @test length(l) == i
                    @test isempty(l) == false
                    for (j, k) in enumerate(l)
                        @test "$j" == k.name
                    end
                    cl = collect(l)
                    @test isa(cl, Vector{Job})
                    @test parse.(Int, getfield.(cl, :name)) == collect(1:i)
                end
            end

            @testset "pop back" begin
                for i = 1:n
                    x = pop!(l)
                    @test length(l) == n - i
                    @test isempty(l) == (i == n)
                    @test parse(Int, x.name) == n - i + 1
                    cl = collect(l)
                    @test jobnameids(cl) == collect(1:n-i)
                end
            end
        end

        @testset "push front / pop front" begin
            l = LinkedJobList()

            @testset "push front" begin
                for i = 1:n
                    I = "$i"
                    pushfirst!(l, Job(do_nothing, name=I))
                    @test first(l).name == I
                    @test length(l) == i
                    @test isempty(l) == false
                    cl = collect(l)
                    @test isa(cl, Vector{Job})
                    @test jobnameids(cl) == collect(i:-1:1)
                end
            end

            @testset "pop front" begin
                for i = 1:n
                    x = popfirst!(l)
                    @test length(l) == n - i
                    @test isempty(l) == (i == n)
                    @test parse(Int, x.name) == n - i + 1
                    cl = collect(l)
                    @test jobnameids(cl) == collect(n-i:-1:1)
                end
            end

        end

        @testset "append / delete / copy / reverse" begin
            
            for i = 1:n
                js = [Job(do_nothing, name="$i") for i in 1:n]
                l = LinkedJobList(js...)

                @testset "append" begin
                    js2 = [Job(do_nothing, name="$i") for i in n+1:2n]
                    l2 = LinkedJobList(js2...)
                    append!(l, l2)
                    @test jobnameids(l)  == collect(1:2n)
                    @test l2 == LinkedJobList()

                    l3 = LinkedJobList(js...)
                    append!(l3, js2)
                    @test jobnameids(l3) == collect(1:2n)
                    l4 = LinkedJobList(js...)
                    push!(l4, js2...)
                    @test jobnameids(l4) == collect(1:2n)
                end

                js2n = [Job(do_nothing, name="$i") for i in 1:2n]
                l = LinkedJobList(js2n...)
                
                @testset "delete" begin
                    delete!(l, n+1:2n)
                    @test jobnameids(l) == collect(1:n)
                    for i = n:-1:1
                        delete!(l, i)
                    end
                    @test l == LinkedJobList()
                    l = LinkedJobList(js...)
                    @test_throws BoundsError delete!(l, n-1:2n)
                    @test_throws BoundsError delete!(l, 2n)
                end

                @testset "copy" begin
                    l2 = copy(l)
                    @test collect(l) == l2
                end

                @testset "reverse" begin
                    l2 = reverse(l)
                    @test reverse(collect(l)) == l2
                end
            end
        end

        @testset "deleteat" begin
            js = [Job(do_nothing, name="$i") for i in 1:10]
            l = LinkedJobList(js...)
            l2 = LinkedJobList()

            j = l[5]
            deleteat!(l, j)
            
            true_ids = [1:4; 6:10]
            @test jobnameids(l)  == true_ids

            i = 1
            for j in l
                if i % 2 == 0
                    deleteat!(l, j)
                    push!(l2, j)
                end
                @test true_ids[i] == parse(Int, j.name)
                i += 1
            end
            @test jobnameids(l2)  == [2,4,7,9]
            @test jobnameids(l)  == [1,3,6,8,10]

        end

        # @testset "map / filter" begin
        #     for i = 1:n
        #         @testset "map" begin
        #             l = MutableLinkedList{Int}(1:n...)
        #             @test map(x -> 2x, l) == MutableLinkedList{Int}(2:2:2n...)
        #             l2 = MutableLinkedList{Float64}()
        #             @test map(x -> x*im, l2) == MutableLinkedList{Complex{Float64}}()
        #             @test map(Int32, l2) == MutableLinkedList{Int32}()
        #             f(x) = x % 2 == 0 ? convert(Int8, x) : convert(Float16, x)
        #             @test typeof(map(f, l)) == MutableLinkedList{Real}
        #         end

        #         @testset "filter" begin
        #             l = MutableLinkedList{Int}(1:n...)
        #             @test filter(x -> x % 2 == 0, l) == MutableLinkedList{Int}(2:2:n...)
        #         end

        #         @testset "show" begin
        #             l = MutableLinkedList{Int32}(1:n...)
        #             io = IOBuffer()
        #             @test sprint(io -> show(io, l.node.next)) == "$(typeof(l.node.next))($(l.node.next.data))"
        #             io1 = IOBuffer()
        #             write(io1, "MutableLinkedList{Int32}(");
        #             write(io1, join(l, ", "));
        #             write(io1, ")")
        #             seekstart(io1)
        #             @test sprint(io -> show(io, l)) == read(io1, String)
        #         end
        #     end
        # end
    end

    #=
    function detail_of_links(l::JobSchedulers.LinkedJobList)
        fields = [:id, :ncpu, :mem, :_prev, :_next, :_head_same_ncpu_mem, :_next_diff_ncpu_mem]

        res = Matrix{Any}(undef, length(l)+1, length(fields))

        res[1,1:length(fields)] .= fields

        for (i, j) in enumerate(l)
            x = i + 1
            for (y, f) in enumerate(fields)
                res[x, y] = getfield(j, f)
            end
        end
        res
    end

    @testset "jump list used in JOB_QUEUE.queuing" begin
        l = JobSchedulers.LinkedJobList()

        j1 = Job(do_nothing, ncpu = 1, mem = 100)
        j2 = Job(do_nothing, ncpu = 1, mem = 100)
        j3 = Job(do_nothing, ncpu = 1, mem = 200)
        j4 = Job(do_nothing, ncpu = 2, mem = 100)
        j5 = Job(do_nothing, ncpu = 2, mem = 100)
        j6 = Job(do_nothing, ncpu = 3, mem = 500)
        j7 = Job(do_nothing, ncpu = 4, mem = 500)
        j8 = Job(do_nothing, ncpu = 5, mem = 500)

        JobSchedulers.push_queuing_and_jump_list!(l, j1)
        JobSchedulers.push_queuing_and_jump_list!(l, j2)
        JobSchedulers.push_queuing_and_jump_list!(l, j3)
        JobSchedulers.push_queuing_and_jump_list!(l, j4)
        JobSchedulers.push_queuing_and_jump_list!(l, j5)
        JobSchedulers.push_queuing_and_jump_list!(l, j6)
        JobSchedulers.push_queuing_and_jump_list!(l, j7)
        JobSchedulers.push_queuing_and_jump_list!(l, j8)

        for (i,j) in enumerate(l)
            j.id = Int64(i)
        end

        link_mt = detail_of_links(l)

        # push test
        @test @view(link_mt[2:9, 6]) == [j1, j1, j3, j4, j4, j6, j7, j8]
        @test @view(link_mt[2:9, 7]) == [j3, j2, j4, j6, j5, j7, j8, j8]

        # remove job 6: single job, adjecent jobs not same ncpu mem

        JobSchedulers.deleteat_queuing_and_jump_list!(l, j6)
        link_mt = detail_of_links(l)

        @test @view(link_mt[2:8, 1]) == [1,2,3,4,5,7,8]
        @test @view(link_mt[2:8, 6]) == [j1, j1, j3, j4, j4, j7, j8]
        @test @view(link_mt[2:8, 7]) == [j3, j2, j4, j7, j5, j8, j8]

        # remove job 2: should not make difference to others
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j2)
        link_mt = detail_of_links(l)

        @test @view(link_mt[2:7, 1]) == [1,3,4,5,7,8]
        @test @view(link_mt[2:7, 6]) == [j1, j3, j4, j4, j7, j8]
        @test @view(link_mt[2:7, 7]) == [j3, j4, j7, j5, j8, j8]

        # remove job 1
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j1)
        link_mt = detail_of_links(l)

        @test j1._head_same_ncpu_mem === j1
        @test j1._next_diff_ncpu_mem === j3 
        @test @view(link_mt[2:end, 1]) == [3,4,5,7,8]
        @test @view(link_mt[2:end, 6]) == [j3, j4, j4, j7, j8]
        @test @view(link_mt[2:end, 7]) == [j4, j7, j5, j8, j8]

        # remove job 4
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j4)
        link_mt = detail_of_links(l)

        @test j4._head_same_ncpu_mem === j4
        @test j4._next_diff_ncpu_mem === j7
        @test @view(link_mt[2:end, 1]) == [3,5,7,8]
        @test @view(link_mt[2:end, 6]) == [j3, j4, j7, j8]
        @test @view(link_mt[2:end, 7]) == [j5, j5, j8, j8]

        # remove job 8
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j8)
        link_mt = detail_of_links(l)
        @test @view(link_mt[2:end, 1]) == [3,5,7]
        @test @view(link_mt[2:end, 6]) == [j3, j4, j7]
        @test @view(link_mt[2:end, 7]) == [j5, j5, j7]

        # add job 9 and 10 with same condition as 7
        j9 = Job(do_nothing, ncpu = 4, mem = 500)
        j10 = Job(do_nothing, ncpu = 4, mem = 500)
        j9.id = Int64(9)
        j10.id = Int64(10)
        JobSchedulers.push_queuing_and_jump_list!(l, j9)
        JobSchedulers.push_queuing_and_jump_list!(l, j10)

        link_mt = detail_of_links(l)
        @test @view(link_mt[2:end, 1]) == [3,5,7,9,10]
        @test @view(link_mt[2:end, 6]) == [j3, j4, j7, j7, j7]
        @test @view(link_mt[2:end, 7]) == [j5, j5, j7, j9, j10]

        # remove 10
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j10)
        link_mt = detail_of_links(l)
        @test @view(link_mt[2:end, 1]) == [3,5,7,9]
        @test @view(link_mt[2:end, 6]) == [j3, j4, j7, j7]
        @test @view(link_mt[2:end, 7]) == [j5, j5, j7, j9]

        # remove 5
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j5)
        link_mt = detail_of_links(l)
        @test @view(link_mt[2:end, 1]) == [3,7,9]
        @test @view(link_mt[2:end, 6]) == [j3, j7, j7]
        @test @view(link_mt[2:end, 7]) == [j7, j7, j9]

        # remove 7
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j7)
        link_mt = detail_of_links(l)
        @test @view(link_mt[2:end, 1]) == [3,9]
        @test @view(link_mt[2:end, 6]) == [j3, j7]
        @test @view(link_mt[2:end, 7]) == [j9, j9]
        @test j9._head_same_ncpu_mem._next_diff_ncpu_mem === j9

        # move first j3
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j3)
        link_mt = detail_of_links(l)
        @test l[1]._head_same_ncpu_mem._next_diff_ncpu_mem == j9

        # remove 9
        JobSchedulers.deleteat_queuing_and_jump_list!(l, j9)
        @test length(l) == 0
        
    end
    =#
end