struct Workspace {
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
    init_workspace(&_workspace);
}

open_workspace(string directory) {
    // TODO Implement
}

Workspace* get_workspace() {
    return &_workspace;
}

#private

_workspace: Workspace; // TODO Change this to be the array
workspaces: Array<Workspace>;
current_workspace := 0;

init_workspace(Workspace* workspace) {
    workspace.run_data.run_buffer_window.static_buffer = &workspace.run_data.run_buffer;
    create_semaphore(&workspace.run_data.run_mutex, initial_value = 1);
}
