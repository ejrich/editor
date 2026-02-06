struct DebuggerData {
    running: bool;
    process: ProcessData;
}

start_or_continue_debugger() {
    workspace := get_workspace();
    if workspace.debugger_data.running {
        // TODO Continue
    }
    else {
        // TODO Start
    }
}

bool stop_debugger() {
    workspace := get_workspace();
    if !workspace.debugger_data.running {
        return false;
    }

    // TODO Stop
    return true;
}

toggle_breakpoint() {
    workspace := get_workspace();
    if !workspace.debugger_data.running return;

    // TODO Implement
}

step_over() {
    workspace := get_workspace();
    if !workspace.debugger_data.running return;

    // TODO Implement
}

step_in() {
    workspace := get_workspace();
    if !workspace.debugger_data.running return;

    // TODO Implement
}

step_out() {
    workspace := get_workspace();
    if !workspace.debugger_data.running return;

    // TODO Implement
}
