set scrolloff=99

nnoremap <buffer> <F7> <Cmd>let time_pos = json_decode(system('echo ''{ "command": ["get_property", "time-pos"] }'' \| socat - /tmp/mpv-socket')).data - 0.3
            \ \| let seconds = float2nr(time_pos)
            \ \| call setline('.', substitute(getline('.'), '^',
            \     '['.printf('%02d', seconds / 60).':'.printf('%02d', seconds % 60).'.'.split(string(time_pos), '\.')[1][0:1].']'
            \  , ''))<CR>j0
nnoremap <buffer> <silent> <F8> <Cmd>silent !echo seek -2 \| socat - /tmp/mpv-socket<CR>
nnoremap <buffer> <F6> -y%k"_Dpb<C-x>2j0
imap <buffer> <F7> <C-g>u<Esc><F7>
imap <buffer> <F8> <Esc><F8>
