#import "lib/shaderc/shaderc.ol"

[flags]
enum ShaderStage {
    None                = 0x0;
    Vertex              = 0x1;
    TessellationControl = 0x2;
    TessellationEval    = 0x4;
    Geometry            = 0x8;
    Fragment            = 0x10;
    Compute             = 0x20;
}

bool compile_shader(string name, string input_file_name, string file_path, string shader_output_directory, Allocate allocator, Free allocator_free) {
    log("Beginning '%' shader compile\n", name);

    found, file, stages, stage_count := read_shader_file(input_file_name, allocator);
    if !found {
        log("Shader file '%' not found\n", input_file_name);
        return false;
    }
    defer allocator_free(file.data);

    shader_file_name := temp_string(shader_output_directory, "/", name, ".shader");
    opened, shader_file := open_file(shader_file_name, FileFlags.Create);
    if !opened {
        log("Failed to open file handle for shader file '%'\n", shader_file_name);
        return false;
    }
    defer close_file(shader_file);

    write_buffer_to_file(shader_file, &stage_count, size_of(stage_count));
    write_buffer_to_file(shader_file, &stages, size_of(stages));

    compiler := shaderc_compiler_initialize();
    defer shaderc_compiler_release(compiler);

    success := true;
    if stages & ShaderStage.Vertex {
        success &&= compile_shader_stage(compiler, ShaderStage.Vertex, shader_file, file, file_path);
    }
    if stages & ShaderStage.TessellationControl {
        success &&= compile_shader_stage(compiler, ShaderStage.TessellationControl, shader_file, file, file_path);
    }
    if stages & ShaderStage.TessellationEval {
        success &&= compile_shader_stage(compiler, ShaderStage.TessellationEval, shader_file, file, file_path);
    }
    if stages & ShaderStage.Geometry {
        success &&= compile_shader_stage(compiler, ShaderStage.Geometry, shader_file, file, file_path);
    }
    if stages & ShaderStage.Fragment {
        success &&= compile_shader_stage(compiler, ShaderStage.Fragment, shader_file, file, file_path);
    }
    if stages & ShaderStage.Compute {
        success &&= compile_shader_stage(compiler, ShaderStage.Compute, shader_file, file, file_path);
    }

    if success {
        log("Successfully compiled '%' shader\n", name);
    }
    else {
        log("Failed to compile '%' shader\n", name);
    }

    return success;
}

Array<u8> compile_shader_for_bundle(string name, string input_file_name, string file_path) {
    log("Beginning '%' shader compile\n", name);

    shader_data: Array<u8>;
    found, file, stages, stage_count := read_shader_file(input_file_name);
    if !found {
        log("Shader file '%' not found\n", input_file_name);
        return shader_data;
    }
    defer default_free(file.data);

    array_reserve(&shader_data, size_of(stage_count) + size_of(stages));
    memory_copy(shader_data.data, &stage_count, size_of(stage_count));
    memory_copy(shader_data.data + size_of(stage_count), &stages, size_of(stages));

    compiler := shaderc_compiler_initialize();
    defer shaderc_compiler_release(compiler);

    success := true;
    if stages & ShaderStage.Vertex {
        success &&= compile_shader_stage_for_bundle(compiler, ShaderStage.Vertex, &shader_data, file, file_path);
    }
    if stages & ShaderStage.TessellationControl {
        success &&= compile_shader_stage_for_bundle(compiler, ShaderStage.TessellationControl, &shader_data, file, file_path);
    }
    if stages & ShaderStage.TessellationEval {
        success &&= compile_shader_stage_for_bundle(compiler, ShaderStage.TessellationEval, &shader_data, file, file_path);
    }
    if stages & ShaderStage.Geometry {
        success &&= compile_shader_stage_for_bundle(compiler, ShaderStage.Geometry, &shader_data, file, file_path);
    }
    if stages & ShaderStage.Fragment {
        success &&= compile_shader_stage_for_bundle(compiler, ShaderStage.Fragment, &shader_data, file, file_path);
    }
    if stages & ShaderStage.Compute {
        success &&= compile_shader_stage_for_bundle(compiler, ShaderStage.Compute, &shader_data, file, file_path);
    }

    if success {
        log("Successfully compiled '%' shader\n", name);
    }
    else {
        error_message := format_string("Failed to compile '%' shader\n", name);
        report_error(error_message);
    }

    return shader_data;
}

#private

