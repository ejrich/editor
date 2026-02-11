#import freetype

default_font := "SourceCodePro"; #const

init_text() {
    error := FT_Init_FreeType(&library);
    if error {
        log("Unable to init FreeType with error code: %\n", error);
        exit_program(1);
    }

    if string_is_empty(settings.font) {
        settings.font = default_font;
    }

    set_font(settings.font);
}

deinit_text() {
    deinit_font();
    FT_Done_FreeType(library);
}

set_font(string font_name) {
    if font.handle deinit_font();

    load_font(font_name);
}

resize_font_glyphs() {
    texture := font.font_texture_start;
    while texture {
        adjust_texture_to_window(texture);
        each glyph in texture.glyphs {
            adjust_glyph_to_window(&glyph);
        }

        texture = texture.next;
    }
}

enum TextAlignment {
    Left;
    Center;
    Right;
}

bool is_font_ready(u32 size) {
    font_texture := load_font_texture(size);
    return font_texture != null;
}

render_text(u32 size, float x, float y, Vector4 color, Vector4 background_color, string format, TextAlignment alignment = TextAlignment.Left, Params args) {
    text := format_string(format, temp_allocate, args);
    render_text(text, size, x, y, color, background_color, alignment);
}

render_text(string text, u32 size, float x, float y, Vector4 color, Vector4 background_color, TextAlignment alignment = TextAlignment.Left) {
    if text.length == 0 return;

    // Load the font and texture
    font_texture := load_font_texture(size);
    if font_texture == null return;

    // Create the glyphs for the text string
    quad_data := temp_allocate_array<QuadInstanceData>(text.length);

    i, length, line_start, line_length := 0;
    x_start := x;
    y_start := y;
    glyphs := font_texture.glyphs;

    while i < text.length {
        char := text[i++];
        if char == '\n' {
            adjust_line_and_draw_background(font_texture, quad_data, line_start, line_length, alignment, x_start, x, y, background_color);
            line_start = length;
            line_length = 0;
            x = x_start;
            y -= font_texture.line_height;
            continue;
        }

        glyph := glyphs[char];
        if glyph.quad_dimensions.x > 0 && glyph.quad_dimensions.y > 0 {
            line_length++;
            x_pos := x + glyph.quad_adjust.x;
            y_pos := y - glyph.quad_adjust.y;

            quad_data[length++] = {
                color = color; position = { x = x_pos; y = y_pos; z = 0.0; } flags = QuadFlags.SingleChannel;
                width = glyph.quad_dimensions.x;
                height = glyph.quad_dimensions.y;
                bottom_left_texture_coord = glyph.bottom_left_texture_coord;
                top_right_texture_coord = glyph.top_right_texture_coord;
            }
        }

        x += font_texture.quad_advance;
    }

    if length == 0 return;

    adjust_line_and_draw_background(font_texture, quad_data, line_start, line_length, alignment, x_start, x, y, background_color);

    // Issue the draw call(s) for the characters
    draw_quad(quad_data.data, length, &font_texture.descriptor_set);
}

struct RenderLineState {
    syntax: Syntax*;
    next_escape_code: EscapeCode*;
    current_escape_code: EscapeCode*;
    current_word_buffer: Array<u8>;
    current_word_cursor: u32;
    in_char: bool;
    in_string: bool;
    in_multi_line_string: bool;
    in_single_line_comment: bool;
    in_multi_line_comment: bool;
}

RenderLineState init_render_line_state(Buffer* buffer) #inline {
    state: RenderLineState = {
        syntax = buffer.syntax;
        next_escape_code = buffer.escape_codes;
    }

    if state.syntax {
        current_word_buffer: Array<u8>[state.syntax.max_keyword_length];
        state.current_word_buffer = current_word_buffer;
    }

    return state;
}

