"""
    progress_bar(percent::Float64, width::Int = 20)

Return ::String for progress bar whose char length is `width`.

- `percent`: range from 0.0 - 1.0, or to be truncated.

- `width`: should be > 3. If <= 10, percentage will not show. If > 10, percentage will show.
"""
function progress_bar(percent::Float64, width::Int = 20)
    if percent > 1.0
        percent = 1.0
    end
    if percent < 0.0
        percent = 0.0
    end
    if width < 3
        width = 3
        w = 1
    elseif width <= 10
        w = width - 2
    else
        w = width - 10  # width of block ()
    end
    if isnan(percent)
        percent = 1.0
    end
    block_w = w * percent
    block_num = floor(Int, block_w)
    block_last_i = round(Int, (block_w - block_num) * 8)
    if block_last_i == 0 || block_last_i == 8
        empty_num = w - block_num
        bar = BAR_LEFT * (@green BLOCK ^ block_num) * (" " ^ empty_num * BAR_RIGHT)
    else
        empty_num = w - block_num - 1
        block_last = BLOCKS[block_last_i]
        bar = BAR_LEFT * (@green BLOCK ^ block_num * block_last) * (" " ^ empty_num * BAR_RIGHT)
    end
    if width <= 10
        return bar
    else
        percent_hint = @green @sprintf("%6.2f%% ", 100 * percent)
        return percent_hint * bar 
    end
end

"""
    queue_progress(;remove_tmp_files::Bool = true, kwargs...)
    queue_progress(stdout_tmp::IO, stderr_tmp::IO;
    group_seperator = r": *", wait_second_for_new_jobs::Int = 1)

- `group_seperator`: delim to split `(job::Job).name` to group and specific job names.

- `wait_second_for_new_jobs`: if `auto_exit`, and all jobs are PAST, not quiting `queue_progress` immediately but wait for a period. If new jobs are submitted, not quiting `queue_progress`.
"""
function queue_progress(;remove_tmp_files::Bool = true, kwargs...)
    now_str = Dates.format(now(),DateFormat("yyyymmdd_HHMMSS")) * "_$(round(Int, rand()*10000))"
    
    stdout_tmp_file = joinpath(homedir(), "julia_$(now_str).out")
    stdout_tmp = open(stdout_tmp_file, "w+")

    stderr_tmp_file = joinpath(homedir(), "julia_$(now_str).err")
    stderr_tmp = open(stderr_tmp_file, "w+")

    # stdlog_tmp_file = joinpath(homedir(), "julia_$(now_str).log")
    # stdlog_tmp_io = open(stdlog_tmp_file, "w+")
    # stdlog_tmp = Logging.SimpleLogger(stdlog_tmp_io)

    try
        queue_progress(stdout_tmp, stderr_tmp; kwargs...)
    catch
        rethrow()
    finally
        close(stdout_tmp)
        close(stderr_tmp)
        # close(stdlog_tmp_io)
        if remove_tmp_files
            rm(stdout_tmp_file)
            rm(stderr_tmp_file)
            # rm(stdlog_tmp_file)
        end
    end
end

