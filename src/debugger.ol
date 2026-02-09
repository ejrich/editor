struct DebuggerData {
    running: bool;
    failed_to_start: bool;
    process: ProcessData;
    buffer: Buffer = { read_only = true; title = get_debugger_buffer_title; }
    buffer_window: BufferWindow;
}

BufferWindow* get_debugger_window(Workspace* workspace) {
    if workspace.debugger_data.running {
        return &workspace.debugger_data.buffer_window;
    }

    return null;
}

start_or_continue_debugger() {
    workspace := get_workspace();
    if workspace.debugger_data.running {
        // TODO Continue
    }
    else if !string_is_empty(workspace.local_settings.debug_command) {
        // TODO Start
        force_command_to_stop();
        workspace.debugger_data.running = true;

        data: JobData;
        data.pointer = workspace;
        queue_work(&low_priority_queue, debugger_thread, data);
    }
}

bool stop_debugger() {
    workspace := get_workspace();
    if !workspace.debugger_data.running {
        return false;
    }

    // TODO Stop
    terminate_process(&workspace.debugger_data.process);
    workspace.debugger_data.running = false;
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

run_to() {
    workspace := get_workspace();
    if !workspace.debugger_data.running return;

    // TODO Implement
}

skip_to() {
    workspace := get_workspace();
    if !workspace.debugger_data.running return;

    // TODO Implement
}

#private

debugger_thread(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    clear_debugger_buffer_window(workspace);

    command := temp_string("lldb -- ", workspace.local_settings.debug_command);
    running := start_command(command, workspace.directory, &workspace.debugger_data.process, true, false);

    if !running {
        workspace.debugger_data.failed_to_start = true;
        return;
    }

    buf: CArray<u8>[1000];
    success, text := read_from_output_pipe(&workspace.debugger_data.process, &buf, buf.length);
    add_to_debugger_buffer(workspace, text);

    send_command_to_debugger(workspace, "r\n");

    while workspace.debugger_data.running {
        success, text = read_from_output_pipe(&workspace.debugger_data.process, &buf, buf.length);

        if !success break;

        add_to_debugger_buffer(workspace, text);
    }

    exit_code: s32;
    close_process_and_get_exit_code(&workspace.debugger_data.process, &exit_code);
}

send_command_to_debugger(Workspace* workspace, string command) {
    #if os == OS.Windows {
        WriteFile(workspace.debugger_data.process.input_pipe, command.data, command.length, null, null);
    }
    #if os == OS.Linux {
        write(workspace.debugger_data.process.input_pipe, command.data, command.length);
    }

    add_to_debugger_buffer(workspace, command);
}

add_to_debugger_buffer(Workspace* workspace, string text) {
    // TODO Filter when necessary
    line := add_text_to_end_of_buffer(&workspace.debugger_data.buffer, text, true);
    workspace.debugger_data.buffer_window.line = workspace.debugger_data.buffer.line_count - 1;
    workspace.debugger_data.buffer_window.cursor = line.length;
    adjust_start_line(&workspace.debugger_data.buffer_window);
    trigger_window_update();
}

clear_debugger_buffer_window(Workspace* workspace) {
    clear_buffer_and_window(&workspace.debugger_data.buffer, &workspace.debugger_data.buffer_window);
}

string get_debugger_buffer_title() {
    workspace := get_workspace();

    if workspace.debugger_data.failed_to_start {
        return format_string("Failed to start gdb with command '%'", temp_allocate, workspace.local_settings.debug_command);
    }

    return format_string("Running debugger with command '%'", temp_allocate, workspace.local_settings.debug_command);
}
