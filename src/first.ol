#import standard
#import "logging.ol"
#import "shaders.ol"

DEVELOPER := true; #const
SHADER_HOT_RELOADING := true; #const
BUNDLED_SHADERS := !DEVELOPER; #const
PROFILE := false; #const

application_name := "Editor";

#run {
    set_executable_name("editor");
    set_output_directory("../run_tree");
    set_output_type_table(OutputTypeTableConfiguration.Used);

    if os == OS.Linux {
        set_linker(LinkerType.Dynamic);
    }

    #if os == OS.Windows {
        set_windows_subsystem(WindowsSubsystem.Windows);
        add_windows_resource_file("../assets/editor.rc");
        if DEVELOPER {
            copy_to_output_directory("lib/shaderc/shaderc_shared.dll");
        }
    }

    if build_env == BuildEnv.Release {
        optimizations: ReleaseOptimizations;
        get_current_optimizations(&optimizations);

        // @Robustness instcombine pass is not working, so disable
        optimizations.combine_redudant_instruction = false;

        optimizations.forget_scalar_evolution_in_loop_unrolling = true;
        set_optimizations(&optimizations);
    }

    add_source_file("main.ol");
    create_shader_library();

    if intercept_compiler_messages() {
        profiling_data_variable, function_names_variable, keybind_definitions_variable, commands_variable: GlobalVariableAst*;
        profiled_function_names: Array<string>;
        keybind_functions: Array<KeybindFunction>;
        commands: Array<Command>;
        function_index, function_names_length, keybind_definitions_length, commands_length: int;

        message: CompilerMessage;
        while get_next_compiler_message(&message) {
            switch message.type {
                case CompilerMessageType.ReadyToBeTypeChecked; {
                    if message.value.ast.type == AstType.Function || message.value.ast.type == AstType.OperatorOverload {
                        function := cast(FunctionAst*, message.value.ast);
                        if add_profiling_to_function(function, function_index) {
                            function_index++;
                            array_insert(&profiled_function_names, function.name);
                            function_names_length += function.name.length + 4;
                        }
                    }
                    else if message.value.ast.type == AstType.GlobalVariable {
                        global := cast(GlobalVariableAst*, message.value.ast);
                        if global.name == "profiling_data" {
                            profiling_data_variable = global;
                        }
                        if global.name == "function_names" {
                            function_names_variable = global;
                        }
                        if global.name == "keybind_definitions" {
                            keybind_definitions_variable = global;
                        }
                        if global.name == "commands" {
                            commands_variable = global;
                        }
                    }
                }
                case CompilerMessageType.TypeCheckSuccessful; {
                    if message.value.ast.type == AstType.Function {
                        function := cast(FunctionAst*, message.value.ast);
                        if array_contains(function.attributes, "keybind") {
                            keybind_function: KeybindFunction = {
                                name = function.name;
                                no_repeat = array_contains(function.attributes, "no_repeat");
                                list = array_contains(function.attributes, "list");
                            }
                            keybind_definitions_length += function.name.length * 2 + 56;
                            if !keybind_function.no_repeat keybind_definitions_length++;
                            if !keybind_function.list keybind_definitions_length++;
                            array_insert(&keybind_functions, keybind_function);
                        }
                        else if array_contains(function.attributes, "command") {
                            if verify_command_arguments(function) {
                                generate_command(function);

                                if function.attributes.length == 1 {
                                    command: Command = {
                                        command = function.name;
                                        function = function.name;
                                    }

                                    commands_length += function.name.length * 2 + 27;
                                    array_insert(&commands, command);
                                }
                                else {
                                    each i in 1..function.attributes.length - 1 {
                                        command: Command = {
                                            command = function.attributes[i];
                                            function = function.name;
                                        }

                                        commands_length += function.name.length + command.command.length + 27;
                                        array_insert(&commands, command);
                                    }
                                }
                            }
                            else {
                                error_string := format_string("Function '%' has the incorrect arguments/return type for a command. The return type needs to be 'string, bool' and the arguments can only be bool, integer, float, or string types", function.name);
                                defer default_free(error_string.data);
                                report_error(error_string, function);
                            }
                        }
                    }
                }
                case CompilerMessageType.ReadyForCodeGeneration; {
                    // Set the profiling_data and function_names variable initial values
                    length := profiled_function_names.length * 4;
                    if length {
                        profiling_data_initial_value: string = { length = length; data = default_allocator(length); }
                        defer default_free(profiling_data_initial_value.data);

                        function_names_initial_value: string = { length = function_names_length; data = default_allocator(function_names_length); }
                        defer default_free(function_names_initial_value.data);

                        profiling_data_initial_value[0] = '[';
                        function_names_initial_value[0] = '[';

                        i := 0;
                        names_index := 1;
                        while i < profiled_function_names.length - 1 {
                            start := i * 4 + 1;
                            profiling_data_initial_value[start] = '{';
                            profiling_data_initial_value[start + 1] = '}';
                            profiling_data_initial_value[start + 2] = ',';
                            profiling_data_initial_value[start + 3] = ' ';

                            name := profiled_function_names[i];
                            function_names_initial_value[names_index++] = '"';
                            memory_copy(function_names_initial_value.data + names_index, name.data, name.length);
                            names_index += name.length;

                            function_names_initial_value[names_index++] = '"';
                            function_names_initial_value[names_index++] = ',';
                            function_names_initial_value[names_index++] = ' ';

                            i++;
                        }

                        profiling_data_initial_value[length - 3] = '{';
                        profiling_data_initial_value[length - 2] = '}';
                        profiling_data_initial_value[length - 1] = ']';

                        name := profiled_function_names[i];
                        function_names_initial_value[names_index++] = '"';
                        memory_copy(function_names_initial_value.data + names_index, name.data, name.length);
                        names_index += name.length;

                        function_names_initial_value[function_names_length - 2] = '"';
                        function_names_initial_value[function_names_length - 1] = ']';

                        set_global_variable_value(profiling_data_variable, profiling_data_initial_value);
                        set_global_variable_value(function_names_variable, function_names_initial_value);
                    }

                    // Set the keybind definitions initial values
                    if keybind_definitions_length {
                        keybind_definitions_length++;
                        keybind_definitions_initial_value: string = { length = keybind_definitions_length; data = default_allocator(keybind_definitions_length); }
                        defer default_free(keybind_definitions_initial_value.data);

                        keybind_definitions_initial_value[0] = '[';

                        i := 1;
                        each function in keybind_functions {
                            prefix := "{name = \""; #const
                            handler := "\"; handler = "; #const
                            no_repeat_true := "; no_repeat = true;"; #const
                            no_repeat_false := "; no_repeat = false;"; #const
                            list_true := " list = true;},"; #const
                            list_false := " list = false;},"; #const

                            memory_copy(keybind_definitions_initial_value.data + i, prefix.data, prefix.length);
                            i += prefix.length;

                            memory_copy(keybind_definitions_initial_value.data + i, function.name.data, function.name.length);
                            i += function.name.length;

                            memory_copy(keybind_definitions_initial_value.data + i, handler.data, handler.length);
                            i += handler.length;

                            memory_copy(keybind_definitions_initial_value.data + i, function.name.data, function.name.length);
                            i += function.name.length;

                            if function.no_repeat {
                                memory_copy(keybind_definitions_initial_value.data + i, no_repeat_true.data, no_repeat_true.length);
                                i += no_repeat_true.length;
                            }
                            else {
                                memory_copy(keybind_definitions_initial_value.data + i, no_repeat_false.data, no_repeat_false.length);
                                i += no_repeat_false.length;
                            }

                            if function.list {
                                memory_copy(keybind_definitions_initial_value.data + i, list_true.data, list_true.length);
                                i += list_true.length;
                            }
                            else {
                                memory_copy(keybind_definitions_initial_value.data + i, list_false.data, list_false.length);
                                i += list_false.length;
                            }
                        }

                        keybind_definitions_initial_value[keybind_definitions_length - 1] = ']';
                        set_global_variable_value(keybind_definitions_variable, keybind_definitions_initial_value);
                    }

                    // Set the command array initial values
                    if commands_length > 0 && commands_variable != null {
                        commands_length++;
                        commands_initial_value: string = { length = commands_length; data = default_allocator(commands_length); }
                        defer default_free(commands_initial_value.data);

                        commands_initial_value[0] = '[';

                        i := 1;
                        bubble_sort(commands, command_sort);
                        each command in commands {
                            prefix := "{name = \""; #const
                            middle := "\"; handler = __"; #const
                            suffix := ";},"; #const

                            memory_copy(commands_initial_value.data + i, prefix.data, prefix.length);
                            i += prefix.length;

                            memory_copy(commands_initial_value.data + i, command.command.data, command.command.length);
                            i += command.command.length;

                            memory_copy(commands_initial_value.data + i, middle.data, middle.length);
                            i += middle.length;

                            memory_copy(commands_initial_value.data + i, command.function.data, command.function.length);
                            i += command.function.length;

                            memory_copy(commands_initial_value.data + i, suffix.data, suffix.length);
                            i += suffix.length;
                        }

                        commands_initial_value[commands_length - 1] = ']';
                        set_global_variable_value(commands_variable, commands_initial_value);
                    }
                }
                case CompilerMessageType.CodeGenerated; {}
                case CompilerMessageType.ExecutableLinked; {}
            }
        }
    }
}