function queue_progress(stdout_tmp::IO, stderr_tmp::IO;
    group_seperator = r": *", wait_second_for_new_jobs::Int = 1)

    progress_loop = true
    old_stdout = Base.stdout
    old_stderr = Base.stderr
    # old_stdlog = global_logger()

    start_pos_stdout_tmp = position(stdout_tmp)
    start_pos_stderr_tmp = position(stderr_tmp)
    # start_pos_stdlog_tmp = position(stdlog_tmp.stream)

    # if !exit_with_key
    #     auto_exit = true
    # end

    try
        event = nothing
        init_term()
        h_old, w_old = 0, 0

        while progress_loop

            if Base.stdout isa Base.TTY
                old_stdout = Base.stdout
                redirect_stdout(stdout_tmp)
            end

            if Base.stderr isa Base.TTY
                old_stderr = Base.stderr
                redirect_stderr(stderr_tmp)
            end

            # if Logging.current_logger isa ConsoleLogger
            #     old_stdlog = Logging.current_logger
            #     global_logger(stdlog_tmp)
            # end

            Base.flush(stdout_tmp)
            Base.flush(stderr_tmp)
            # Base.flush(stdlog_tmp.stream)

            # handle keyboard event
            # if exit_with_key && Base.stdin isa Base.TTY
            #     if event == Terming.KeyPressedEvent(Terming.ESC) || event == Terming.KeyPressedEvent('x') || event == Terming.KeyPressedEvent('q')
            #         progress_loop = false
            #         # T.alt_screen(false)
            #     else
            #         sequence = T.read_stream()
            #         event = Terming.parse_sequence(sequence)
            #     end
            # end

            # handle auto exit
            if length(queue()) == 0
                sleep(wait_second_for_new_jobs)
                if length(queue()) == 0
                    progress_loop = false
                    # T.alt_screen(false)
                end
            end

            queue_update = queue_summary(;group_seperator = group_seperator)

            h, w = T.displaysize()

            if h == h_old && w == w_old
                display_size_update = false
            else
                display_size_update = true
                h_old, w_old = h, w
            end

            if queue_update || display_size_update
                T.clear()
                row = view_update_resources(h, w; row = 1)
                row = view_update_job_group_title(h, w; row = row)
                row = view_update_job_group(h, w; row = row, job_group = ALL_JOB_GROUP, highlight = true)
                while row < h
                    for job_group in values(JOB_GROUPS)
                        job_group.total < 2 && continue
                        row = view_update_job_group(h, w; row = row, job_group = job_group)
                    end
                    break
                end
                row = view_update_job_group(h, w; row = row, job_group = OTHER_JOB_GROUP, highlight = true)
            end

            sleep(0.1)
        end
    catch
        rethrow()
    finally
        reset_term()

        old_stdout != Base.stdout && redirect_stdout(old_stdout)
        old_stderr != Base.stderr && redirect_stderr(old_stderr)
        # old_stdlog != global_logger() && global_logger(old_stdlog)
        

        # if !(stdlog_tmp.stream isa IOBuffer)
        #     println(Pipelines.stderr_origin, @cyan @bold "Logs   saved to $(stdlog_tmp.stream)")
        # end
        # println(Pipelines.stdout_origin, @yellow @bold "Stdout saved to $stdout_tmp")
        # println(Pipelines.stderr_origin, @red @bold "Stderr saved to $stderr_tmp")
    end
    isopen(stdout_tmp) && Base.flush(stdout_tmp)
    isopen(stderr_tmp) && Base.flush(stderr_tmp)
    # isopen(stdlog_tmp.stream) && Base.flush(stdlog_tmp.stream)
    
    print_rest_lines(Pipelines.stdout_origin, stdout_tmp, start_pos_stdout_tmp)
    # print_rest_lines(Pipelines.stderr_origin, stdlog_tmp.stream, start_pos_stdlog_tmp)
    print_rest_lines(Pipelines.stderr_origin, stderr_tmp, start_pos_stderr_tmp)
end

function print_rest_lines(io_to::IO, io_from::IO, io_from_position::Int; with_log_style::Bool = true)
    lock(io_from.lock)
    try
        seek(io_from, io_from_position)
        log_style = :nothing
        while !eof(io_from)
            line = readline(io_from)
            if with_log_style
                line, log_style = style_line(line, log_style)
            end
            println(io_to, line)
        end
    catch
        rethrow()
    finally
        unlock(io_from)
    end
end

"""
    styled_line, log_style_of_this_line = style_line(line::String, log_style_of_last_line::Symbol)
"""
function style_line(line::String, log_style::Symbol)
    if startswith(line, "ERROR:")
        line = replace(line, r"^ERROR" => @red(@bold "ERROR:"))
        log_style = :nothing
    elseif startswith(line, r" *@ ")   # traceback info
        line = @dim(line)
        log_style = :nothing
    elseif startswith(line, r"^[\[┌] Info:")
        # Info: Debug: Warning: Error:
        # cyan  blue   yellow   red
        line = @bold(@cyan line[1:7]) * line[8:end]
        log_style = :info
    elseif startswith(line, r"^[\[┌] Debug:")
        line = @bold(@blue line[1:8]) * line[9:end]
        log_style = :debug
    elseif startswith(line, r"^[\[┌] Warning:")
        line = @bold(@yellow line[1:10]) * line[11:end]
        log_style = :warning
        startswith(line, r"^[\[┌] Error:")
        line = @bold(@red line[1:8]) * line[9:end]
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
        end
        if line_1 == "└"  # close of log message
            log_style = :nothing
        end
        line_rest, _ = style_line(line[2:end], :nothing)
        line = line_1 * line_rest
    end
    return line, log_style
