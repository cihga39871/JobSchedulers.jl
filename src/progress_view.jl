

# https://gist.github.com/ConnerWill/d4b6c776b509add763e17f9f113fd25b#erase-functions
const erase_rest_line = Terming.CSI * "0K"
const erase_current_line = Terming.CSI * "2K"

"""
    progress_bar(percent::Float64, width::Integer = 20)

Return ::String for progress bar whose char length is `width`.

- `percent`: range from 0.0 - 1.0, or to be truncated.

- `width`: should be > 3. If <= 10, percentage will not show. If > 10, percentage will show.
"""
function progress_bar(percent::Float64, width::Integer = 20; is_in_terminal::Bool = true)
    if percent > 1.0
        percent = 1.0
    end
    if percent < 0.0
        percent = 0.0
    end
    if isnan(percent)
        percent = 1.0
    end

    if is_in_terminal
        if width < 3
            width = 3
            w = 1
        elseif width <= 10
            w = width - 2
        else
            w = width - 10  # width of blocks
        end
    else
        width = 39871
        w = 20
    end

    block_w = w * percent
    block_num = floor(Int, block_w)
    block_last_i = round(Int, (block_w - block_num) * 8)
    if block_last_i == 0 || block_last_i == 8
        empty_num = w - block_num
        if is_in_terminal
            bar = BAR_LEFT * (@green BLOCK ^ block_num) * (" " ^ empty_num * BAR_RIGHT)
        else
            bar = BAR_LEFT * (BLOCK ^ block_num) * (" " ^ empty_num * BAR_RIGHT)
        end
    else
        empty_num = w - block_num - 1
        block_last = BLOCKS[block_last_i]
        if is_in_terminal
            bar = BAR_LEFT * (@green BLOCK ^ block_num * block_last) * (" " ^ empty_num * BAR_RIGHT)
        else
            bar = BAR_LEFT * (BLOCK ^ block_num * block_last) * (" " ^ empty_num * BAR_RIGHT)
        end
    end
    if width <= 10
        return bar
    else
        if is_in_terminal
            percent_hint = @green @sprintf("%6.2f%% ", 100 * percent)
        else
            percent_hint = @sprintf("%6.2f%% ", 100 * percent)
        end
        return percent_hint * bar 
    end
end

"""
    queue_progress(;remove_tmp_files::Bool = true, kwargs...)
    queue_progress(stdout_tmp::IO, stderr_tmp::IO;
    group_seperator = GROUP_SEPERATOR, wait_second_for_new_jobs::Int = 1, loop::Bool = true, exit_num_jobs::Int = 0)

- `group_seperator`: delim to split `(job::Job).name` to group and specific job names.

- `wait_second_for_new_jobs::Int`: if `auto_exit`, and all jobs are PAST, not quiting `queue_progress` immediately but wait for a period. If new jobs are submitted, not quiting `queue_progress`.

- `loop::Bool`: if false, only show the current progress and exit. 

- `exit_num_jobs::Int`: exit when `queue()` has less than `Int` number of jobs. It is useful to ignore some jobs that are always running or recurring.
"""
function queue_progress(;remove_tmp_files::Bool = true, kwargs...)

    is_in_terminal = ScopedStreams.stdout_origin isa Base.TTY  # does not care about stderr, since progress meter use stdout. 
    if !is_in_terminal
        # Not in terminal == stdout is a file
        # We do not want to contaminate stdout with non-readable chars
        normal_print_queue_progress()
        return
    end

    # COV_EXCL_START
    now_str = Dates.format(now(),DateFormat("yyyymmdd_HHMMSS")) * "_$(round(Int, rand()*10000))"
    
    stdout_tmp_file = joinpath(homedir(), "julia_$(now_str).out")
    stdout_tmp = open(stdout_tmp_file, "w+")

    stderr_tmp_file = joinpath(homedir(), "julia_$(now_str).err")
    stderr_tmp = open(stderr_tmp_file, "w+")

    try
        queue_progress(stdout_tmp, stderr_tmp; kwargs...)
    catch
        rethrow()
    finally
        close(stdout_tmp)
        close(stderr_tmp)
        if remove_tmp_files
            rm(stdout_tmp_file)
            rm(stderr_tmp_file)
        end
    end
    # COV_EXCL_STOP
