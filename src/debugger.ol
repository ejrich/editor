struct DebuggerData {
    running: bool;
    started: bool;
    failed_to_start: bool;
    exited: bool;
    exit_code: int;
    process: ProcessData;
    buffer: Buffer = { read_only = true; title = get_debugger_buffer_title; }
    buffer_window: BufferWindow;
    send_mutex: Semaphore;
    command_executing: bool;
    skip_next_stop: bool;
    parse_status: DebuggerParseStatus;
    paused_file_index: s32;
    paused_line: u32;
    view: DebuggerView;
    views_focused: bool;
    view_start_index: u16;
    view_index: u16;
    local_variables: DynamicArray<LocalVariable>;
    local_variables_data: string;
    watches: DynamicArray<WatchExpression>;
    watch_index: int;
    editing_watch: bool;
    editing_watch_index: u16;
    stack_frames: DynamicArray<StackFrame>;
    max_function_length: int;
    max_location_length: int;
    stack_frames_data: string;
    threads: DynamicArray<Thread>;
    registers: DynamicArray<Register>;
}

enum DebuggerView : u8 {
    Locals;
    Watches;
    Stack;
    Threads;
    Registers;
}

enum DebuggerParseStatus : u8 {
    None;
    Source;
    Variables;
    StackTrace;
    Registers;
    Threads;
    Expression;
}

// TODO Move breakpoint lines when deleting/adding lines
struct Breakpoint {
    line: u32;
    active: bool;
    next: Breakpoint*;
}

struct LocalVariable {
    name: string;
    type: string;
    value: DebugValue;
}

struct StackFrame {
    active: bool;
    index: u16;
    address: u64;
    function: string;
    location: string;
}

struct Register {
    name: string;
    size: u8;
    value: u64;
}

struct Thread {
    number: int;
    id: int;
    active: bool;
}

struct WatchExpression {
    expression: string;
    parsing: bool;
    parsing_type: bool;
    parsing_value: bool;
    error: bool;
    type: string;
    data: string;
    value: DebugValue;
    value_data: string;
}

struct DebugValue {
    error: bool;
    is_pointer: bool;
    is_struct: bool;
    expanded: bool;
    value: string;
    struct_field_values: Array<StructFieldDebugValue>;

    // For memory management
    parent: DebugValue*;
    data: string;
}

struct StructFieldDebugValue {
    name: string;
    value: DebugValue;
}

struct DynamicArray<T> {
    length: u64;
    array: Array<T>;
}

draw_debugger_views(Workspace* workspace) {
    if !workspace.debugger_data.running return;

    divider_quad: QuadInstanceData = {
        color = appearance.font_color;
        position = { y = global_font_config.bottom_window_divider_y; }
        flags = QuadFlags.Solid;
        width = 1.0 / settings.window_width;
        height = global_font_config.bottom_window_divider_height;
    }

    draw_quad(&divider_quad, 1);

    x := global_font_config.quad_advance;
    y := 1.0 - global_font_config.first_line_offset - global_font_config.line_height * (global_font_config.max_lines_with_bottom_window + 1);

    views := cast(EnumTypeInfo*, type_of(DebuggerView));
    each view in views.values {
        color := appearance.font_color;
        background: Vector4;
        if view.value == cast(u8, workspace.debugger_data.view) {
            color = appearance.visual_font_color;
            background = appearance.font_color;
        }

        render_text(view.name, settings.font_size, x, y, color, background);
        x += (view.name.length + 1) * global_font_config.quad_advance;
    }

    draw_list_line(y);

    x = 0.0;
    y -= global_font_config.line_height;

    available_lines := global_font_config.bottom_window_max_lines - 1;
    i := workspace.debugger_data.view_start_index;
    blank_background: Vector4;

    switch workspace.debugger_data.view {
        case DebuggerView.Locals; {
            if !workspace.debugger_data.command_executing {
                variable_index, line_index := 0;
                while available_lines > 0 && variable_index < workspace.debugger_data.local_variables.length {
                    if workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
                        draw_selected_line(y);
                    }

                    local := &workspace.debugger_data.local_variables.array[variable_index++];

                    if line_index < i {
                        x, y, line_index, available_lines, i = draw_debug_value(workspace, &local.value, x, y, line_index, available_lines, i);
                    }
                    else {
                        render_text(local.name, settings.font_size, x, y, appearance.font_color, blank_background);

                        x += (local.name.length + 1) * global_font_config.quad_advance;
                        render_text("(", settings.font_size, x, y, appearance.font_color, blank_background);

                        x += global_font_config.quad_advance;
                        render_text(local.type, settings.font_size, x, y, appearance.font_color, blank_background);

                        x += local.type.length * global_font_config.quad_advance;
                        render_text(") =", settings.font_size, x, y, appearance.font_color, blank_background);

                        x += 4 * global_font_config.quad_advance;
                        x, y, line_index, available_lines, i = draw_debug_value(workspace, &local.value, x, y, line_index, available_lines, i);
                    }

                    if line_index >= i && available_lines > 0 {
                        i++;
                        draw_list_line(y);
                        available_lines--;
                        y -= global_font_config.line_height;
                    }
                    line_index++;
                    x = 0.0;
                }
            }
        }
        case DebuggerView.Watches; {
            watch_index, line_index := 0;
            while available_lines > 0 && watch_index < workspace.debugger_data.watches.length {
                if workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
                    draw_selected_line(y, workspace.debugger_data.editing_watch);
                }

                if workspace.debugger_data.editing_watch && workspace.debugger_data.views_focused && watch_index == workspace.debugger_data.editing_watch_index {
                    watch_string: string = {
                        length = watch_length;
                        data = watch_buffer.data;
                    }

                    render_highlighted_line_with_cursor(watch_string, x, y, watch_cursor, 1.0);
                    watch_index++;
                }
                else {
                    watch := &workspace.debugger_data.watches.array[watch_index++];

                    if line_index < i {
                        x, y, line_index, available_lines, i = draw_debug_value(workspace, &watch.value, x, y, line_index, available_lines, i);
                    }
                    else {
                        render_text(watch.expression, settings.font_size, x, y, appearance.font_color, blank_background);

                        if !workspace.debugger_data.command_executing {
                            x += (watch.expression.length + 1) * global_font_config.quad_advance;

                            if watch.error {
                                render_text("= ??", settings.font_size, x, y, appearance.font_color, blank_background);
                            }
                            else if !watch.parsing {
                                render_text("(", settings.font_size, x, y, appearance.font_color, blank_background);

                                x += global_font_config.quad_advance;
                                render_text(watch.type, settings.font_size, x, y, appearance.font_color, blank_background);

                                x += watch.type.length * global_font_config.quad_advance;
                                render_text(") =", settings.font_size, x, y, appearance.font_color, blank_background);

                                x += 4 * global_font_config.quad_advance;
                                x, y, line_index, available_lines, i = draw_debug_value(workspace, &watch.value, x, y, line_index, available_lines, i);
                            }
                        }
                    }
                }

                if line_index >= i && available_lines > 0 {
                    i++;
                    draw_list_line(y);
                    available_lines--;
                    y -= global_font_config.line_height;
                }
                line_index++;
                x = 0.0;
            }

            if workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
                draw_selected_line(y, workspace.debugger_data.editing_watch);
                if workspace.debugger_data.editing_watch {
                    watch_string: string = {
                        length = watch_length;
                        data = watch_buffer.data;
                    }

                    render_highlighted_line_with_cursor(watch_string, x, y, watch_cursor, 1.0);
                }
            }
        }
        case DebuggerView.Stack; {
            if !workspace.debugger_data.command_executing {
                header_start := "  #   "; #const
                render_text(header_start, settings.font_size, x, y, appearance.font_color, blank_background);

                x += header_start.length * global_font_config.quad_advance;
                render_text("Function", settings.font_size, x, y, appearance.font_color, blank_background);

                x += workspace.debugger_data.max_function_length * global_font_config.quad_advance;
                render_text("Location", settings.font_size, x, y, appearance.font_color, blank_background);

                x += workspace.debugger_data.max_location_length * global_font_config.quad_advance;
                render_text("Address", settings.font_size, x, y, appearance.font_color, blank_background);
                draw_list_line(y);

                while available_lines > 0 && i < workspace.debugger_data.stack_frames.length {
                    x = 0.0;
                    y -= global_font_config.line_height;

                    if workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
                        draw_selected_line(y);
                    }

                    frame := workspace.debugger_data.stack_frames.array[i++];
                    if frame.active {
                        draw_cursor(x, y, appearance.syntax_colors[cast(u8, SyntaxColor.Red)]);
                    }

                    x += 2 * global_font_config.quad_advance;
                    render_text(settings.font_size, x, y, appearance.font_color, blank_background, "%", frame.index);

                    x += 4 * global_font_config.quad_advance;
                    render_text(frame.function, settings.font_size, x, y, appearance.font_color, blank_background);

                    x += workspace.debugger_data.max_function_length * global_font_config.quad_advance;
                    render_text(frame.location, settings.font_size, x, y, appearance.font_color, blank_background);

                    x += workspace.debugger_data.max_location_length * global_font_config.quad_advance;
                    render_text(settings.font_size, x, y, appearance.font_color, blank_background, "0x%", uint_format(frame.address, 16, 16));

                    available_lines--;
                }
            }
        }
        case DebuggerView.Threads; {
            if !workspace.debugger_data.command_executing {
                render_text("  #     Id", settings.font_size, x, y, appearance.font_color, blank_background);
                draw_list_line(y);

                while available_lines > 0 && i < workspace.debugger_data.threads.length {
                    x = 0.0;
                    y -= global_font_config.line_height;

                    if workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
                        draw_selected_line(y);
                    }

                    thread := workspace.debugger_data.threads.array[i++];
                    if thread.active {
                        draw_cursor(x, y, appearance.syntax_colors[cast(u8, SyntaxColor.Red)]);
                    }

                    x += 2 * global_font_config.quad_advance;
                    render_text(settings.font_size, x, y, appearance.font_color, blank_background, "%", thread.number);

                    x += 6 * global_font_config.quad_advance;
                    render_text(settings.font_size, x, y, appearance.font_color, blank_background, "%", thread.id);

                    available_lines--;
                }
            }
        }
        case DebuggerView.Registers; {
            if !workspace.debugger_data.command_executing {
                render_text("Name      Value", settings.font_size, x, y, appearance.font_color, blank_background);
                draw_list_line(y);

                while available_lines > 0 && i < workspace.debugger_data.registers.length {
                    x = 0.0;
                    y -= global_font_config.line_height;

                    if workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
                        draw_selected_line(y);
                    }

                    register := workspace.debugger_data.registers.array[i++];
                    render_text(register.name, settings.font_size, x, y, appearance.font_color, blank_background);

                    x += 10 * global_font_config.quad_advance;
                    render_text(settings.font_size, x, y, appearance.font_color, blank_background, "0x%", uint_format(register.value, 16, register.size / 4));

                    available_lines--;
                }
            }
        }
    }
}

