struct TerminalData {
    displaying: bool;
    running: bool;
    writing: bool;
    exit_code: int;
    directory: string;
    command_line: BufferLine*;
    command_line_index: int;
    command_start_index: int;
    command_write_cursor: int;
    buffer: Buffer = { read_only = true; title = get_terminal_title; }
    buffer_window: BufferWindow;
    process: ProcessData;
    command_history: Array<string>;
    selected_history_index: int;
}

start_or_close_terminal() {
    workspace := get_workspace();
    stop_running_terminal_command(workspace);

    if workspace.terminal_data.displaying {
        workspace.bottom_window_selected = false;
        workspace.terminal_data = {
            displaying = false;
            writing = false;
        }
    }
    else if !workspace.debugger_data.running {
        close_run_buffer_and_stop_command();
        set_command_line(workspace);

        workspace.bottom_window_selected = true;
        workspace.terminal_data = {
            displaying = true;
            writing = true;
            buffer_window = {
                line = workspace.terminal_data.command_line_index;
                cursor = workspace.terminal_data.command_write_cursor;
            }
        }
        adjust_start_line(&workspace.terminal_data.buffer_window);
    }
}

bool handle_terminal_press(PressState state, KeyCode code, ModCode mod, string char) {
    workspace := get_workspace();
    if !workspace.terminal_data.writing || unable_to_input_to_terminal(workspace) return false;

    // Pipe input to running commands or the command buffer
    if workspace.terminal_data.running {
        if code == KeyCode.Escape {
            workspace.terminal_data.writing = false;
        }
        else if code == KeyCode.C && mod == ModCode.Control {
            stop_running_terminal_command(workspace);
        }
        else {
            #if os == OS.Windows {
                WriteFile(workspace.terminal_data.process.input_pipe, char.data, char.length, null, null);
            }
            #if os == OS.Linux {
                write(workspace.terminal_data.process.input_pipe, char.data, char.length);
            }
        }
    }
    else {
        switch code {
            case KeyCode.Escape;
                workspace.terminal_data.writing = false;
            case KeyCode.Backspace; {
                if workspace.terminal_data.command_write_cursor > workspace.terminal_data.command_start_index {
                    workspace.terminal_data.command_write_cursor = delete_from_line(workspace.terminal_data.command_line, workspace.terminal_data.command_write_cursor - 1, workspace.terminal_data.command_write_cursor, false);
                }
            }
            case KeyCode.Tab; {
                // @Future Tab autocomplete
            }
            case KeyCode.Enter; {
                handle_command(workspace);
            }
            case KeyCode.Delete; {
                if workspace.terminal_data.command_write_cursor < workspace.terminal_data.command_line.length {
                    delete_from_line(workspace.terminal_data.command_line, workspace.terminal_data.command_write_cursor, workspace.terminal_data.command_write_cursor + 1, false);
                }
            }
            case KeyCode.Up; {
                if workspace.terminal_data.selected_history_index > 0 {
                    workspace.terminal_data.selected_history_index--;
                    set_command_from_history(workspace);
                }
            }
            case KeyCode.Down; {
                if workspace.terminal_data.selected_history_index < workspace.terminal_data.command_history.length {
                    workspace.terminal_data.selected_history_index++;
                    set_command_from_history(workspace);
                }
            }
            case KeyCode.Left; {
                workspace.terminal_data.command_write_cursor = clamp(workspace.terminal_data.command_write_cursor - 1, workspace.terminal_data.command_start_index, workspace.terminal_data.command_line.length);
                workspace.terminal_data.buffer_window.cursor = workspace.terminal_data.command_write_cursor;
            }
            case KeyCode.Right; {
                workspace.terminal_data.command_write_cursor = clamp(workspace.terminal_data.command_write_cursor + 1, workspace.terminal_data.command_start_index, workspace.terminal_data.command_line.length);
                workspace.terminal_data.buffer_window.cursor = workspace.terminal_data.command_write_cursor;
            }
            default; {
                if code == KeyCode.C && mod == ModCode.Control {
                    set_command_line(workspace);
                }
                else {
                    add_text_to_line(workspace.terminal_data.command_line, char, workspace.terminal_data.command_write_cursor);
                    workspace.terminal_data.command_write_cursor += char.length;
                    workspace.terminal_data.buffer_window.cursor += char.length;
                }
            }
        }
    }

    return true;
}

