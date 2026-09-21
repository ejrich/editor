struct ToolSchema {
    type: ToolSchemaType;
    name: string;
    description: string;
    strict: bool;
    parameters: JsonSchema;
    output_schema: JsonSchema;
}

enum ToolSchemaType {
    function = 1;
}

interface string, bool ToolCall(Workspace* workspace, string arguments)

struct Tool {
    name: string;
    call: ToolCall;
}

tools: Array<Tool>;
tool_schemas: Array<ToolSchema>;

struct ReadFileArguments {
    ["The path of the file to read"]
    file: string;
}

struct ReadFileOutput {
    ["If the file was able to be read"]
    success: bool;
    ["The path of the file that was read"]
    file: string;
    ["The contents of the file"]
    text: string;
    ["Error message if unable to read the file"]
    error: string;
}

[tool, "Reads the entire text of a requested file"]
string, bool read_file_text(Workspace* workspace, ReadFileArguments args, ReadFileOutput output) {
    path := temp_string(workspace.directory, "/", args.file);
    if !file_exists(path) return "{\"success\":false,\"error\":\"File doesn't exist\"}", false;

    buffer := open_workspace_file_buffer(workspace, path, args.file);
    if buffer == null return "{\"success\":false,\"error\":\"Unable to load file\"}", false;

    output = {
        success = true;
        file = args.file;
        text = read_buffer_lines(buffer, 1, buffer.line_count);
    }

    output_json := serialize_json(output);
    free_allocation(output.text.data);
    return output_json, true;
}

struct ReadFileLineArguments {
    ["The path of the file to read"]
    file: string;
    ["The first line to include in the response"]
    start: u32;
    ["The last line to include in the response"]
    end: u32;
}

struct ReadFileLinesOutput {
    ["If the file was able to be read"]
    success: bool;
    ["The path of the file that was read"]
    file: string;
    ["The first line read, may be different than the request"]
    start_line: u32;
    ["The last line read, may be different than the request"]
    end_line: u32;
    ["The text of the queried lines in the file"]
    text: string;
    ["Error message if unable to read the file"]
    error: string;
}

[tool, "Reads a block of lines from a requested file"]
string, bool read_file_lines(Workspace* workspace, ReadFileLineArguments args, ReadFileLinesOutput output) {
    path := temp_string(workspace.directory, "/", args.file);
    if !file_exists(path) return "{\"success\":false,\"error\":\"File doesn't exist\"}", false;

    buffer := open_workspace_file_buffer(workspace, path, args.file);
    if buffer == null return "{\"success\":false,\"error\":\"Unable to load file\"}", false;

    output = {
        success = true;
        file = args.file;
        start_line = clamp(args.start, 1, buffer.line_count);
        end_line = clamp(args.end, 1, buffer.line_count);
        text = read_buffer_lines(buffer, args.start, args.end);
    }

    output_json := serialize_json(output);
    free_allocation(output.text.data);
    return output_json, true;
}

struct CreateFileArguments {
    ["The path and name of the new file"]
    file_path: string;
    ["The initial text to create the file with"]
    text: string;
}

struct CreateFileOutput {
    file_path: string;
    ["If creating the file was successful"]
    success: bool;
    ["Error message if creating the file was unsuccessful"]
    error: string;
}

[tool, "Creates a file with the specified text"]
string, bool create_file(Workspace* workspace, CreateFileArguments args, CreateFileOutput output) {
    path := temp_string(workspace.directory, "/", args.file_path);
    if file_exists(path) return "{\"success\":false,\"error\":\"File already exists\"}", false;

    buffer := open_workspace_file_buffer(workspace, path, args.file_path);
    if buffer == null return "{\"success\":false,\"error\":\"Unable to create file\"}", false;

    add_text_to_end_of_buffer(buffer, args.text, false);
    save_buffer(workspace, buffer);
    return "{\"success\":true}", false;
}

struct WriteFileArguments {
    ["The path of the file to write"]
    file: string;
    ["Commands for how to edit the file"]
    write_commands: Array<WriteFileCommand>;
}

