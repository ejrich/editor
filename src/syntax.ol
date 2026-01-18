Syntax* get_syntax_for_file(string file_path) {
    extension_start := file_path.length;
    each i in file_path.length {
        if file_path[i] == '.' {
            extension_start = i + 1;
        }
    }

    if extension_start + 1 < file_path.length {
        extension: string = {
            length = file_path.length - extension_start;
            data = file_path.data + extension_start;
        }

        each syntax in syntax_configurations {
            if syntax.extension == extension {
                log("%\n", syntax);
                return &syntax;
            }
        }
    }

    return null;
}

struct Syntax {
    extension: string;
    keywords: Array<SyntaxKeyword>;
    single_line_comment: string;
    multi_line_comment_start: string;
    multi_line_comment_end: string;
    string_start_end: string;
    multi_line_string_start_end: string;
}

struct SyntaxKeyword {
    value: string;
    level: u8;
}

keyword_levels := 3; #const

#private

syntax_configurations: Array<Syntax> = [
    {
        extension = "ol";
        keywords = [
            // TODO Fix the compiler to generate these values
            { value = "return";    level = 0; },
            { value = "true";      level = 0; },
            { value = "false";     level = 0; },
            { value = "if";        level = 0; },
            { value = "else";      level = 0; },
            { value = "while";     level = 0; },
            { value = "each";      level = 0; },
            { value = "in";        level = 0; },
            { value = "out";       level = 0; },
            { value = "struct";    level = 0; },
            { value = "enum";      level = 0; },
            { value = "union";     level = 0; },
            { value = "interface"; level = 0; },
            { value = "null";      level = 0; },
            { value = "cast";      level = 0; },
            { value = "operator";  level = 0; },
            { value = "break";     level = 0; },
            { value = "continue";  level = 0; },
            { value = "asm";       level = 0; },
            { value = "switch";    level = 0; },
            { value = "case";      level = 0; },
            { value = "default";   level = 0; },
            { value = "defer";     level = 0; },
        ]
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        string_start_end = "\"";
        multi_line_string_start_end = "\"\"\"";
    },
    {
        extension = "c";
        keywords = [
            { value = "auto";     level = 0; },
            { value = "break";    level = 0; },
            { value = "case";     level = 0; },
            { value = "char";     level = 0; },
            { value = "const";    level = 0; },
            { value = "continue"; level = 0; },
            { value = "default";  level = 0; },
            { value = "do";       level = 0; },
            { value = "double";   level = 0; },
            { value = "else";     level = 0; },
            { value = "enum";     level = 0; },
            { value = "extern";   level = 0; },
            { value = "float";    level = 0; },
            { value = "for";      level = 0; },
            { value = "goto";     level = 0; },
            { value = "if";       level = 0; },
            { value = "int";      level = 0; },
            { value = "long";     level = 0; },
            { value = "register"; level = 0; },
            { value = "return";   level = 0; },
            { value = "short";    level = 0; },
            { value = "signed";   level = 0; },
            { value = "sizeof";   level = 0; },
            { value = "static";   level = 0; },
            { value = "struct";   level = 0; },
            { value = "switch";   level = 0; },
            { value = "typedef";  level = 0; },
            { value = "union";    level = 0; },
            { value = "unsigned"; level = 0; },
            { value = "void";     level = 0; },
            { value = "volatile"; level = 0; },
            { value = "while";    level = 0; },
        ]
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        string_start_end = "\"";
    },
    {
        extension = "cs";
        keywords = [
            { value = "abstract";   level = 0; },
            { value = "as";         level = 0; },
            { value = "base";       level = 0; },
            { value = "bool";       level = 0; },
            { value = "break";      level = 0; },
            { value = "byte";       level = 0; },
            { value = "case";       level = 0; },
            { value = "catch";      level = 0; },
            { value = "char";       level = 0; },
            { value = "checked";    level = 0; },
            { value = "class";      level = 0; },
            { value = "const";      level = 0; },
            { value = "continue";   level = 0; },
            { value = "decimal";    level = 0; },
            { value = "default";    level = 0; },
            { value = "delegate";   level = 0; },
            { value = "do";         level = 0; },
            { value = "double";     level = 0; },
            { value = "else";       level = 0; },
            { value = "enum";       level = 0; },
            { value = "event";      level = 0; },
            { value = "explicit";   level = 0; },
            { value = "extern";     level = 0; },
            { value = "false";      level = 0; },
            { value = "finally";    level = 0; },
            { value = "fixed";      level = 0; },
            { value = "float";      level = 0; },
            { value = "for";        level = 0; },
            { value = "foreach";    level = 0; },
            { value = "goto";       level = 0; },
            { value = "if";         level = 0; },
            { value = "implicit";   level = 0; },
            { value = "in";         level = 0; },
            { value = "int";        level = 0; },
            { value = "interface";  level = 0; },
            { value = "internal";   level = 0; },
            { value = "is";         level = 0; },
            { value = "lock";       level = 0; },
            { value = "long";       level = 0; },
            { value = "namespace";  level = 0; },
            { value = "new";        level = 0; },
            { value = "null";       level = 0; },
            { value = "object";     level = 0; },
            { value = "operator";   level = 0; },
            { value = "out";        level = 0; },
            { value = "override";   level = 0; },
            { value = "params";     level = 0; },
            { value = "private";    level = 0; },
            { value = "protected";  level = 0; },
            { value = "public";     level = 0; },
            { value = "readonly";   level = 0; },
            { value = "ref";        level = 0; },
            { value = "return";     level = 0; },
            { value = "sbyte";      level = 0; },
            { value = "sealed";     level = 0; },
            { value = "short";      level = 0; },
            { value = "sizeof";     level = 0; },
            { value = "stackalloc"; level = 0; },
            { value = "static";     level = 0; },
            { value = "string";     level = 0; },
            { value = "struct";     level = 0; },
            { value = "switch";     level = 0; },
            { value = "this";       level = 0; },
            { value = "throw";      level = 0; },
            { value = "true";       level = 0; },
            { value = "try";        level = 0; },
            { value = "typeof";     level = 0; },
            { value = "uint";       level = 0; },
            { value = "ulong";      level = 0; },
            { value = "unchecked";  level = 0; },
            { value = "unsafe";     level = 0; },
            { value = "ushort";     level = 0; },
            { value = "using";      level = 0; },
            { value = "virtual";    level = 0; },
            { value = "void";       level = 0; },
            { value = "volatile";   level = 0; },
            { value = "while";      level = 0; },
        ]
        single_line_comment = "//";
        multi_line_comment_start = "/*";
        multi_line_comment_end = "*/";
        string_start_end = "\"";
    }
]
