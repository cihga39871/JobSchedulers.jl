
struct Cron
    second::UInt64
    minute::UInt64
    hour::UInt64
    day_of_month::UInt64
    month::UInt64
    day_of_week::UInt64
    union_of_days::Bool  # union or intersect day of month and day of week. It is same as Crontab's behaviors: How a cron bug became the de-facto standard (https://crontab.guru/cron-bug.html)
    function Cron(second, minute, hour, day_of_month, month, day_of_week)
        new(
            cron_value_parse(second),
            cron_value_parse(minute),
            cron_value_parse(hour),
            cron_value_parse(day_of_month),
            cron_value_parse(month),
            cron_value_parse(day_of_week),
            is_union_of_days(day_of_month, day_of_week)
        )
    end
end

"""
    Cron(second, minute, hour, day_of_month, month, day_of_week)
    Cron(;
        second = 0,
        minute = '*',
        hour = '*',
        day_of_month = '*',
        month = '*',
        day_of_week = '*',
    )

`Cron` stores the schedule of a repeative `Job`, implemented according to Linux-based `crontab`(5) table.

Jobs are executed when the **second, minute, hour and month** fields match the current time. If neither `day_of_month` nor `day_of_week` **starts with** `*`, cron takes the union (∪) of their values `day_of_month ∪ day_of_week`. Otherwise cron takes the intersection (∩) of their values `day_of_month ∩ day_of_week`.

## When an argument is an `Int`:

| Field          | Allowed values             |
| -------------- | -------------------------- |
| `second`       | 0-59                       |
| `minute`       | 0-59                       |
| `hour`         | 0-23                       |
| `day_of_month` | 1-31                       |
| `month`        | 1-12                       |
| `day_of_week`  | 1-7 (1 is Monday)          |

!!! compat "Diff between Linux crontab"
    1. Typical Linux distributions do not have `second` filed as JobSchedulers.
    2. Sunday is only coded `7` in JobSchedulers, while it is `0` or `7` in Linux, so the behaviors like `day_of_week = "*/2"` are different in two systems.
    3. From JobSchedulers v0.11, `Cron` has been rewritten based on the standard crontab, including its bug described [here](https://crontab.guru/cron-bug.html).

## When an argument is a `String` or `Char`:

An argument may be an asterisk (`*`), which always stands for ``first-last``.

Ranges of numbers are allowed. Ranges are two numbers separated with a hyphen. The specified range is inclusive. For example, 8-11 for an ``hours`` entry specifies execution at hours 8, 9, 10 and 11.

Lists are allowed. A list is a set of numbers (or ranges) separated by commas. Examples: `"1,2,5,9"`, `"0-4,8-12"`.

Step values can be used in conjunction with ranges. Following a range with `/<number>` specifies skips of the number's value through the range. For example, `"0-23/2"` can be used in the `hour` argument to specify Job execution every other hour (the alternative is `"0,2,4,6,8,10,12,14,16,18,20,22"`). Steps are also permitted after an asterisk, so if you want to say ``every two hours``, just use `"*/2"`.

## When an argument is a `Vector`:

`Vector` works like lists mentioned above. For example, `[1,2,5,9]` is equivalent to `"1,2,5,9"`.

## When an argument is a `UInt64`:

`UInt64` is the internal type of `Cron` fileds. All the previous types will be converted to a `UInt64` bit array. The start index of the bit array is 0. Bits outside of the allowed values (see the table above) are ignored.
"""
function Cron(; 
    second = 0x0000000000000001, 
    minute = 0xffffffffffffffff,
    hour = 0xffffffffffffffff,
    day_of_month = 0xffffffffffffffff,
    month = 0xffffffffffffffff,
    day_of_week = 0xffffffffffffffff)
    Cron(second, minute, hour, day_of_month, month, day_of_week)
end

function Base.:(==)(c1::Cron, c2::Cron)
    if c1 === c2
        return true
    end
    c1.second == c2.second &&
    c1.minute == c2.minute &&
    c1.hour == c2.hour &&
    c1.day_of_month == c2.day_of_month &&
    c1.month == c2.month &&
    c1.day_of_week == c1.day_of_week
