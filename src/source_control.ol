enum SourceControl {
    None;
    Git;
    Perforce;
    Svn;
}

source_control_status() {
    list_title: string;

    switch local_settings.source_control {
        case SourceControl.Git; {
            list_title = "Git Status";
        }
        case SourceControl.Perforce; {
            list_title = "P4 Status";
        }
        case SourceControl.Svn; {
            list_title = "SVN Status";
        }
    }

    if !string_is_empty(list_title) {
        queue_work(&low_priority_queue, load_status);
        start_list_mode(list_title, get_status_entries, load_diff);
    }
}

source_control_pull() {
    switch local_settings.source_control {
        case SourceControl.Git; {
            queue_command_to_run("git pull");
        }
        case SourceControl.Perforce; {
            queue_command_to_run("p4 sync");
        }
        case SourceControl.Svn; {
            queue_command_to_run("svn update");
        }
    }
}

source_control_checkout() {
    switch local_settings.source_control {
        case SourceControl.Perforce; {
            queue_command_to_run("p4 edit ...");
        }
    }
}

source_control_revert() {
    switch local_settings.source_control {
        case SourceControl.Git; {
            queue_command_to_run("git reset --hard");
        }
        case SourceControl.Perforce; {
            queue_command_to_run("p4 revert -a");
        }
        case SourceControl.Svn; {
            queue_command_to_run("svn revert");
        }
    }
}

source_control_commit(string message) {
    if !string_is_empty(commit_command) {
        free_allocation(commit_command.data);
    }

    switch local_settings.source_control {
        case SourceControl.Git; {
            commit_command = format_string("git commit -m \"%\"", allocate, message);
        }
        case SourceControl.Perforce; {
            commit_command = format_string("p4 submit -d \"%\"", allocate, message);
        }
        case SourceControl.Svn; {
            commit_command = format_string("svn commit -m \"%\"", allocate, message);
        }
    }

    if !string_is_empty(commit_command) {
        queue_command_to_run(commit_command);
    }
}

#private

commit_command: string;

load_status(int index, JobData data) {
    status_buffer: Buffer*;
    switch local_settings.source_control {
        case SourceControl.Git; {
            status_buffer = run_command_and_save_to_buffer("git status -s");
        }
        case SourceControl.Perforce; {
            status_buffer = run_command_and_save_to_buffer("p4 diff -f -sa");
        }
        case SourceControl.Svn; {
            status_buffer = run_command_and_save_to_buffer("svn status --quiet");
        }
        default; return;
    }

    defer free_buffer(status_buffer);
    get_status_result_count(status_buffer);

    // TODO Change this for git staging
    i := 0;
    line := status_buffer.lines;
    while line {
        if line.length {
            status_entries[i++] = line_to_string(line);
        }
        line = line.next;
    }
}

status_entries: Array<string>;
entries_reserved := 0;
entries_block_size := 50; #const

get_status_result_count(Buffer* buffer) {
    result_count := 0;
    line := buffer.lines;
    while line {
        if line.length {
            result_count++;
        }
        line = line.next;
    }

    prepare_status_entries(result_count);
}

prepare_status_entries(int count) {
    each entry in status_entries {
        free_allocation(entry.data);
    }
    status_entries.length = 0;

    if count > entries_reserved {
        free_allocation(status_entries.data);

        while entries_reserved < count {
            entries_reserved += entries_block_size;
        }

        array_resize(&status_entries, entries_reserved, allocate);
    }

    status_entries.length = count;
}

string line_to_string(BufferLine* line) {
    value: string = { length = line.length; }
    if line.length <= line_buffer_length {
        value.data = line.data.data;
        allocate_strings(&value);
    }
    else {
        value.data = allocate(line.length);
        memory_copy(value.data, line.data.data, line_buffer_length);
        i := line_buffer_length;

        line = line.child;
        while line {
            memory_copy(value.data + i, line.data.data, line.length);
            i += line.length;
            line = line.next;
        }
    }

    return value;
}

Array<string> get_status_entries() {
    return status_entries;
}

load_diff(int index, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    value := entry.value;

    command: string;
    switch local_settings.source_control {
        case SourceControl.Git; {
            command = temp_string(true, "git diff ", value);
        }
        case SourceControl.Perforce; {
            command = temp_string(true, "p4 diff ", value);
        }
        case SourceControl.Svn; {
            command = temp_string(true, "svn diff ", value);
        }
        default; return;
    }

    diff_buffer := run_command_and_save_to_buffer(command);

    if value == entry.value {
        entry.buffer = diff_buffer;
    }
    else {
        free_buffer(diff_buffer);
    }
}
