enum SourceControl {
    None;
    Git;
    Perforce;
    Svn;
}

// TODO Implement these
source_control_status() {
    switch local_settings.source_control {
        case SourceControl.Git; {
        }
        case SourceControl.Perforce; {
        }
        case SourceControl.Svn; {
        }
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

source_control_commit() {
    switch local_settings.source_control {
        case SourceControl.Git; {
        }
        case SourceControl.Perforce; {
        }
        case SourceControl.Svn; {
        }
    }
}