end

"""
    Cron(special::Symbol)

Instead of the six arguments of `Cron`, one of the following special symbols may appear instead:

| `special`   | Meaning                                       |
| ----------- | --------------------------------------------- |
| `:yearly`   | Run once a year, `Cron(0,0,0,1,1,0)`          |
| `:annually` | (same as `:yearly`)                           |
| `:monthly`  | Run once a month, `Cron(0,0,0,1,'*','*')`     |
| `:weekly`   | Run once a week, `Cron(0,0,0,'*','*',1)`      |
| `:daily`    | Run once a day, `Cron(0,0,0,'*','*','*')`     |
| `:midnight` | (same as `:daily`)                            |
| `:hourly`   | Run once an hour, `Cron(0,0,'*','*','*','*')` |
| `:none`     | Never repeat, `Cron(0,0,0,0,0,0)`             |

Caution: Linux crontab's special `:reboot` is not supported here.

To run every minute, just use `Cron()`.
"""
function Cron(special::Symbol)
    if special === :none
        Cron(0,0,0,0,0,0)
    elseif special === :yearly || special === :annually
        Cron(0,0,0,1,1,'*')
    elseif special === :monthly
        Cron(0,0,0,1,'*','*')
    elseif special === :weekly
        Cron(0,0,0,'*','*',1)
    elseif special === :daily || special === :midnight
        Cron(0,0,0,'*','*','*')
    elseif special === :hourly
        Cron(0,0,'*','*','*','*')
    else
        error("Cron: special symbol $special not recognized. Valid options are :yearly, :annually, :monthly, :weekly, :daily, :midnight, :hourly")
    end
end

function Base.isempty(c::Cron)
    c == cron_none
end

# COV_EXCL_START
const stepmasks = map(1:64) do step
    final = 0x0000000000000000
    for i in 0:step:64
        final = final | (0x0000000000000001 << i)
    end
    final
end
# COV_EXCL_STOP

"""
    is_union_of_days(day_of_month, day_of_week) :: Bool

Wether we choose union or intersection of `day_of_month` and `day_of_week`.

To adapt with Crontab's behavior: How a cron bug became the de-facto standard (https://crontab.guru/cron-bug.html)
"""
function is_union_of_days(day_of_month, day_of_week)
    asterisk_dom = first_is_asterisk(day_of_month)
    asterisk_dow = first_is_asterisk(day_of_week)

    do_intersect = asterisk_dom || asterisk_dow
    return !do_intersect
end

first_is_asterisk(value::Integer) = false  # COV_EXCL_LINE
first_is_asterisk(value::Char) = value == '*'
first_is_asterisk(value::Function) = value == *
first_is_asterisk(value::String) = length(value) >= 1 && value[1] == '*'
first_is_asterisk(value::Vector) = length(value) >= 1 && first_is_asterisk(value[1])


"""
    cron_value_parse(value::UInt64)
    cron_value_parse(value::Signed)
    cron_value_parse(value::AbstractString)
    cron_value_parse(value::Char)
    cron_value_parse(value::Vector)
    cron_value_parse(*) = cron_value_parse('*')

Parse crontab-like value to `UInt64`. See details: [`Cron`](@ref).
"""
@inline function cron_value_parse(value::UInt64)
    value
end
@inline function cron_value_parse(value::Signed)
    if value > 60 || value < 0
        error("Cron: cannot parse $value::Signed: out of range.")
    end
    0x0000000000000001 << value
end
@inline function cron_value_parse(value::Function)
    if value == *
        return 0xffffffffffffffff
    else
        error("Cron: cannot parse $value::Function: invalid. Only * is allowed.")
    end
end
@inline function cron_value_parse(value::AbstractString)  # "0-4,8-12,5/2"
    value = replace(value, r"[ \t]" => "")
    if value == "*"
        return 0xffffffffffffffff
    end
    values = split(value, ",")

    uint = UInt64(0)
    for v in values
        uint |= _cron_value_parse(v)
    end

    uint
