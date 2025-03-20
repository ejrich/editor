au BufEnter *.ol :setlocal commentstring=//\ %s
au BufEnter *.glsl :setlocal commentstring=//\ %s

lua SetupP4(string.lower(vim.fn.hostname()) .. "-editor")

if has('win32')
    map <leader><F8>  :Dispatch C:\lang\ol\bin\Debug\net8.0\ol.exe src/first.ol<CR>
    map <leader>t<F8> :Dispatch C:\lang\ol\bin\Debug\net8.0\ol.exe -R src/first.ol<CR>
    map <leader><F5>  :Dispatch .\run_tree\editor src/first.ol<CR>
else
    map <leader><F8>  :Dispatch ~/lang/ol/bin/Debug/net8.0/ol src/first.ol<CR>
    map <leader>t<F8> :Dispatch ~/lang/ol/bin/Debug/net8.0/ol -R src/first.ol<CR>
    map <leader><F5>  :Dispatch ./run_tree/editor src/first.ol<CR>
endif