bool, string, ShaderStage, int read_shader_file(string input_file_name, Allocate allocator = default_allocator) {
    shader_data: Array<u8>;
    found, file := read_file(input_file_name, allocator);
    if !found {
        log("Shader file '%' not found\n", input_file_name);
        return false, empty_string, ShaderStage.None, 0;
    }

    stage_count := 0;
    stages: ShaderStage;

    if file[0] == '/' && file[1] == '/' {
        start := 2;
        while file[start] == ' ' {
            start++;
        }

        end := start;
        while file[end] != '\n' {
            end++;
        }

        shader_stage_type := cast(EnumTypeInfo*, type_of(ShaderStage));

        stage_name: string = { length = 0; data = file.data + start; }
        each i in end - start {
            if file[start + i] == '|' {
                value_found := false;
                each value in shader_stage_type.values {
                    if value.name == stage_name {
                        stage_count++;
                        stages |= cast(ShaderStage, value.value);
                        value_found = true;
                        break;
                    }
                }

                if !value_found {
                    log("Invalid shader stage name '%'\n", stage_name);
                }

                stage_name = { length = 0; data = file.data + start + i + 1; }
            }
            else {
                stage_name.length++;
            }
        }

        if stage_name.length {
            value_found := false;
            each value in shader_stage_type.values {
                if value.name == stage_name {
                    stage_count++;
                    stages |= cast(ShaderStage, value.value);
                    value_found = true;
                    break;
                }
            }

            if !value_found {
                log("Invalid shader stage name '%'\n", stage_name);
            }
        }
    }
    else {
        stage_count = 2;
        stages = ShaderStage.Vertex | ShaderStage.Fragment;
    }

    return true, file, stages, stage_count;
}

bool compile_shader_stage(shaderc_compiler* compiler, ShaderStage stage, File shader_file, string file, string file_name) {
    result := compile_stage(compiler, stage, file, file_name);
    defer shaderc_result_release(result);

    status := shaderc_result_get_compilation_status(result);

    if status != shaderc_compilation_status.shaderc_compilation_status_success {
        error_count := shaderc_result_get_num_errors(result);
        error_message := convert_c_string(shaderc_result_get_error_message(result));
        log("% error(s) compiling % shader:\n\n%\n", error_count, stage, error_message);

        length: s64 = 0;
        write_buffer_to_file(shader_file, &length, size_of(length));
        return false;
    }

    length := shaderc_result_get_length(result);
    write_buffer_to_file(shader_file, &length, size_of(length));

    bytes := shaderc_result_get_bytes(result);
    write_buffer_to_file(shader_file, bytes, length);
    return true;
}

bool compile_shader_stage_for_bundle(shaderc_compiler* compiler, ShaderStage stage, Array<u8>* shader_data, string file, string file_name) {
    result := compile_stage(compiler, stage, file, file_name);
    defer shaderc_result_release(result);

    status := shaderc_result_get_compilation_status(result);

    if status != shaderc_compilation_status.shaderc_compilation_status_success {
        error_count := shaderc_result_get_num_errors(result);
        error_message := convert_c_string(shaderc_result_get_error_message(result));
        log("% error(s) compiling % shader:\n\n%\n", error_count, stage, error_message);

        length: s64 = 0;
        array_reserve(shader_data, shader_data.length + size_of(length));
        memory_copy(shader_data.data, &length, size_of(length));
        return false;
    }

    length := shaderc_result_get_length(result);
    bytes := shaderc_result_get_bytes(result);

    start := shader_data.length;
    array_reserve(shader_data, shader_data.length + size_of(length) + length);
    memory_copy(shader_data.data + start, &length, size_of(length));
    memory_copy(shader_data.data + start + size_of(length), bytes, length);
    return true;
}

shaderc_compilation_result* compile_stage(shaderc_compiler* compiler, ShaderStage stage, string file, string file_name) {
    options := shaderc_compile_options_initialize();
    defer shaderc_compile_options_release(options);

    stage_name: string;
    shader_kind: shaderc_shader_kind;

    switch stage {
        case ShaderStage.Vertex; {
            stage_name = "_VERT";
            shader_kind = shaderc_shader_kind.shaderc_vertex_shader;
        }
        case ShaderStage.TessellationControl; {
            stage_name = "_TESC";
            shader_kind = shaderc_shader_kind.shaderc_tess_control_shader;
        }
        case ShaderStage.TessellationEval; {
            stage_name = "_TESE";
            shader_kind = shaderc_shader_kind.shaderc_tess_evaluation_shader;
        }
        case ShaderStage.Geometry; {
            stage_name = "_GEOM";
            shader_kind = shaderc_shader_kind.shaderc_geometry_shader;
        }
        case ShaderStage.Fragment; {
            stage_name = "_FRAG";
            shader_kind = shaderc_shader_kind.shaderc_fragment_shader;
        }
        case ShaderStage.Compute; {
            stage_name = "_COMP";
            shader_kind = shaderc_shader_kind.shaderc_compute_shader;
        }
        default;
            assert(false, "Invalid shader stage when compiling shaders");
    }

    enabled := "1"; #const
    shaderc_compile_options_add_macro_definition(options, stage_name, stage_name.length, enabled, enabled.length);

    if DEVELOPER {
        developer_macro := "DEVELOPER";
        shaderc_compile_options_add_macro_definition(options, developer_macro, developer_macro.length, enabled, enabled.length);
    }

    #if build_env == BuildEnv.Release {
        shaderc_compile_options_set_optimization_level(options, shaderc_optimization_level.shaderc_optimization_level_performance);
    }
    else {
        shaderc_compile_options_set_generate_debug_info(options);
        debug_macro := "_DEBUG"; #const
        shaderc_compile_options_add_macro_definition(options, debug_macro, debug_macro.length, enabled, enabled.length);
    }

    result := shaderc_compile_into_spv(compiler, file, file.length, shader_kind, file_name, "main", options);

    return result;
}