end

function queue_progress(stdout_tmp::IO, stderr_tmp::IO;
    wait_second_for_new_jobs::Integer = 1, loop::Bool = true, exit_num_jobs::Integer = 0)

    is_in_terminal = ScopedStreams.stdout_origin isa Base.TTY  # does not care about stderr, since progress meter use stdout. 
    if !is_in_terminal
        # Not in terminal == stdout is a file
        # We do not want to contaminate stdout with non-readable chars
        normal_print_queue_progress()
        return
    end

    stdout_tmp = ScopedStreams.deref(stdout_tmp)
    stderr_tmp = ScopedStreams.deref(stderr_tmp)

    redirect_stream(stdout_tmp, stderr_tmp) do 
            
        start_pos_stdout_tmp = position(stdout_tmp)
        start_pos_stderr_tmp = position(stderr_tmp)

        # COV_EXCL_START
        is_interactive = isinteractive() && ScopedStreams.deref(Base.stdin) isa Base.TTY
        
        # if !exit_with_key
        #     auto_exit = true
        # end
        row = 1 # the current row of cursor

        groups_shown = JobGroup[]
        
        init_group_state!()
        global PROGRESS_METER = true

        try
            h_old, w_old = 0, 0
            
            term_init = true
            while true

                Base.flush(stdout_tmp)
                Base.flush(stderr_tmp)

                queue_update = if isready(SCHEDULER_PROGRESS_ACTION[])
                    take!(SCHEDULER_PROGRESS_ACTION[])
                    true
                else
                    false
                end

                h, w = T.displaysize()

                if h == h_old && w == w_old
                    display_size_update = false
                else
                    display_size_update = true
                    h_old, w_old = h, w
                end
                
                if queue_update || display_size_update
                    if term_init
                        init_term(h)
                        term_init = false
                    end
                    row = view_update(h, w; row = 1, groups_shown = groups_shown, is_in_terminal = is_in_terminal, is_interactive = is_interactive)
                end

                # # handle keyboard event
                # if is_interactive
                #     event = handle_keyboard_event()
                #     if event === :quit
                #         break
                #     end
                # end

                # handle auto exit
                if !loop
                    break
                end

                if scheduler_status(verbose=false) != RUNNING
                    @error "Scheduler was not running. Jump out from the progress bar."
                    scheduler_status()
                    break
                end
                if !are_remaining_jobs_more_than(exit_num_jobs)
                    sleep(wait_second_for_new_jobs)
                    if !are_remaining_jobs_more_than(exit_num_jobs)
                        break
                        # T.alt_screen(false)
                    end
                end
                
                sleep(0.1)
            end
        catch
            rethrow()
        finally
            global PROGRESS_METER = false
            h, w = T.displaysize()
            reset_term(row, h)

            isopen(stdout_tmp) && Base.flush(stdout_tmp)
            isopen(stderr_tmp) && Base.flush(stderr_tmp)

            print_rest_lines(ScopedStreams.stdout_origin, stdout_tmp, start_pos_stdout_tmp)
            print_rest_lines(ScopedStreams.stderr_origin, stderr_tmp, start_pos_stderr_tmp)
        end
        # COV_EXCL_STOP
    end

end

function print_rest_lines(io_to::IO, io_from::IO, io_from_position::Integer; with_log_style::Bool = true)
    seek(io_from, io_from_position)
    log_style = :nothing
    while !eof(io_from)
        line = readline(io_from)
        if with_log_style
            line, log_style = style_line(line, log_style)
        end
        println(io_to, line)
    end
end

