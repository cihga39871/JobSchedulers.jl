# struct NodeIterate
#     l::MutableLinkedList
# end

# Base.iterate(ni::NodeIterate) = ni.l.len == 0 ? nothing : (ni.l.node.next, ni.l.node.next.next)
# Base.iterate(ni::NodeIterate, n::DataStructures.ListNode) = n === ni.l.node ? nothing : (n, n.next)

# function Base.deleteat!(l::MutableLinkedList, node::DataStructures.ListNode)
#     prev = node.prev
#     next = node.next
#     prev.next = next
#     next.prev = prev
#     l.len -= 1
#     return l
# end


"""
    LinkedJobList()
    LinkedJobList(j::Job)

Every job can only be in ONE `LinkedJobList`. All iterative copy of `LinkedJobList` will output `Vector{Job}`.
"""
mutable struct LinkedJobList
    len::Int
    node::Job
    # lock::ReentrantLock
    function LinkedJobList()
        new(0, Job(undef))
    end
end


"""
    deleteat!(l::LinkedJobList, node::Job)

Delete `node::Job` from `l::LinkedJobList`.

Caution: user needs to confirm that `node::Job` shall in `l::LinkedJobList`. This function will not check it.
"""
function Base.deleteat!(l::LinkedJobList, node::Job)
    # lock(l.lock) do
        prev = node._prev
        next = node._next
        prev._next = next
        next._prev = prev
        l.len -= 1
    # end
    return l
end

#=
The following codes are copied and edited from Mutable Linked List, DataStructures.jl.
Original code path: https://github.com/JuliaCollections/DataStructures.jl/blob/master/src/mutable_list.jl
License: MIT: https://github.com/JuliaCollections/DataStructures.jl/blob/master/License.md
=#

function LinkedJobList(elts::Job...)
    l = LinkedJobList()
    for elt in elts
        push!(l, elt)
    end
    return l
end


Base.iterate(l::LinkedJobList) = l.len == 0 ? nothing : (l.node._next, l.node._next._next)
Base.iterate(l::LinkedJobList, n::Job) = n === l.node ? nothing : (n, n._next)

Base.isempty(l::LinkedJobList) = l.len == 0
Base.length(l::LinkedJobList) = l.len
Base.collect(l::LinkedJobList) = Job[x for x in l]
Base.eltype(::Type{<:LinkedJobList}) = Job
Base.lastindex(l::LinkedJobList) = l.len

function Base.first(l::LinkedJobList)
    isempty(l) && throw(ArgumentError("List is empty"))
    return l.node._next
end

function Base.last(l::LinkedJobList)
    isempty(l) && throw(ArgumentError("List is empty"))
    return l.node._prev
end

function Base.:(==)(l1::LinkedJobList, l2::LinkedJobList)
    length(l1) == length(l2) || return false
    for (i, j) in zip(l1, l2)
        i == j || return false
    end
    return true
end

#=
#INFO: Not tested. not used.

function Base.map(f::Base.Callable, l::LinkedJobList)
    if isempty(l) && f isa Function
        S = Core.Compiler.return_type(f, Tuple{Job})
        return Vector{S}()
    elseif isempty(l) && f isa Type
        return Vector{f}()
    else
        S = typeof(f(first(l)))
        l2 = Vector{S}()
        for h in l
            el = f(h)
            if el isa S
                push!(l2, el)
            else
                R = typejoin(S, typeof(el))
                l2 = Vector{R}(collect(l2)...)
                push!(l2, el)
            end
        end
        return l2
    end
end

function Base.filter(f::Function, l::LinkedJobList)
    l2 = Vector{Job}()
    for h in l
        if f(h)
            push!(l2, h)
        end
    end
    return l2
end
=#

function Base.reverse(l::LinkedJobList)
    l2 = Vector{Job}()
    for h in l
        pushfirst!(l2, h)
    end
    return l2
end

