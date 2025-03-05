struct NodeIterate
    l::MutableLinkedList
end

Base.iterate(ni::NodeIterate) = ni.l.len == 0 ? nothing : (ni.l.node.next, ni.l.node.next.next)
Base.iterate(ni::NodeIterate, n::DataStructures.ListNode) = n === ni.l.node ? nothing : (n, n.next)

function Base.deleteat!(l::MutableLinkedList, node::DataStructures.ListNode)
    prev = node.prev
    next = node.next
    prev.next = next
    next.prev = prev
    l.len -= 1
    return l
end
