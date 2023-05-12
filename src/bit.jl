
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
    @boundscheck uint64checkbounds(i)
    unsafe_bitgetindex(uint, i)
end

function unsafe_bitfindnext(uint::UInt64, start::Int)
    mask = 0xffffffffffffffff << start

    begin
        if uint & mask != 0
            return trailing_zeros(uint & mask)
        end
    end
    return nothing
end

"""
    bitfindnext(uint::UInt64, start::Integer)

Returns the index of the next true element, or nothing if all false
"""
function bitfindnext(uint::UInt64, start::Integer)
    start = Int(start)
    start >= 0 || error("BoundsError: attempt to access bits of $(typeof(uint)) at index [$start]")
    start > 63 && return nothing
    unsafe_bitfindnext(uint, start)
end
