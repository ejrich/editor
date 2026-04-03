init_exception_handler() {
    #if os == OS.Windows {
        // TODO Implement
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
    // TODO Implement
}
#if os == OS.Linux {
    signal_handler(int signal) {
        log("Hello world\n");
        // TODO Implement
        exit_program(-1);
    }
}
