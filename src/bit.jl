
## Indexing

@inline function unsafe_bitgetindex(uint::UInt64, i::Int)
    u = UInt64(1) << i
    r = (uint & u) != 0
    return r
end

function bitcheckbounds(uint::Unsigned, i::Int)
    if i < 0 || i > (sizeof(uint) * 8 - 1)
        error("BoundsError: attempt to access bits of $(typeof(uint)) at index [$i]")
    end
end

@inline function bitgetindex(uint::UInt64, i::Int)
    @boundscheck bitcheckbounds(uint, i)
    unsafe_bitgetindex(uint, i)
end

function unsafe_bitfindnext(uint::UInt64, start::Int)
    mask = 0xffffffffffffffff << start
    if uint & mask != 0
        return trailing_zeros(uint & mask)
    end
    return nothing
end

"""
    bitfindnext(uint::UInt64, start::Integer)

Returns the index of the next true element, or nothing if all false. Index starts from 0.
"""
function bitfindnext(uint::UInt64, start::Integer)
    start = Int(start)
    start >= 0 || error("BoundsError: attempt to access bits of $(typeof(uint)) at index [$start]")
    start > 63 && return nothing
    unsafe_bitfindnext(uint, start)
end

"""
    bitfindnext(uint::UInt64, start::Integer, range::UnitRange{Int64})

Returns the index of the next true element in the `range` of `uint`, or nothing if all false. Index of unit starts from 0.
"""
function bitfindnext(uint::UInt64, start::Integer, r::UnitRange{Int64}; not_found = nothing)
    start = Int(start)
    if start == r.stop + 1  # carry (in math)
        start = r.start
    end
    (0 <= r.start <= start <= r.stop <= 63) || error("BoundsError: attempt to access $r bits of $(typeof(uint)) at index [$start]")

    uint == 0xffffffffffffffff && (return start)

    next = unsafe_bitfindnext(uint, start)
    if next in r
        #return next
    else # next can be nothing (not found), or 1 in front
        if start == r.start  # do not repeat, just return nothing
            #return next
        else
            next = unsafe_bitfindnext(uint, r.start)
            if next in r
                #return next
            else
                next = nothing
            end
        end
    end
    if isnothing(next)
        return not_found
    else
        return next
    end
end


function bitsfind(uint::UInt64, r::UnitRange{Int64}; empty_add_0::Bool = false)
    res = Vector{Int64}()
    for i in r
        if bitgetindex(uint, i)
            push!(res, i)
        end
    end
    if empty_add_0 && length(res) == 0
        push!(res, 0)
    end
    res
end