bool change_terminal_cursor(bool append, bool boundary) {
    workspace := get_workspace();
    if unable_to_input_to_terminal(workspace) return false;

    if workspace.terminal_data.running {
        workspace.terminal_data.writing = true;
        return true;
    }

    if boundary || workspace.terminal_data.command_line_index != workspace.terminal_data.buffer_window.line {
        if append {
            workspace.terminal_data.command_write_cursor = workspace.terminal_data.command_line.length;
        }
        else {
            workspace.terminal_data.command_write_cursor = workspace.terminal_data.command_start_index;
        }
    }
    else {
        workspace.terminal_data.command_write_cursor = workspace.terminal_data.buffer_window.cursor;
        if append {
            workspace.terminal_data.command_write_cursor++;
        }

        workspace.terminal_data.command_write_cursor = clamp(workspace.terminal_data.command_write_cursor, workspace.terminal_data.command_start_index, workspace.terminal_data.command_line.length);
    }

    workspace.terminal_data = {
        writing = true;
        buffer_window = {
            line = workspace.terminal_data.command_line_index;
            cursor = workspace.terminal_data.command_write_cursor;
        }
    }
    adjust_start_line(&workspace.terminal_data.buffer_window);

    return true;
}

BufferWindow* get_terminal_window(Workspace* workspace) {
    if workspace.terminal_data.displaying {
        return &workspace.terminal_data.buffer_window;
    }

    return null;
}

clear_terminal_buffer_window(Workspace* workspace) {
    clear_buffer_and_window(&workspace.terminal_data.buffer, &workspace.terminal_data.buffer_window);
}

#private

bool unable_to_input_to_terminal(Workspace* workspace) {
    if !workspace.terminal_data.displaying ||
        !workspace.bottom_window_selected ||
        get_debugger_window(workspace) != null ||
        get_run_window(workspace) != null
        return true;

    return false;
}

stop_running_terminal_command(Workspace* workspace) {
    if workspace.terminal_data.running {
        #if os == OS.Windows {
            TerminateJobObject(workspace.terminal_data.process.job_object, 0);
        }
        else {
            kill(workspace.terminal_data.process.pid, KillSignal.SIGKILL);
        }
    }
}

set_command_from_history(Workspace* workspace) {
    delete_from_line(workspace.terminal_data.command_line, workspace.terminal_data.command_start_index, workspace.terminal_data.command_line.length, false);

    if workspace.terminal_data.selected_history_index < workspace.terminal_data.command_history.length {
        command := workspace.terminal_data.command_history[workspace.terminal_data.selected_history_index];
        add_text_to_line(workspace.terminal_data.command_line, command, workspace.terminal_data.command_start_index);
    }

    workspace.terminal_data = {
        command_write_cursor = workspace.terminal_data.command_line.length;
        buffer_window = {
            cursor = workspace.terminal_data.command_line.length;
        }
    }
}

set_command_line(Workspace* workspace) {
    last_line := get_buffer_line(&workspace.terminal_data.buffer, workspace.terminal_data.buffer.line_count - 1);
    if last_line.length > 0 {
        new_line := allocate_line();
        last_line.next = new_line;
        new_line.previous = last_line;
        last_line = new_line;

        workspace.terminal_data.buffer.line_count++;
        calculate_line_digits(&workspace.terminal_data.buffer);
    }

    line_start := temp_string(workspace.terminal_data.directory, "> ");
    add_text_to_line(last_line, line_start);
    workspace.terminal_data = {
        command_line = last_line;
        command_line_index = workspace.terminal_data.buffer.line_count - 1;
        command_start_index = line_start.length;
        command_write_cursor = line_start.length;
        buffer_window = {
            line = workspace.terminal_data.buffer.line_count - 1;
            cursor = line_start.length;
        }
        selected_history_index = workspace.terminal_data.command_history.length;
    }
    adjust_start_line(&workspace.terminal_data.buffer_window);
}