"""
    styled_line, log_style_of_this_line = style_line(line::String, log_style_of_last_line::Symbol)
"""
function style_line(line::String, log_style::Symbol)
    if length(line) <= 1
        return line, log_style
    elseif startswith(line, "ERROR:")
        line = replace(line, r"^ERROR\:" => @red(@bold "ERROR:"))
        log_style = :nothing
    elseif startswith(line, r" *@ ")   # traceback info
        line = @dim(line)
        log_style = :nothing
    elseif startswith(line, r"^[\[┌] Info: ")
        # Info: Debug: Warning: Error:
        # cyan  blue   yellow   red
        a = nextind(line, 1, 1) - 2  # first_utf_char_additional_length
        line = @bold(@cyan line[1:7 + a]) * line[8 + a:end]
        log_style = :info
    elseif startswith(line, r"^[\[┌] Debug: ")
        a = nextind(line, 1, 1) - 2  # first_utf_char_additional_length
        line = @bold(@blue line[1:8 + a]) * line[9 + a:end]
        log_style = :debug
    elseif startswith(line, r"^[\[┌] Warning: ")
        a = nextind(line, 1, 1) - 2  # first_utf_char_additional_length
        line = @bold(@yellow line[1:10 + a]) * line[11 + a:end]
        log_style = :warning
    elseif startswith(line, r"^[\[┌] Error: ")
        a = nextind(line, 1, 1) - 2  # first_utf_char_additional_length
        line = @bold(@red line[1:8 + a]) * line[9 + a:end]
        log_style = :error
    elseif startswith(line, r"^[│└] ")
        line_1 = line[1:1]
        line_1 = if log_style === :info
            @bold(@cyan line_1)
        elseif log_style === :debug
            @bold(@blue line_1)
        elseif log_style === :warning
            @bold(@yellow line_1)
        elseif log_style === :error
            @bold(@red line_1)
        else
            line_1
        end
        if line[1] == '└'  # close of log message
            log_style = :nothing
        end
        a = nextind(line, 1, 1) - 2  # first_utf_char_additional_length
        line_rest, _ = style_line(line[2 + a:end], :nothing)
        line = line_1 * line_rest
    end
    return line, log_style
end

function view_update_resources(h::Integer, w::Integer; row::Integer = 2, max_cpu::Integer = JobSchedulers.SCHEDULER_MAX_CPU, max_mem::Int64 = JobSchedulers.SCHEDULER_MAX_MEM, is_in_terminal::Bool = true)
    global RESOURCE
    if h - row < 5
        # no render: height not enough
        return row
    end

    title = is_in_terminal ? @bold("CURRENT RESOURCES:") : "CURRENT RESOURCES:"

    cpu_text = ("    CPU: ")
    cpu_val = "$(RESOURCE.cpu)/$max_cpu"
    cpu_width = 9 + length(cpu_val)
    if RESOURCE.cpu < max_cpu
        cpu_text *= is_in_terminal ? @green(cpu_val) : cpu_val
    else
        cpu_text *= is_in_terminal ? @yellow(cpu_val) : cpu_val
    end


    mem_text = ("    MEM: ")
    mem_percent = @sprintf("%3.2f%%", RESOURCE.mem / max_mem * 100)
    mem_width = 9 + length(mem_percent)
    if RESOURCE.mem < max_mem
        mem_text *= is_in_terminal ? @green(mem_percent) : mem_percent
    else
        mem_text *= is_in_terminal ? @yellow(mem_percent) : mem_percent
    end

    # render
    is_in_terminal && T.cmove(row, 1)

    T.println(title, erase_rest_line)
    row += 1
    if cpu_width + mem_width <= w
        T.print(cpu_text)
        T.println(mem_text, erase_rest_line)
        row +=1
    else
        T.println(cpu_text, erase_rest_line)
        T.println(mem_text, erase_rest_line)
        row += 2
    end
    return row
end

