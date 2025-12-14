start_list_mode(string title) {
    list_title = title;
    display_list = true;
    start_list_command_mode();
}

bool draw_list() {
    if !display_list || !is_font_ready(settings.font_size) return false;

    draw_divider(true);

    draw_list_title();

    draw_command();

    return true;
}

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

#private

display_list := false;
list_title: string;
