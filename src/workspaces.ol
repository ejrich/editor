struct Workspace {
    active: bool;
    index: u8;
    directory: string;
    title: string;
    buffers: Array<Buffer>;
    left_window: EditorWindow = { displayed = true; }
    right_window: EditorWindow;
    current_window: SelectedWindow;
    bottom_window_selected: bool;
    run_data: RunData;
    terminal_data: TerminalData;
    debugger_data: DebuggerData;
    local_settings: LocalSettings;
    command_keybinds: Array<CommandKeybind>;
}

init_workspaces() {
    initial: Workspace;
    each workspace, i in workspaces {
        workspace = initial;
        workspace.index = (i + 1) % number_of_workspaces;
        workspace.run_data.buffer_window.static_buffer = &workspace.run_data.buffer;
        workspace.terminal_data.buffer_window.static_buffer = &workspace.terminal_data.buffer;
        create_semaphore(&workspace.run_data.run_mutex, initial_value = 1);
    }

    init_workspace(&workspaces[current_workspace]);
}

draw_workspaces() {
    x := -1.0 + global_font_config.quad_advance;
    y := 1.0 - global_font_config.top_line_offset;

    each workspace, i in workspaces {
        if workspace.active {
            text_color := appearance.visual_font_color;
            if i == current_workspace {
                text_color = appearance.font_color;
            }
            render_text(settings.font_size, x, y, text_color, vec4(), "%: %", workspace.index, workspace.title);

            x += global_font_config.quad_advance * (workspace.title.length + 4);
        }
    }
}

change_workspace(KeyCode code) {
    new_workspace := -1;
    switch code {
        case KeyCode.One;   new_workspace = 0;
        case KeyCode.Two;   new_workspace = 1;
        case KeyCode.Three; new_workspace = 2;
        case KeyCode.Four;  new_workspace = 3;
        case KeyCode.Five;  new_workspace = 4;
        case KeyCode.Six;   new_workspace = 5;
        case KeyCode.Seven; new_workspace = 6;
        case KeyCode.Eight; new_workspace = 7;
        case KeyCode.Nine;  new_workspace = 8;
        case KeyCode.Zero;  new_workspace = 9;
    }

    if new_workspace < 0 return;

    workspace := &workspaces[new_workspace];
    if !workspace.active return;

    change_current_workspace(new_workspace);
}

cycle_workspace(int change) {
    target_workspace := current_workspace + change;
    if target_workspace >= number_of_workspaces {
        target_workspace = 0;
    }
    else if target_workspace < 0 {
        target_workspace = number_of_workspaces - 1;
    }

    while target_workspace != current_workspace {
        if workspaces[target_workspace].active {
            change_current_workspace(target_workspace);
            return;
        }

        target_workspace += change;
        if target_workspace >= number_of_workspaces {
            target_workspace = 0;
        }
        else if target_workspace < 0 {
            target_workspace = number_of_workspaces - 1;
        }
    }
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

        close_current_workspace(false);
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

enum CloseWorkspaceResult {
    Success;
    OpenBuffersInCurrent;
    NoWorkspacesActive;
}

CloseWorkspaceResult close_current_workspace(bool change_to_next_active, bool force_close = false) {
    if !can_close_workspace() && !force_close {
        return CloseWorkspaceResult.OpenBuffersInCurrent;
    }

    next_workspace: int;
    if change_to_next_active {
        next_workspace = next_active_workspace();
        if next_workspace < 0 {
            return CloseWorkspaceResult.NoWorkspacesActive;
        }
    }

    workspace := &workspaces[current_workspace];

    free_allocation(workspace.directory.data);
    workspace.directory = empty_string;
    workspace.title = empty_string;

    each buffer in workspace.buffers {
        free_buffer(&buffer, false, true);
    }
    if workspace.buffers.length {
        workspace.buffers.length = 0;
        free_allocation(workspace.buffers.data);
    }

    close_editor_window(&workspace.left_window, true);
    close_editor_window(&workspace.right_window, false);

    close_local_settings(&workspace.local_settings);
    if workspace.command_keybinds.length {
        workspace.command_keybinds.length = 0;
        free_allocation(workspace.command_keybinds.data);
    }

    workspace.current_window = SelectedWindow.Left;
    workspace.bottom_window_selected = false;
    workspace.run_data.current_command.displayed = false;
    workspace.active = false;

    if change_to_next_active {
        change_current_workspace(next_workspace);
    }

    return CloseWorkspaceResult.Success;
}

Workspace* get_workspace() {
    return &workspaces[current_workspace];
}

reload_workspace() {
    workspace := &workspaces[current_workspace];
    close_local_settings(&workspace.local_settings);
    load_local_settings(workspace);
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

    load_local_settings(workspace);
    clear_terminal_buffer_window(workspace);
    workspace.terminal_data.directory = workspace.directory;
}

change_current_workspace(int index) {
    set_directory(workspaces[index].directory);
    current_workspace = index;
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

int next_active_workspace() {
    each i in number_of_workspaces - 1 {
        index := (current_workspace + i + 1) % number_of_workspaces;
        if workspaces[index].active {
            return index;
        }
    }

    return -1;
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
