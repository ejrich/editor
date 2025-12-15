enum SourceControl {
    None;
    Git;
    Perforce;
    Svn;
}

source_control_status() {
    list_title: string;
    data: JobData;

    // TODO Add list sources
    switch local_settings.source_control {
        case SourceControl.Git; {
            list_title = "Git Status";
            queue_work(&low_priority_queue, load_git_status, data);
        }
        case SourceControl.Perforce; {
            list_title = "P4 Status";
            queue_work(&low_priority_queue, load_p4_status, data);
        }
        case SourceControl.Svn; {
            list_title = "SVN Status";
            queue_work(&low_priority_queue, load_svn_status, data);
        }
    }

    if !string_is_empty(list_title) {
        start_list_mode(list_title, get_status_entries);
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

load_git_status(int index, JobData data) {
    // TODO Implement
}

load_p4_status(int index, JobData data) {
    status_buffer := run_command_and_save_to_buffer("p4 diff -f -sa");

    // TODO Save to status entries
}

load_svn_status(int index, JobData data) {
    // TODO Implement
}

status_entries: Array<string>;

Array<string> get_status_entries() {
    return status_entries;
}