evaluate_line_without_rendering(RenderLineState* state, BufferLine* line, u32 line_number) {
    if state.syntax {
        single_line_comment_length := state.syntax.single_line_comment.length;
        multi_line_comment_start_length := state.syntax.multi_line_comment_start.length;
        multi_line_comment_end_length := state.syntax.multi_line_comment_end.length;
        multi_line_string_boundary_length := state.syntax.multi_line_string_boundary.length;

        max_length := max(single_line_comment_length, multi_line_comment_start_length, multi_line_comment_end_length, multi_line_string_boundary_length);

        if max_length {
            escaping := false;
            i := 0;

            while i < line.length {
                char := get_char(line, i);
                if is_whitespace(char) {
                    escaping = false;
                }
                else if state.in_multi_line_string {
                    if char == '\\' {
                        escaping = !escaping;
                    }
                    else {
                        if !escaping && match_value_in_line(line, char, state.syntax.multi_line_string_boundary, i) {
                            state.in_multi_line_string = false;
                            i += multi_line_string_boundary_length - 1;
                        }
                        escaping = false;
                    }
                }
                else if state.in_string {
                    if char == '\\' {
                        escaping = !escaping;
                    }
                    else {
                        if !escaping && char == state.syntax.string_boundary {
                            state.in_string = false;
                        }

                        escaping = false;
                    }
                }
                else {
                    if state.in_multi_line_comment {
                        if match_value_in_line(line, char, state.syntax.multi_line_comment_end, i) {
                            state.in_multi_line_comment = false;
                            i += multi_line_comment_end_length - 1;
                        }
                    }
                    else if single_line_comment_length > 0 && match_value_in_line(line, char, state.syntax.single_line_comment, i) {
                        break;
                    }
                    else if multi_line_comment_start_length > 0 && match_value_in_line(line, char, state.syntax.multi_line_comment_start, i) {
                        state.in_multi_line_comment = true;
                        i += multi_line_comment_start_length - 1;
                    }
                    else if multi_line_string_boundary_length > 0 && match_value_in_line(line, char, state.syntax.multi_line_string_boundary, i) {
                        state.in_multi_line_string = true;
                        i += multi_line_string_boundary_length - 1;
                    }
                    else if char == state.syntax.string_boundary {
                        state.in_string = true;
                    }

                    escaping = false;
                }

                i++;
            }
        }
    }
    else if state.next_escape_code {
        while state.next_escape_code != null && state.next_escape_code.line == line_number {
            change_current_escape_code(state);
        }
    }

    reset_render_line_state(state);
}

u32 render_line(RenderLineState* state, BufferLine* line, float x, float y, u32 line_number, u32 digits, int cursor, bool render_cursor, float max_x, u32 lines_available, int visual_start, int visual_end, bool has_breakpoint, bool debug_line) {
    // Load the font and texture
    font_texture := load_font_texture(settings.font_size);
    if font_texture == null return 0;

    glyphs := font_texture.glyphs;
    x_start := x;

    // Draw the line background
    if cursor >= 0 {
        line_number_offset := (digits + 1) * font_texture.quad_advance;
        available_line_width := max_x - x - line_number_offset;

        full_line_width := line.length * font_texture.quad_advance;
        rendered_line_count := cast(u32, (full_line_width / available_line_width) + 1);

        draw_line_background(font_texture, x, y, max_x, rendered_line_count);
    }

    // Draw the breakpoint
    if has_breakpoint {
        breakpoint_quad: QuadInstanceData = {
            color = appearance.syntax_colors[cast(u8, SyntaxColor.Red)];
            flags = QuadFlags.Solid;
            position = {
                x = x + (font_texture.quad_advance * digits) / 2.0;
                y = y - font_texture.max_line_bearing_y / 3 + font_texture.line_height * 0.5;
                z = 0.1;
            }
            width = font_texture.quad_advance * digits;
            height = font_texture.line_height;
        }

        draw_quad(&breakpoint_quad, 1);
    }

    // Draw the debug pointer
    if debug_line {
        draw_cursor(x + font_texture.quad_advance * digits, y, appearance.syntax_colors[cast(u8, SyntaxColor.Yellow)]);
    }

    // Create the glyphs for the line number
    {
        line_number_quads: Array<QuadInstanceData>[digits];
        length := 0;
        digit_index := digits - 1;
        line_number_value := line_number;
        while line_number_value > 0 {
            digit := line_number_value % 10;

            glyph := glyphs[digit + '0'];
            x_pos := x + digit_index * font_texture.quad_advance + glyph.quad_adjust.x;
            y_pos := y - glyph.quad_adjust.y;

            line_number_quads[length++] = {
                color = appearance.line_number_color;
                position = { x = x_pos; y = y_pos; z = 0.0; }
                flags = QuadFlags.SingleChannel;
                width = glyph.quad_dimensions.x;
                height = glyph.quad_dimensions.y;
                bottom_left_texture_coord = glyph.bottom_left_texture_coord;
                top_right_texture_coord = glyph.top_right_texture_coord;
            }

            digit_index--;
            line_number_value /= 10;
        }

        x_start += (digits + 1) * font_texture.quad_advance;
        x = x_start;

        draw_quad(line_number_quads.data, length, &font_texture.descriptor_set);
    }

    return render_line(state, line, font_texture, x_start, x, y, max_x, line_number, lines_available, cursor, render_cursor, visual_start, visual_end);
}

