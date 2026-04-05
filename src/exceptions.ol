init_exception_handler() {
    #if os == OS.Windows {
        process_handle = GetCurrentProcess();
        SymSetOptions(0x10);
        SymInitialize(process_handle, null, true);
        AddVectoredExceptionHandler(1, exception_handler);
    }
    #if os == OS.Linux {
        sigaction: Sigaction = {
            sa_handler = signal_handler;
        }
        a := rt_sigaction(11, &sigaction, null, 8);
        log("%\n", a);
    }
}

#private

#if os == OS.Windows {
    process_handle: Handle*;

    int exception_handler(EXCEPTION_POINTERS* exception_info) {
        stack_frames := 100; #const
        stack: Array<void*>[stack_frames];

        frames := RtlCaptureStackBackTrace(4, stack_frames, stack.data, null);

        max_name_length := 255;
        symbol_buffer: Array<u8>[size_of(SYMBOL_INFO) + max_name_length];

        symbol := cast(SYMBOL_INFO*, symbol_buffer.data);
        symbol.SizeOfStruct = size_of(SYMBOL_INFO);
        symbol.MaxNameLen = max_name_length;
        line: IMAGEHLP_LINE = {
            SizeOfStruct = size_of(IMAGEHLP_LINE);
        }
        column: int;

        log("Exception occured, printing current stack:\n");

        each i in frames {
            address := cast(s64, stack[i]);
            success := SymFromAddr(process_handle, address, null, symbol);
            if success {
                name := convert_c_string(&symbol.Name);
                success = SymGetLineFromAddr64(process_handle, address, &column, &line);
                if success {
                    file := convert_c_string(line.FileName);
                    log("%:%:% % - %\n", file, line.LineNumber, column, name, stack[i]);
                }
                else {
                    log("% - %\n", name, stack[i]);
                }
            }
            else {
                log("% - %\n", i, stack[i]);
            }
        }

        exit_program(-1);
        return 0;
    }
}
#if os == OS.Linux {
    signal_handler(int signal) {
        log("Hello world\n");
        // TODO Implement
        exit_program(-1);
    }
}
