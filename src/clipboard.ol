init_clipboard() {
    #if os == OS.Windows {
        AddClipboardFormatListener(window.handle);

        get_current_clipboard();
    }
}

enum ClipboardMode {
    Normal;
    Lines;
    Block;
}

struct Clipboard {
    mode: ClipboardMode;
    value: string;
    value_lines: u32;
}

clipboard: Clipboard;

save_string_to_clipboard(string value, ClipboardMode mode) {
    #if os == OS.Linux {
        XSetSelectionOwner(window.handle, CLIPBOARD, window.window, 0);
    }
    else #if os == OS.Windows {
        success := OpenClipboard(window.handle);
        if success {
            EmptyClipboard();

            value_handle := GlobalAlloc(0x42, value.length + 1);
            if value_handle == null {
                log("Failed to allocate pointer for clipboard for '%'\n", value);
                return;
            }

            value_pointer := GlobalLock(value_handle);
            memory_copy(value_pointer, value.data, value.length);
            GlobalUnlock(value_handle);

            ignore_next_clipboard_event = true;
            SetClipboardData(ClipboardFormat.CF_TEXT, value_handle);

            CloseClipboard();
        }
    }

    set_clipboard(value, mode);
}

set_clipboard(string value, ClipboardMode mode = ClipboardMode.Normal) {
    line_count: u32 = 1;
    each i in value.length {
        if value[i] == '\n'
            line_count++;
    }

    clipboard = {
        mode = mode;
        value = value;
        value_lines = line_count;
    }
}

#if os == OS.Windows {
    ignore_next_clipboard_event := false;

    get_current_clipboard() {
        clipboard_string: string;

        success := OpenClipboard(window.handle);
        if success {
            clipboard_handle := GetClipboardData(ClipboardFormat.CF_TEXT);
            if clipboard_handle {
                clipboard_pointer := GlobalLock(clipboard_handle);
                clipboard_string = convert_c_string(clipboard_pointer);

                GlobalUnlock(clipboard_handle);

                allocate_strings(&clipboard_string);
                set_clipboard(clipboard_string);
            }

            CloseClipboard();
        }
    }
}
