start_list_mode(string title, ListEntries entries, Callback load_entry, ListFilter filter, ListEntrySelect select = null, ListCleanup cleanup = null) {
    list = {
        displaying = true;
        browsing = false;
        title = title;
        selected_index = 0;
        entries = entries;
        load_entry = load_entry;
        filter = filter;
        select = select;
        cleanup = cleanup;
    }
    start_list_command_mode();
}

filter_list(string filter) {
    list.filter(filter);
}

enter_list_browse_mode() {
    list.browsing = true;
}

bool draw_list() {
    if !list.displaying || !is_font_ready(settings.font_size) return false;

    draw_divider(true);

    draw_list_title();

    draw_list_entries();

    draw_selected_entry();

    draw_command(!list.browsing);

    return true;
}

bool handle_list_press(PressState state, KeyCode code, ModCode mod, string char) {
    if !list.displaying || !list.browsing return false;

    switch code {
        case KeyCode.Enter; {
            if list.select != null && !string_is_empty(selected_entry.key) {
                list.select(selected_entry.key);
                list = {
                    displaying = false;
                    browsing = false;
                }
                exit_command_mode();
            }
        }
        case KeyCode.Up; {
            change_list_select(1);
        }
        case KeyCode.Down; {
            change_list_select(-1);
        }
    }

    handle_keybind_event(code, mod, true);
    return true;
}

bool exit_list_mode() {
    if !list.displaying || !list.browsing return false;

    list = {
        displaying = false;
        browsing = false;
    }
    free_buffer(selected_entry.buffer);
    exit_command_mode();
    if list.cleanup != null {
        list.cleanup();
    }

    return true;
}

bool change_list_select(int change) {
    if !list.displaying || !list.browsing return false;

    new_index := list.selected_index + change;

    entries := list.entries();
    if new_index >= entries.length {
        new_index = 0;
    }
    else if new_index < 0 {
        new_index = entries.length;
    }

    list.selected_index = new_index;
    return true;
}

bool change_list_cursor(bool append, bool boundary) {
    if !list.displaying || !list.browsing return false;

    move_command_cursor(append, boundary);
    list.browsing = false;
    return true;
}

struct ListEntry {
    key: string;
    display: string;
}

struct SelectedEntry {
    key: string;
    buffer: Buffer*;
    start_line: int;
}

#private

draw_list_title() {
    initial_y := 1.0 - global_font_config.first_line_offset;

    info_quad: QuadInstanceData = {
        color = appearance.current_line_color;
        position = {
            x = 0.0;
            y = initial_y - global_font_config.max_lines_without_run_window * global_font_config.line_height + global_font_config.block_y_offset;
            z = 0.2;
        }
        flags = QuadFlags.Solid;
        width = 2.0;
        height = global_font_config.line_height;
    }

    draw_quad(&info_quad, 1);

    y := initial_y - global_font_config.line_height * global_font_config.max_lines_without_run_window;
    render_text(list.title, settings.font_size, 0.0, y, appearance.font_color, vec4(), TextAlignment.Center);
}

draw_list_entries() {
    if list.entries == null return;

    initial_y := 1.0 - global_font_config.first_line_offset - (global_font_config.max_lines_without_run_window - 1) * global_font_config.line_height + global_font_config.block_y_offset;

    entries := list.entries();

    if entries.length == 0 {
        free_buffer(selected_entry.buffer);
        selected_entry = {
            key = empty_string;
            buffer = null;
            start_line = 0;
        }
        return;
    }

    list.selected_index = clamp(list.selected_index, 0, entries.length - 1);
    if entries[list.selected_index].key != selected_entry.key {
        free_buffer(selected_entry.buffer);
        selected_entry = {
            key = entries[list.selected_index].key;
            buffer = null;
            start_line = 0;
        }

        load_entry_data: JobData;
        load_entry_data.pointer = &selected_entry;
        queue_work(&low_priority_queue, list.load_entry, load_entry_data);
    }

    entries_to_display := clamp(entries.length, 0, global_font_config.max_lines_without_run_window);
    max_chars_per_line := global_font_config.max_chars_per_line - 4;
    x := -1.0 + global_font_config.quad_advance * 2;

    each i in entries_to_display {
        entry := entries[i];
        if entry.display.length > max_chars_per_line {
            entry.display.length = max_chars_per_line;
        }

        y := initial_y + global_font_config.line_height * i;
        if i == list.selected_index {
            draw_line_background(-1.0, y, 0.0);
        }
        render_text(entry.display, settings.font_size, x, y, appearance.font_color, vec4());
    }

}

draw_selected_entry() {
    if selected_entry.buffer == null return;

    line_index := 0;
    available_lines_to_render := global_font_config.max_lines_without_run_window;
    line := selected_entry.buffer.lines;

    y := 1.0 - global_font_config.first_line_offset;

    while line != null && available_lines_to_render > 0 {
        if line_index >= selected_entry.start_line {
            lines := render_line(line, 0.0, y, 1.0, available_lines_to_render);
            y -= global_font_config.line_height * lines;
            available_lines_to_render -= lines;
        }

        line = line.next;
        line_index++;
    }
}

struct ListData {
    displaying := false;
    browsing := false;
    title: string;
    selected_index: int;
    entries: ListEntries;
    load_entry: Callback;
    filter: ListFilter;
    select: ListEntrySelect;
    cleanup: ListCleanup;
}

interface Array<ListEntry> ListEntries()
interface ListFilter(string filter)
interface ListEntrySelect(string key)
interface ListCleanup()

list: ListData;
selected_entry: SelectedEntry;
