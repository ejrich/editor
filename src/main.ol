#import atomic
#import "buffers.ol"
#import "events.ol"
#import "graphics.ol"
#import "keybinds.ol"
#import "memory.ol"
#import "settings.ol"
#import "text.ol"
#import "thread_pool.ol"
#import "window.ol"

#if DEVELOPER {
    #import "commands.ol"
}

main() {
    init_subsystems();

    // TODO Remove
    open_file_buffer("src/first.ol");

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
            draw_buffers();
            draw_performance_stats(average_frame_time, frequency);
            submit_frame();
        }
    }

    deinit_subsystems();
}

draw_performance_stats(float average_frame_time, float frequency) {
    if show_performance_stats {
        fps := 1 / average_frame_time;

        buffer: Array<u8>[10];
        string_buffer: StringBuffer = { buffer = buffer; }
        write_float(&string_buffer, float_format(fps, 1));
        add_to_string_buffer(&string_buffer, " FPS");
        fps_string: string = { length = string_buffer.length; data = buffer.data; }

        text_color: Vector4 = { x = 1.0; y = 1.0; z = 1.0; w = 1.0; }
        render_text(fps_string, 20, vec3(0.99, 0.95), text_color, TextAlignment.Right);

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

            p := vec3(0.99, 0.90);
            each t in execution_times {
                p.y -= 0.05;

                data := profiling_data[t];
                s := format_string("% - % times, % seconds", temp_allocate, function_names[t], data.times_called, data.execution_time / frequency);
                render_text(s, 20, p, text_color, TextAlignment.Right);
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
allocate_strings(Params<string*> strings) {
    length: u64;
    each str in strings {
        length += str.length;
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

#private

running := true;

show_performance_stats := false;
show_profiling_data := false;

program_directory: string;

init_subsystems() {
    init_memory();
    init_logging();
    init_display();
    load_settings();
    load_keybinds();

    create_window();
    init_thread_pool();
    init_graphics();
    init_text();
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
