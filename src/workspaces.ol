struct Workspace {
    active: bool;
    directory: string;
    title: string;
    buffers: Array<Buffer>;
    left_window: EditorWindow = { displayed = true; }
    right_window: EditorWindow;
    current_window: SelectedWindow;
    run_window_selected: bool;
    run_data: RunData;
}

init_workspaces() {
    initial: Workspace;
    each workspace in workspaces {
        workspace = initial;
        workspace.run_data.run_buffer_window.static_buffer = &workspace.run_data.run_buffer;
        create_semaphore(&workspace.run_data.run_mutex, initial_value = 1);
    }

    init_workspace(&workspaces[current_workspace]);
}

open_workspace(string directory) {
    // TODO Implement
}

Workspace* get_workspace() {
    return &workspaces[current_workspace];
}

#private

workspaces: Array<Workspace>[10];
current_workspace := 0;

init_workspace(Workspace* workspace) {
    workspace.active = true;
    workspace.directory = get_working_directory();
    workspace.title = workspace.directory;

    #if os == OS.Windows {
        dir_char := '\\'; #const
    }
    else {
        dir_char := '/'; #const
    }

    each i in workspace.directory.length {
        if workspace.directory[i] == dir_char {
            workspace.title = {
                length = workspace.directory.length - i - 1;
                data = workspace.directory.data + i + 1;
            }
        }
    }
}
