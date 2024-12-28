
struct Cron
    second::UInt
    minute::UInt
    hour::UInt
    day_of_month::UInt
    month::UInt
    day_of_week::UInt
    function Cron(second, minute, hour, day_of_month, month, day_of_week)
        new(
            cron_value_parse(second),
            cron_value_parse(minute),
            cron_value_parse(hour),
            cron_value_parse(day_of_month),
            cron_value_parse(month),
            cron_value_parse(day_of_week)
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

`Cron` stores the schedule of a repeative `Job`, inspired by Linux-based `crontab`(5) table.

Jobs are executed by JobScheduler when the second, minute, and hour fields match the current time, and when at least one of the two day fields (day of month & month, or day of week) match the current time.

## When an argument is an `Int`:

| Field          | Allowed values             |
| -------------- | -------------------------- |
| `second`       | 0-59                       |
| `minute`       | 0-59                       |
| `hour`         | 0-23                       |
| `day_of_month` | 1-31                       |
| `month`        | 1-12                       |
| `day_of_week`  | 1-7 (1 is Monday)          |

## When an argument is a `String` or `Char`:

An argument may be an asterisk (`*`), which always stands for ``first-last``.

Ranges of numbers are allowed. Ranges are two numbers separated with a hyphen. The specified range is inclusive. For example, 8-11 for an ``hours`` entry specifies execution at hours 8, 9, 10 and 11.

Lists are allowed. A list is a set of numbers (or ranges) separated by commas. Examples: `"1,2,5,9"`, `"0-4,8-12"`.

Step values can be used in conjunction with ranges. Following a range with `/<number>` specifies skips of the number's value through the range. For example, `"0-23/2"` can be used in the `hour` argument to specify Job execution every other hour (the alternative is `"0,2,4,6,8,10,12,14,16,18,20,22"`). Steps are also permitted after an asterisk, so if you want to say ``every two hours``, just use `"*/2"`.

## When an argument is a `Vector`:

`Vector` works like lists mentioned above. For example, `[1,2,5,9]` is equivalent to `"1,2,5,9"`.

## When an argument is a `UInt`:

`UInt` is the internal type of `Cron` fileds. All the previous types will be converted to a `UInt` bit array. The start index of the bit array is 0. Bits outside of the allowed values (see the table above) are ignored.
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

const stepmasks = map(1:64) do step
    final = 0x0000000000000000
    for i in 0:step:64
        final = final | (0x0000000000000001 << i)
    end
    final
end

"""
    cron_value_parse(value::UInt)
    cron_value_parse(value::Int)
    cron_value_parse(value::String)
    cron_value_parse(value::Char)
    cron_value_parse(value::Vector)
    cron_value_parse(*) = cron_value_parse('*')

Parse crontab-like value to `UInt`. See details: [`Cron`](@ref).
"""
@inline function cron_value_parse(value::UInt)
    value
end
@inline function cron_value_parse(value::Int)
    if value > 60 || value < 0
        error("Cron: cannot parse $value::Int: out of range.")
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
@inline function cron_value_parse(value::String)  # "0-4,8-12,5/2"
    if value == "*"
        return 0xffffffffffffffff
    end
    m = match(r"^([\d\-\,]+|\*)(/(\d+))?$", value)
    if isnothing(m)
        error("Cron: cannot parse $value: not a crontab value format. Example: *    */2    1,5,7   1-4,8    1-6,8-9/3")
    end
    ranges = m.captures[1]  # "0-4,8-12,5"
    steps = m.captures[3]  # nothing or "2"

    if isnothing(steps)
        return cron_value_ranges_parse(ranges)
    end

    step = parse(Int, steps)
    if step > 64 || step < 1
        error("Cron: cannot parse /$step in $value: valid step range is 1-64.")
    end
    range_uint = cron_value_ranges_parse(ranges)
    offset = trailing_zeros(range_uint)
    step_mask = stepmasks[step] << offset
    return range_uint & step_mask
end

@inline function cron_value_parse(value::Char)  # "0-4,8-12,5/2"
    if value == '*'
        return 0xffffffffffffffff
    end
    cron_value_parse(string(value))
end

function cron_value_ranges_parse(ranges::SubString{String})
    if ranges == "*"
        return 0xffffffffffffffff
    end
    range_split = split(ranges, ",")
    final = 0x0000000000000000
    for i in range_split
        i_split = split(i, '-')
        if length(i_split) == 1
            v = parse(Int, i_split[1])
            final = final | cron_value_parse(v)
        elseif length(i_split) == 2
            start = parse(Int, i_split[1])
            stop = parse(Int, i_split[2])
            if start > stop
                error("Cron: cannot parse $i in $ranges: only <small number>-<large number> is allowed. Example: 1-2   3-6")
            end
            bit_value = ~(0xffffffffffffffff << (stop + 1)) & (0xffffffffffffffff << start)
            final = final | bit_value
        else
            error("Cron: cannot parse $i in $ranges: only <small number>-<large number> is allowed. Example: 1-2   3-6")
        end
    end
    final
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
    Dates.tonext(dt::DateTime, c::Cron) -> Union{DateTime, Nothing}
    Dates.tonext(t::Time, c::Cron; same::Bool = false) -> Time
    Dates.tonext(d::Date, c::Cron; same::Bool = false) -> Union{DateTime, Nothing}

Jobs are executed by JobScheduler when the second, minute, hour, and month of year fields match the current time, and when at least one of the two day fields (day of month, or day of week) match the current time.
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

    # next_available_day
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

function tonext_dayofweek(d::Date, c::Cron; same::Bool = false)
    dow = bitfindnext(c.day_of_week, dayofweek(d) + !same, 1:7)
    if isnothing(dow)
        return nothing # check month-day
    else
        num_day = dow - dayofweek(d)
        if num_day < 0
            num_day += 7
        elseif num_day == 0 && !same
            num_day += 7
        end
        if same && num_day == 0
            return d
        elseif !same && num_day == 1
            return d + Day(1)
        end
        return d + Day(num_day)
    end
end

function tonext_monthday(d::Date, c::Cron; same::Bool = false, limit::Date = d + Day(3000))
    # day of month invalid?
    dom = bitfindnext(c.day_of_month, 1, 1:31)
    mon = bitfindnext(c.month, 1, 1:12)
    if isnothing(dom) || isnothing(mon)
        return nothing
    end

    # stepwise 
    if same && is_valid_month_day(d, c)
        return d
    end
    d2 = d + Day(1)
    while d2 <= limit
        if is_valid_month_day(d2, c)
            return d2
        else
            d2 += Day(1)
        end
    end
    return nothing
end

function Dates.tonext(d::Date, c::Cron; same::Bool = false)
    based = date_based_on(c)
    if based == :everyday
        return (same ? d : d + Day(1))
    elseif based == :monthday
        return tonext_monthday(d, c; same = same)
    elseif based == :dayofweek
        return tonext_dayofweek(d, c; same = same)
    elseif based == :both
        next_dow = tonext_dayofweek(d, c; same = same)
        if (same && next_dow == d) || (!same && next_dow == d + Day(1))
            return next_dow
        end
        next_md = tonext_monthday(d, c; same = same, limit = next_dow)
        return (next_md < next_dow ? next_md : next_dow)
    else  # :none
        return nothing
    end
end


@inline function is_same_time(dt::DateTime, sec::Int, min::Int, hr::Int)
    sec == second(dt) && min == minute(dt) && hr == hour(dt)
end

@inline function is_time_larger(dt::DateTime, sec::Int, min::Int, hr::Int)
    if hr > hour(dt)
        return true
    elseif hr < hour(dt)
        return false
    end
    if min > minute(dt)
        return true
    elseif min < minute(dt)
        return false
    end
    return sec > second(dt)
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

@inline function is_same_day(dt::DateTime, dom, mon, dow)
    dow == dayofweek(dt) || (dom == day(dt) && mon == month(dt))
end

@inline function is_every_day_of_week(c::Cron)
    c.day_of_week & 0x00000000000000fe == 0x00000000000000fe
end
@inline function is_none_day_of_week(c::Cron)
    c.day_of_week & 0x00000000000000fe == 0
end

@inline function is_every_month(c::Cron)
    (c.month & 0x0000000000001ffe == 0x0000000000001ffe)
end
@inline function is_every_day_of_month(c::Cron)
    (c.day_of_month & 0x00000000fffffffe == 0x00000000fffffffe)
end

@inline function is_every_month_day(c::Cron)
    is_every_month(c) && is_every_day_of_month(c)
end
@inline function is_none_month_day(c::Cron)
    (c.month & 0x0000000000001ffe == 0) || (c.day_of_month & 0x00000000fffffffe == 0)
end



@inline function is_every_day(c::Cron)
    is_every_day_of_week(c) || is_every_month_day(c)
end

@inline function is_one_at(uint::UInt, idx::Int)
    x = 1 << idx
    uint & x == x
end

function is_valid_day(dt::Date, c::Cron)
    if is_one_at(c.day_of_week, dayofweek(dt))
        return true
    end
    is_one_at(c.month, month(dt)) && is_one_at(c.day_of_month, day(dt))
end
is_valid_day(dt::DateTime, c::Cron) = is_valid_day(Date(dt), c)

function is_valid_month_day(dt::Date, c::Cron)
    is_one_at(c.month, month(dt)) && is_one_at(c.day_of_month, day(dt))
end

"""
    date_based_on(c::Cron) -> Symbol

Whether date of `c` is based on `:dayofweek`, `:monthday`, `:everyday`, `:both`, or `:none`.
"""
function date_based_on(c::Cron)
    if is_every_day_of_week(c)
        if is_every_month_day(c)
            :everyday
        else
            if is_none_month_day(c)
                :everyday
            else
                :monthday
            end
        end
    else # dow
        if is_every_month_day(c)
            if is_none_day_of_week(c)
                :everyday
            else
                :dayofweek
            end
        else
            if is_none_day_of_week(c)
                if is_none_month_day(c)
                    :none
                else
                    :monthday
                end
            else
                if is_none_month_day(c)
                    :dayofweek
                else
                    :both
                end
            end
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
        return "at $(hours[1]):$(minutes[1]):$(seconds[1])"
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

    if !every_hour
        hour_str = get_hour_description(hours)
        str *= " past $hour_str"
    end
    str
end

function get_second_description(seconds::Vector{Int})
    if length(seconds) == 0
        "0 second"
    elseif length(seconds) == 1
        "$(seconds[1]) second"
    else
        str = join(seconds, ",")
        "$(str) seconds"
    end
end
function get_minute_description(minutes::Vector{Int})
    if length(minutes) == 0
        "0 minute"
    elseif length(minutes) == 1
        "$(minutes[1]) minute"
    else
        str = join(minutes, ",")
        "$(str) minutes"
    end
end
function get_hour_description(hours::Vector{Int})
    if length(hours) == 0
        "0 hour"
    elseif length(hours) == 1
        "$(hours[1]) hour"
    else
        str = join(hours, ",")
        "$(str) hours"
    end
end

function get_date_description(c::Cron)
    based = date_based_on(c)
    if based === :everyday
        return ""
    elseif based === :dayofweek
        dow_str = get_dow_description(c)
        return "on $dow_str"
    elseif based === :monthday
        monthday_str = get_monthday_description(c)
        return monthday_str
    else
        dow_str = get_dow_description(c)
        monthday_str = get_monthday_description(c)
        return "on $dow_str or $monthday_str"
    end
end

function get_dow_description(c::Cron)
    dows = bitsfind(c.day_of_week, 1:7)
    human_readables = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    dows2 = human_readables[dows]
    str = join(dows2, ",")
end

function get_monthday_description(c::Cron)
    if is_every_month(c)
        if is_every_day_of_month(c)
            ""
        else
            days = bitsfind(c.day_of_month, 1:31)
            day_str = join(days, ",")
            "on day-of-month $day_str"
        end
    else
        months = bitsfind(c.month, 1:12)
        human_readables = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        months2 = human_readables[months]
        mon_str = join(months2, ",")
        if is_every_day_of_month(c)
            "everyday in $mon_str"
        else
            days = bitsfind(c.day_of_month, 1:31)
            day_str = join(days, ",")
            "on day-of-month $day_str in $mon_str"
        end
    end
end