end

function view_update_resources(h::Int, w::Int; row::Int = 2, max_cpu = JobSchedulers.SCHEDULER_MAX_CPU, max_mem = JobSchedulers.SCHEDULER_MAX_MEM)
    title = @bold("CURRENT RESOURCES:")

    cpu_text = ("    CPU: ")
    cpu_val = "$CPU_RUNNING/$max_cpu"
    cpu_width = 9 + length(cpu_val)
    if CPU_RUNNING < max_cpu
        cpu_text *= @green(cpu_val)
    else
        cpu_text *= @yellow(cpu_val)
    end


    mem_text = ("    MEM: ")
    mem_percent = @sprintf("%3.2f%%", MEM_RUNNING / max_mem * 100)
    mem_width = 9 + length(mem_percent)
    if MEM_RUNNING < max_mem
        mem_text *= @green("$mem_percent")
    else
        mem_text *= @yellow("$mem_percent")
    end

    # render
    T.cmove(row, 1)

    if h - row < 5
        # no render: height not enough
        return row
    end

    T.println(title)
    row += 1
    if cpu_width + mem_width <= w
        T.print(cpu_text)
        T.println(mem_text)
        row +=1
    else
        T.println(cpu_text)
        T.println(mem_text)
        row += 2
    end
    return row
end

function view_update_job_group_title(h::Int, w::Int; row::Int = 2)
    title = @bold("JOB PROGRESS:")
    description = "(" * @green("running") * "," *
                        @red("failed") * "," *
                        @yellow("cancelled") * "," *
                        @bold("total") * ")"
    width_description = 32

    T.cmove(row, 1)

    if h - row > 0
        T.println(title)
        row += 1
    end

    if h - row > 0 && w > width_description + 4
        T.print("   ")
        T.println(description)
        row += 1
    end
    return row
end

function view_update_job_group(h::Int, w::Int; row::Int = 2, job_group = ALL_JOB_GROUP, highlight::Bool = false)
    width_progress = w ÷ 4
    if width_progress < 12
        width_progress = max(w ÷ 5, 5)
    end

    percent = (job_group.total - job_group.queuing - job_group.running) / job_group.total
    text_progress = progress_bar(percent, width_progress)
    
    group_name = job_group.group_name
    width_group_name = length(group_name) + 1
    
    if isempty(job_group.job_names)
        job_name = ""
    else
        job_name = replace(job_group.job_names[end], group_name => ""; count = 1)
        if startswith(job_name, r"[A-Za-z0-9]*")
            job_name = ": " * job_name
        end
    end
    width_job_name = length(job_name)


    running = string(job_group.running)
    failed = string(job_group.failed)
    cancelled = string(job_group.cancelled)
    total = string(job_group.total)

    width_counts = length(running) + length(failed) + length(cancelled) + length(total) + 6
    text_counts = "(" * @green(running) * "," *
                        @red(failed) * "," *
                        @yellow(cancelled) * "," *
                        @bold(total) * ")"
    
    # render progress bar line
    T.cmove(row, 1)
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
        if highlight
            T.print(@bold @cyan group_name)
        else
            T.print(@bold group_name)
        end
    end
    if show_job && length(job_name) > 0
        T.print(@dim job_name)
    end
    if show_counts
        T.print(" " * text_counts)
    end
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


function init_term()
    # try
    #     T.raw!(true)
    # catch
    # end
    # T.alt_screen(true)
    cshow(false)
    # T.clear()
end

function reset_term()
    T.cmove_line_last()
    T.cmove_down()
    # T.println(@dim "\nExit progress interface.")
    # try
    #     T.raw!(false)
    # catch
    # end
    # T.alt_screen(false)
    T.cshow(true)
end

# function progress_display(CPU_RUNNING::Int, MEM_RUNNING::Int)
#     init_term()
#     view_update_resources(CPU_RUNNING, MEM_RUNNING)
#     handle_event()
#     reset_term()
#     return
# end