bool handle_debugger_press(PressState state, KeyCode code, ModCode mod, string char) {
    workspace := get_workspace();

    if !workspace.debugger_data.running || !workspace.bottom_window_selected || !workspace.debugger_data.views_focused || workspace.debugger_data.view != DebuggerView.Watches {
        if workspace.debugger_data.view != DebuggerView.Locals || (code != KeyCode.Left && code != KeyCode.Right) {
            return false;
        }
    }

    switch code {
        case KeyCode.Enter; {
            if workspace.debugger_data.editing_watch {
                expression := get_watch_string();

                if workspace.debugger_data.editing_watch_index < workspace.debugger_data.watches.length {
                    if expression.length {
                        watch := &workspace.debugger_data.watches.array[workspace.debugger_data.editing_watch_index];
                        if watch.expression != expression {
                            clear_watch(watch);
                            watch.expression = expression;
                            trigger_load_watches(workspace);
                        }
                    }
                    else {
                        delete_watch(workspace, workspace.debugger_data.editing_watch_index);
                    }
                }
                else if expression.length {
                    allocate_strings(&expression);
                    watch: WatchExpression = {
                        expression = expression;
                    }

                    add_to_array(&workspace.debugger_data.watches, watch);
                    trigger_load_watches(workspace);
                }

                workspace.debugger_data.editing_watch = false;
            }
            else {
                watch_cursor = 0;
                watch_length = 0;

                line_index := 0;
                add_watch := true;
                each i in workspace.debugger_data.watches.length {
                    watch := &workspace.debugger_data.watches.array[i];
                    if line_index == workspace.debugger_data.view_index {
                        memory_copy(watch_buffer.data, watch.expression.data, watch.expression.length);

                        watch_cursor = watch.expression.length;
                        watch_length = watch.expression.length;
                        workspace.debugger_data.editing_watch = true;
                        add_watch = false;
                        workspace.debugger_data.editing_watch_index = i;
                        break;
                    }
                    else if line_index > workspace.debugger_data.view_index {
                        add_watch = false;
                        break;
                    }

                    line_index += get_debug_value_lines(&watch.value);
                }

                if add_watch {
                    workspace.debugger_data.editing_watch_index = workspace.debugger_data.watches.length;
                    workspace.debugger_data.editing_watch = true;
                }
            }

            return true;
        }
        case KeyCode.Escape; {
            workspace.debugger_data.editing_watch = false;
            return true;
        }
        case KeyCode.Backspace; {
            if workspace.debugger_data.editing_watch {
                if watch_length {
                    if watch_cursor < watch_length {
                        memory_copy(watch_buffer.data + watch_cursor - 1, watch_buffer.data + watch_cursor, watch_length - watch_cursor);
                    }

                    watch_cursor--;
                    watch_length--;
                }
            }
            else {
                delete_watch_at_current_index(workspace);
            }

            return true;
        }
        case KeyCode.Delete; {
            if workspace.debugger_data.editing_watch {
                if watch_cursor < watch_length {
                    memory_copy(watch_buffer.data + watch_cursor, watch_buffer.data + watch_cursor + 1, watch_length - watch_cursor);

                    watch_length--;
                }
            }
            else {
                delete_watch_at_current_index(workspace);
            }

            return true;
        }
        case KeyCode.Left; {
            if workspace.debugger_data.editing_watch {
                watch_cursor = clamp(watch_cursor - 1, 0, watch_length);
                return true;
            }
            else if !workspace.debugger_data.command_executing {
                line_index := 0;
                current_line := workspace.debugger_data.view_index;
                finished := false;

                switch workspace.debugger_data.view {
                    case DebuggerView.Locals; {
                        each i in workspace.debugger_data.local_variables.length {
                            local := &workspace.debugger_data.local_variables.array[i];
                            line_index, finished = toggle_debug_value(&local.value, line_index, current_line, false);

                            if finished break;
                        }

                        return true;
                    }
                    case DebuggerView.Watches; {
                        each i in workspace.debugger_data.watches.length {
                            watch := &workspace.debugger_data.watches.array[i];
                            line_index, finished = toggle_debug_value(&watch.value, line_index, current_line, false);

                            if finished break;
                        }

                        return true;
                    }
                }
            }
        }
        case KeyCode.Right; {
            if workspace.debugger_data.editing_watch {
                watch_cursor = clamp(watch_cursor + 1, 0, watch_length);
                return true;
            }
            else if !workspace.debugger_data.command_executing {
                line_index := 0;
                current_line := workspace.debugger_data.view_index;
                finished := false;

                switch workspace.debugger_data.view {
                    case DebuggerView.Locals; {
                        each i in workspace.debugger_data.local_variables.length {
                            local := &workspace.debugger_data.local_variables.array[i];
                            line_index, finished = toggle_debug_value(&local.value, line_index, current_line, true);

                            if finished break;
                        }

                        return true;
                    }
                    case DebuggerView.Watches; {
                        each i in workspace.debugger_data.watches.length {
                            watch := &workspace.debugger_data.watches.array[i];
                            line_index, finished = toggle_debug_value(&watch.value, line_index, current_line, true);

                            if finished break;
                        }

                        return true;
                    }
                }
            }
        }
        default; {
            if char.length > 0 && (mod & ModCode.Control) != ModCode.Control && workspace.debugger_data.editing_watch {
                if watch_length + char.length <= watch_buffer_length {
                    if watch_cursor < watch_length {
                        each i in watch_length - watch_cursor {
                            index := watch_length - i - 1;
                            watch_buffer[index + char.length] = watch_buffer[index];
                        }
                    }

                    memory_copy(watch_buffer.data + watch_cursor, char.data, char.length);

                    watch_cursor += char.length;
                    watch_length += char.length;
                }

                return true;
            }
        }
    }

    return false;
}

