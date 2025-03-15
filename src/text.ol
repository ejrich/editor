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

enum TextAlignment {
    Left;
    Center;
    Right;
}

render_text(u32 size, Vector3 position, Vector4 color, string format, TextAlignment alignment = TextAlignment.Left, Params args) {
    text := format_string(format, temp_allocate, args);
    render_text(text, size, position, color, alignment);
}

render_text(string text, u32 size, Vector3 position, Vector4 color, TextAlignment alignment = TextAlignment.Left) {
    if text.length == 0 return;

    // Load the font and texture
    font_texture := load_font_texture(size);
    if font_texture == null return;

    // Create the glyphs for the text string
    quad_data: Array<QuadInstanceData>[text.length];
    i, length, line_start, line_length := 0;
    x := position.x;
    y := position.y;
    glyphs := font_texture.glyphs;

    while i < text.length {
        char := text[i++];
        if char == '\n' {
            adjust_line(quad_data, line_start, line_length, alignment, position.x, x);
            line_start = length;
            line_length = 0;
            x = position.x;
            y -= font_texture.y_adjust / settings.window_height;
            continue;
        }

        glyph := glyphs[char];
        if glyph.width > 0 && glyph.height > 0 {
            line_length++;
            x_pos := x + (glyph.width / 2 + glyph.bearing.x) / settings.window_width;
            y_pos := y - (glyph.height / 2 - glyph.bearing.y) / settings.window_height;

            quad_data[length++] = {
                color = color; position = { x = x_pos; y = y_pos; z = position.z; } single_channel = 1;
                width = glyph.width / settings.window_height; height = glyph.height / settings.window_height;
                bottom_left_texture_coord = glyph.bottom_left_texture_coord; top_right_texture_coord = glyph.top_right_texture_coord;
            }
        }

        x += glyph.advance / settings.window_width;
    }

    if length == 0 return;

    adjust_line(quad_data, line_start, line_length, alignment, position.x, x);

    // Issue the draw call(s) for the characters
    draw_quad(quad_data.data, length, &font_texture.descriptor_set);
}

render_text_box(string text, u32 size, Vector3 position, Vector4 color, float max_width) {
    if text.length == 0 return;

    // Load the font and texture
    font_texture := load_font_texture(size);
    if font_texture == null return;

    // Create the glyphs for the text string
    quad_data: Array<QuadInstanceData>[text.length];
    index, length, first_rendered_char := 0;
    x := position.x;
    y := position.y;
    width := 0.0;
    glyphs := font_texture.glyphs;

    while index < text.length {
        char := text[index++];
        if char == '\n'
            break; // @Future allow multi-line text boxes

        glyph := glyphs[char];
        if glyph.width > 0 && glyph.height > 0 {
            x_pos := x + (glyph.width / 2 + glyph.bearing.x) / settings.window_width;
            y_pos := y - (glyph.height / 2 - glyph.bearing.y) / settings.window_height;

            quad_data[length++] = {
                color = color; position = { x = x_pos; y = y_pos; z = position.z; } single_channel = 1;
                width = glyph.width / settings.window_width; height = glyph.height / settings.window_height;
                bottom_left_texture_coord = glyph.bottom_left_texture_coord; top_right_texture_coord = glyph.top_right_texture_coord;
            }
        }

        advance := glyph.advance / settings.window_width;
        x += advance;
        width += advance;
        if width > max_width {
            first_rendered_char++;
            width -= quad_data[first_rendered_char].position.x - quad_data[first_rendered_char - 1].position.x;
        }
    }

    if length == 0 return;

    // Issue the draw call(s) for the characters
    if first_rendered_char > 0 {
        x_adjust := quad_data[first_rendered_char].position.x - quad_data[0].position.x;
        each i in first_rendered_char..length - 1 {
            quad_data[i].position.x -= x_adjust;
        }
    }

    draw_quad(quad_data.data + first_rendered_char, length - first_rendered_char, &font_texture.descriptor_set);
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
    y_adjust: float;
    texture: Texture;
    descriptor_set: DescriptorSet;
    glyphs: Array<Glyph>;
    next: FontTexture*;
}

struct Glyph {
    width: float;
    height: float;
    bearing: Vector2;
    advance: float;
    x_offset: u32;
    bottom_left_texture_coord: Vector2;
    top_right_texture_coord: Vector2;
}


#private

library: FT_Library*;

adjust_line(Array<QuadInstanceData> array, int start_index, int length, TextAlignment alignment, float x0, float x1) {
    x_adjust: float;
    switch alignment {
        case TextAlignment.Left;   return;
        case TextAlignment.Center; x_adjust = (x1 - x0) / 2;
        case TextAlignment.Right;  x_adjust = x1 - x0;
    }

    each i in start_index..start_index + length - 1 {
        array[i].position.x -= x_adjust;
    }
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
    texture.y_adjust = size * 0.001875 * display_height;

    // Load the data for each glyph
    texture_width, texture_height, char_index: u32;
    array_resize(&texture.glyphs, font.char_count, allocate, reallocate);

    font_handle := font.handle;
    semaphore_wait(&font.handle_mutex);

    char_height := size * 2;
    FONT_ADJUSTMENT := 1.5; #const

    FT_Set_Pixel_Sizes(font_handle, 0, char_height);

    character := FT_Get_First_Char(font_handle, &char_index);
    while char_index != 0 && character < 128 {
        FT_Load_Glyph(font_handle, char_index, FT_LoadFlags.FT_LOAD_RENDER);

        glyph_slot := *font_handle.glyph;
        glyph: Glyph = {
            bearing = { x = cast(float, glyph_slot.bitmap_left); y = glyph_slot.bitmap_top * FONT_ADJUSTMENT; }
            advance = (glyph_slot.advance.x >> 6) * FONT_ADJUSTMENT; x_offset = texture_width;
        }

        texture_width += glyph_slot.bitmap.width + 2;
        if texture_height < glyph_slot.bitmap.rows
            texture_height = glyph_slot.bitmap.rows;

        texture.glyphs[character] = glyph;
        character = FT_Get_Next_Char(font_handle, character, &char_index);
    }

    // Create the buffer for the texture
    image_buffer := allocate(texture_width * texture_height);
    defer free_allocation(image_buffer);

    character = FT_Get_First_Char(font.handle, &char_index);
    while char_index != 0 && character < 128 {
        FT_Load_Glyph(font_handle, char_index, FT_LoadFlags.FT_LOAD_RENDER);

        glyph_bitmap := font_handle.glyph.bitmap;
        glyph := texture.glyphs[character];

        each i in 0..glyph_bitmap.rows - 1 {
            offset := cast(u32, glyph.x_offset) + i * texture_width;
            memory_copy(image_buffer + offset, glyph_bitmap.buffer + i * glyph_bitmap.width, glyph_bitmap.width);
        }

        // Adjust glyph dimensions
        texture.glyphs[character] = {
            width = cast(float, glyph_bitmap.width); height = glyph_bitmap.rows * FONT_ADJUSTMENT;
            bottom_left_texture_coord = { x = 1.0 * glyph.x_offset / texture_width; y = 0.0; }
            top_right_texture_coord = { x = cast(float, glyph_bitmap.width + glyph.x_offset) / texture_width; y = cast(float, glyph_bitmap.rows) / texture_height; }
        }

        character = FT_Get_Next_Char(font_handle, character, &char_index);
    }

    semaphore_release(&font.handle_mutex);

    texture.texture = create_texture(image_buffer, texture_width, texture_height, 1, index, 1);
    texture.descriptor_set = create_quad_descriptor_set(texture.texture);
    texture.loaded = true;
}
