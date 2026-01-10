// TODO Reworking the terminal
// - Don't directly run the terminal process, I don't care about handling all of that
// - Show the directory, handle 'cd' and track the directory in TerminalData
// - Handle clear to reset the terminal buffer
// - Handle up/down to get to previous commands
// - Allow the use to type commands, then execute the commands using the appropriate shell
//   - Make sure to to handle things like escaped chars and paths with spaces
// - Allow for scrolling and refocus the bottom when typing a new command
// - Handle cancelling commands with Ctrl+C


init_terminal() {
    #if os == OS.Linux {
        shell = get_environment_variable("SHELL", allocate);
        if string_is_empty(shell) {
            shell = "/bin/sh";
        }
    }
}

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
    pipes: TerminalPipes;
}

start_or_close_terminal() {
    workspace := get_workspace();
    if workspace.terminal_data.running {
        #if os == OS.Windows {
            CloseHandle(workspace.terminal_data.pipes.input);
            CloseHandle(workspace.terminal_data.pipes.output);
            TerminateThread(workspace.terminal_data.process.thread, command_exited_code);
            TerminateProcess(workspace.terminal_data.process.process, command_exited_code);
        }
        else {
            close(workspace.terminal_data.pipes.input);
            close(workspace.terminal_data.pipes.output);
            kill(workspace.terminal_data.process.pid, command_exited_code);
        }

        workspace.bottom_window_selected = false;
        workspace.terminal_data = {
            running = false;
            writing = false;
        }
    }

    if workspace.terminal_data.displaying {
        workspace.bottom_window_selected = false;
        workspace.terminal_data = {
            displaying = false;
            writing = false;
        }
    }
    else {
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
    }
}

bool handle_terminal_press(PressState state, KeyCode code, ModCode mod, string char) {
    workspace := get_workspace();
    if !workspace.terminal_data.displaying || !workspace.terminal_data.writing || !workspace.bottom_window_selected || get_run_window(workspace) != null return false;

    // Pipe input to running commands or the command buffer
    if workspace.terminal_data.running {
        if code == KeyCode.Escape {
            workspace.terminal_data.writing = false;
        }
        else {
            #if os == OS.Windows {
                WriteFile(workspace.terminal_data.pipes.input, char.data, char.length, null, null);
            }
            #if os == OS.Linux {
                write(workspace.terminal_data.pipes.input, char.data, char.length);
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
                tab_array: Array<u8>[settings.tab_size];
                each space in tab_array {
                    space = ' ';
                }
                tab_string: string = { length = tab_array.length; data = tab_array.data; }
                // TODO Implement
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
                // TODO Implement
            }
            case KeyCode.Down; {
                // TODO Implement
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
                add_text_to_line(workspace.terminal_data.command_line, char, workspace.terminal_data.command_write_cursor);
                workspace.terminal_data.command_write_cursor += char.length;
                workspace.terminal_data.buffer_window.cursor += char.length;
            }
        }
    }

    return true;
}

bool change_terminal_cursor(bool append, bool boundary) {
    workspace := get_workspace();
    if !workspace.terminal_data.displaying || !workspace.bottom_window_selected || get_run_window(workspace) != null return false;

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
    workspace.terminal_data.buffer_window = {
        cursor = 0;
        line = 0;
        start_line = 0;
    }

    if workspace.terminal_data.buffer.line_count == 0 {
        workspace.terminal_data.buffer = {
            line_count = 1;
            line_count_digits = 1;
            lines = allocate_line();
        }
    }
    else if workspace.terminal_data.buffer.line_count == 1 {
        free_child_lines(workspace.terminal_data.buffer.lines.child);
        workspace.terminal_data.buffer.lines.length = 0;
    }
    else {
        line := workspace.terminal_data.buffer.lines;

        workspace.terminal_data.buffer = {
            line_count = 1;
            line_count_digits = 1;
            lines = allocate_line();
        }

        while line {
            next := line.next;
            free_line_and_children(line);
            line = next;
        }
    }
}

#private


