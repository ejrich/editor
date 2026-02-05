init_shell() {
    #if os == OS.Linux {
        shell = get_environment_variable("SHELL", allocate);
        if string_is_empty(shell) {
            shell = "/bin/sh";
        }
    }
}

queue_command_to_run(string command) {
    params := new<RunCommandParams>();
    params.command = command;
    params.workspace = get_workspace();

    data: JobData;
    data.pointer = params;
    queue_work(&low_priority_queue, run_command, data);
}

force_command_to_stop() {
    workspace := get_workspace();

    if workspace.run_data.current_command.running {
        #if os == OS.Windows {
            TerminateThread(workspace.run_data.current_process.thread, command_exited_code);
            TerminateProcess(workspace.run_data.current_process.process, command_exited_code);
        }
        else {
            kill(workspace.run_data.current_process.pid, KillSignal.SIGKILL);
        }

        workspace.run_data.current_command.exited = true;
    }
}

close_run_buffer_and_stop_command() {
    workspace := get_workspace();
    workspace.bottom_window_selected = false;
    workspace.run_data.current_command.displayed = false;
    force_command_to_stop();
}

BufferWindow* get_run_window(Workspace* workspace) {
    if workspace.run_data.current_command.displayed {
        return &workspace.run_data.buffer_window;
    }

    return null;
}

Buffer* run_command_and_save_to_buffer(string command) {
    buffer := new<Buffer>();
    buffer.read_only = true;
    buffer.line_count = 1;
    buffer.line_count_digits = 1;
    buffer.lines = allocate_line();

    process: ProcessData;
    success, exit_code := execute_command(command, &process, buffer);

    return buffer;
}

run_command_silent(string command) {
    process: ProcessData;
    execute_command(command, &process, null);
}

struct RunData {
    buffer: Buffer = { read_only = true; title = get_run_buffer_title; }
    buffer_window: BufferWindow;
    current_command: CommandRunData;
    current_process: ProcessData;
    run_mutex: Semaphore;
}

bool start_command(string command, string directory, ProcessData* process_data, bool handle_stdin, bool is_terminal) {
    #if os == OS.Windows {
        sa: SECURITY_ATTRIBUTES = { nLength = size_of(SECURITY_ATTRIBUTES); bInheritHandle = true; }
        stdout_read_handle, stdout_write_handle, stdin_read_handle, stdin_write_handle: Handle*;
        if !CreatePipe(&stdout_read_handle, &stdout_write_handle, &sa, 0) {
            return false;
        }
        SetHandleInformation(stdout_read_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        si: STARTUPINFOA = {
            cb = size_of(STARTUPINFOA); dwFlags = 0x100;
            hStdInput = GetStdHandle(STD_INPUT_HANDLE);
            hStdError = stdout_write_handle; hStdOutput = stdout_write_handle;
        }

        if handle_stdin {
            if !CreatePipe(&stdin_read_handle, &stdin_write_handle, &sa, 0) {
                return false;
            }
            SetHandleInformation(stdin_write_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

            si.hStdInput = stdin_read_handle;
        }

        pi: PROCESS_INFORMATION;

        flags := ProcessCreationFlags.DETACHED_PROCESS;
        if is_terminal {
            flags = ProcessCreationFlags.CREATE_SUSPENDED | ProcessCreationFlags.CREATE_NO_WINDOW;
            command = temp_string("powershell -NoLogo ", command);
        }

        current_directory: u8*;
        if !string_is_empty(directory) {
            current_directory = directory.data;
        }

        if !CreateProcessA(null, command, null, null, true, flags, null, current_directory, &si, &pi) {
            CloseHandle(stdout_read_handle);
            CloseHandle(stdout_write_handle);

            if handle_stdin {
                CloseHandle(stdin_read_handle);
                CloseHandle(stdin_write_handle);
            }
            return false;
        }

        if is_terminal {
            job_object := CreateJobObjectA(null, null);
            AssignProcessToJobObject(job_object, pi.hProcess);
            ResumeThread(pi.hThread);

            if process_data {
                process_data.job_object = job_object;
            }
        }

        if process_data {
            process_data.thread = pi.hThread;
            process_data.process = pi.hProcess;

            if handle_stdin {
                process_data.input_pipe = stdin_write_handle;
            }
            process_data.output_pipe = stdout_read_handle;
        }

        if handle_stdin {
            CloseHandle(stdin_read_handle);
        }
        CloseHandle(stdout_write_handle);
    }
    else {
        stdout_pipe_files, stdin_pipe_files: Array<int>[2];
        if pipe2(stdout_pipe_files.data, 0x80000) < 0 {
            return false;
        }

        if handle_stdin {
            if pipe2(stdin_pipe_files.data, 0x80000) < 0 {
                return false;
            }
        }

        pid := fork();

        if pid < 0 {
            return false;
        }

        read_pipe := 0; #const
        write_pipe := 1; #const

        if pid == 0 {
            close(stdout_pipe_files[read_pipe]);
            dup2(stdout_pipe_files[write_pipe], stdout);

            if handle_stdin {
                close(stdin_pipe_files[write_pipe]);
                dup2(stdin_pipe_files[read_pipe], stdin);
            }

            if !string_is_empty(directory) {
                chdir(directory.data);
            }

            exec_args: Array<u8*>[5];
            exec_args[0] = shell.data;
            exec_args[1] = "-c".data;
            exec_args[2] = "--".data;
            exec_args[3] = command.data;
            exec_args[4] = null;
            execve(shell.data, exec_args.data, __environment_variables_pointer);
            exit(-1);
        }

        close(stdout_pipe_files[write_pipe]);
        if handle_stdin {
            close(stdin_pipe_files[read_pipe]);
        }

        if process_data {
            process_data.pid = pid;
            if handle_stdin {
                process_data.input_pipe = stdin_pipe_files[write_pipe];
            }
            process_data.output_pipe = stdout_pipe_files[read_pipe];
        }
    }

    return true;
}

close_process_and_get_exit_code(ProcessData* process_data, int* exit_code) {
    #if os == OS.Windows {
        GetExitCodeProcess(process_data.process, exit_code);

        CloseHandle(process_data.job_object);
        CloseHandle(process_data.thread);
        CloseHandle(process_data.process);
        CloseHandle(process_data.input_pipe);
        CloseHandle(process_data.output_pipe);
    }
    else {
        close(process_data.input_pipe);
        close(process_data.output_pipe);

        wait4(process_data.pid, exit_code, 0, null);
    }
}

