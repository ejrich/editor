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
}

[tool, "Reads the entire text of a requested file"]
string, bool read_file_text(Workspace* workspace, ReadFileArguments args, ReadFileOutput output) {
    print("Read file - %\n", args);
    return "{success:true}", false;
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
}

[tool, "Reads a block of lines from a requested file"]
string, bool read_file_lines(Workspace* workspace, ReadFileLineArguments args, ReadFileLinesOutput output) {
    print("Read file lines - %\n", args);
    return "{success:true}", false;
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
    print("Create file - %\n", args);
    return "{success:true}", false;
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
}

[tool, "Writes to a file with commands"]
string, bool write_file(Workspace* workspace, WriteFileArguments args, WriteFileOutput output) {
    print("Write file - %\n", args);
    return "{success:true,lines_written:0,lines_deleted:0}", false;
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
    print("Rename file - %\n", args);
    return "{success:true}", false;
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
    print("Delete file - %\n", args);
    return "{success:true}", false;
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
    print("Search for files - %\n", args);
    return "{results:[]}", false;
}

struct SearchArguments {
    ["Text to search for, not a regex but can include '\\n'"]
    query: string;
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
string, bool search_for_text(Workspace* workspace, WriteFileArguments args, WriteFileOutput output) {
    print("Search for text - %\n", args);
    return "{results:[]}", false;
}

struct StatusCheckArguments {
    ["Message to update the client"]
    message: string;
}

struct StatusCheckOutput {
    completed: bool;
}

[tool, "Gives a status update"]
string, bool status_check(Workspace* workspace, StatusCheckArguments args, StatusCheckOutput output) {
    print("Status check - %\n", args);
    return "{completed:true}", false;
}
