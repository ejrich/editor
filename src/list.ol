start_list_mode(string title) {
    list_title = title;
    display_list = true;
    start_list_command_mode();
}

enter_list_browse_mode() {
    browsing = true;
}

exit_list_mode() {
    display_list = false;
}

bool draw_list() {
    if !display_list || !is_font_ready(settings.font_size) return false;

    draw_divider(true);

    draw_list_title();

    draw_list_entries();

    draw_selected_item();

    draw_command();

    return true;
}

bool handle_list_press(PressState state, KeyCode code, ModCode mod, string char) {
    if !display_list || !browsing return false;

    switch code {
        case KeyCode.Escape; {
            display_list = false;
            browsing = false;
            exit_command_mode();
        }
        case KeyCode.I; {
            browsing = false;
        }
    }

    // TODO Implement browsing
    return true;
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
    render_text(list_title, settings.font_size, 0.0, y, appearance.font_color, vec4(), TextAlignment.Center);
}

draw_list_entries() {
    // TODO Implement
    initial_y := 1.0 - global_font_config.first_line_offset;
}

draw_selected_item() {
    // TODO Implement
}

display_list := false;
browsing := false;
list_title: string;