u32 render_line(RenderLineState* state, BufferLine* line, float x, float y, float max_x, u32 line_number, u32 lines_available, int max_line_chars, int selected_line) {
    // Load the font and texture
    font_texture := load_font_texture(settings.font_size);
    if font_texture == null return 0;

    visual_start, visual_end := -1;
    if line_number - 1 == selected_line {
        visual_start = 0;
        visual_end = line.length;
    }

    return render_line(state, line, font_texture, x, x, y, max_x, line_number, lines_available, 0, false, visual_start, visual_end, max_line_chars);
}

draw_line_background(float x, float y, float max_x, u32 rendered_line_count = 1) {
    // Load the font and texture
    font_texture := load_font_texture(settings.font_size);
    if font_texture == null return;

    draw_line_background(font_texture, x, y, max_x, rendered_line_count);
}

render_line_with_cursor(string text, float x, float y, int cursor, float max_x, u32 lines_available = 1, bool render_cursor = true) {
    // Load the font and texture
    font_texture := load_font_texture(settings.font_size);
    if font_texture == null return;

    render_line_with_cursor(font_texture, text, x, x, y, cursor, render_cursor, max_x, lines_available);
}


struct Font {
    handle: FT_Face*;
    handle_mutex: Semaphore;
    char_count: int;
    font_texture_start: FontTexture*;
}

font: Font;

struct FontTexture {
    loaded: bool;
    size: u32;
    // Graphics objects
    texture: Texture;
    descriptor_set: DescriptorSet;
    glyphs: Array<Glyph>;
    // High level glpyh data in pixel count
    pixel_height: u32;
    pixel_max_bearing_y: u32;
    pixel_advance: u32;
    // High level glpyh data adjusted to size of window
    line_height: float;
    max_line_bearing_y: float;
    block_y_offset: float;
    quad_advance: float;
    next: FontTexture*;
}

struct Glyph {
    // Base dimensions, saved for changes in window size
    pixel_dimensions: Vector2;
    pixel_bearing: Vector2;
    // Dimensions used for rendering
    quad_dimensions: Vector2;
    quad_adjust: Vector2;
    // Measurements for addressing the texture
    x_offset: u32;
    bottom_left_texture_coord: Vector2;
    top_right_texture_coord: Vector2;
}

struct GlobalFontConfig {
    quad_advance: float;
    line_height: float;
    top_line_offset: float;
    first_line_offset: float;
    block_y_offset: float;
    max_lines_without_bottom_window: u32;
    max_lines_with_bottom_window: u32;
    bottom_window_max_lines: u32;
    max_chars_per_line: u32;
    max_chars_per_line_full: u32;
    divider_y: float;
    divider_height: float;
    divider_y_with_bottom_window: float;
    divider_height_with_bottom_window: float;
}

global_font_config: GlobalFontConfig;


#private

library: FT_Library*;

draw_line_background(FontTexture* font_texture, float x, float y, float max_x, u32 rendered_line_count) {
    current_line_quad: QuadInstanceData = {
        color = appearance.current_line_color;
        flags = QuadFlags.Solid;
        position = {
            x = (max_x + x) / 2;
            y = y - font_texture.max_line_bearing_y / 3 + font_texture.line_height * (1 - rendered_line_count / 2.0);
            z = 0.2;
        }
        width = max_x - x;
        height = rendered_line_count * font_texture.line_height;
    }

    draw_quad(&current_line_quad, 1);
}