function Base.copy(l::LinkedJobList)
    l2 = Vector{Job}()
    for h in l
        push!(l2, h)
    end
    return l2
end

function Base.getindex(l::LinkedJobList, idx::Int)
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    node = l.node
    for i in 1:idx
        node = node._next
    end
    return node
end

function Base.getindex(l::LinkedJobList, r::UnitRange)
    @boundscheck 0 < first(r) < last(r) <= l.len || throw(BoundsError(l, r))
    l2 = Vector{Job}()
    node = l.node
    for i in 1:first(r)
        node = node._next
    end
    len = length(r)
    for j in 1:len
        push!(l2, node)
        node = node._next
    end
    return l2
end

function Base.setindex!(l::LinkedJobList, data::Job, idx::Int)
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    prev_node = l.node
    for i in 1:(idx-1)
        prev_node = prev_node._next
    end

    old_node = prev_node._next

    data._prev = old_node._prev
    data._next = old_node._next

    prev_node._next = data
    data._next._prev = data
    # old_node link to itself
    # old_node._prev = old_node
    # old_node._next = old_node

    return l
end

function Base.append!(l1::LinkedJobList, l2::LinkedJobList)
    l1.node._prev._next = l2.node._next # l1's last's next is now l2's first
    l2.node._prev._next = l1.node # l2's last's next is now l1.node
    l2.node._next._prev = l1.node._prev # l2's first's prev is now l1's last
    l1.node._prev      = l2.node._prev # l1's first's prev is now l2's last
    l1.len += length(l2)
    # make l2 empty
    l2.node._prev = l2.node
    l2.node._next = l2.node
    l2.len = 0
    return l1
end

function Base.append!(l::LinkedJobList, elts...)
    for elt in elts
        for v in elt
            push!(l, v)
        end
    end
    return l
end

function Base.delete!(l::LinkedJobList, idx::Int)
    @boundscheck 0 < idx <= l.len || throw(BoundsError(l, idx))
    node = l.node
    for i = 1:idx
        node = node._next
    end
    prev = node._prev
    next = node._next
    prev._next = next
    next._prev = prev
    l.len -= 1
    return l
end

Base.deleteat!(l::LinkedJobList, r::UnitRange) = Base.delete!(l::LinkedJobList, r::UnitRange)

function Base.delete!(l::LinkedJobList, r::UnitRange)
    @boundscheck 0 < first(r) < last(r) <= l.len || throw(BoundsError(l, r))
    node = l.node
    for i in 1:first(r)
        node = node._next
    end
    prev = node._prev
    len = length(r)
    for j in 1:len
        node = node._next
    end
    next = node
    prev._next = next
    next._prev = prev
    l.len -= len
    return l
end

function Base.push!(l::LinkedJobList, node::Job)
    oldlast = l.node._prev
    node._next = l.node
    node._prev = oldlast
    l.node._prev = node
    oldlast._next = node
    l.len += 1
    return l
end

function Base.push!(l::LinkedJobList, data1::Job, data::Job...)
    push!(l, data1)
    for v in data
        push!(l, v)
    end
    return l
end

function Base.pushfirst!(l::LinkedJobList, node::Job)
    oldfirst = l.node._next
    node._prev = l.node
    node._next = oldfirst
    l.node._next = node
    oldfirst._prev = node
    l.len += 1
    return l
end

function Base.pop!(l::LinkedJobList)
    isempty(l) && throw(ArgumentError("List must be non-empty"))
    data = l.node._prev
    last = data._prev
    last._next = l.node
    l.node._prev = last
    l.len -= 1
    return data
end

function Base.popfirst!(l::LinkedJobList)
    isempty(l) && throw(ArgumentError("List must be non-empty"))
    data = l.node._next
    first = data._next
    first._prev = l.node
    l.node._next = first
    l.len -= 1
    return data
end

function Base.show(io::IO, l::LinkedJobList)
    print(io, "LinkedJobList($(length(l)) jobs)")
end