
function supervise(cmd::Cmd;retry=typemax(Int))
    cmdProgram = CmdProgram(;
        cmd=cmd
    )
    submit!(cmdProgram; retry=retry, touch_run_id_file=false, skip_when_done=false)
    wait_queue()
end

function supervise(cmdProg::CmdProgram;retry=typemax(Int))
    submit!(cmdProg; retry=retry, touch_run_id_file=false, skip_when_done=false)
    wait_queue()
end

function supervise(juliaProg::JuliaProgram;retry=typemax(Int))
    submit!(juliaProg; retry=retry, touch_run_id_file=false, skip_when_done=false)
    wait_queue()
end