u32 render_line(RenderLineState* state, BufferLine* line, FontTexture* font_texture, float x_start, float x, float y, float max_x, u32 line_number, u32 lines_available, int cursor, bool render_cursor, int visual_start, int visual_end, int max_line_chars = -1) {
    line_count: u32;
    text: string = { length = clamp(line.length, 0, line_buffer_length); data = line.data.data; }

    if state.syntax != null || state.next_escape_code != null || state.current_escape_code != null {
        line_count, x, y = render_line_with_cursor_and_state(font_texture, state, line, x_start, x, y, line_number, cursor, render_cursor, max_x, lines_available, visual_start, visual_end, max_line_chars = max_line_chars);
    }
    else {
        line_count, x, y = render_line_with_cursor(font_texture, text, x_start, x, y, cursor, render_cursor, max_x, lines_available, visual_start, visual_end, max_line_chars = max_line_chars);

        if line.child {
            child := line.child;
            index := text.length;
            while child {
                text = { length = child.length; data = child.data.data; }
                line_count, x, y = render_line_with_cursor(font_texture, text, x_start, x, y, cursor, render_cursor, max_x, lines_available, visual_start, visual_end, line_count, index, max_line_chars);

                index += child.length;
                child = child.next;
            }
        }
    }

    return line_count;
}

u32, float, float render_line_with_cursor(FontTexture* font_texture, string text, float x_start, float x, float y, int cursor, bool render_cursor, float max_x, u32 lines_available, int visual_start = -1, int visual_end = -1, u32 line_count = 1, u32 index = 0, int max_line_chars = -1) {
    // Create the glyphs for the text string
    glyphs := font_texture.glyphs;
    quad_data: Array<QuadInstanceData>[text.length];
    length := 0;

    each i in text.length {
        if max_line_chars != -1 && index >= max_line_chars {
            break;
        }

        if x + font_texture.quad_advance > max_x {
            if line_count >= lines_available
                break;

            x = x_start;
            y -= font_texture.line_height;
            line_count++;
        }

        font_color := appearance.font_color;
        if index == cursor && render_cursor {
            font_color = appearance.cursor_font_color;
            draw_cursor(x, y, appearance.cursor_color);
        }
        else if index >= visual_start && index <= visual_end {
            font_color = appearance.visual_font_color;
            draw_cursor(x, y, appearance.font_color);
        }

        char := text[i];
        if char < glyphs.length {
            glyph := glyphs[char];
            if glyph.quad_dimensions.x > 0 && glyph.quad_dimensions.y > 0 {
                x_pos := x + glyph.quad_adjust.x;
                y_pos := y - glyph.quad_adjust.y;

                quad_data[length++] = {
                    color = font_color;
                    position = { x = x_pos; y = y_pos; z = 0.0; }
                    flags = QuadFlags.SingleChannel;
                    width = glyph.quad_dimensions.x;
                    height = glyph.quad_dimensions.y;
                    bottom_left_texture_coord = glyph.bottom_left_texture_coord;
                    top_right_texture_coord = glyph.top_right_texture_coord;
                }
            }
        }

        x += font_texture.quad_advance;
        index++;
    }

    if cursor == index && render_cursor {
        draw_cursor(x, y, appearance.cursor_color);
    }

    // Issue the draw call(s) for the characters
    if length > 0
        draw_quad(quad_data.data, length, &font_texture.descriptor_set);

    return line_count, x, y;
}