struct WriteFileCommand {
    ["What the command to run on the file: 'Insert' will add text at start_line, 'Delete' will delete from the start_line to end_line, and 'Overwrite' will delete from start_line to end_line and write the text at start_line"]
    type: WriteFileCommandType;
    ["The starting line of the command"]
    start_line: u32;
    ["The end line of the command"]
    end_line: u32;
    ["The text to insert for the 'Insert' and 'Overwrite' commands"]
    text: string;
}

enum WriteFileCommandType {
    Insert;
    Delete;
    Overwrite;
}

struct WriteFileOutput {
    ["If the file was written to using the given commands"]
    success: bool;
    ["The number of lines that were written by the commands"]
    lines_written: u32;
    ["The number of lines that were deleted by the commands"]
    lines_deleted: u32;
    ["Error message if the file was not written to"]
    error: string;
}

[tool, "Writes to a file with commands"]
string, bool write_file(Workspace* workspace, WriteFileArguments args, WriteFileOutput output) {
    path := temp_string(workspace.directory, "/", args.file);
    if !file_exists(path) return "{\"success\":false,\"error\":\"File doesn't exist\"}", false;

    buffer := open_workspace_file_buffer(workspace, path, args.file);

    each command in args.write_commands {
        // print("%\n", command);
        switch command.type {
            case WriteFileCommandType.Insert; {
                begin_change(buffer, -1, 0, 0, command.start_line - 1);

                line := get_buffer_line(buffer, command.start_line - 1);
                line = add_new_line(null, buffer, line, true, false);
                lines_written := add_text_lines_to_buffer(buffer, line, command.text);

                record_change(buffer, command.start_line - 1, command.start_line + lines_written, 0, command.start_line + lines_written);
                output.lines_written += lines_written + 1;
            }
            case WriteFileCommandType.Delete; {
                begin_change(buffer, command.start_line - 1, command.end_line - 1, 0, command.start_line - 1);

                line := get_buffer_line(buffer, command.start_line - 1);
                delete_lines_in_range(buffer, line, command.end_line - command.start_line, true);

                record_change(buffer, -1, 0, 0, command.start_line - 1);
                output.lines_deleted += command.end_line - command.start_line + 1;
            }
            case WriteFileCommandType.Overwrite; {
                begin_change(buffer, command.start_line - 1, command.end_line - 1, 0, command.start_line - 1);

                line := get_buffer_line(buffer, command.start_line - 1);
                delete_lines_in_range(buffer, line, command.end_line - command.start_line, false);
                lines_written := add_text_lines_to_buffer(buffer, line, command.text);

                record_change(buffer, command.start_line - 1, command.start_line + lines_written, 0, command.start_line + lines_written);
                output.lines_deleted += command.end_line - command.start_line + 1;
                output.lines_written += lines_written + 1;
            }
        }
    }

    calculate_line_digits(buffer);

    free_allocation(args.write_commands.data);

    output.success = true;
    output_json := serialize_json(output);
    return output_json, true;
}

struct RenameFileArguments {
    ["The path of the file to rename"]
    file: string;
    ["The new path to rename the file"]
    new_path: string;
}

struct RenameFileOutput {
    ["If renaming the file was successful"]
    success: bool;
    ["The new path of the file"]
    new_path: string;
    ["Error message if the file was not renamed"]
    error: string;
}

[tool, "Renames a file"]
string, bool rename_file(Workspace* workspace, RenameFileArguments args, RenameFileOutput output) {
    path := temp_string(workspace.directory, "/", args.file);
    if !file_exists(path) return "{\"success\":false,\"error\":\"File doesn't exist\"}", false;
    new_path := temp_string(workspace.directory, "/", args.new_path);
    if file_exists(new_path) return "{\"success\":false,\"error\":\"New file already exists\"}", false;

    buffer_exists := false;
    each buffer in workspace.buffers {
        if buffer.relative_path == args.file {
            allocate_strings(&args.file);
            old_path := buffer.relative_path;
            buffer.relative_path = args.file;
            free_allocation(old_path.data);

            success, lines, bytes, file := save_buffer(workspace, &buffer);
            if !success {
                return "{\"success\":false,\"error\":\"Unable to save new file\"}", false;
            }
            if !delete_file(path) {
                return "{\"success\":false,\"error\":\"Unable to delete old file\"}", false;
            }

            buffer_exists = true;
            break;
        }
    }

    if !buffer_exists && !rename_file(path, new_path) {
        return "{\"success\":false,\"error\":\"Unable to rename file\"}", false;
    }

    output = {
        success = true;
        new_path = args.file;
    }

    output_json := serialize_json(output);
    return output_json, true;
}

