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

u32 render_line(string text, float x, float y, u32 line_number, u32 digits, int cursor, bool render_cursor, float max_x, u32 lines_available, int visual_start, int visual_end) {
    // Load the font and texture
    font_texture := load_font_texture(settings.font_size);
    if font_texture == null return 0;

    glyphs := font_texture.glyphs;
    x_start := x;

    // Draw the line background
    if cursor >= 0 {
        line_number_offset := (digits + 1) * font_texture.quad_advance;
        available_line_width := max_x - x - line_number_offset;

        full_line_width := text.length * font_texture.quad_advance;
        rendered_line_count := cast(u32, (full_line_width / available_line_width) + 1);

        current_line_quad: QuadInstanceData = {
            color = appearance.current_line_color;
            flags = QuadFlags.Solid;
            position = {
                x = (max_x + x) / 2;
                y = y - font_texture.max_line_bearing_y / 3 + font_texture.line_height * (1 - rendered_line_count / 2.0);
                z = 0.2; }
            width = max_x - x;
            height = rendered_line_count * font_texture.line_height;
        }

        draw_quad(&current_line_quad, 1);
    }

    // Create the glyphs for the line number
    {
        line_number_quads: Array<QuadInstanceData>[digits];
        length := 0;
        digit_index := digits - 1;
        while line_number > 0 {
            digit := line_number % 10;

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
            line_number /= 10;
        }

        x_start += (digits + 1) * font_texture.quad_advance;
        x = x_start;

        draw_quad(line_number_quads.data, length, &font_texture.descriptor_set);
    }

    return render_line_with_cursor(font_texture, text, x, y, cursor, render_cursor, max_x, lines_available, visual_start, visual_end);
}

render_line_with_cursor(string text, float x, float y, int cursor, float max_x, u32 lines_available = 1) {
    // Load the font and texture
    font_texture := load_font_texture(settings.font_size);
    if font_texture == null return;

    render_line_with_cursor(font_texture, text, x, y, cursor, true, max_x, lines_available);
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
    first_line_offset: float;
    block_y_offset: float;
    max_lines: u32;
    max_chars_per_line: u32;
    max_chars_per_line_full: u32;
    divider_y: float;
    divider_height: float;
}

global_font_config: GlobalFontConfig;


#private

library: FT_Library*;

u32 render_line_with_cursor(FontTexture* font_texture, string text, float x, float y, int cursor, bool render_cursor, float max_x, u32 lines_available, int visual_start = -1, int visual_end = -1) {
    // Create the glyphs for the text string
    glyphs := font_texture.glyphs;
    x_start := x;
    line_count := 1;
    quad_data: Array<QuadInstanceData>[text.length];
    i, length := 0;

    while i < text.length {
        if x + font_texture.quad_advance > max_x {
            if line_count >= lines_available
                break;

            x = x_start;
            y -= font_texture.line_height;
            line_count++;
        }

        font_color := appearance.font_color;
        if i == cursor && render_cursor {
            font_color = appearance.cursor_font_color;
            draw_cursor(x, y, appearance.cursor_color);
        }
        else if i >= visual_start && i <= visual_end {
            font_color = appearance.visual_font_color;
            draw_cursor(x, y, appearance.font_color);
        }

        char := text[i];
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

        x += font_texture.quad_advance;
        i++;
    }

    if cursor == text.length && render_cursor {
        draw_cursor(x, y, appearance.cursor_color);
    }

    // Issue the draw call(s) for the characters
    if length > 0
        draw_quad(quad_data.data, length, &font_texture.descriptor_set);

    return line_count;
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
}

adjust_texture_to_window(FontTexture* texture) {
    texture.line_height = cast(float, texture.pixel_height) / settings.window_height;
    texture.max_line_bearing_y = cast(float, texture.pixel_max_bearing_y) / settings.window_height;
    texture.quad_advance = cast(float, texture.pixel_advance) / settings.window_width;
    texture.block_y_offset = texture.line_height / 2.0 - texture.max_line_bearing_y / 3.0;

    if texture.size == settings.font_size {
        max_lines := cast(u32, 2.0 / texture.line_height) - 2;

        global_font_config = {
            quad_advance = texture.quad_advance;
            line_height = texture.line_height;
            first_line_offset = texture.line_height - texture.max_line_bearing_y / 3.0;
            block_y_offset = texture.block_y_offset;
            max_lines = max_lines;
            max_chars_per_line = cast(u32, 1.0 / texture.quad_advance);
            max_chars_per_line_full = cast(u32, 2.0 / texture.quad_advance);
            divider_y = texture.line_height + texture.max_line_bearing_y / 4.0;
            divider_height = texture.line_height * max_lines + texture.max_line_bearing_y / 2.0;
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
