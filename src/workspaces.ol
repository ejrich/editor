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

enum OpenWorkspaceResult {
    Success;
    InvalidDirectory;
    OpenBuffersInCurrent;
    MaxWorkspacesActive;
}

OpenWorkspaceResult open_workspace(string directory, bool replace_current) {
    valid_directory := is_directory(directory);
    if !valid_directory {
        return OpenWorkspaceResult.InvalidDirectory;
    }

    new_workspace_index := current_workspace;
    if replace_current {
        if !can_close_workspace() {
            return OpenWorkspaceResult.OpenBuffersInCurrent;
        }

        close_workspace();
    }
    else if !can_open_new_workspace(&new_workspace_index) {
        return OpenWorkspaceResult.MaxWorkspacesActive;
    }

    set_directory(directory);
    init_workspace(&workspaces[new_workspace_index]);
    current_workspace = new_workspace_index;
    open_files_list();

    return OpenWorkspaceResult.Success;
}

bool close_workspace(bool change_to_next_active = false) {
    if !can_close_workspace() {
        return false;
    }

    workspace := &workspaces[current_workspace];

    each buffer in workspace.buffers {
        free_buffer(&buffer, false, true);
    }
    if workspace.buffers.length {
        workspace.buffers.length = 0;
        free_allocation(workspace.buffers.data);
    }

    close_editor_window(&workspace.left_window, true);
    close_editor_window(&workspace.right_window, false);

    workspace.current_window = SelectedWindow.Left;
    workspace.run_window_selected = false;
    workspace.run_data.current_command.displayed = false;
    workspace.active = false;

    if change_to_next_active {
        // TODO Implement
    }

    return true;
}

Workspace* get_workspace() {
    return &workspaces[current_workspace];
}

#private

number_of_workspaces := 10; #const
workspaces: Array<Workspace>[number_of_workspaces];
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

bool can_open_new_workspace(int* index) {
    each workspace, i in workspaces {
        if !workspace.active {
            *index = i;
            return true;
        }
    }

    return false;
}

bool can_close_workspace() {
    workspace := &workspaces[current_workspace];
    each buffer in workspace.buffers {
        if buffer.has_changes {
            return false;
        }
    }

    return true;
}

close_editor_window(EditorWindow* window, bool displayed) {
    window.displayed = displayed;

    buffer_window := window.buffer_window;
    while buffer_window {
        next := buffer_window.next;
        free_allocation(buffer_window);
        buffer_window = next;
    }
    window.buffer_window = null;

    clear_jumps(&window.current_jump);
}