// Shader metaprogram
create_shader_library() {
    directory := get_compiler_working_directory();
    shader_directory := temp_string(directory, "/shaders");

    success, files := get_files_in_directory(shader_directory);
    shaders: Array<string>;
    shader_string_length := 0;
    shader_codes: Array<Array<u8>>;
    if success {
        each file in files {
            if file.type == FileType.File && ends_with(file.name, ".glsl") {
                file.name.length -= 5;
                array_insert(&shaders, file.name);
                shader_string_length += file.name.length + 6;

                if BUNDLED_SHADERS {
                    input_file_name := temp_string(shader_directory, "/", file.name, ".glsl");
                    file_path := temp_string("../src/shaders/", file.name, ".glsl", "\0");
                    shader_code := compile_shader_for_bundle(file.name, input_file_name, file_path);
                    array_insert(&shader_codes, shader_code);
                }
            }
        }
    }

    shader_names_data: Array<u8>[shader_string_length];
    shader_names: string = { length = shader_string_length; data = shader_names_data.data; }

    i := 0;
    each shader in shaders {
        prefix := "    "; #const
        suffix := ";\n"; #const

        memory_copy(shader_names.data + i, prefix.data, prefix.length);
        i += prefix.length;

        memory_copy(shader_names.data + i, shader.data, shader.length);
        i += shader.length;

        memory_copy(shader_names.data + i, suffix.data, suffix.length);
        i += suffix.length;
    }

    shader_names_code := format_string("enum ShaderName : s32 {\n    Invalid = -1;\n%}", shader_names);
    add_code(shader_names_code);

    if BUNDLED_SHADERS {
        shader_codes_code := format_string("__shader_codes: Array<Array<u8>> = %", shader_codes);
        add_code(shader_codes_code);
    }

    pipelines_code := format_string("""
struct GraphicsPipelines {
    pipelines: CArray<GraphicsPipeline>[%];
    layouts: CArray<GraphicsPipelineLayout>[%];
}

__graphics_pipelines: GraphicsPipelines;""", shaders.length, shaders.length);
    add_code(pipelines_code);

    if DEVELOPER && SHADER_HOT_RELOADING {
        shader_code := format_string("""
struct ShaderDefinition {
    source: string;
    last_updated: u64;
}

__shader_library: Array<ShaderDefinition>[%];""", shaders.length);
        add_code(shader_code);
    }
}