#if os == OS.Windows {
    struct ProcessData {
        thread: Handle*;
        process: Handle*;
        job_object: Handle*;
        input_pipe: Handle*;
        output_pipe: Handle*;
    }
}
else {
    struct ProcessData {
        pid: int;
        input_pipe: int;
        output_pipe: int;
    }

    shell: string;
}

struct RunCommandParams {
    command: string;
    workspace: Workspace*;
}

command_exited_code := -100; #const

#private

run_command(int index, JobData data) {
    params: RunCommandParams* = data.pointer;
    defer free_allocation(params);

    semaphore_wait(&params.workspace.run_data.run_mutex);
    defer semaphore_release(&params.workspace.run_data.run_mutex);

    clear_run_buffer_window(params.command, params.workspace);

    log("Executing command: '%'\n", params.command);

    params.workspace.run_data.current_command = {
        command = params.command;
        running = true;
        exit_code = 0;
        failed = false;
        exited = false;
        displayed = true;
    }

    success, exit_code := execute_command(params.command, &params.workspace.run_data.current_process, &params.workspace.run_data.buffer, &params.workspace.run_data.buffer_window, &params.workspace.run_data.current_command.exited);

    if success {
        params.workspace.run_data.current_command.exit_code = exit_code;
    }
    else {
        params.workspace.run_data.current_command.failed = true;
    }

    params.workspace.run_data.current_command.running = false;
    log("Exit code: %\n", params.workspace.run_data.current_command.exit_code);
    trigger_window_update();
}

bool, int execute_command(string command, ProcessData* process_data, Buffer* buffer, BufferWindow* buffer_window = null, bool* exited = null) {
    exit_code: int;

    started := start_command(command, empty_string, process_data, false, false);

    if started {
        #if os == OS.Windows {
            buf: CArray<u8>[1000];
            while exited == null || !(*exited) {
                read: int;
                success := ReadFile(process_data.output_pipe, &buf, buf.length, &read, null);

                if !success || read == 0 break;

                text: string = { length = read; data = &buf; }
                add_to_buffer(buffer_window, buffer, text);
            }
        }
        else {
            buf: CArray<u8>[1000];
            while exited == null || !(*exited) {
                length := read(process_data.output_pipe, &buf, buf.length);

                if length <= 0 break;

                text: string = { length = length; data = &buf; }
                add_to_buffer(buffer_window, buffer, text);
            }
        }

        close_process_and_get_exit_code(process_data, &exit_code);
    }

    return started, exit_code;
}


clear_run_buffer_window(string command, Workspace* workspace) {
    workspace.run_data.buffer_window = {
        cursor = 0;
        line = 0;
        start_line = 0;
    }

    line := workspace.run_data.buffer.lines;
    escape_code := workspace.terminal_data.buffer.escape_codes;

    workspace.run_data.buffer = {
        line_count = 1;
        line_count_digits = 1;
        lines = allocate_line();
        escape_codes = null;
    }

    while line {
        next := line.next;
        free_line_and_children(line);
        line = next;
    }

    while escape_code {
        next := escape_code.next;
        free_allocation(escape_code);
        escape_code = next;
    }
}

add_to_buffer(BufferWindow* buffer_window, Buffer* buffer, string text) {
    change_line := false;
    if buffer_window {
        change_line = buffer_window.line == buffer.line_count - 1;
    }

    add_text_to_end_of_buffer(buffer, text, true);

    if change_line {
        buffer_window.line = buffer.line_count - 1;
        adjust_start_line(buffer_window);
    }

    trigger_window_update();
}

struct CommandRunData {
    command: string;
    running: bool;
    exit_code: int;
    failed: bool;
    exited: bool;
    displayed: bool;
}

string get_run_buffer_title() {
    workspace := get_workspace();

    if workspace.run_data.current_command.running {
        return format_string("Running: %", temp_allocate, workspace.run_data.current_command.command);
    }

    if workspace.run_data.current_command.failed {
        return format_string("Failed to execute: %", temp_allocate, workspace.run_data.current_command.command);
    }

    if workspace.run_data.current_command.exit_code == 0 {
        return format_string("Success: %", temp_allocate, workspace.run_data.current_command.command);
    }

    return format_string("Failed with code %: %", temp_allocate, workspace.run_data.current_command.exit_code, workspace.run_data.current_command.command);
}
