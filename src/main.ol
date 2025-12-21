#import atomic
#import "buffers.ol"
#import "changes.ol"
#import "clipboard.ol"
#import "control.ol"
#import "commands.ol"
#import "events.ol"
#import "graphics.ol"
#import "jumps.ol"
#import "keybinds.ol"
#import "list.ol"
#import "local_settings.ol"
#import "memory.ol"
#import "run.ol"
#import "settings.ol"
#import "source_control.ol"
#import "text.ol"
#import "thread_pool.ol"
#import "window.ol"

main() {
    init_subsystems();

    each input_file in get_command_line_arguments() {
        open_file_buffer(input_file, false);
    }

    frequency := cast(float, get_performance_frequency());
    start := get_performance_counter();
    frame, frames_accumulated := 0;

    average_frame_time := 0.1;
    time_accumulated := 0.0;

    while running {
        end := get_performance_counter();
        time_step := (end - start) / frequency;
        start = end;

        reset_temp_buffer();

        handle_inputs();

        time_accumulated += time_step;
        frames_accumulated++;
        if time_accumulated > 0.1 {
            average_frame_time = time_accumulated / frames_accumulated;

            time_accumulated = 0.0;
            frames_accumulated = 0;
        }

        #if DEVELOPER && SHADER_HOT_RELOADING {
            frame = (frame + 1) % 20;
            if frame == 0 reload_updated_shaders();
        }

        // Render buffers
        if set_current_command_buffer() {
            begin_ui_render_pass();

            if !draw_list() {
                draw_buffers();
            }

            draw_performance_stats(average_frame_time, frequency);
            submit_frame();
        }
    }

    deinit_subsystems();
}

draw_performance_stats(float average_frame_time, float frequency) {
    if show_performance_stats {
        fps := 1 / average_frame_time;

        buffer: Array<u8>[50];
        string_buffer: StringBuffer = { buffer = buffer; }
        write_float(&string_buffer, float_format(fps, 1));
        add_to_string_buffer(&string_buffer, " FPS");
        fps_string: string = { length = string_buffer.length; data = buffer.data; }

        text_color: Vector4 = { x = 1.0; y = 1.0; z = 1.0; w = 1.0; }
        background_color: Vector4;
        render_text(fps_string, 20, 0.99, 0.95, text_color, background_color, TextAlignment.Right);

        #if PROFILE {
            if show_profiling_data return;

            execution_times: Array<int> = [0, 0, 0, 0, 0]
            each data, i in profiling_data {
                if data.execution_time {
                    index := 0;
                    while index < 5 {
                        compare := profiling_data[execution_times[index]];
                        if data.execution_time > compare.execution_time {
                            end_index := 4;
                            while end_index > index {
                                execution_times[end_index] = execution_times[end_index - 1];
                                end_index--;
                            }
                            execution_times[index] = i;
                            break;
                        }

                        index++;
                    }
                }
            }

            x := 0.99;
            y := 0.90;
            each t in execution_times {
                y -= 0.05;

                data := profiling_data[t];
                s := format_string("% - % times, % seconds", temp_allocate, function_names[t], data.times_called, data.execution_time / frequency);
                render_text(s, 20, x, y, text_color, background_color, TextAlignment.Right);
            }
        }
    }

    #if PROFILE reset_profiling_data();
}

toggle_performance_stats(bool profiling) {
    if profiling {
        show_profiling_data = !show_profiling_data;
    }
    else {
        show_performance_stats = !show_performance_stats;
    }
}

signal_shutdown() {
    running = false;
}

// Takes in a list of strings and allocates the data in a single block
allocate_strings(bool null_terminate = false, Params<string*> strings) {
    length: u64;
    each str in strings {
        length += str.length;
    }

    if null_terminate {
        length++;
    }

    if length == 0 return;

    pointer := allocate(length);
    i: s64;
    each str in strings {
        memory_copy(pointer + i, str.data, str.length);
        str.data = pointer + i;
        i += str.length;
    }
}

bool string_contains(string value, string sub_value) {
    if sub_value.length == 0 return true;
    if sub_value.length > value.length return false;
    if sub_value.length == value.length return value == sub_value;

    each i in value.length - sub_value.length + 1 {
        if value[i] == sub_value[0] {
            test_value: string = {
                length = sub_value.length;
                data = value.data + i;
            }
            if test_value == sub_value {
                return true;
            }
        }
    }

    return false;
}

s32 clamp(s32 value, s32 min, s32 max) {
    if value < min return min;
    if value > max return max;
    return value;
}

float clamp(float value, float min, float max) {
    if value < min return min;
    if value > max return max;
    return value;
}

string get_program_directory() {
    if program_directory.length == 0 {
        path_length := 4096; #const
        executable_path: CArray<u8>[path_length];
        #if os == OS.Linux {
            self_path := "/proc/self/exe"; #const
            bytes := readlink(self_path.data, &executable_path, path_length - 1);

            each i in 1..bytes-1 {
                if executable_path[i] == '/' {
                    program_directory.length = i;
                }
            }
        }
        else #if os == OS.Windows {
            bytes := GetModuleFileNameA(null, &executable_path, path_length);

            length := 0;
            each i in 1..bytes-1 {
                if executable_path[i] == '\\' {
                    program_directory.length = i;
                }
            }
        }

        program_directory.data = &executable_path;
        allocate_strings(&program_directory);
    }

    return program_directory;
}

Array<string> split_string(string value) #inline {
    lines := 1;
    each i in value.length {
        if value[i] == '\n' {
            lines++;
        }
    }

    value_lines: Array<string>[lines];
    if lines == 1 {
        value_lines[0] = value;
    }
    else {
        index := 0;
        str: string = { data = value.data; }
        each i in value.length {
            if value[i] == '\n' {
                value_lines[index++] = str;
                str = { length = 0; data = value.data + i + 1; }
            }
            else {
                str.length++;
            }
        }
        value_lines[index++] = str;
    }

    return value_lines;
}

string create_empty_string(u32 length) #inline {
    string_data: Array<u8>[length];
    str: string = { length = length; data = string_data.data; }
    each i in length {
        str[i] = ' ';
    }

    return str;
}

current_directory: string;

#private

running := true;

show_performance_stats := false;
show_profiling_data := false;

program_directory: string;

init_subsystems() {
    init_memory();
    get_working_directory();
    init_logging();
    init_display();
    load_settings();
    load_keybinds();
    load_local_settings();

    create_window();
    init_thread_pool();
    init_clipboard();
    init_graphics();
    init_text();
    init_run();
}

deinit_subsystems() {
    wait_for_graphics_idle();

    write_keybinds();
    write_settings();
    deinit_text();
    deinit_graphics();

    close_window();
    deallocate_arenas();

    deinit_logging();
}

get_working_directory() {
    #if os == OS.Windows {
        current_directory = {
            length = GetCurrentDirectoryA(0, null);
        }
        current_directory.data = allocate(current_directory.length);
        current_directory.length = GetCurrentDirectoryA(current_directory.length, current_directory.data);
    }
    #if os == OS.Linux {
        // TODO Use the syscall getcwd
    }
}
