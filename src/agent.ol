#import openssl

init_ssl() {
    CRYPTO_set_mem_functions(CRYPTO_malloc_impl, CRYPTO_realloc_impl, CRYPTO_free_impl);

    cacert := temp_string(get_program_directory(), "/cacert.pem");
    ssl_context = initialize_openssl(OpenSSLMethod.Client, cacert);
    assert(ssl_context != null, "Unable to initialize OpenSSL context");
}

deinit_ssl() {
    SSL_CTX_free(ssl_context);
}


#private

ssl_context: SSL_CTX*;

void* CRYPTO_malloc_impl(u64 num, u8* file, int line) {
    str := convert_c_string(file);
    return allocate(num);
}

void* CRYPTO_realloc_impl(void* addr, u64 num, u8* file, int line) {
    str := convert_c_string(file);
    if addr == null return allocate(num);

    block := cast(MemoryBlock*, addr) - 1;
    return reallocate(addr, block.size, num);
}

CRYPTO_free_impl(void* addr, u8* file, int line) {
    str := convert_c_string(file);
    free_allocation(addr);
}