end

function _cron_value_parse(value::AbstractString)  # 0-4    5-8/2  5/2   */2
    m = match(r"^(\d+|\*)(-(\d+))?(/(\d+))?$", value)

    if isnothing(m)
        error("Cron: cannot parse $value: not a crontab value format. Example: *    5     */2    1-12/4     5/2. They can be combined with comma (,) to form a union.")
    end
    start = m.captures[1]  # int or *
    stop  = m.captures[3]  # nothing or int
    step  = m.captures[5]  # nothing or int

    uint = cron_range_and_step_parse(start, stop, step)
    return uint
end

@inline function cron_value_parse(value::Char)  # "0-4,8-12,5/2"
    if value == '*'
        return 0xffffffffffffffff
    end
    cron_value_parse(string(value))
end

function cron_range_and_step_parse(start::AbstractString, stop::Nothing, step::Nothing)
    start == "*" && (return 0xffffffffffffffff)
    cron_value_parse(parse(Int, start))
end
function cron_range_and_step_parse(start::AbstractString, stop::AbstractString, step::Nothing)
    stop_int = parse(Int, stop)

    if start == "*"
        start_uint = 0xffffffffffffffff
    else
        start_int = parse(Int, start) 
        @assert start_int <= stop_int "Cron: cannot parse range $start-$stop because start > stop."
        
        start_uint = 0xffffffffffffffff << start_int
    end

    ~(0xffffffffffffffff << (stop_int + 1)) & start_uint
end
function cron_range_and_step_parse(start::AbstractString, stop::AbstractString, step::AbstractString)
    range_uint = cron_range_and_step_parse(start, stop, nothing)
    step_int = parse(Int, step)

    @assert 1 <= step_int <= 64 "Cron: cannot parse step /$step because step must from 1 to 64."

    offset = trailing_zeros(range_uint)
    step_mask = stepmasks[step_int] << offset
    range_uint & step_mask
end
function cron_range_and_step_parse(start::AbstractString, stop::Nothing, step::AbstractString)
    # regard as start-all/step
    cron_range_and_step_parse(start, "64", step)
end


function cron_value_parse(value::Vector)
    final = 0x0000000000000000
    for v in value
        final = final | cron_value_parse(v)
    end
    final
end

const cron_none = Cron(:none)

"""
    Dates.tonext(dt::DateTime, c::Cron; same::Bool = false) -> Union{DateTime, Nothing}
    Dates.tonext(t::Time, c::Cron; same::Bool = false) -> Time
    Dates.tonext(d::Date, c::Cron; same::Bool = false, limit::Date = d + Day(3000)) -> Union{DateTime, Nothing}

Adjust date or time to the next one corresponding to `c::Cron`. Setting `same=true` allows the current date or time to be considered as the next one, allowing for no adjustment to occur.
"""
function Dates.tonext(dt::DateTime, c::Cron; same::Bool = false)
    now_date = Date(dt)
    if is_valid_day(now_date, c)
        # today
        now_time = Time(hour(dt), minute(dt), second(dt))
        next_time = tonext(now_time, c, same=same)
        if ifelse(same, >=, >)(next_time, now_time)
            # today
            return DateTime(now_date, next_time)
        end
    end

    # next available day
    next_date = tonext(now_date, c)
    if isnothing(next_date)
        return nothing
    end
    next_time = tonext(Time(0,0,0), c, same=true)
    next_dt = DateTime(next_date, next_time)
    return next_dt
end

function Dates.tonext(t::Time, c::Cron; same::Bool = false)
    sec = bitfindnext(c.second, second(t) + !same, 0:59; not_found = 0)
    min_carry = same ? (sec < second(t)) : (sec <= second(t))

    min = bitfindnext(c.minute, minute(t) + min_carry, 0:59; not_found = 0)
    hr_carry = if min > minute(t)
        false
    elseif min == minute(t)
        min_carry
    else
        true
    end
    hr  = bitfindnext(c.hour, hour(t) + hr_carry, 0:23; not_found = 0)
    Time(hr, min, sec)
