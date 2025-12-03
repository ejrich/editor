init_run() {
    create_semaphore(&run_mutex, initial_value = 1);
}

queue_command_to_run(string command) {
    data: JobData;
    data.string = command;
    queue_work(&low_priority_queue, run_command, data);
}

force_command_to_stop() {
    if current_command.running {
        current_command.exited = true;
    }
}

#private

run_command(int index, JobData data) {
    semaphore_wait(&run_mutex);
    defer semaphore_release(&run_mutex);

    log("Executing command: '%'\n", data.string);

    current_command = {
        command = data.string;
        running = true;
        exit_code = 0;
        failed = false;
        exited = false;
    }

    #if os == OS.Windows {
        sa: SECURITY_ATTRIBUTES = { nLength = size_of(SECURITY_ATTRIBUTES); bInheritHandle = true; }
        read_handle, write_handle: Handle*;

        if !CreatePipe(&read_handle, &write_handle, &sa, 0) {
            current_command.failed = true;
            return;
        }
        SetHandleInformation(read_handle, HandleFlags.HANDLE_FLAG_INHERIT, HandleFlags.None);

        si: STARTUPINFOA = { cb = size_of(STARTUPINFOA); dwFlags = 0x100; hStdInput = GetStdHandle(STD_INPUT_HANDLE); hStdOutput = write_handle; }
        pi: PROCESS_INFORMATION;

        if !CreateProcessA(null, current_command.command, null, null, true, 0, null, null, &si, &pi) {
            CloseHandle(read_handle);
            CloseHandle(write_handle);
            current_command.failed = true;
            return;
        }

        CloseHandle(si.hStdInput);
        CloseHandle(write_handle);

        buf: CArray<u8>[1000];
        while !current_command.exited {
            /*
            read: int;
            success := ReadFile(read_handle, &buf, 1000, &read, null);

            if !success || read == 0 break;
            */
        }

        if current_command.exited {
            TerminateThread(pi.hThread, command_exited_code);
            TerminateProcess(pi.hProcess, command_exited_code);
        }

        GetExitCodeProcess(pi.hProcess, &current_command.exit_code);

        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        CloseHandle(read_handle);
    }
    else {
        current_command.exit_code = system(command);
    }

    log("Exit code: %\n", current_command.exit_code);
}

run_mutex: Semaphore;

command_exited_code := -100; #const

struct CommandRunData {
    command: string;
    running: bool;
    exit_code: int;
    failed: bool;
    exited: bool;
}

current_command: CommandRunData;
