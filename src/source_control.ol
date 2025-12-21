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
        start_list_mode(list_title, get_status_entries, load_diff, change_filter, open_status_file);
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
    if !string_is_empty(status_filter) {
        free_allocation(status_filter.data);
    }
    status_filter = empty_string;

    status_buffer: Buffer*;
    switch local_settings.source_control {
        case SourceControl.Git; {
            status_buffer = run_command_and_save_to_buffer("git status -s");
        }
        case SourceControl.Perforce; {
            status_buffer = run_command_and_save_to_buffer("p4 diff -sa");
        }
        case SourceControl.Svn; {
            status_buffer = run_command_and_save_to_buffer("svn status --quiet");
        }
        default; return;
    }

    defer free_buffer(status_buffer);
    get_status_result_count(status_buffer);

    i := 0;
    line := status_buffer.lines;
    while line {
        if line.length {
            file, display := line_to_entry(line);
            status_entries[i++] = {
                key = file;
                display = display;
            }
        }
        line = line.next;
    }

    apply_status_filter();
}

status_entries: Array<ListEntry>;

status_filter: string;
filtered_status_entries: Array<ListEntry>;

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
        if entry.key != entry.display {
            free_allocation(entry.display.data);
        }
        free_allocation(entry.key.data);
    }
    status_entries.length = 0;
    filtered_status_entries.length = 0;

    if count > entries_reserved {
        free_allocation(status_entries.data);
        free_allocation(filtered_status_entries.data);

        while entries_reserved < count {
            entries_reserved += entries_block_size;
        }

        array_resize(&status_entries, entries_reserved, allocate);
        array_resize(&filtered_status_entries, entries_reserved, allocate);
    }

    status_entries.length = count;
    filtered_status_entries.length = count;
}

string, string line_to_entry(BufferLine* line) {
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

    file, display: string;
    switch local_settings.source_control {
        case SourceControl.Git; {
            // TODO Implement
            file = value;
            display = value;
        }
        case SourceControl.Perforce; {
            if starts_with(value, current_directory) {
                relative_path: string = {
                    length = value.length - current_directory.length;
                    data = value.data + current_directory.length;
                }
                if relative_path[0] == '\\' || relative_path[0] == '/' {
                    relative_path.length--;
                    relative_path.data = relative_path.data + 1;
                }

                allocate_strings(&relative_path);
                each i in relative_path.length {
                    if relative_path[i] == '\\' {
                        relative_path[i] = '/';
                    }
                }

                free_allocation(value.data);
                value = relative_path;
            }
            file = value;
            display = value;
        }
        case SourceControl.Svn; {
            // TODO Implement
            file = value;
            display = value;
        }
    }

    return file, display;
}

Array<ListEntry> get_status_entries() {
    return filtered_status_entries;
}

load_diff(int thread, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    file := entry.key;

    command: string;
    switch local_settings.source_control {
        case SourceControl.Git; {
            command = temp_string(true, "git diff ", file);
        }
        case SourceControl.Perforce; {
            command = temp_string(true, "p4 diff ", file);
        }
        case SourceControl.Svn; {
            command = temp_string(true, "svn diff ", file);
        }
        default; return;
    }

    diff_buffer := run_command_and_save_to_buffer(command);

    if file == entry.key {
        entry.buffer = diff_buffer;
    }
    else {
        free_buffer(diff_buffer);
    }
}

change_filter(string filter) {
    if !string_is_empty(status_filter) {
        free_allocation(status_filter.data);
    }
    allocate_strings(&filter);
    status_filter = filter;

    apply_status_filter();
}

apply_status_filter() {
    if string_is_empty(status_filter) {
        filtered_status_entries.length = status_entries.length;
        each entry, i in status_entries {
            filtered_status_entries[i] = entry;
        }
    }
    else {
        filtered_status_entries.length = 0;
        each entry in status_entries {
            if string_contains(entry.key, status_filter) {
                filtered_status_entries[filtered_status_entries.length++] = entry;
            }
        }
    }
}

open_status_file(string file) {
    open_file_buffer(file, true);
}