end

function Dates.tonext(d::Date, c::Cron; same::Bool = false, limit::Date = d + Day(3000))
    # same month?
    mon = bitfindnext(c.month, 1, 1:12)  # can be same month

    if mon === nothing
        return nothing
    end

    # stepwise 
    if same && is_valid_day(d, c)
        return d
    end
    d2 = d + Day(1)
    while d2 <= limit
        if is_valid_day(d2, c)
            return d2
        else
            d2 += Day(1)
        end
    end
    return nothing  # COV_EXCL_LINE
end


@inline function is_every_second(c::Cron)
    c.second & 0x0fffffffffffffff == 0x0fffffffffffffff
end

@inline function is_every_minute(c::Cron)
    c.minute & 0x0fffffffffffffff == 0x0fffffffffffffff
end

@inline function is_every_hour(c::Cron)
    c.hour & 0x0000000000ffffff == 0x0000000000ffffff
end

@inline function is_every_day_of_week(c::Cron)
    c.day_of_week & 0x00000000000000fe == 0x00000000000000fe
end
@inline function is_none_day_of_week(c::Cron)
    c.day_of_week & 0x00000000000000fe == 0
end


@inline function is_every_day_of_month(c::Cron)
    c.day_of_month & 0x00000000fffffffe == 0x00000000fffffffe
end
@inline function is_none_day_of_month(c::Cron)
    c.day_of_month & 0x00000000fffffffe == 0
end

@inline function is_every_month(c::Cron)
    (c.month & 0x0000000000001ffe == 0x0000000000001ffe)
end

@inline function is_none_month(c::Cron)
    c.month & 0x0000000000001ffe == 0
end

@inline function is_one_at(uint::Unsigned, idx::Signed)
    x = UInt64(1) << idx
    uint & x == x
end

"""
    is_valid_day(dt::Date, c::Cron)

Is `dt` is a valid day matching `c`?
"""
function is_valid_day(dt::Date, c::Cron)
    is_month_valid = is_one_at(c.month, month(dt))

    if !is_month_valid
        return false
    end

    is_dow_valid = is_one_at(c.day_of_week, dayofweek(dt))
    is_dom_valid = is_one_at(c.day_of_month, day(dt))

    if c.union_of_days
        is_dow_valid || is_dom_valid
    else
        is_dow_valid && is_dom_valid
    end
end
is_valid_day(dt::DateTime, c::Cron) = is_valid_day(Date(dt), c)

"""
    date_based_on(c::Cron) -> Symbol

Whether date of `c` is based on `:day_of_week`, `:day_of_month`, `:union`, `:intersect`, `:everyday`, `:none`, or `:undefined`.
"""
function date_based_on(c::Cron)
    if is_none_month(c)
        return :none
    end

    none_dow = is_none_day_of_week(c)
    none_dom = is_none_day_of_month(c)
    if c.union_of_days
        none_dow && none_dom && (return :none)
    else # intersect
        (none_dow || none_dom) && (return :none)
    end

    all_dow = is_every_day_of_week(c)
    all_dom = is_every_day_of_month(c)

    some_dow = !(all_dow || none_dow)
    some_dom = !(all_dom || none_dom)

    if c.union_of_days
        # any dow or dom
        if all_dow || all_dom
            return :everyday
        elseif some_dow && some_dom
            return :union
        elseif some_dow
            return :day_of_week
        elseif some_dom
            return :day_of_month
        else
            # COV_EXCL_START
            @warn "Undefined: Please report a bug with the Cron info. Thank you." c
            return :undefined
            # COV_EXCL_STOP
        end
    else
        # both match dow and dom
        if all_dow && all_dom
            return :everyday
        elseif all_dow && some_dom
            return :day_of_month
        elseif some_dow && all_dom
            return :day_of_week
        elseif some_dow && some_dom
            return :intersect
        else
            # COV_EXCL_START
            @warn "Undefined: Please report a bug with the Cron info. Thank you." c
            return :undefined
            # COV_EXCL_STOP
        end
    end