handle_command(Workspace* workspace) {
    command := get_command(workspace);

    arg_string_buffer: Array<u8>[command.length];
    args: Array<string>[command.length];
    args.length = 0;

    arg_count := 0;
    whitespace := true;
    in_quote := false;
    escaping := false;
    escape_enabled := os != OS.Windows; #const
    arg: string = { data = arg_string_buffer.data; }
    each i in command.length {
        char := command[i];
        if whitespace {
            if char != ' ' {
                arg_count++;

                whitespace = false;
                if char == '"' {
                    in_quote = true;
                }

                arg[arg.length++] = char;
            }
        }
        else if escape_enabled && escaping {
            switch char {
                case 'n';  char = '\n';
                case 't';  char = '\t';
                case '\\'; char = '\\';
            }
            arg[arg.length++] = char;
            escaping = false;
        }
        else if escape_enabled && char == '\\' {
            escaping = true;
        }
        else if in_quote {
            if char == '"' {
                in_quote = false;
            }
        }
        else if char == ' ' {
            whitespace = true;
            args[args.length++] = arg;
            arg.data = arg_string_buffer.data + arg.length;
            arg.length = 0;
        }
        else {
            arg[arg.length++] = char;
        }
    }

    if !whitespace {
        args[args.length++] = arg;
    }

    add_new_line(null, &workspace.terminal_data.buffer, workspace.terminal_data.command_line, false, false);
    calculate_line_digits(&workspace.terminal_data.buffer);
    workspace.terminal_data.buffer_window = {
        line = workspace.terminal_data.buffer_window.line + 1;
        cursor = 0;
    }
    adjust_start_line(&workspace.terminal_data.buffer_window);

    if args.length == 0 {
        set_command_line(workspace);
        return;
    }

    allocate_strings(&command);
    array_insert(&workspace.terminal_data.command_history, command, allocate, reallocate);

    arg0 := args[0];
    if arg0 == "cd" {
        if args.length == 1 {
            home_directory := get_environment_variable(home_environment_variable, allocate);
            change_terminal_directory(workspace, home_directory);
        }
        else if args.length == 2 {
            arg1 := args[1];
            if arg1 == "~" {
                home_directory := get_environment_variable(home_environment_variable, allocate);
                change_terminal_directory(workspace, home_directory);
            }
            else {
                set_directory(workspace.terminal_data.directory);
                valid := is_directory(arg1);
                if valid {
                    set_directory(arg1);
                    new_directory := get_working_directory();
                    change_terminal_directory(workspace, new_directory);
                }
                else {
                    add_to_terminal_buffer(workspace, "'");
                    add_to_terminal_buffer(workspace, arg1);
                    add_to_terminal_buffer(workspace, "' is not a valid directory");
                }
                set_directory(workspace.directory);
            }
        }
        set_command_line(workspace);
    }
    else if arg0 == "clear" || arg0 == "cls" {
        clear_terminal_buffer_window(workspace);
        set_command_line(workspace);
    }
    else {
        data: JobData;
        data.pointer = workspace;
        queue_work(&low_priority_queue, execute_terminal_command, data);
    }
}

change_terminal_directory(Workspace* workspace, string new_directory) {
    if workspace.terminal_data.directory.data != workspace.directory.data {
        free_allocation(workspace.terminal_data.directory.data);
    }
    workspace.terminal_data.directory = new_directory;
}

execute_terminal_command(int index, JobData data) {
    log("Starting terminal\n");
    workspace: Workspace* = data.pointer;

    defer {
        workspace.terminal_data.running = false;
        set_command_line(workspace);
        trigger_window_update();
    }

    command := get_command(workspace);
    workspace.terminal_data.running = start_command(command, workspace.terminal_data.directory, &workspace.terminal_data.process, true, true);

    if !workspace.terminal_data.running return;

    buf: CArray<u8>[1000];
    while workspace.terminal_data.running {
        success, text := read_from_output_pipe(&workspace.terminal_data.process, &buf, buf.length);

        if !success break;

        add_to_terminal_buffer(workspace, text);
    }

    close_process_and_get_exit_code(&workspace.terminal_data.process, &workspace.terminal_data.exit_code);

    log("Terminal command exited with code %\n", workspace.terminal_data.exit_code);
}

string get_command(Workspace* workspace) #inline {
    if workspace.terminal_data.command_line == null return empty_string;

    length := workspace.terminal_data.command_line.length - workspace.terminal_data.command_start_index;
    command_buffer: Array<u8>[length + 1];
    command: string = { length = length; data = command_buffer.data; }

    if workspace.terminal_data.command_line.length < line_buffer_length {
        memory_copy(command_buffer.data, workspace.terminal_data.command_line.data.data + workspace.terminal_data.command_start_index, command_buffer.length);
    }
    else {
        i := 0;
        if workspace.terminal_data.command_start_index < line_buffer_length {
            copy_length := line_buffer_length - workspace.terminal_data.command_start_index;
            memory_copy(command_buffer.data, workspace.terminal_data.command_line.data.data + workspace.terminal_data.command_start_index, copy_length);
            i += copy_length;
        }

        line_start_index := workspace.terminal_data.command_start_index;
        child := workspace.terminal_data.command_line.child;
        while child {
            if line_start_index >= line_buffer_length {
                line_start_index -= line_buffer_length;
            }
            else {
                copy_length := child.length - line_start_index;
                memory_copy(command_buffer.data + i, child.data.data + line_start_index, copy_length);
                line_start_index = 0;
                i += copy_length;
            }
            child = child.next;
        }
    }

    command_buffer[length] = 0;

    return command;
}

add_to_terminal_buffer(Workspace* workspace, string text) {
    line := add_text_to_end_of_buffer(&workspace.terminal_data.buffer, text, true);
    workspace.terminal_data.buffer_window.line = workspace.terminal_data.buffer.line_count - 1;
    workspace.terminal_data.buffer_window.cursor = line.length;
    adjust_start_line(&workspace.terminal_data.buffer_window);
    trigger_window_update();
}

string get_terminal_title() {
    return "Terminal";
}
