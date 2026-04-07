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
        a := rt_sigaction(LinuxSignal.SIGSEGV, &sigaction, null, 8);
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

        if exception_info != null && exception_info.ExceptionRecord != null {
            log("Exception occured with code 0x%\n", uint_format(exception_info.ExceptionRecord.ExceptionCode, 16, 8));
        }
        else {
            log("Exception occured\n");
        }

        log("Stack trace:\n");

        each i in frames {
            address := cast(s64, stack[i]);
            success := SymFromAddr(process_handle, address, null, symbol);
            frame := frames - i - 1;
            if success {
                name := convert_c_string(&symbol.Name);
                success = SymGetLineFromAddr64(process_handle, address, &column, &line);
                if success {
                    file := convert_c_string(line.FileName);
                    log("% %:%:% % - %\n", frame, file, line.LineNumber, column, name, stack[i]);
                }
                else {
                    log("% % - %\n", frame, name, stack[i]);
                }
            }
            else {
                log("% - %\n", frame, stack[i]);
            }
        }

        exit_program(-1);
        return 0;
    }
}
#if os == OS.Linux {
    signal_handler(LinuxSignal signal) {
        log("Hello world\n");
        // TODO Implement
        exit_program(-1);
    }
}