#if os == OS.Windows {
    struct TerminalPipes {
        input: Handle*;
        output: Handle*;
    }
}
else {
    struct TerminalPipes {
        input: int;
        output: int;
    }

    shell: string;
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
    }
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
                valid := is_directory(arg1);
                if valid {
                    set_directory(arg1);
                    new_directory := get_working_directory();
                    set_directory(workspace.directory);
                    change_terminal_directory(workspace, new_directory);
                }
                else {
                    add_to_terminal_buffer(workspace, "'");
                    add_to_terminal_buffer(workspace, arg1);
                    add_to_terminal_buffer(workspace, "' is not a valid directory");
                }
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
    }

    #if os == OS.Windows {
        sa: SECURITY_ATTRIBUTES = { nLength = size_of(SECURITY_ATTRIBUTES); bInheritHandle = true; }
        stdout_read_handle, stdout_write_handle: Handle*;
        if !CreatePipe(&stdout_read_handle, &stdout_write_handle, &sa, 0) {
            return;
        }
        SetHandleInformation(stdout_read_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        stdin_read_handle, stdin_write_handle: Handle*;
        if !CreatePipe(&stdin_read_handle, &stdin_write_handle, &sa, 0) {
            return;
        }
        SetHandleInformation(stdin_write_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        si: STARTUPINFOA = {
            cb = size_of(STARTUPINFOA); dwFlags = 0x100;
            hStdInput = stdin_read_handle;
            hStdError = stdout_write_handle; hStdOutput = stdout_write_handle;
        }
        pi: PROCESS_INFORMATION;

        command := get_command(workspace);
        ps_command := temp_string("powershell -NoLogo ", command);
        if !CreateProcessA(null, ps_command, null, null, true, 0x8000000, null, workspace.terminal_data.directory, &si, &pi) {
            log("Failed to start terminal\n");
            CloseHandle(stdout_read_handle);
            CloseHandle(stdout_write_handle);
            CloseHandle(stdin_read_handle);
            CloseHandle(stdin_write_handle);
            return;
        }

        CloseHandle(stdin_read_handle);
        CloseHandle(stdout_write_handle);

        workspace.terminal_data = {
            running = true;
            process = {
                thread = pi.hThread;
                process = pi.hProcess;
            }
            pipes = {
                input = stdin_write_handle;
                output = stdout_read_handle;
            }
        }

        buf: CArray<u8>[1000];
        while workspace.terminal_data.running {
            read: int;
            success := ReadFile(stdout_read_handle, &buf, buf.length, &read, null);

            if !success || read == 0 break;

            text: string = { length = read; data = &buf; }
            add_to_terminal_buffer(workspace, text);
        }

        GetExitCodeProcess(pi.hProcess, &workspace.terminal_data.exit_code);

        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(stdout_read_handle);
        CloseHandle(stdin_write_handle);
    }
    else {
        stdout_pipe_files: Array<int>[2];
        if pipe2(stdout_pipe_files.data, 0x80000) < 0 {
            return;
        }

        stdin_pipe_files: Array<int>[2];
        if pipe2(stdin_pipe_files.data, 0x80000) < 0 {
            return;
        }

        pid := fork();

        if pid < 0 {
            return;
        }

        read_pipe := 0; #const
        write_pipe := 1; #const

        if pid == 0 {
            close(stdout_pipe_files[read_pipe]);
            dup2(stdout_pipe_files[write_pipe], stdout);

            close(stdin_pipe_files[write_pipe]);
            dup2(stdin_pipe_files[read_pipe], stdin);

            command := get_command(workspace);
            chdir(workspace.terminal_data.directory.data);

            exec_args: Array<u8*>[4];
            exec_args[0] = shell.data;
            exec_args[1] = "-c".data;
            exec_args[2] = "--".data;
            exec_args[3] = command.data;
            exec_args[4] = null;
            execve(shell.data, exec_args.data, __environment_variables_pointer);
            exit(-1);
        }

        close(stdout_pipe_files[write_pipe]);
        close(stdin_pipe_files[read_pipe]);

        workspace.terminal_data = {
            running = true;
            process = {
                pid = pid;
            }
            pipes = {
                input = stdin_pipe_files[write_pipe];
                output = stdout_pipe_files[read_pipe];
            }
        }

        buf: CArray<u8>[1000];
        while workspace.terminal_data.running {
            length := read(stdout_pipe_files[read_pipe], &buf, buf.length);

            if length <= 0 break;

            text: string = { length = length; data = &buf; }
            add_to_terminal_buffer(workspace, text);
        }

        if workspace.terminal_data.running {
            close(stdout_pipe_files[read_pipe]);
            close(stdin_pipe_files[write_pipe]);
        }

        wait4(pid, &workspace.terminal_data.exit_code, 0, null);
    }

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
    add_text_to_end_of_buffer(&workspace.terminal_data.buffer, text);
    workspace.terminal_data.buffer_window.line = workspace.terminal_data.buffer.line_count - 1;
    adjust_start_line(&workspace.terminal_data.buffer_window);
}

string get_terminal_title() {
    return "Terminal";
}
