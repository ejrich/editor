init_exception_handler() {
    #if os == OS.Windows {
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
    int exception_handler(EXCEPTION_POINTERS* exception_inf) {
        log("Hello world\n");
        // TODO Implement
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