# COV_EXCL_START
function view_update_job_group_title(h::Integer, w::Integer; row::Integer = 2, is_in_terminal::Bool = true)
    
    if is_in_terminal
        title = @bold("JOB PROGRESS:")
        description = @dim("[") * @green("running") * @dim(", ") *
                            @red("failed") *
                            @yellow("+cancelled") * @dim(", ") * 
                            "done/" *
                            @bold("total") * @dim("]")
    else
        title = "JOB PROGRESS:"
        description = "[running, failed+cancelled, done/total]"
    end
    width_description = 43  # 4 + length(description_plain)

    is_in_terminal && T.cmove(row, 1)

    if h - row > 0
        T.println(title, erase_rest_line)
        row += 1
    end

    if h - row > 0 && w > width_description
        T.print("    ")
        T.println(description, erase_rest_line)
        row += 1
    end
    return row
end

zero_dim(num::Integer, text) = num == 0 ? @dim(text) : text

function view_update_job_group(h::Integer, w::Integer; row::Integer = 2, job_group::JobGroup = ALL_JOB_GROUP, highlight::Bool = false, is_in_terminal::Bool = true, group_seperator_at_begining = Regex("^" * GROUP_SEPERATOR.pattern))
    width_progress = w ÷ 4
    if width_progress < 12
        width_progress = max(w ÷ 5, 5)
    end

    percent = (job_group.total - job_group.queuing - job_group.running) / job_group.total
    text_progress = progress_bar(percent, width_progress; is_in_terminal = is_in_terminal)
    
    group_name = job_group.name
    width_group_name = length(group_name) + 1
    
    job_name = isempty(job_group.jobs) ? "" : first(job_group.jobs).name
    if job_name != ""
        job_name = replace(job_name, group_name => ""; count = 1)
        job_name = ": " * replace(job_name, group_seperator_at_begining => "", count = 1)
    end
    width_job_name = length(job_name)


    running = string(job_group.running)
    failed = string(job_group.failed)
    cancelled = string(job_group.cancelled)
    done = string(job_group.done)
    total = string(job_group.total)
    
    width_counts = length(running) + length(failed) + length(cancelled) + length(done) + length(total) + 8
    if is_in_terminal
        text_counts = @dim("[") * @green(zero_dim(job_group.running, running)) * @dim(", ") *
                            @red(zero_dim(job_group.failed, failed)) * 
                            @yellow(zero_dim(job_group.cancelled, "+" * cancelled)) * 
                            @dim(", ") * zero_dim(job_group.done, done) * "/"*
                            @bold(total) * @dim("]")
    else
        text_counts = "[" * running * ", " *
                            failed * "+" *
                            cancelled * ", " * 
                            done * "/" *
                            total * "]"
    end
    
    # render progress bar line
    if is_in_terminal
        # T.clear_line(row)
        T.cmove(row, 1)
    end
    T.print(text_progress)
    col_left = w - width_progress

    show_counts = col_left > width_counts
    if show_counts
        col_left -= width_counts
    end
    
    if col_left > 3
        show_group = true
        if col_left < width_group_name
            group_name = group_name[1:col_left - 2] * ".."
            show_job = false
            col_left = 0
        else
            show_job = true
            col_left -= width_group_name
        end
    else
        show_group = false
        show_job = false
    end

    if col_left > 3
        if col_left < width_job_name
            job_name = job_name[1:col_left - 2] * ".."
        end
    end

    if show_group
        if !is_in_terminal
            T.print(group_name)
        elseif highlight
            T.print(@bold @cyan group_name)
        else
            T.print(@bold group_name)
        end
    end
    if show_job && length(job_name) > 0
        T.print(is_in_terminal ? @dim(job_name) : job_name)
    end
    if show_counts
        T.print(" " * text_counts)
    end
    T.print(erase_rest_line)
    T.println()
    row += 1
    return row
end

# function handle_quit()
#     keep_running = false
#     T.cmove_line_last()
#     T.println("\nAll jobs are finished")
#     return keep_running
# end
# function handle_event()
#     is_running = true
#     while is_running
#         sequence = T.read_stream()
#         if sequence == "\e" # ESC
#             is_running = handle_quit()
#         end
#     end
# end