u32, float, float render_line_with_cursor_and_state(FontTexture* font_texture, RenderLineState* state, BufferLine* line, float x_start, float x, float y, u32 line_number, int cursor, bool render_cursor, float max_x, u32 lines_available, int visual_start = -1, int visual_end = -1, u32 line_count = 1, int max_line_chars = -1) {
    // Create the glyphs for the text string
    glyphs := font_texture.glyphs;
    quad_data: Array<QuadInstanceData>[line.length];
    length, reset_state_after, skip, quads_to_draw := 0;
    escaping, max_quads_exceeded := false;

    single_line_comment_length, multi_line_comment_start_length, multi_line_comment_end_length, multi_line_string_boundary_length := 0;
    line_color_set: = false;
    line_color: Vector4;

    if state.syntax {
        single_line_comment_length = state.syntax.single_line_comment.length;
        multi_line_comment_start_length = state.syntax.multi_line_comment_start.length;
        multi_line_comment_end_length = state.syntax.multi_line_comment_end.length;
        multi_line_string_boundary_length = state.syntax.multi_line_string_boundary.length;

        if line.length > 0 && state.syntax.line_color_modifiers.length > 0 {
            each modifier in state.syntax.line_color_modifiers {
                if match_value_in_line(line, line.data.data[0], modifier.start, 0) {
                    line_color_set = true;
                    line_color = appearance.syntax_colors[cast(u8, modifier.color)];
                }
            }
        }
    }

    each i in line.length {
        if state.next_escape_code != null && state.next_escape_code.line == line_number && state.next_escape_code.column == i {
            change_current_escape_code(state);
        }

        if max_line_chars != -1 && i >= max_line_chars && !max_quads_exceeded {
            quads_to_draw = length;
            max_quads_exceeded = true;
        }

        if !max_quads_exceeded && x + font_texture.quad_advance > max_x {
            if line_count >= lines_available
                break;

            x = x_start;
            y -= font_texture.line_height;
            line_count++;
        }

        char := get_char(line, i);
        if char < glyphs.length {
            glyph := glyphs[char];

            // Set the color of the text
            font_color := appearance.font_color;
            drawing_cursor := false;
            if i == cursor && render_cursor {
                font_color = appearance.cursor_font_color;
                draw_cursor(x, y, appearance.cursor_color);
                drawing_cursor = true;
            }
            else if i >= visual_start && i <= visual_end {
                font_color = appearance.visual_font_color;
                draw_cursor(x, y, appearance.font_color);
                drawing_cursor = true;
            }
            else if state.current_escape_code {
                if state.current_escape_code.foreground_color.w {
                    font_color = state.current_escape_code.foreground_color;
                }
                if state.current_escape_code.background_color.w {
                    draw_cursor(x, y, state.current_escape_code.background_color);
                }
            }
            else if line_color_set {
                font_color = line_color;
            }
            else if state.in_single_line_comment || state.in_multi_line_comment {
                font_color = appearance.comment_color;
            }
            else if state.in_string || state.in_multi_line_string {
                font_color = appearance.string_color;
            }
            else if state.in_char {
                font_color = appearance.char_color;
            }

            // Handle state
            if state.syntax {
                if reset_state_after > 0 {
                    reset_state_after--;
                    if reset_state_after == 0 {
                        state.in_multi_line_string = false;
                        state.in_multi_line_comment = false;
                    }
                }
                else if skip {
                    skip--;
                }
                else if !line_color_set {
                    if is_whitespace(char) {
                        check_for_keyword(state, quad_data, length);
                        escaping = false;
                    }
                    else if state.in_multi_line_string {
                        if char == '\\' {
                            escaping = !escaping;
                        }
                        else {
                            if !escaping && match_value_in_line(line, char, state.syntax.multi_line_string_boundary, i) {
                                reset_state_after = multi_line_string_boundary_length - 1;
                            }
                            escaping = false;
                        }
                    }
                    else if state.in_string {
                        if char == '\\' {
                            escaping = !escaping;
                        }
                        else {
                            if !escaping && char == state.syntax.string_boundary {
                                state.in_string = false;
                            }

                            escaping = false;
                        }
                    }
                    else if state.in_char {
                        if char == '\\' {
                            escaping = !escaping;
                        }
                        else {
                            if !escaping && char == state.syntax.char_boundary {
                                state.in_char = false;
                            }

                            escaping = false;
                        }
                    }
                    else if !state.in_single_line_comment {
                        if state.in_multi_line_comment {
                            if match_value_in_line(line, char, state.syntax.multi_line_comment_end, i) {
                                reset_state_after = multi_line_comment_end_length - 1;
                            }
                        }
                        else if single_line_comment_length > 0 && match_value_in_line(line, char, state.syntax.single_line_comment, i) {
                            check_for_keyword(state, quad_data, length);
                            state.in_single_line_comment = true;
                            if !drawing_cursor {
                                font_color = appearance.comment_color;
                            }
                        }
                        else if multi_line_comment_start_length > 0 && match_value_in_line(line, char, state.syntax.multi_line_comment_start, i) {
                            check_for_keyword(state, quad_data, length);
                            state.in_multi_line_comment = true;
                            skip = multi_line_comment_start_length - 1;
                            if !drawing_cursor {
                                font_color = appearance.comment_color;
                            }
                        }
                        else if multi_line_string_boundary_length > 0 && match_value_in_line(line, char, state.syntax.multi_line_string_boundary, i) {
                            check_for_keyword(state, quad_data, length);
                            state.in_multi_line_string = true;
                            skip = multi_line_string_boundary_length - 1;
                            if !drawing_cursor {
                                font_color = appearance.string_color;
                            }
                        }
                        else if state.syntax != null && state.syntax.string_boundary > 0 && char == state.syntax.string_boundary {
                            check_for_keyword(state, quad_data, length);
                            state.in_string = true;
                            if !drawing_cursor {
                                font_color = appearance.string_color;
                            }

                        }
                        else if state.syntax != null && state.syntax.char_boundary > 0 && char == state.syntax.char_boundary {
                            check_for_keyword(state, quad_data, length);
                            state.in_char = true;
                            if !drawing_cursor {
                                font_color = appearance.char_color;
                            }

                        }
                        else if is_text_character(char) {
                            if state.current_word_cursor < state.current_word_buffer.length {
                                state.current_word_buffer[state.current_word_cursor] = char;
                            }
                            state.current_word_cursor++;
                        }
                        else {
                            check_for_keyword(state, quad_data, length);
                        }

                        escaping = false;
                    }
                }
            }

            if glyph.quad_dimensions.x > 0 && glyph.quad_dimensions.y > 0 {
                x_pos := x + glyph.quad_adjust.x;
                y_pos := y - glyph.quad_adjust.y;

                quad_data[length++] = {
                    color = font_color;
                    position = { x = x_pos; y = y_pos; z = 0.0; }
                    flags = QuadFlags.SingleChannel;
                    width = glyph.quad_dimensions.x;
                    height = glyph.quad_dimensions.y;
                    bottom_left_texture_coord = glyph.bottom_left_texture_coord;
                    top_right_texture_coord = glyph.top_right_texture_coord;
                }
            }
        }

        x += font_texture.quad_advance;
    }

    check_for_keyword(state, quad_data, length);

    if cursor == line.length && render_cursor {
        draw_cursor(x, y, appearance.cursor_color);
    }

    // Issue the draw call(s) for the characters
    if length > 0 {
        if max_quads_exceeded {
            length = quads_to_draw;
        }
        draw_quad(quad_data.data, length, &font_texture.descriptor_set);
    }

    reset_render_line_state(state);

    return line_count, x, y;
}