bool change_debugger_tab(int change) {
    workspace := get_workspace();

    if !workspace.debugger_data.running || !workspace.bottom_window_selected || !workspace.debugger_data.views_focused {
        return false;
    }

    view_type := cast(EnumTypeInfo*, type_of(DebuggerView));
    last_view := view_type.values[view_type.values.length - 1].value;

    view := cast(s8, workspace.debugger_data.view);
    view += change;

    if view < 0 {
        view = last_view;
    }
    else if view > last_view {
        view = 0;
    }

    workspace.debugger_data = {
        view = cast(DebuggerView, view);
        view_start_index = 0;
        view_index = 0;
    }

    return true;
}

bool change_debugger_index(int change) {
    workspace := get_workspace();

    if !workspace.debugger_data.running || !workspace.bottom_window_selected || !workspace.debugger_data.views_focused || (workspace.debugger_data.command_executing && workspace.debugger_data.view != DebuggerView.Watches) || workspace.debugger_data.editing_watch {
        return false;
    }

    adjust_view_index(workspace, change);

    return true;
}

BufferWindow* get_debugger_window(Workspace* workspace) {
    if workspace.debugger_data.running {
        return &workspace.debugger_data.buffer_window;
    }

    return null;
}

start_or_continue_debugger() {
    workspace := get_workspace();
    if workspace.debugger_data.running {
        continue_debugger(workspace);
    }
    else if !string_is_empty(workspace.local_settings.debug_command) {
        force_command_to_stop();
        workspace.debugger_data = {
            running = true;
            failed_to_start = false;
            exited = false;
            view = DebuggerView.Locals;
            view_start_index = 0;
            view_index = 0;
            skip_next_stop = false;
            local_variables = { length = 0; }
            stack_frames = { length = 0; }
            threads = { length = 0; }
        }

        data: JobData;
        data.pointer = workspace;
        queue_work(&low_priority_queue, debugger_thread, data);
    }
}

bool stop_debugger() {
    workspace := get_workspace();
    if !workspace.debugger_data.running {
        return false;
    }

    data: JobData;
    data.pointer = workspace;
    queue_work(&low_priority_queue, exit_debugger, data);
    return true;
}

toggle_breakpoint() {
    workspace := get_workspace();
    if workspace.bottom_window_selected return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null return;

    line := clamp(buffer_window.line, 0, buffer.line_count - 1) + 1;

    breakpoint := buffer.breakpoints;
    clear := false;
    while breakpoint {
        if breakpoint.line == line {
            clear = true;
            break;
        }

        breakpoint = breakpoint.next;
    }

    if workspace.debugger_data.running {
        was_executing := workspace.debugger_data.command_executing;
        if was_executing {
            escape_debugger(workspace);
        }

        command: string;
        if clear {
            path_end := 0;
            each i in buffer.relative_path.length {
                if buffer.relative_path[i] == '/' {
                    path_end = i + 1;
                }
            }

            file: string = { length = buffer.relative_path.length - path_end; data = buffer.relative_path.data + path_end; }
            command = format_string("br clear -f % -l %\n", temp_allocate, file, line);
        }
        else {
            command = format_string("b %:%\n", temp_allocate, buffer.relative_path, line);
        }

        send_command_to_debugger(workspace, command);

        if was_executing {
            continue_debugger(workspace);
        }
    }

    if clear {
        current_breakpoint := buffer.breakpoints;
        if current_breakpoint == breakpoint {
            buffer.breakpoints = breakpoint.next;
        }
        else {
            while current_breakpoint {
                if current_breakpoint.next == breakpoint {
                    current_breakpoint.next = breakpoint.next;
                    break;
                }

                current_breakpoint = current_breakpoint.next;
            }
        }

        free_allocation(breakpoint);
    }
    else {
        breakpoint = new<Breakpoint>();
        breakpoint.line = line;
        breakpoint.active = true;

        current_breakpoint := buffer.breakpoints;
        if current_breakpoint == null || line < current_breakpoint.line {
            breakpoint.next = current_breakpoint;
            buffer.breakpoints = breakpoint;
        }
        else {
            while current_breakpoint {
                if current_breakpoint.next == null || line < current_breakpoint.next.line {
                    breakpoint.next = current_breakpoint.next;
                    current_breakpoint.next = breakpoint;
                    break;
                }

                current_breakpoint = current_breakpoint.next;
            }
        }
    }
}

