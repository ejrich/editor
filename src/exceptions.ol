init_exception_handler() {
    #if os == OS.Windows {
        process_handle = GetCurrentProcess();
        SymSetOptions(0x10);
        SymInitialize(process_handle, null, true);
        AddVectoredExceptionHandler(1, exception_handler);
    }
    #if os == OS.Linux {
        handler: SigHandler_T;
        handler.sigaction_handler = signal_handler;
        sigaction: Sigaction = {
            sa_handler = handler;
            sa_flags = 0x4000000;
            sa_restorer = signal_restorer;
        }
        rt_sigaction(LinuxSignal.SIGSEGV, &sigaction, null, 8);
    }

    a: int* = null;
    b := *a;
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
            if success {
                name := convert_c_string(&symbol.Name);
                success = SymGetLineFromAddr64(process_handle, address, &column, &line);
                if success {
                    file := convert_c_string(line.FileName);
                    log("% %:%:% % - %\n", i, file, line.LineNumber, column, name, stack[i]);
                }
                else {
                    log("% % - %\n", i, name, stack[i]);
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
    struct StackFrameAddress {
        previous: StackFrameAddress*;
        return_address: void*;
    }

    signal_handler(LinuxSignal signal, SigInfo* info, UContext* context) {
        path_length := 4096; #const
        executable_path: CArray<u8>[path_length];
        self_path := "/proc/self/exe"; #const
        bytes := readlink(self_path.data, &executable_path, path_length - 1);

        has_debug_info := false;
        path_string: string = { length = bytes; data = &executable_path; }
        found, executable_file := read_file(path_string);
        if found {
            header := cast(Elf64_Ehdr*, executable_file.data);
            log("%\n", *header);

            sections: Array<Elf64_Shdr>;
            sections.length = header.e_shnum;
            sections.data = cast(Elf64_Shdr*, executable_file.data + header.e_shoff);
            shstrtab := sections[header.e_shstrndx];
            each section in sections {
                name := convert_c_string(executable_file.data + shstrtab.sh_offset + section.sh_name);
                log("Section %: %\n", name, section);
                if name == ".debug_info" {
                    has_debug_info = true;
                }
            }
        }

        frame: StackFrameAddress*;
        asm {
            out frame, rbp;
        }

        log("Stack trace:\n");

        index := 0;
        while frame {
            log("% - %\n", index++, frame);
            frame = frame.previous;
        }

        exit_program(-1);
    }

    signal_restorer() {
        rt_sigreturn();
    }

    struct Elf64_Ehdr {
        __reserved1: u64;
        __reserved2: u64;
        e_type: u16;
        e_machine: u16;
        e_version: u32;
        e_entry: u64;
        e_phoff: u64;
        e_shoff: u64;
        e_flags: u32;
        e_ehsize: u16;
        e_phentsize: u16;
        e_phnum: u16;
        e_shentsize: u16;
        e_shnum: u16;
        e_shstrndx: u16;
    }

    struct Elf64_Shdr {
        sh_name: u32;
        sh_type: u32;
        sh_flags: u64;
        sh_addr: u64;
        sh_offset: u64;
        sh_size: u64;
        sh_link: u32;
        sh_info: u32;
        sh_addralign: u64;
        sh_entsize: u64;
    }
}
