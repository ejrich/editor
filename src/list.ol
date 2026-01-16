start_list_mode(string title, ListEntries entries, ListTotal total, Callback load_entry, ListFilter filter, ListEntrySelect select = null, ListEntryAction action = null, ListCleanup cleanup = null, string initial_value = empty_string) {
    list = {
        displaying = true;
        browsing = false;
        title = title;
        selected_index = 0;
        entries = entries;
        total = total;
        load_entry = load_entry;
        filter = filter;
        select = select;
        action = action;
        cleanup = cleanup;
    }
    start_list_command_mode(initial_value);
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
            select_list_entry();
        }
        case KeyCode.Tab; {
            if list.action != null && !string_is_empty(selected_entry.key) {
                list.action(selected_entry.key);
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

    if selected_entry.can_free_buffer {
        free_buffer(selected_entry.buffer);
    }
    selected_entry = {
        key = empty_string;
        buffer = null;
        can_free_buffer = true;
        start_line = 0;
    }

    exit_command_mode();
    if list.cleanup != null {
        list.cleanup();
    }

    return true;
}

select_list_entry() {
    if !list.displaying return;

    if list.select != null && !string_is_empty(selected_entry.key) {
        list.select(selected_entry.key);
        list = {
            displaying = false;
            browsing = false;
        }
        exit_command_mode();
    }
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

bool change_selected_entry_start_line(int change) {
    if !list.displaying return false;

    if selected_entry.buffer {
        selected_entry.start_line = clamp(selected_entry.start_line + change, 0, selected_entry.buffer.line_count - 1);
    }

    return true;
}

struct ListEntry {
    key: string;
    display: string;
}

struct SelectedEntry {
    key: string;
    buffer: Buffer*;
    can_free_buffer: bool;
    start_line: int;
    selected_line: int;
}

#private

draw_list_title() {
    initial_y := 1.0 - global_font_config.first_line_offset;

    info_quad: QuadInstanceData = {
        color = appearance.current_line_color;
        position = {
            x = 0.0;
            y = initial_y - global_font_config.max_lines_without_bottom_window * global_font_config.line_height + global_font_config.block_y_offset;
            z = 0.2;
        }
        flags = QuadFlags.Solid;
        width = 2.0;
        height = global_font_config.line_height;
    }

    draw_quad(&info_quad, 1);

    y := initial_y - global_font_config.line_height * global_font_config.max_lines_without_bottom_window;
    render_text(list.title, settings.font_size, 0.0, y, appearance.font_color, vec4(), TextAlignment.Center);
}

draw_list_entries() {
    if list.entries == null return;

    initial_y := 1.0 - global_font_config.first_line_offset - global_font_config.max_lines_without_bottom_window * global_font_config.line_height;

    entries := list.entries();
    total_entries := list.total();

    x := -1.0 + global_font_config.quad_advance * 2;
    if total_entries == 0 {
        render_text("0 / 0 Results", settings.font_size, x, initial_y, appearance.font_color, vec4());
    }
    else {
        render_text(settings.font_size, x, initial_y, appearance.font_color, vec4(), "% / % Results", entries.length, total_entries);
    }

    initial_y += global_font_config.line_height;

    if entries.length == 0 {
        if selected_entry.can_free_buffer {
            free_buffer(selected_entry.buffer);
        }
        selected_entry = {
            key = empty_string;
            buffer = null;
            can_free_buffer = true;
            start_line = 0;
            selected_line = -1;
        }
        return;
    }

    list.selected_index = clamp(list.selected_index, 0, entries.length - 1);
    if entries[list.selected_index].key != selected_entry.key {
        if selected_entry.can_free_buffer {
            free_buffer(selected_entry.buffer);
        }
        selected_entry = {
            key = entries[list.selected_index].key;
            buffer = null;
            can_free_buffer = true;
            start_line = 0;
            selected_line = -1;
        }

        load_entry_data: JobData;
        load_entry_data.pointer = &selected_entry;
        queue_work(&low_priority_queue, list.load_entry, load_entry_data);
    }

    entries_to_display, start_index: int;
    if entries.length > global_font_config.max_lines_without_bottom_window {
        entries_to_display = global_font_config.max_lines_without_bottom_window;
        if list.selected_index < global_font_config.max_lines_without_bottom_window {
            start_index = 0;
        }
        else {
            start_index = list.selected_index - global_font_config.max_lines_without_bottom_window + 1;
        }
    }
    else {
        entries_to_display = entries.length;
        start_index = 0;
    }
    max_chars_per_line := global_font_config.max_chars_per_line - 4;

    each i in entries_to_display {
        index := i + start_index;
        entry := entries[index];
        if entry.display.length > max_chars_per_line {
            entry.display.length = max_chars_per_line;
        }

        y := initial_y + global_font_config.line_height * i;
        if index == list.selected_index {
            draw_line_background(-1.0, y, 0.0);
        }
        render_text(entry.display, settings.font_size, x, y, appearance.font_color, vec4());
    }
}

draw_selected_entry() {
    if selected_entry.buffer == null return;

    line_index := 0;
    available_lines_to_render := global_font_config.max_lines_without_bottom_window;
    line := selected_entry.buffer.lines;

    y := 1.0 - global_font_config.first_line_offset;

    while line != null && available_lines_to_render > 0 {
        if line_index >= selected_entry.start_line {
            lines := render_line(line, 0.0, y, 1.0, available_lines_to_render, global_font_config.max_chars_per_line, line_index == selected_entry.selected_line);
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
    total: ListTotal;
    load_entry: Callback;
    filter: ListFilter;
    select: ListEntrySelect;
    action: ListEntryAction;
    cleanup: ListCleanup;
}

interface Array<ListEntry> ListEntries()
interface int ListTotal()
interface ListFilter(string filter)
interface ListEntrySelect(string key)
interface ListEntryAction(string key)
interface ListCleanup()

list: ListData;
selected_entry: SelectedEntry;
