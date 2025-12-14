enum SourceControl {
    None;
    Git;
    Perforce;
    Svn;
}

source_control_status() {
    list_title: string;

    // TODO Add list sources
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
        start_list_mode(list_title);
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