bool is_text_character(u8 char) {
    if char >= '0' && char <= '9' return true;
    if char >= 'A' && char <= 'Z' return true;
    if char >= 'a' && char <= 'z' return true;
    if char == '_' return true;

    return false;
}

check_for_keyword(RenderLineState* state, Array<QuadInstanceData> quad_data, int length) {
    if state.current_word_cursor > 0 {
        if state.current_word_cursor <= state.syntax.max_keyword_length {
            current_word: string = {
                length = state.current_word_cursor;
                data = state.current_word_buffer.data;
            }
            each keyword in state.syntax.keywords {
                if keyword.value == current_word {
                    color := appearance.syntax_colors[cast(u8, keyword.color)];
                    each j in 1..keyword.value.length {
                        quad_data[length - j].color = color;
                    }
                    break;
                }
            }
        }
        state.current_word_cursor = 0;
    }
}

bool match_value_in_line(BufferLine* line, u8 char, string value, int i) {
    matched := false;
    if char == value[0] && i + value.length <= line.length {
        matched = true;
        each j in 1..value.length - 1 {
            next_char := get_char(line, i + j);
            if next_char != value[j] {
                matched = false;
                break;
            }
        }
    }

    return matched;
}

reset_render_line_state(RenderLineState* state) {
    state.current_word_cursor = 0;
    state.in_char = false;
    state.in_string = false;
    state.in_single_line_comment = false;
}

change_current_escape_code(RenderLineState* state) {
    state.current_escape_code = state.next_escape_code;
    if state.current_escape_code {
        if state.current_escape_code.reset {
            state.current_escape_code = null;
        }
        state.next_escape_code = state.next_escape_code.next;
    }
}

adjust_line_and_draw_background(FontTexture* font_texture, Array<QuadInstanceData> array, int start_index, int length, TextAlignment alignment, float x0, float x1, float y, Vector4 background_color) {
    x_adjust: float;
    switch alignment {
        case TextAlignment.Center; x_adjust = (x1 - x0) / 2;
        case TextAlignment.Right;  x_adjust = x1 - x0;
    }

    if x_adjust != 0.0 {
        each i in start_index..start_index + length - 1 {
            array[i].position.x -= x_adjust;
        }
    }

    if background_color.w > 0.0 {
        background: QuadInstanceData = {
            color = background_color;
            position = { x = (x0 + x1) / 2 - x_adjust; y = y + font_texture.block_y_offset; z = 0.1; }
            flags = QuadFlags.Solid;
            width = x1 - x0;
            height = font_texture.line_height;
        }

        draw_quad(&background, 1);
    }
}