// Profiling declarations
bool add_profiling_to_function(FunctionAst* function, int index) {
    #if !PROFILE return false;

    if function.flags == FunctionFlags.None && function.name != "get_performance_counter" && function.name != "record_function_time"  && function.name != "reset_profiling_data"{
        code := format_string("__frame_start := get_performance_counter();\ndefer record_function_time(__frame_start, %);", index);
        insert_code(function, code);
        default_free(code.data);

        return true;
    }

    return false;
}

#if PROFILE {
    record_function_time(u64 start, int index) {
        end := get_performance_counter();
        diff := end - start;

        if profiling_data.length > index {
            profiling_data[index].times_called++;
            profiling_data[index].execution_time += diff;
        }
    }

    reset_profiling_data() {
        each data in profiling_data {
            data = { times_called = 0; execution_time = 0; }
        }
    }

    struct ProfilingData {
        times_called: int;
        execution_time: u64;
    }

    profiling_data: Array<ProfilingData>;
    function_names: Array<string>;
}

struct KeybindFunction {
    name: string;
    no_repeat: bool;
    list: bool;
}

// Code for verifying and generating commands
struct Command {
    command: string;
    function: string;
}

int command_sort(Command a, Command b) {
    if a.command > b.command return 1;
    if a.command < b.command return -1;
    return 0;
}

