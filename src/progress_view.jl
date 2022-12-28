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
    elseif width <= 10
        w = width - 2
    else
        w = width - 10  # width of block ()
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

function queue_progress(;group_seperator = r": *")
    now_str = Dates.format(now(),DateFormat("yyyymmdd_HHMMSS")) * "_$(round(Int, rand()*10000))"
    
    stdout_tmp_file = "julia_$(now_str).out"
    stdout_tmp = open(joinpath(homedir(), stdout_tmp_file), "w+")

    stderr_tmp_file = "julia_$(now_str).err"
    stderr_tmp = open(joinpath(homedir(), stderr_tmp_file), "w+")

    stdlog_tmp_file = "julia_$(now_str).log"
    stdlog_tmp_io = open(joinpath(homedir(), stdlog_tmp_file), "w+")
    stdlog_tmp = Logging.SimpleLogger(stdlog_tmp_io)

    try
        queue_progress(stdout_tmp, stderr_tmp, stdlog_tmp;group_seperator = group_seperator)
    catch
        rethrow()
    finally
        close(stdout_tmp)
        close(stderr_tmp)
        close(stdlog_tmp_io)
    end
end

function queue_progress(stdout_tmp::IO, stderr_tmp::IO, stdlog_tmp::Logging.AbstractLogger;
    group_seperator = r": *")

    progress_loop = true
    old_stdout = Base.stdout
    old_stderr = Base.stderr
    old_stdlog = global_logger()

    try
        while progress_loop
            
            if Base.stdout isa Base.TTY
                old_stdout = Base.stdout
                redirect_stdout(stdout_tmp)
            end

            if Base.stderr isa Base.TTY
                old_stderr = Base.stderr
                redirect_stderr(stderr_tmp)
            end

            if Logging.current_logger isa ConsoleLogger
                old_stdlog = Logging.current_logger
                global_logger(stdlog_tmp)
            end

            cpu_running, mem_running = queue_summary(;group_seperator = group_seperator)

            progress_display(cpu_running, mem_running)
        end
    catch
        rethrow()
    finally
        old_stdout != Base.stdout && redirect_stdout(old_stdout)
        old_stderr != Base.stderr && redirect_stderr(old_stderr)
        old_stdlog != global_logger() && global_logger(old_stdlog)
        isopen(stdout_tmp.stream) && flush(stdout_tmp)
        isopen(stderr_tmp.stream) && flush(stderr_tmp)
        isopen(stdlog_tmp.stream) && flush(stdlog_tmp.stream)

        if !(stdlog_tmp.stream isa IOBuffer)
            println(Pipelines.stderr_origin, @cyan @bold "Logging saved to $(stdlog_tmp.stream)")
        end
        println(Pipelines.stdout_origin, @yellow @bold "Stdout saved to $stdout_tmp")
        println(Pipelines.stderr_origin, @red @bold "Stderr saved to $stderr_tmp")
    end
end


function gen_views()
    h, w = T.displaysize()
    T.clear()
end


function view_update_resources(cpu_running::Int, mem_running::Int; row::Int = 2, max_cpu = JobSchedulers.SCHEDULER_MAX_CPU, max_mem = JobSchedulers.SCHEDULER_MAX_MEM)
    title = @bold("RESOURCES CLAIMED:")

    cpu_text = @bold("    CPU: ")
    cpu_val = "$cpu_running/$max_cpu"
    cpu_width = 9 + length(cpu_val)
    if cpu_running < max_cpu
        cpu_text *= @green(cpu_val)
    else
        cpu_text *= @yellow(cpu_val)
    end


    mem_text = @bold("    MEM: ")
    mem_percent = @sprintf("%3.2f%%", mem_running / max_mem * 100)
    mem_width = 9 + length(mem_percent)
    if mem_running < max_mem
        mem_text *= @green("$mem_percent")
    else
        mem_text *= @yellow("$mem_percent")
    end

    # render
    h,w = T.displaysize()
    T.cmove(row, 1)
    T.println(title)
    if cpu_width + mem_width <= w
        T.print(cpu_text)
        T.println(mem_text)
    else
        T.println(cpu_text)
        T.println(mem_text)
    end
end


function handle_quit()
    keep_running = false
    T.cmove_line_last()
    T.println("\nAll jobs are finished")
    return keep_running
end
function handle_event()
    is_running = true
    while is_running
        sequence = T.read_stream()
        if sequence == "\e" # ESC
            is_running = handle_quit()
        end
    end
end


function init_term()
    T.raw!(true)
    # T.alt_screen(true)
    cshow(false)
    T.clear()
end

function reset_term()
    T.raw!(false)
    # T.alt_screen(false)
    T.cshow(true)
end

function progress_display(cpu_running::Int, mem_running::Int)
    init_term()
    view_update_resources(cpu_running, mem_running)
    handle_event()
    reset_term()
    return
end