struct DeleteFileArguments {
    ["The path of the file to delete"]
    file: string;
}

struct DeleteFileOutput {
    ["If the file was deleted"]
    success: bool;
    ["Error message if the file was not deleted"]
    error: string;
}

[tool, "Deletes a file"]
string, bool delete_file(Workspace* workspace, DeleteFileArguments args, DeleteFileOutput output) {
    path := temp_string(workspace.directory, "/", args.file);
    if !file_exists(path) return "{\"success\":false,\"error\":\"File doesn't exist\"}", false;
    if !delete_file(path) return "{\"success\":false,\"error\":\"Unable to delete file\"}", false;
    return "{\"success\":true}", false;
}

struct FindFilesArguments {
    ["Query for files, not a regex"]
    query: string;
}

struct FindFilesOutput {
    ["Files that match the query"]
    results: Array<string>;
}

[tool, "Searches for files"]
string, bool find_files(Workspace* workspace, FindFilesArguments args, FindFilesOutput output) {
    output.results = find_files(workspace, args.query, 20);

    output_json := serialize_json(output);

    if output.results.length {
        each result in output.results {
            free_allocation(result.data);
        }
        free_allocation(output.results.data);
    }

    return output_json, true;
}

struct SearchArguments {
    ["Text to search for, not a regex but can include '\\n'"]
    query: string;
    ["Optional file filter for searches, use empty string for no filter"]
    filter: string;
}

struct SearchOutput {
    ["Results that match the text"]
    results: Array<SearchResult>;
}

struct SearchResult {
    ["The file where the text was found"]
    file: string;
    ["The line where the text was found"]
    line: u32;
    ["The column where the text was found"]
    column: u32;
}

[tool, "Searches for text"]
string, bool search_for_text(Workspace* workspace, SearchArguments args, SearchOutput output) {
    output.results = search_for_text(workspace, args.filter, args.query, 20);

    output_json := serialize_json(output);

    if output.results.length {
        each result in output.results {
            free_allocation(result.file.data);
        }
        free_allocation(output.results.data);
    }

    return output_json, true;
}

struct StatusCheckArguments {
    ["Message to update the client"]
    message: string;
}

struct StatusCheckOutput {
    completed: bool;
}

[tool, "Give the user a status update"]
string, bool status_check(Workspace* workspace, StatusCheckArguments args, StatusCheckOutput output) {
    add_to_agent_buffer(workspace, args.message);
    add_agent_buffer_new_lines(workspace, 2);
    return "{\"completed\":true}", false;
}

#private

string read_buffer_lines(Buffer* buffer, int start, int end) {
    start = clamp(start, 1, buffer.line_count);
    end = clamp(end, 1, buffer.line_count);

    start_line := buffer.lines;
    line_number := 1;

    while line_number < start {
        start_line = start_line.next;
        line_number++;
    }

    text: string;
    line := start_line;
    while line_number <= end {
        text.length += line.length + 1;
        line = line.next;
        line_number++;
    }

    line_number = start;
    line = start_line;
    text.data = allocate(text.length);
    while line_number <= end {
        copy_length := clamp(line.length, 0, line_buffer_length);
        memory_copy(text.data + text.length, line.data.data, copy_length);
        text.length += copy_length;

        child := line.child;
        while (child) {
            memory_copy(text.data + text.length, child.data.data, child.length);
            text.length += child.length;
        }

        text[text.length++] = '\n';

        line = line.next;
        line_number++;
    }

    return text;
}