step_over() {
    workspace := get_workspace();
    if !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    send_command_to_debugger(workspace, "n\n");
    workspace.debugger_data.command_executing = true;
}

step_in() {
    workspace := get_workspace();
    if !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    send_command_to_debugger(workspace, "s\n");
    workspace.debugger_data.command_executing = true;
}

step_out() {
    workspace := get_workspace();
    if !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    send_command_to_debugger(workspace, "finish\n");
    workspace.debugger_data.command_executing = true;
}

run_to() {
    workspace := get_workspace();
    if workspace.bottom_window_selected || !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null return;

    line := clamp(buffer_window.line, 0, buffer.line_count - 1) + 1;

    command := format_string("br set -o 1 -f % -l %\n", temp_allocate, buffer.relative_path, line);
    send_command_to_debugger(workspace, command);
    continue_debugger(workspace);
}

skip_to() {
    workspace := get_workspace();
    if workspace.bottom_window_selected || !workspace.debugger_data.running || workspace.debugger_data.command_executing return;

    buffer_window, buffer := get_current_window_and_buffer();
    if buffer_window == null || buffer == null || buffer_window.buffer_index != workspace.debugger_data.paused_file_index return;

    line := clamp(buffer_window.line, 0, buffer.line_count - 1) + 1;

    command := format_string("jump %\n", temp_allocate, line);
    send_command_to_debugger(workspace, command);
    workspace.debugger_data.paused_line = line;
}

#private

adjust_view_index(Workspace* workspace, int change = 0) {
    available_lines := global_font_config.bottom_window_max_lines - 1;

    new_index := workspace.debugger_data.view_index + change;
    if new_index <= 0 {
        workspace.debugger_data = {
            view_start_index = 0;
            view_index = 0;
        }
    }
    else {
        max := 0;
        switch workspace.debugger_data.view {
            case DebuggerView.Locals; {
                if workspace.debugger_data.local_variables.length {
                    each i in workspace.debugger_data.local_variables.length {
                        local := &workspace.debugger_data.local_variables.array[i];
                        max += get_debug_value_lines(&local.value);
                    }
                    max--;
                }
            }
            case DebuggerView.Watches; {
                each i in workspace.debugger_data.watches.length {
                    watch := &workspace.debugger_data.watches.array[i];
                    max += get_debug_value_lines(&watch.value);
                }
            }
            case DebuggerView.Stack; {
                available_lines--;
                max = workspace.debugger_data.stack_frames.length - 1;
            }
            case DebuggerView.Threads; {
                available_lines--;
                max = workspace.debugger_data.threads.length - 1;
            }
            case DebuggerView.Registers; {
                available_lines--;
                max = workspace.debugger_data.registers.length - 1;
            }
        }

        if max == 0 {
            workspace.debugger_data = {
                view_start_index = 0;
                view_index = 0;
            }
        }
        else {
            new_index = clamp(new_index, 0, max);
            if new_index < workspace.debugger_data.view_start_index {
                workspace.debugger_data.view_start_index = new_index;
            }
            else if new_index - workspace.debugger_data.view_start_index >= available_lines {
                workspace.debugger_data.view_start_index = new_index - available_lines + 1;
            }
            workspace.debugger_data.view_index = new_index;
        }
    }
}

delete_watch_at_current_index(Workspace* workspace) {
    line_index := 0;
    each i in workspace.debugger_data.watches.length {
        watch := &workspace.debugger_data.watches.array[i];
        if line_index == workspace.debugger_data.view_index {
            delete_watch(workspace, i);
            break;
        }
        else if line_index > workspace.debugger_data.view_index {
            break;
        }

        line_index += get_debug_value_lines(&watch.value);
    }
}

delete_watch(Workspace* workspace, int watch_index) {
    if watch_index < workspace.debugger_data.watches.length {
        watch := &workspace.debugger_data.watches.array[watch_index];
        clear_watch(watch);

        if watch_index < workspace.debugger_data.watches.length - 1 {
            each i in watch_index..workspace.debugger_data.watches.length - 2 {
                workspace.debugger_data.watches.array[i] = workspace.debugger_data.watches.array[i + 1];
            }
        }

        workspace.debugger_data.watches.length--;
    }
}

clear_watch(WatchExpression* watch) {
    free_allocation(watch.expression.data);
    free_allocation(watch.data.data);

    watch.type = { length = 0; data = null; }
    watch.data = { length = 0; data = null; }
}

string get_watch_string() {
    expression: string;
    start := 0;

    each i in watch_length {
        char := watch_buffer[i];
        if !is_whitespace(char) {
            if expression.data == null {
                expression = {
                    length = 1;
                    data = watch_buffer.data + i;
                }
                start = i;
            }
            else {
                expression.length = i - start + 1;
            }
        }
    }

    return expression;
}

watch_buffer_length := 100; #const
watch_buffer: Array<u8>[watch_buffer_length];
watch_cursor: int;
watch_length: int;

draw_list_line(float y) {
    line_quad: QuadInstanceData = {
        color = appearance.font_color;
        position = {
            x = 0.5;
            y = y - global_font_config.block_y_offset;
        }
        flags = QuadFlags.Solid;
        width = 1.0;
        height = 1.0 / settings.window_height;
    }

    draw_quad(&line_quad, 1);
}

draw_selected_line(float y, bool highlight = false) {
    line_quad: QuadInstanceData = {
        color = appearance.current_line_color;
        position = {
            x = 0.5;
            y = y + global_font_config.block_y_offset;
            z = 0.3;
        }
        flags = QuadFlags.Solid;
        width = 1.0;
        height = global_font_config.line_height;
    }

    if highlight {
        line_quad.color = appearance.font_color;
    }

    draw_quad(&line_quad, 1);
}

int, bool toggle_debug_value(DebugValue* value, int line_index, int current_line, bool expand) {
    toggled := false;
    if value.is_struct {
        if value.expanded {
            if !expand && line_index == current_line {
                value.expanded = false;
                collapse_struct_fields(value);
                toggled = true;
            }
            else {
                line_index++;
                each struct_field_value in value.struct_field_values {
                    lines, finished := toggle_debug_value(&struct_field_value.value, line_index, current_line, expand);
                    line_index = lines;
                    if finished {
                        toggled = true;
                        break;
                    }
                }
            }
        }
        else if expand && line_index == current_line {
            value.expanded = true;
            toggled = true;
        }
    }
    else {
        // TODO Handle expanded pointers
        line_index++;
    }

    return line_index, toggled;
}