draw_cursor(float x, float y, Vector4 color) {
    x_pos := x + global_font_config.quad_advance / 2.0;
    y_pos := y + global_font_config.block_y_offset;

    cursor_quad: QuadInstanceData = {
        color = color;
        position = { x = x_pos; y = y_pos; z = 0.1; }
        flags = QuadFlags.Solid;
        width = global_font_config.quad_advance;
        height = global_font_config.line_height;
    }

    draw_quad(&cursor_quad, 1);
}

FontTexture* load_font_texture(u32 size) {
    if font.font_texture_start == null {
        new_font_texture := new<FontTexture>();
        new_font_texture.size = size;

        if compare_exchange(&font.font_texture_start, new_font_texture, null) == null {
            data: JobData;
            data.pointer = new_font_texture;
            queue_work(&low_priority_queue, load_font_texture_job, data);
            return null;
        }

        free_allocation(new_font_texture);
    }

    font_texture := font.font_texture_start;
    while font_texture {
        if font_texture.size == size {
            if font_texture.loaded
                return font_texture;

            // The texture is currently being loaded
            return null;
        }
        if font_texture.next == null {
            new_font_texture := new<FontTexture>();
            new_font_texture.size = size;

            if compare_exchange(&font_texture.next, new_font_texture, null) == null {
                data: JobData;
                data.pointer = new_font_texture;
                queue_work(&low_priority_queue, load_font_texture_job, data);
                return null;
            }

            free_allocation(new_font_texture);
        }

        font_texture = font_texture.next;
    }

    return null;
}

load_font(string name) {
    font_path := temp_string(get_program_directory(), "/fonts/", name, ".ttf");
    success, font_file := read_file(font_path, allocate);
    if !success {
        log("Font '%' at path '%' not found\n", name, font_path);
        exit_program(1);
    }

    error := FT_New_Memory_Face(library, font_file.data, font_file.length, 0, &font.handle);
    if error {
        log("Error creating font face '%', code '%'\n", name, error);
        exit_program(1);
    }

    char_index: u32;
    character := FT_Get_First_Char(font.handle, &char_index);
    while char_index != 0 && character < 128 {
        character = FT_Get_Next_Char(font.handle, character, &char_index);
    }

    font.char_count = character + 1;

    create_semaphore(&font.handle_mutex, initial_value = 1);
}

deinit_font() {
    FT_Done_Face(font.handle);

    texture := font.font_texture_start;
    while texture {
        destroy_texture(texture.texture);
        destroy_descriptor_set(texture.descriptor_set);
        texture = texture.next;
    }
}