end

# pretty print
function Base.show(io::IO, ::MIME"text/plain", c::Cron)
    return print(io, simplify(c, true))
end

function get_time_description(c::Cron)
    every_sec = is_every_second(c)
    every_min = is_every_minute(c)
    every_hour = is_every_hour(c)
    
    seconds = bitsfind(c.second, 0:59, empty_add_0 = true)
    minutes = bitsfind(c.minute, 0:59, empty_add_0 = true)
    hours = bitsfind(c.hour, 0:23, empty_add_0 = true)

    if length(seconds) == length(minutes) == length(hours) == 1

        return "at $(Time(hours[1], minutes[1], seconds[1]))"
    end

    str = if every_min
        if every_sec
            "every second"
        else
            sec_str = get_second_description(seconds)
            "every minute at $sec_str"
        end
    else
        min_str = get_minute_description(minutes)
        if every_sec
            "every second at $min_str"
        else
            sec_str = get_second_description(seconds)
            "at $min_str, $sec_str"
        end
    end

    if every_hour
        str *= " past every hour"
    else
        hour_str = get_hour_description(hours)
        str *= " past $hour_str"
    end
    str
end

function get_second_description(seconds::Vector{Int})
    if length(seconds) == 0
        "no second"
    elseif length(seconds) == 1
        "$(seconds[1]) second"
    else
        str = join(seconds, ", ", " and ")
        "$(str) seconds"
    end
end
function get_minute_description(minutes::Vector{Int})
    if length(minutes) == 0
        "no minute"
    elseif length(minutes) == 1
        "$(minutes[1]) minute"
    else
        str = join(minutes, ", ", " and ")
        "$(str) minutes"
    end
end
function get_hour_description(hours::Vector{Int})
    if length(hours) == 0
        "no hour"
    elseif length(hours) == 1
        "$(hours[1]) hour"
    else
        str = join(hours, ", ", " and ")
        "$(str) hours"
    end
end

function get_date_description(c::Cron)
    based = date_based_on(c)
    str = ""
    if based === :everyday
        str *= "everyday"
    elseif based === :day_of_week
        str *= get_dow_description(c)
    elseif based === :day_of_month
        str *= get_dom_description(c)
    elseif based === :union
        str *= get_dom_description(c) * " and " * get_dow_description(c)
    elseif based === :intersect
        str *= get_dom_description(c) * " if it's " * get_dow_description(c)
    elseif based === :none
        return "no repeated date"
    end

    # month
    if is_every_month(c)
        nothing
    else
        str *= get_month_description(c)
    end

    str
end

function get_dow_description(c::Cron)
    dows = bitsfind(c.day_of_week, 1:7)
    if isempty(dows)
        return "on no day of week"
    end
    human_readables = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    dows2 = human_readables[dows]
    return "on " * join(dows2, ", ", " and ")
end

function get_month_description(c::Cron)
    months = bitsfind(c.month, 1:12)
    if isempty(months)
        return " in no month"
    end
    human_readables = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    months2 = human_readables[months]
    return " in " * join(months2, ", ", " and ")
end

function get_dom_description(c::Cron)
    days = bitsfind(c.day_of_month, 1:31)
    day_str = join(days, ", ", " and ")
    return "on day-of-month $day_str"
end

function get_monthday_description(c::Cron)
    if is_every_month(c)
        if is_every_day_of_month(c)
            ""
        else
            days = bitsfind(c.day_of_month, 1:31)
            day_str = join(days, ", ", " and ")
            "on day-of-month $day_str"
        end
    else
        months = bitsfind(c.month, 1:12)
        human_readables = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        months2 = human_readables[months]
        mon_str = join(months2, ", ", " and ")
        if is_every_day_of_month(c)
            "everyday in $mon_str"
        else
            days = bitsfind(c.day_of_month, 1:31)
            day_str = join(days, ", ", " and ")
            "on day-of-month $day_str in $mon_str"
        end
    end
end