int get_debug_value_lines(DebugValue* value) {
    line_count := 1;

    if value.is_struct {
        if value.expanded {
            each struct_field_value in value.struct_field_values {
                line_count += get_debug_value_lines(&struct_field_value.value);
            }
        }
    }
    else {
        // TODO Handle expanded pointers
    }

    return line_count;
}

collapse_struct_fields(DebugValue* value) {
    each struct_field_value in value.struct_field_values {
        if struct_field_value.value.expanded {
            struct_field_value.value.expanded = false;
            collapse_struct_fields(&struct_field_value.value);
        }
    }
}

float, float, int, int, u16 draw_debug_value(Workspace* workspace, DebugValue* value, float x, float y, int line_index, int available_lines, u16 i, int depth = 1) {
    blank_background: Vector4;

    if value.is_struct {
        value_separation := 2;
        if !value.expanded && line_index >= i {
            render_text("{", settings.font_size, x, y, appearance.font_color, blank_background);
            x += 2 * global_font_config.quad_advance;
            value_separation = 1;
        }

        if value.expanded && available_lines > 0 {
            if line_index >= i {
                draw_list_line(y);
                available_lines--;
                y -= global_font_config.line_height;
                i++;
            }
            x = depth * 2 * global_font_config.quad_advance;
            line_index++;
        }

        each struct_field_value, j in value.struct_field_values {
            if value.expanded {
                if available_lines <= 0 break;
            }
            else if x >= 1.0 {
                break;
            }

            if line_index >= i {
                if value.expanded && workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
                    draw_selected_line(y);
                }

                render_text(struct_field_value.name, settings.font_size, x, y, appearance.font_color, blank_background);

                x += (struct_field_value.name.length + value_separation - 1) * global_font_config.quad_advance;
                render_text("=", settings.font_size, x, y, appearance.font_color, blank_background);
            }

            x += value_separation * global_font_config.quad_advance;
            x, y, line_index, available_lines, i = draw_debug_value(workspace, &struct_field_value.value, x, y, line_index, available_lines, i, depth + 1);

            if value.expanded {
                if j < value.struct_field_values.length - 1 {
                    if line_index >= i && available_lines > 0 {
                        i++;
                        draw_list_line(y);
                        available_lines--;
                        y -= global_font_config.line_height;
                    }
                    x = depth * 2 * global_font_config.quad_advance;
                    line_index++;
                }
            }
            else {
                x += global_font_config.quad_advance;
            }
        }

        if !value.expanded && line_index >= i && x < 1.0 {
            render_text("}", settings.font_size, x, y, appearance.font_color, blank_background);
        }
    }
    else if line_index >= i {
        if depth > 1 && workspace.debugger_data.views_focused && i == workspace.debugger_data.view_index {
            draw_selected_line(y);
        }

        render_text(value.value, settings.font_size, x, y, appearance.font_color, blank_background);
        x += value.value.length * global_font_config.quad_advance;

        if value.is_pointer && value.expanded {
            // TODO Get this value
        }
    }

    return x, y, line_index, available_lines, i;
}

debugger_thread(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    clear_debugger_buffer_window(workspace);

    found_executable := false;
    executable, args: string;
    each i in workspace.local_settings.debug_command.length {
        char := workspace.local_settings.debug_command[i];
        if found_executable {
            if char == ' ' {
                args = {
                    length = workspace.local_settings.debug_command.length - i;
                    data = workspace.local_settings.debug_command.data + i;
                }
                break;
            }
            else {
                executable.length++;
            }
        }
        else if char != ' ' {
            found_executable = true;
            executable = {
                length = 1;
                data = workspace.local_settings.debug_command.data + i;
            }
        }
    }

    #if os == OS.Windows {
        if !ends_with(executable, ".exe") {
            executable = temp_string(executable, ".exe");
        }
    }

    command := temp_string("lldb -- ", executable, args);
    workspace.debugger_data.started = start_command(command, workspace.directory, &workspace.debugger_data.process, true, false);

    if !workspace.debugger_data.started {
        workspace.debugger_data.failed_to_start = true;
        return;
    }

    buf: CArray<u8>[10000];
    success, text := read_from_output_pipe(&workspace.debugger_data.process, &buf, buf.length);
    add_to_debugger_buffer(workspace, text);

    each buffer in workspace.buffers {
        breakpoint := buffer.breakpoints;
        while breakpoint {
            if breakpoint.active {
                command = format_string("b %:%\n", temp_allocate, buffer.relative_path, breakpoint.line);
                send_command_to_debugger(workspace, command);
            }

            breakpoint = breakpoint.next;
        }
    }

    send_command_to_debugger(workspace, "target stop-hook add\n");
    send_command_to_debugger(workspace, "source info\n");
    send_command_to_debugger(workspace, "v\n");
    send_command_to_debugger(workspace, "bt\n");
    send_command_to_debugger(workspace, "register read\n");
    send_command_to_debugger(workspace, "thread list\n");
    send_command_to_debugger(workspace, "DONE\n");

    send_command_to_debugger(workspace, "r\n");
    workspace.debugger_data.command_executing = true;

    while workspace.debugger_data.running {
        success, text = read_from_output_pipe(&workspace.debugger_data.process, &buf, buf.length);

        if !success break;

        if !parse_debugger_output(workspace, text) {
            add_to_debugger_buffer(workspace, text);
        }
    }

    close_process_and_get_exit_code(&workspace.debugger_data.process, &workspace.debugger_data.exit_code);
    workspace.debugger_data.exited = true;

    log("lldb exited with code %\n", workspace.debugger_data.exit_code);
}

exit_debugger(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    escape_debugger(workspace);
    send_command_to_debugger(workspace, "kill\n");
    send_command_to_debugger(workspace, "quit\n");
    workspace.debugger_data.running = false;

    trigger_window_update();
}

escape_debugger(Workspace* workspace) {
    workspace.debugger_data.skip_next_stop = true;

    #if os == OS.Windows {
        send_command_to_debugger(workspace, "process interrupt\n");
    }
    #if os == OS.Linux {
        kill(workspace.debugger_data.process.pid, KillSignal.SIGINT);
    }

    sleep(200);
    workspace.debugger_data.command_executing = false;
}

continue_debugger(Workspace* workspace) {
    if !workspace.debugger_data.command_executing {
        send_command_to_debugger(workspace, "c\n");
        workspace.debugger_data.command_executing = true;
    }
}

send_command_to_debugger(Workspace* workspace, string command) {
    semaphore_wait(&workspace.debugger_data.send_mutex);
    defer semaphore_release(&workspace.debugger_data.send_mutex);

    #if os == OS.Windows {
        WriteFile(workspace.debugger_data.process.input_pipe, command.data, command.length, null, null);
    }
    #if os == OS.Linux {
        write(workspace.debugger_data.process.input_pipe, command.data, command.length);
    }
}

