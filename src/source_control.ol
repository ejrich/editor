enum SourceControl {
    None;
    Git;
    Perforce;
    Svn;
}

source_control_status() {
    list_title: string;

    workspace := get_workspace();
    switch workspace.local_settings.source_control {
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
        // Free the existing entries before loading
        each entry in status_entries {
            switch workspace.local_settings.source_control {
                case SourceControl.Git; {
                    free_allocation(entry.key.data);
                    free_allocation(entry.display.data);
                }
                case SourceControl.Perforce;
                case SourceControl.Svn;
                    free_allocation(entry.display.data);
            }
        }
        status_entries.length = 0;
        git_status_entries.length = 0;
        filtered_status_entries.length = 0;

        queue_work(&low_priority_queue, load_status);
        start_list_mode(list_title, get_status_entries, get_total_status_entries, load_diff, change_filter, open_status_file, change_status);
    }
}

source_control_pull() {
    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Git; {
            queue_command_to_run("git pull");
        }
        case SourceControl.Perforce; {
            set_perforce_client();
            queue_command_to_run("p4 sync");
        }
        case SourceControl.Svn; {
            queue_command_to_run("svn update");
        }
    }
}

source_control_checkout() {
    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Perforce; {
            set_perforce_client();
            queue_command_to_run("p4 edit ...");
        }
    }
}

source_control_revert() {
    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Git; {
            queue_command_to_run("git reset --hard");
        }
        case SourceControl.Perforce; {
            set_perforce_client();
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

    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Git; {
            commit_command = format_string("git commit -m \"%\"", allocate, message);
        }
        case SourceControl.Perforce; {
            set_perforce_client();
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
    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Git; {
            status_buffer = run_command_and_save_to_buffer("git status -s");
        }
        case SourceControl.Perforce; {
            set_perforce_client();
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
            file, display := line_to_entry(line, i);
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
git_status_entries: Array<GitStatus>;

enum GitStatus {
    None          = 0x0;
    Untracked     = 0x1;
    Added         = 0x2;
    Changed       = 0x4;
    ChangedStaged = 0x8;
    Deleted       = 0x10;
    DeletedStaged = 0x20;
}

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
    if count > entries_reserved {
        while entries_reserved < count {
            entries_reserved += entries_block_size;
        }

        reallocate_array(&status_entries, entries_reserved);
        reallocate_array(&git_status_entries, entries_reserved);
        reallocate_array(&filtered_status_entries, entries_reserved);
    }

    status_entries.length = count;
    filtered_status_entries.length = count;
}

string, string line_to_entry(BufferLine* line, int status_index) {
    value: string = {
        length = clamp(line.length, 0, line_buffer_length);
        data = line.data.data;
    }

    file, display: string;
    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Git; {
            status := char_to_git_status(value[0], true) | char_to_git_status(value[1]);
            file = {
                length = value.length - 3;
                data = value.data + 3;
            }
            allocate_strings(&file);
            display = build_git_entry_display(file, status);
            git_status_entries[status_index] = status;
        }
        case SourceControl.Perforce; {
            if starts_with(value, workspace.directory) {
                relative_path: string = {
                    length = value.length - workspace.directory.length;
                    data = value.data + workspace.directory.length;
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

                value = relative_path;
            }
            else {
                allocate_strings(&value);
            }
            file = value;
            display = value;
        }
        case SourceControl.Svn; {
            allocate_strings(&value);
            file = {
                length = value.length - 8;
                data = value.data + 8;
            }
            display = value;
        }
    }

    return file, display;
}

Array<ListEntry> get_status_entries() {
    return filtered_status_entries;
}

int get_total_status_entries() {
    return status_entries.length;
}

load_diff(int thread, JobData data) {
    entry := cast(SelectedEntry*, data.pointer);
    file := entry.key;

    command: string;
    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Git; {
            command = temp_string("git --no-pager diff HEAD -- ", file);
        }
        case SourceControl.Perforce; {
            set_perforce_client();
            command = temp_string("p4 diff ", file);
        }
        case SourceControl.Svn; {
            command = temp_string("svn diff ", file);
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

change_status(string file) {
    workspace := get_workspace();
    switch workspace.local_settings.source_control {
        case SourceControl.Git; {
            each entry, i in status_entries {
                if file == entry.key {
                    status := git_status_entries[i];
                    add, reset := false;
                    add_status, reset_status := GitStatus.None;

                    if status == GitStatus.Untracked {
                        add = true;
                        add_status = GitStatus.Added;
                    }
                    if status & GitStatus.Added {
                        reset = true;
                        reset_status = GitStatus.Untracked;
                    }
                    if status & GitStatus.Changed {
                        add = true;
                        add_status = GitStatus.ChangedStaged;
                    }
                    if status & GitStatus.ChangedStaged {
                        reset = true;
                        reset_status = GitStatus.Changed;
                    }
                    if status & GitStatus.Deleted {
                        add = true;
                        add_status = GitStatus.DeletedStaged;
                    }
                    if status & GitStatus.DeletedStaged {
                        reset = true;
                        reset_status = GitStatus.Deleted;
                    }

                    if add {
                        command := temp_string("git add ", entry.key);
                        run_command_silent(command);
                        git_status_entries[i] = add_status;
                        set_git_status_display(entry.display, add_status);
                    }
                    else if reset {
                        command := temp_string("git restore --staged ", entry.key);
                        run_command_silent(command);
                        git_status_entries[i] = reset_status;
                        set_git_status_display(entry.display, reset_status);
                    }
                    break;
                }
            }

            apply_status_filter();
        }
        case SourceControl.Perforce;
        case SourceControl.Svn; {} // No action needed
    }
}


// Git specific functions
GitStatus char_to_git_status(u8 char, bool first = false) {
    if first {
        switch char {
            case '?'; return GitStatus.Untracked;
            case 'A'; return GitStatus.Added;
            case 'D'; return GitStatus.DeletedStaged;
            case 'M'; return GitStatus.ChangedStaged;
        }

        return GitStatus.None;
    }

    switch char {
        case '?'; return GitStatus.Untracked;
        case 'D'; return GitStatus.Deleted;
        case 'M'; return GitStatus.Changed;
    }

    return GitStatus.None;
}

string build_git_entry_display(string file, GitStatus status) {
    display: string = {
        length = file.length + 4;
        data = allocate(file.length + 4);
    }

    set_git_status_display(display, status);
    memory_copy(display.data + 4, file.data, file.length);

    return display;
}

set_git_status_display(string display, GitStatus status) {
    display[0] = ' ';
    display[1] = ' ';
    display[2] = ' ';
    display[3] = ' ';

    if status == GitStatus.Untracked {
        display[0] = '?';
    }
    else {
        if status & GitStatus.Added {
            display[0] = '+';
        }
        if status & GitStatus.Changed {
            display[2] = '~';
        }
        if status & GitStatus.ChangedStaged {
            display[0] = '~';
        }
        if status & GitStatus.Deleted {
            display[2] = '-';
        }
        if status & GitStatus.DeletedStaged {
            display[0] = '-';
        }
    }
}


// Perforce specific functions
set_perforce_client() {
    workspace := get_workspace();
    command := temp_string("p4 set P4CLIENT=", workspace.local_settings.perforce_client_name);
    run_command_silent(command);
}
