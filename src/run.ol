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
            kill(workspace.run_data.current_process.pid, command_exited_code);
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

    success, exit_code := execute_command(command, buffer);

    return buffer;
}

run_command_silent(string command) {
    execute_command(command, null, null);
}

struct RunData {
    buffer: Buffer = { read_only = true; title = get_run_buffer_title; }
    buffer_window: BufferWindow;
    current_command: CommandRunData;
    current_process: ProcessData;
    run_mutex: Semaphore;
}

#if os == OS.Windows {
    struct ProcessData {
        thread: Handle*;
        process: Handle*;
        job_object: Handle*;
    }
}
else {
    struct ProcessData {
        pid: int;
    }
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

    success, exit_code := execute_command(params.command, &params.workspace.run_data.buffer, &params.workspace.run_data.buffer_window, &params.workspace.run_data.current_process, &params.workspace.run_data.current_command.exited);

    if success {
        params.workspace.run_data.current_command.exit_code = exit_code;
    }
    else {
        params.workspace.run_data.current_command.failed = true;
    }

    params.workspace.run_data.current_command.running = false;
    log("Exit code: %\n", params.workspace.run_data.current_command.exit_code);
}

bool, int execute_command(string command, Buffer* buffer, BufferWindow* buffer_window = null, ProcessData* process_data = null, bool* exited = null) {
    exit_code: int;

    #if os == OS.Windows {
        sa: SECURITY_ATTRIBUTES = { nLength = size_of(SECURITY_ATTRIBUTES); bInheritHandle = true; }
        read_handle, write_handle: Handle*;

        if !CreatePipe(&read_handle, &write_handle, &sa, 0) {
            return false, 0;
        }
        SetHandleInformation(read_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        si: STARTUPINFOA = {
            cb = size_of(STARTUPINFOA); dwFlags = 0x100;
            hStdInput = GetStdHandle(STD_INPUT_HANDLE);
            hStdError = write_handle; hStdOutput = write_handle;
        }
        pi: PROCESS_INFORMATION;

        if !CreateProcessA(null, command, null, null, true, ProcessCreationFlags.DETACHED_PROCESS, null, null, &si, &pi) {
            CloseHandle(read_handle);
            CloseHandle(write_handle);
            return false, 0;
        }

        if process_data {
            process_data.thread = pi.hThread;
            process_data.process = pi.hProcess;
        }

        CloseHandle(si.hStdInput);
        CloseHandle(write_handle);

        buf: CArray<u8>[1000];
        while exited == null || !(*exited) {
            read: int;
            success := ReadFile(read_handle, &buf, buf.length, &read, null);

            if !success || read == 0 break;

            text: string = { length = read; data = &buf; }
            add_to_buffer(buffer_window, buffer, text);
        }

        GetExitCodeProcess(pi.hProcess, &exit_code);

        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(read_handle);
    }
    else {
        pipe_files: Array<int>[2];
        if pipe2(pipe_files.data, 0x80000) < 0 {
            return false, 0;
        }

        pid := fork();

        if pid < 0 {
            return false, 0;
        }

        read_pipe := 0; #const
        write_pipe := 1; #const

        if pid == 0 {
            close(pipe_files[read_pipe]);
            dup2(pipe_files[write_pipe], stdout);

            exec_args: Array<u8*>[5];
            exec_args[0] = "sh".data;
            exec_args[1] = "-c".data;
            exec_args[2] = "--".data;
            exec_args[3] = command.data;
            exec_args[4] = null;
            execve("/bin/sh".data, exec_args.data, __environment_variables_pointer);
            exit(-1);
        }

        close(pipe_files[write_pipe]);

        if process_data {
            process_data.pid = pid;
        }

        buf: CArray<u8>[1000];
        while exited == null || !(*exited) {
            length := read(pipe_files[read_pipe], &buf, buf.length);

            if length <= 0 break;

            text: string = { length = length; data = &buf; }
            add_to_buffer(buffer_window, buffer, text);
        }

        close(pipe_files[read_pipe]);
        wait4(pid, &exit_code, 0, null);
    }

    return true, exit_code;
}

clear_run_buffer_window(string command, Workspace* workspace) {
    workspace.run_data.buffer_window = {
        cursor = 0;
        line = 0;
        start_line = 0;
    }

    line := workspace.run_data.buffer.lines;

    workspace.run_data.buffer = {
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

add_to_buffer(BufferWindow* buffer_window, Buffer* buffer, string text) {
    change_line := false;
    if buffer_window {
        change_line = buffer_window.line == buffer.line_count - 1;
    }

    add_text_to_end_of_buffer(buffer, text);

    if change_line {
        buffer_window.line = buffer.line_count - 1;
        adjust_start_line(buffer_window);
    }
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