bool parse_debugger_output(Workspace* workspace, string text) {
    if workspace.debugger_data.parse_status == DebuggerParseStatus.None {
        source_info_start := "Lines found in module "; #const
        if starts_with(text, source_info_start) {
            // Execution is paused, start parsing the program state
            workspace.debugger_data.command_executing = false;
            workspace.debugger_data.parse_status = DebuggerParseStatus.Source;
        }
        else {
            process := "Process "; #const
            if starts_with(text, process) {
                i := process.length;
                parsing_pid := true;
                parsing_status := false;
                while i < text.length {
                    char := text[i];
                    if char == ' ' {
                        if parsing_pid {
                            parsing_pid = false;
                            parsing_status = true;
                        }
                    }
                    else if parsing_pid && (char < '0' || char > '9') {
                        break;
                    }
                    else if parsing_status {
                        status: string = { length = text.length - i; data = text.data + i; }
                        if starts_with(status, "stopped") {
                            workspace.debugger_data.command_executing = false;
                            if !workspace.debugger_data.skip_next_stop {
                                trigger_load_watches(workspace);
                            }

                            workspace.debugger_data.skip_next_stop = false;
                            return true;
                        }

                        break;
                    }

                    i++;
                }
            }

            return false;
        }
    }

    clear_start_of_line(&text);

    debug_line_start := "(lldb)"; #const
    if starts_with(text, debug_line_start) {
        if workspace.debugger_data.parse_status == DebuggerParseStatus.Expression {
            return true;
        }

        text.length -= debug_line_start.length;
        text.data += debug_line_start.length;

        clear_start_of_line(&text);
    }

    if text.length == 0 return true;

    switch workspace.debugger_data.parse_status {
        case DebuggerParseStatus.Source; {
            // Lines found in module `editor
            // [0x000000000041ad44-0x000000000041ad59): /home/evan/editor/src/buffers.ol:3:5
            workspace.debugger_data.paused_file_index = -1;

            move_to_next_line(&text);
            text_parts := split_string(text, ' ');
            if text_parts.length >= 2 && starts_with(text_parts[1], workspace.directory) {
                location := text_parts[1];
                location.length -= workspace.directory.length + 1;
                location.data += workspace.directory.length + 1;

                location_parts := split_string(location, ':');
                if location_parts.length >= 2 {
                    file := location_parts[0];
                    line_number := location_parts[1];

                    each i in file.length {
                        if file[i] == '\\' {
                            file[i] = '/';
                        }
                    }

                    file_found := false;
                    each buffer, i in workspace.buffers {
                        if buffer.relative_path == file {
                            workspace.debugger_data.paused_file_index = i;
                            file_found = true;
                            break;
                        }
                    }

                    line := 0;
                    each i in line_number.length {
                        char := line_number[i];
                        if char >= '0' && char <= '9' {
                            line *= 10;
                            line += char - '0';
                        }
                        else {
                            break;
                        }
                    }
                    workspace.debugger_data.paused_line = line;

                    buffer_window: BufferWindow*;
                    if file_found {
                        buffer_window = open_buffer_index(workspace, workspace.debugger_data.paused_file_index);
                    }
                    else {
                        buffer_window = open_file_buffer(file, true);
                        workspace.debugger_data.paused_file_index = workspace.buffers.length - 1;
                    }

                    buffer_window.line = line - 1;
                    adjust_start_line(buffer_window);
                }
            }

            workspace.debugger_data.parse_status = DebuggerParseStatus.Variables;
        }
        case DebuggerParseStatus.Variables; {
            // (Workspace *) workspace = 0xff0000000000000a
            // (BufferWindow *) bottom_window = 0x00000000004795e0
            // (bool) bottom_focused = true
            allocate_strings(&text);
            if !string_is_empty(workspace.debugger_data.local_variables_data) {
                free_allocation(workspace.debugger_data.local_variables_data.data);
            }
            each i in workspace.debugger_data.local_variables.length {
                clear_debug_value(&workspace.debugger_data.local_variables.array[i].value);
            }
            workspace.debugger_data.local_variables_data = text;
            workspace.debugger_data.local_variables.length = 0;

            parsing_type := true;
            parsing_name, parsing_value, parse_value_to_eol, in_string, escape, reset := false;
            struct_depth := 0;
            variable: LocalVariable;
            i := 0;
            while i < text.length {
                char := text[i++];
                if parsing_type {
                    if char == '(' {
                        variable.type.data = text.data + i;
                    }
                    else if char == ')' {
                        parsing_type = false;
                        parsing_name = true;
                    }
                    else if variable.type.data {
                        variable.type.length++;
                    }
                }
                else if parsing_name {
                    if char == ' ' {
                        if variable.name.length {
                            parsing_name = false;
                            parsing_value = true;
                        }
                        else {
                            variable.name.data = text.data + i;
                        }
                    }
                    else {
                        variable.name.length++;
                    }
                }
                else if parsing_value {
                    i++;
                    variable.value = parse_debug_value(text, &i);

                    parsing_value = false;
                    parsing_type = true;
                    add_to_array(&workspace.debugger_data.local_variables, variable);

                    variable = {
                        name = { length = 0; data = null; }
                        type = { length = 0; data = null; }
                    }
                }
            }

            workspace.debugger_data.parse_status = DebuggerParseStatus.StackTrace;
        }
        case DebuggerParseStatus.StackTrace; {
            // * thread #1, name = 'editor', stop reason = breakpoint 1.1
            //   * frame #0: 0x000000000041ad44 editor`draw_buffers at buffers.ol:3:5
            //     frame #1: 0x000000000040dcaf editor`main at main.ol:78:17
            //     frame #2: 0x00000000004055a1 editor`__start(argc=2, argv=0x00007fffffffd128) at runtime.ol:296:5
            //     frame #3: 0x00000000004596dd editor`_start + 13
            move_to_next_line(&text);

            allocate_strings(&text);
            if !string_is_empty(workspace.debugger_data.stack_frames_data) {
                free_allocation(workspace.debugger_data.stack_frames_data.data);
            }
            workspace.debugger_data = {
                stack_frames = { length = 0; }
                max_function_length = "Function ".length;
                max_location_length = "Location ".length;
                stack_frames_data = text;
            }

            lines := split_string(text);
            each line in lines {
                if line.length {
                    frame: StackFrame = { active = line[2] == '*'; }

                    line_start := "    frame #"; #const
                    i := line_start.length;
                    while i < line.length {
                        char := line[i++];
                        if char >= '0' && char <= '9' {
                            frame.index *= 10;
                            frame.index += char - '0';
                        }
                        else {
                            break;
                        }
                    }

                    i += 3;
                    while i < line.length {
                        char := line[i++];
                        if char >= '0' && char <= '9' {
                            frame.address *= 16;
                            frame.address += char - '0';
                        }
                        else if char >= 'A' && char <= 'F' {
                            frame.address *= 16;
                            frame.address += char - '7';
                        }
                        else if char >= 'a' && char <= 'f' {
                            frame.address *= 16;
                            frame.address += char - 'W';
                        }
                        else {
                            break;
                        }
                    }

                    i++;
                    while i < line.length {
                        char := line[i];
                        if char == '`' && frame.function.length == 0 {
                            frame.function.data = line.data + i + 1;
                        }
                        else if frame.function.data {
                            if char == '(' || char == ' ' {
                                break;
                            }
                            else {
                                frame.function.length++;
                            }
                        }

                        i++;
                    }

                    while i < line.length {
                        sub_line: string = { length = line.length - i; data = line.data + i; }
                        location_start := " at "; #const
                        if starts_with(sub_line, location_start) {
                            sub_line.length -= location_start.length;
                            sub_line.data += location_start.length;
                            frame.location = sub_line;
                            break;
                        }
                        i++;
                    }

                    trim_whitespace_from_end(&frame.location);
                    if frame.function.length + 1 > workspace.debugger_data.max_function_length {
                        workspace.debugger_data.max_function_length = frame.function.length + 1;
                    }

                    if frame.location.length + 1 > workspace.debugger_data.max_location_length {
                        workspace.debugger_data.max_location_length = frame.location.length + 1;
                    }

                    add_to_array(&workspace.debugger_data.stack_frames, frame);
                }
            }

            workspace.debugger_data.parse_status = DebuggerParseStatus.Registers;
        }
        case DebuggerParseStatus.Registers; {
            // General Purpose Registers:
            //        rax = 0x0000000000000000
            //        rbx = 0x0000000000000000
            //        rcx = 0xff0000000000000a
            //        rdx = 0x000000000047b8e0  editor`__bss_start + 37888
            //        rdi = 0x00000000000001ff
            //        rsi = 0x0000000000002300
            //        rbp = 0x00007fffffffd120
            //        rsp = 0x00007fffffffcfd0
            //         r8 = 0x00007fffd830d000
            //         r9 = 0x0000000000000000
            //        r10 = 0x0000000000000000
            //        r11 = 0x0000000000000000
            //        r12 = 0x00000000004596d0  editor`_start
            //        r13 = 0x00007fffffffd120
            //        r14 = 0x0000000000000000
            //        r15 = 0x0000000000000000
            //        rip = 0x000000000041ad44  editor`draw_buffers + 4 at buffers.ol:3:5
            //     rflags = 0x0000000000000202
            //         cs = 0x0000000000000033
            //         fs = 0x0000000000000000
            //         gs = 0x0000000000000000
            //         ss = 0x000000000000002b
            //    fs_base = 0x00007ffff76f2340
            //    gs_base = 0x0000000000000000
            //         ds = 0x0000000000000000
            //         es = 0x0000000000000000
            move_to_next_line(&text);

            initial := workspace.debugger_data.registers.length == 0;
            index := 0;
            lines := split_string(text);
            each line in lines {
                if line.length {
                    register: Register*;
                    i := 0;
                    if initial {
                        value: Register;

                        while i < line.length {
                            char := line[i];
                            if char == ' ' {
                                if value.name.length > 0 {
                                    allocate_strings(&value.name);
                                    i += 4;
                                    break;
                                }
                            }
                            else {
                                if value.name.length == 0 {
                                    value.name.data = line.data + i;
                                }
                                value.name.length++;
                            }

                            i++;
                        }

                        register = &value;
                    }
                    else {
                        register = &workspace.debugger_data.registers.array[index++];
                        register.size = 0;
                        register.value = 0;

                        while i < line.length {
                            char := line[i++];
                            if char == '=' {
                                i += 2;
                                break;
                            }
                        }
                    }

                    base, size_factor: u8;
                    while i < line.length {
                        char := line[i++];
                        if base == 0 {
                            switch char {
                                case 'b'; {
                                    base = 2;
                                    size_factor = 1;
                                }
                                case 'x'; {
                                    base = 16;
                                    size_factor = 4;
                                }
                            }
                        }
                        else {
                            if char >= '0' && char <= '9' {
                                register.value *= base;
                                register.value += char - '0';
                                register.size += size_factor;
                            }
                            else if char >= 'A' && char <= 'F' {
                                register.value *= base;
                                register.value += char - '7';
                                register.size += size_factor;
                            }
                            else if char >= 'a' && char <= 'f' {
                                register.value *= base;
                                register.value += char - 'W';
                                register.size += size_factor;
                            }
                            else {
                                break;
                            }
                        }
                    }

                    if initial {
                        add_to_array(&workspace.debugger_data.registers, *register);
                    }
                }
            }

            workspace.debugger_data.parse_status = DebuggerParseStatus.Threads;
        }
        case DebuggerParseStatus.Threads; {
            // Process 14109 stopped
            // * thread #1: tid = 14109, 0x000000000041ad44 editor`draw_buffers at buffers.ol:3:5, name = 'editor', stop reason = breakpoint 1.1
            //   thread #2: tid = 14216, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #3: tid = 14217, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #4: tid = 14218, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #5: tid = 14219, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #6: tid = 14220, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #7: tid = 14221, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #8: tid = 14222, 0x0000Threads, Threads, r`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #9: tid = 14223, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046fc30) at thread.ol:55:13, name = 'editor'
            //   thread #10: tid = 14224, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #11: tid = 14225, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #12: tid = 14226, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #13: tid = 14227, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #14: tid = 14228, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #15: tid = 14229, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020Threads, Threads, 13, name = 'editor'
            //   thread #16: tid = 14230, 0x00000000004455d5 editor`semaphore_wait(semaphore=0x000000000046e020) at thread.ol:55:13, name = 'editor'
            //   thread #17: tid = 14289, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #18: tid = 14290, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #19: tid = 14291, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #20: tid = 14292, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor:disk$0'
            //   thread #23: tid = 14295, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor'
            //   thread #24: tid = 14298, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'editor'
            //   thread #25: tid = 14319, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_canThreads, WSI swapchain q'
            //   thread #26: tid = 14320, 0x00007ffff7cdf9f2 libc.so.6`__syscall_cancel_arch at syscall_cancel.S:56, name = 'WSI swapchain e'
            move_to_next_line(&text);

            workspace.debugger_data.threads.length = 0;
            lines := split_string(text);
            each line in lines {
                if line.length {
                    thread: Thread = { active = line[0] == '*'; }

                    line_start := "  thread #"; #const
                    i := line_start.length;
                    while i < line.length {
                        char := line[i++];
                        if char >= '0' && char <= '9' {
                            thread.number *= 10;
                            thread.number += char - '0';
                        }
                        else {
                            break;
                        }
                    }

                    i += 7;
                    first := true;
                    base := 10;
                    while i < line.length {
                        char := line[i++];
                        if first {
                            if char == '0' {
                                base = 16;
                                i++;
                                continue;
                            }
                        }

                        if char >= '0' && char <= '9' {
                            thread.id *= base;
                            thread.id += char - '0';
                        }
                        else if base == 16 {
                            if char >= 'A' && char <= 'F' {
                                thread.id *= 16;
                                thread.id += char - '7';
                            }
                            else if char >= 'a' && char <= 'f' {
                                thread.id *= 16;
                                thread.id += char - 'W';
                            }
                            else {
                                break;
                            }
                        }
                        else {
                            break;
                        }
                    }

                    add_to_array(&workspace.debugger_data.threads, thread);
                }
            }

            workspace.debugger_data.parse_status = DebuggerParseStatus.None;
        }
        case DebuggerParseStatus.Expression; {
            // Ex 1:
            // (BufferWindow) {
            //   cursor = 257
            //   line = 0
            //   start_line = 17
            //   buffer_index = 0
            //   hex_view = true
            //   start_byte = 32767
            //   previous = 0x0000000000000006
            // Ex 2:
            // (unsigned int) 1
            // Ex 3:
            // (BufferWindow *) 0x00000000004795e0
            // Ex 4 (Error case):
            // error: Couldn't apply expression side effects : Couldn't dematerialize a result variable: couldn't read its memory
            watch := &workspace.debugger_data.watches.array[workspace.debugger_data.watch_index];
            if !watch.parsing {
                watch.parsing = true;
                watch.parsing_type = true;
                watch.parsing_value = false;
                clear_debug_value(&watch.value);
            }

            if watch.parsing_type && (text.length == 0 || text[0] != '(') {
                watch.error = true;
                watch.parsing_type = false;
            }
            else {
                watch.error = false;
                allocate_strings(&text);
                if watch.parsing_type {
                    if !string_is_empty(watch.data) {
                        watch.type = { length = 0; data = null; }
                        free_allocation(watch.data.data);
                    }
                    if !string_is_empty(watch.value_data) {
                        free_allocation(watch.value_data.data);
                    }
                    watch.data = text;
                }
                else if watch.parsing_value {
                    watch.value_data = text;
                }

                i := 0;
                while i < text.length {
                    if watch.parsing_type {
                        char := text[i++];
                        if char == '(' {
                            watch.type.data = text.data + i;
                        }
                        else if char == ')' {
                            i++;
                            watch.parsing_type = false;
                            watch.parsing_value = true;
                        }
                        else {
                            watch.type.length++;
                        }
                    }
                    else if watch.parsing_value {
                        watch.value = parse_debug_value(text, &i);
                        watch.parsing_value = false;
                        break;
                    }
                }
            }

            if !watch.parsing_type && !watch.parsing_value {
                watch.parsing = false;
                workspace.debugger_data.parse_status = DebuggerParseStatus.None;
            }
        }
    }

    return true;
}