function init_term(h::Integer)
    # try
    #     T.raw!(true)
    # catch
    # end
    # T.alt_screen(true)
    try
        T.cshow(false)
    catch
    end
    print(ScopedStreams.stdout_origin, "\n" ^ h)
    # T.clear()
end

"""
    reset_term(row_from, row_to)

Empty lines from `row_from` to `row_to`. Set cursor to `row_from`. Show cursor.
"""
function reset_term(row_from, row_to)
    for r in row_from:row_to
        T.clear_line(r)
    end
    T.cmove(row_from, 1)
    T.println()
    # T.println(@dim "\nExit progress interface.")
    # try
    #     T.raw!(false)
    # catch
    # end
    # T.alt_screen(false)
    try
        T.cshow(true)
    catch
    end
end


"""
    view_update(h, w; row = 1, groups_shown::Vector{JobGroup} = JobGroup[], is_in_terminal::Bool = true, is_interactive = true, group_seperator_at_begining = Regex("^" * GROUP_SEPERATOR.pattern))

Update the whole screen view.
"""
function view_update(h, w; row = 1, groups_shown::Vector{JobGroup} = JobGroup[], is_in_terminal::Bool = true, is_interactive = true, group_seperator_at_begining = Regex("^" * GROUP_SEPERATOR.pattern))
    empty!(groups_shown)

    # is_in_terminal && T.clear()

    row = view_update_resources(h, w; row = row, is_in_terminal = is_in_terminal)

    if ALL_JOB_GROUP.total == 0
        if is_in_terminal
            T.cmove(row, 1)
            T.println((@bold @yellow "NO JOB SUBMITTED."), erase_rest_line)
        else
            T.println("NO JOB SUBMITTED.")
        end
        row += 1
        @goto ret
    end

    row = view_update_job_group_title(h, w; row = row, is_in_terminal = is_in_terminal)

    row = view_update_job_group(h, w; row = row, job_group = ALL_JOB_GROUP, highlight = true, is_in_terminal = is_in_terminal, group_seperator_at_begining = group_seperator_at_begining)

    # specific job groups
    lock(JOB_GROUPS_LOCK) do
        for job_group in values(JOB_GROUPS)
            job_group.total < 2 && continue
            if row >= h - 1
                break
            end
            row = view_update_job_group(h, w; row = row, job_group = job_group, is_in_terminal = is_in_terminal, group_seperator_at_begining = group_seperator_at_begining)
            push!(groups_shown, job_group)
        end
    end

    compute_other_job_group!(groups_shown)

    if OTHER_JOB_GROUP.total > 0
        row = view_update_job_group(h, w; row = row, job_group = OTHER_JOB_GROUP, highlight = true, is_in_terminal = is_in_terminal, group_seperator_at_begining = group_seperator_at_begining)
    end

    if is_in_terminal
        # clear rest lines
        for r in row:h
            T.cmove(r,1)
            T.print(erase_current_line)
        end
    end
    @label ret
    # if is_interactive
    #     T.cmove_line_last()
    #     T.cmove_left()
    #     T.print("Press q or x to quit.")
    # end
    return row
end

# COV_EXCL_STOP

# function handle_keyboard_event()
#     bb = bytesavailable(Base.stdin)
#     bb == 0 && return :nothing
#     data = read(stdin, bb)
#     for c in data
#         if c == 0x71 || c == 0x78 # q or x
#             return :quit
#         end
#     end
#     return :nothing
# end

function normal_print_queue_progress(; group_seperator = GROUP_SEPERATOR, wait_all_jobs = true)
    if wait_all_jobs
        wait_queue(show_progress = false)
    end
    # queue_summary(;group_seperator = group_seperator)
    println()
    group_seperator_at_begining = Regex("^" * group_seperator.pattern)
    view_update(39871, 120; row = 1, groups_shown = JobGroup[], is_in_terminal = false, is_interactive = false, group_seperator_at_begining = group_seperator_at_begining)
    println()
end