bool verify_command_arguments(FunctionAst* function) {
    if function.return_type.type != TypeKind.Compound return false;

    compound_return_type := cast(CompoundTypeInfo*, function.return_type);
    if compound_return_type.types.length != 2 ||
        compound_return_type.types[0].type != TypeKind.String ||
        compound_return_type.types[1].type != TypeKind.Boolean
        return false;

    each argument in function.arguments {
        switch argument.type_info.type {
            case TypeKind.Boolean;
            case TypeKind.Integer;
            case TypeKind.Float;
            case TypeKind.String; {} // Valid Types
            default; return false;
        }
    }

    return true;
}

generate_command(FunctionAst* function) {
    function_parts: Array<string>;

    declaration := format_string("""
CommandResult, string, bool __%(Array<string> args) {
    if args.length != % return CommandResult.IncorrectArgumentCount, empty_string, false;
    success: bool;""", function.name, function.arguments.length);
    code_length := declaration.length;
    array_insert(&function_parts, declaration);

    arguments_length := 0;
    function_arguments: Array<string>;

    each argument, i in function.arguments {
        argument_parsed: string;
        if argument.type_info.type == TypeKind.String {
            argument_parsed = format_string("""
    arg% := args[%];""", i, i);
        }
        else {
            argument_parsed = format_string("""
    arg%: %;
    success, arg% = try_parse_%(args[%]);
    if !success return CommandResult.IncorrectArgumentTypes, empty_string, false;""", i, argument.type_info.name, i, argument.type_info.name, i);
        }

        code_length += argument_parsed.length;
        array_insert(&function_parts, argument_parsed);

        call_argument := format_string("arg%, ", i);
        arguments_length += call_argument.length;
        array_insert(&function_arguments, call_argument);
    }

    arguments_string: string;
    defer default_free(arguments_string.data);
    if arguments_length > 0 {
        arguments_length -= 2;
        arguments_string = { length = arguments_length; data = default_allocator(arguments_length); }

        offset := 0;
        each argument, i in function_arguments {
            if i == function_arguments.length - 1 {
                memory_copy(arguments_string.data + offset, argument.data, argument.length - 2);
            }
            else {
                memory_copy(arguments_string.data + offset, argument.data, argument.length);
            }

            offset += argument.length;
            default_free(argument.data);
        }
    }

    ending := format_string("""
    result_string, free_result_string := %(%);
    return CommandResult.Success, result_string, free_result_string;
}""", function.name, arguments_string);
    code_length += ending.length;
    array_insert(&function_parts, ending);

    code_string: string = { length = code_length; data = default_allocator(code_length); }
    defer default_free(code_string.data);
    offset := 0;
    each part in function_parts {
        memory_copy(code_string.data + offset, part.data, part.length);
        offset += part.length;
        default_free(part.data);
    }

    add_code(code_string);
}


// General helper functions
bool ends_with(string value, string ending) {
    if ending.length > value.length return false;

    start_index := value.length - ending.length;
    each i in ending.length {
        if value[start_index + i] != ending[i] return false;
    }

    return true;
}

bool starts_with(string value, string start) {
    if start.length > value.length return false;

    each i in start.length {
        if value[i] != start[i] return false;
    }

    return true;
}

string temp_string(bool null_terminate = true, Params<string> parts) #inline {
    length := 0;
    each part in parts length += part.length;

    if null_terminate length++;

    string_data: Array<u8>[length];
    result: string = { length = string_data.length; data = string_data.data; }

    i := 0;
    each part in parts {
        memory_copy(result.data + i, part.data, part.length);
        i += part.length;
    }

    if null_terminate {
        result[length - 1] = 0;
        result.length--;
    }

    return result;
}

create_directories_recursively(string file) {
    i := file.length;
    while i > 0 {
        if file[i - 1] == '/' {
            sub_path: string = { length = i; data = file.data; }
            if file_exists(sub_path) {
                i++;
                break;
            }
        }
        i--;
    }

    while i < file.length {
        if file[i - 1] == '/' {
            sub_path: string = { length = i; data = file.data; }
            create_directory(sub_path);
        }
        i++;
    }
}