clear_start_of_line(string* text) {
    i := 0;
    while i < text.length {
        if !is_whitespace(text.data[i]) {
            break;
        }
        i++;
    }
    text.length -= i;
    text.data += i;
}

move_to_next_line(string* value) {
    i := 0;
    while i < value.length {
        char := value.data[i++];
        if char == '\n' {
            break;
        }
    }

    value.length -= i;
    value.data += i;
}

clear_debug_value(DebugValue* value) {
    if value.is_struct {
        each struct_field_value in value.struct_field_values {
            clear_debug_value(&struct_field_value.value);
        }

        free_allocation(value.struct_field_values.data);
        value.struct_field_values.length = 0;
    }

    if value.parent != null && value.parent.data.length > 0 {
        free_allocation(value.parent.data.data);
        value.parent.data = { length = 0; data = null; }
    }
}

DebugValue parse_debug_value(string text, int* index) {
    value: DebugValue;
    struct_field_value: StructFieldDebugValue;

    first := true;
    i := *index;

    while i < text.length {
        char := text[i];
        if first {
            if char == '{' {
                value.is_struct = true;
            }
            else {
                value.value = {
                    length = 1;
                    data = text.data + i;
                }
            }

            first = false;
        }
        else if !value.is_struct {
            if char == '\n' {
                trim_whitespace_from_end(&value.value);
                break;
            }
            else {
                value.value.length++;

                if value.value == "0x" {
                    value.is_pointer = true;
                }
            }
        }
        else {
            if struct_field_value.name.length == 0 {
                if char == '}' {
                    break;
                }
                else if !is_whitespace(char) {
                    struct_field_value.name = {
                        length = 1;
                        data = text.data + i;
                    }
                }
            }
            else if char == ' ' {
                i += 3;
                struct_field_value.value = parse_debug_value(text, &i);
                array_insert(&value.struct_field_values, struct_field_value, allocate, reallocate);

                struct_field_value.name = empty_string;
            }
            else {
                struct_field_value.name.length++;
            }
        }

        i++;
    }

    *index = i;

    return value;
}

