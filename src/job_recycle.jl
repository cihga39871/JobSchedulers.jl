
"""
    recyclable!(job::Job)

Mark a `Job` as recyclable, meaning that it **won't be used by user's code** anymore and can be reused for another job after it reaches a `done` state.

This is useful for optimizing performance by avoiding unnecessary object creation and destruction.
"""
function recyclable!(job::Job)
    set_recyclable!(job, true)
end