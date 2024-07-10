set scrolloff=99

nnoremap <buffer> <F7> <Cmd>let time_pos = json_decode(system('echo ''{ "command": ["get_property", "time-pos"] }'' \| socat - /tmp/mpv-socket')).data - 0.3
            \ \| let m = floor(time_pos / 60)
            \ \| let s = time_pos - (m * 60)
            \ \| call setline('.', substitute(getline('.'), '^', printf('[%02.0f:%05.2f]', m, s), ''))
            \ <CR>j0
nnoremap <buffer> <silent> <F8> <Cmd>silent !echo seek -2 \| socat - /tmp/mpv-socket<CR>
nnoremap <buffer> <F6> -y%k"_Dpb<C-x>2j0
imap <buffer> <F7> <C-g>u<Esc><F7>
imap <buffer> <F8> <Esc><F8, , ss>