load_font_texture_job(int index, JobData data) {
    texture: FontTexture* = data.pointer;

    size := texture.size;

    // Load the data for each glyph
    texture_width, texture_height, char_index: u32;
    array_resize(&texture.glyphs, font.char_count, allocate, reallocate);

    font_handle := font.handle;
    semaphore_wait(&font.handle_mutex);

    char_height := size * 3;

    FT_Set_Pixel_Sizes(font_handle, 0, char_height);

    character := FT_Get_First_Char(font_handle, &char_index);
    while char_index != 0 && character < 128 {
        FT_Load_Glyph(font_handle, char_index, FT_LoadFlags.FT_LOAD_RENDER);

        glyph_slot := *font_handle.glyph;
        glyph: Glyph = {
            pixel_dimensions = { x = cast(float, glyph_slot.bitmap.width); y = cast(float, glyph_slot.bitmap.rows); }
            pixel_bearing = { x = cast(float, glyph_slot.bitmap_left); y = cast(float, glyph_slot.bitmap_top); }
            x_offset = texture_width;
        }
        adjust_glyph_to_window(&glyph);

        texture_width += glyph_slot.bitmap.width + 2;
        if texture_height < glyph_slot.bitmap.rows
            texture_height = glyph_slot.bitmap.rows;

        if glyph_slot.bitmap_top > 0 && texture.pixel_max_bearing_y < glyph_slot.bitmap_top
            texture.pixel_max_bearing_y = glyph_slot.bitmap_top;

        advance := glyph_slot.advance.x >> 6;
        if advance > 0 && texture.pixel_advance < advance
            texture.pixel_advance = advance;

        texture.glyphs[character] = glyph;
        character = FT_Get_Next_Char(font_handle, character, &char_index);
    }

    texture.pixel_height = texture_height + 5;

    adjust_texture_to_window(texture);

    // Create the buffer for the texture
    image_buffer := allocate(texture_width * texture_height);
    defer free_allocation(image_buffer);

    character = FT_Get_First_Char(font.handle, &char_index);
    while char_index != 0 && character < 128 {
        FT_Load_Glyph(font_handle, char_index, FT_LoadFlags.FT_LOAD_RENDER);

        glyph_bitmap := font_handle.glyph.bitmap;
        glyph := texture.glyphs[character];

        each i in glyph_bitmap.rows {
            offset := cast(u32, glyph.x_offset) + i * texture_width;
            memory_copy(image_buffer + offset, glyph_bitmap.buffer + i * glyph_bitmap.width, glyph_bitmap.width);
        }

        // Adjust glyph dimensions
        texture.glyphs[character] = {
            bottom_left_texture_coord = { x = 1.0 * glyph.x_offset / texture_width; y = 0.0; }
            top_right_texture_coord = {
                x = (glyph.pixel_dimensions.x + glyph.x_offset) / texture_width;
                y = glyph.pixel_dimensions.y / texture_height;
            }
        }

        character = FT_Get_Next_Char(font_handle, character, &char_index);
    }

    semaphore_release(&font.handle_mutex);

    texture.texture = create_texture(image_buffer, texture_width, texture_height, 1, index, 1);
    texture.descriptor_set = create_quad_descriptor_set(texture.texture);
    texture.loaded = true;

    trigger_window_update();
}

adjust_texture_to_window(FontTexture* texture) {
    texture.line_height = cast(float, texture.pixel_height) / settings.window_height;
    texture.max_line_bearing_y = cast(float, texture.pixel_max_bearing_y) / settings.window_height;
    texture.quad_advance = cast(float, texture.pixel_advance) / settings.window_width;
    texture.block_y_offset = texture.line_height / 2.0 - texture.max_line_bearing_y / 3.0;

    if texture.size == settings.font_size {
        total_lines_excluding_command := cast(u32, 2.0 / texture.line_height) - 2;
        max_lines := total_lines_excluding_command - 1;
        bottom_window_lines := (total_lines_excluding_command / 4) - 1;
        main_window_lines_with_bottom_window := total_lines_excluding_command - bottom_window_lines - 2;
        top_line_offset := texture.line_height - texture.max_line_bearing_y / 3.0;

        global_font_config = {
            quad_advance = texture.quad_advance;
            line_height = texture.line_height;
            top_line_offset = top_line_offset;
            first_line_offset = top_line_offset + texture.line_height;
            block_y_offset = texture.block_y_offset;
            max_lines_without_bottom_window = max_lines;
            max_lines_with_bottom_window = main_window_lines_with_bottom_window;
            bottom_window_max_lines = bottom_window_lines;
            max_chars_per_line = cast(u32, 1.0 / texture.quad_advance);
            max_chars_per_line_full = cast(u32, 2.0 / texture.quad_advance);
            divider_y = texture.line_height / 2.0 + texture.max_line_bearing_y / 2.5;
            divider_height = texture.line_height * max_lines;
            divider_y_with_bottom_window =  texture.line_height * (bottom_window_lines + 2) / 2.0 + texture.max_line_bearing_y / 2.5;
            divider_height_with_bottom_window = texture.line_height * main_window_lines_with_bottom_window;
        }
    }
}

adjust_glyph_to_window(Glyph* glyph) {
    glyph.quad_dimensions = {
        x = glyph.pixel_dimensions.x / settings.window_width;
        y = glyph.pixel_dimensions.y / settings.window_height;
    }
    glyph.quad_adjust = {
        x = (glyph.pixel_dimensions.x / 2 + glyph.pixel_bearing.x) / settings.window_width;
        y = (glyph.pixel_dimensions.y / 2 - glyph.pixel_bearing.y) / settings.window_height;
    }
}