add_to_array<T>(DynamicArray<T>* array, T value) {
    block_size := 10; #const
    if array.length == array.array.length {
        array_resize(&array.array, array.length + block_size, allocate, reallocate);
    }

    array.array[array.length++] = value;
}

trigger_load_watches(Workspace* workspace) {
    if !workspace.debugger_data.command_executing {
        data: JobData;
        data.pointer = workspace;
        queue_work(&low_priority_queue, load_watches, data);
    }
}

load_watches(int thread, JobData data) {
    workspace: Workspace* = data.pointer;

    each i in workspace.debugger_data.watches.length {
        evaluate_watch(workspace, i);
    }

    adjust_view_index(workspace);
}

evaluate_watch(Workspace* workspace, int index) {
    watch := workspace.debugger_data.watches.array[index];

    workspace.debugger_data = {
        parse_status = DebuggerParseStatus.Expression;
        watch_index = index;
    }

    command := temp_string("p ", watch.expression, "\n");
    send_command_to_debugger(workspace, command);

    while workspace.debugger_data.parse_status != DebuggerParseStatus.None {}
}

add_to_debugger_buffer(Workspace* workspace, string text) {
    line := add_text_to_end_of_buffer(&workspace.debugger_data.buffer, text, true);
    workspace.debugger_data.buffer_window.line = workspace.debugger_data.buffer.line_count - 1;
    workspace.debugger_data.buffer_window.cursor = line.length;
    adjust_start_line(&workspace.debugger_data.buffer_window);
    trigger_window_update();
}

clear_debugger_buffer_window(Workspace* workspace) {
    clear_buffer_and_window(&workspace.debugger_data.buffer, &workspace.debugger_data.buffer_window);
}

string get_debugger_buffer_title() {
    workspace := get_workspace();

    if workspace.debugger_data.failed_to_start {
        return "Failed to start lldb";
    }

    if !workspace.debugger_data.command_executing {
        return "Execution paused";
    }

    if workspace.debugger_data.exited {
        return format_string("lldb exited, code %", temp_allocate, workspace.debugger_data.exit_code);
    }

    return "Running debugger";
}
