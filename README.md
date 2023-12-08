This is a collection of scripts to manage LRC synchronized lyrics of songs playings in mpv. It provides keybindings to download the lyrics of the current song, and also scripts to create and synchronize lyrics yourself with vim on Unix-like systems.

## lrc.lua

### musixmatch-download

Downloads the lyrics of the currently playing song from Musixmatch's API.

The default keybinding is `Alt+m`, and it can be changed by binding `script-message musixmatch-download`

### netease-download

Downloads the lyrics of the currently playing song from NetEase's API. It has more Japanese lyrics than Musixmatch.

The default keybinding is `Alt+n`, and it can be changed by binding `script-message netease-download`

### offset-sub

After adjusting `sub-delay` in mpv, this offsets the timestamps in the current subtitle file accordingly. It then resets `sub-delay` and reloads the subtitle track so you can offset it again if necessary. This works with any external subtitle and not just LRC. ffmpeg needs to be in `PATH`, or in the same folder as mpv on Windows, for this to work.

The default keybinding is `Alt+o`, and it can be changed by binding `script-message offset-sub`

## lrc.sh

This POSIX script creates the skeleton of a new LRC file by fetching the metadata of the song playing in mpv and your nickname from the first argument to it, and opens it in `$EDITOR`. It also opens `$BROWSER`, falling back to chromium if that is not defined, pointing it to search page for the lyrics in the browser's default search engine. When it detects Japanese characters in the song path, it searches for lyrics in Japanese.

When lyrics sites try to block copying text, you can inspect the HTML element with the lyrics and execute `copy($0.innerText)` in the console.

If the current song already has an LRC file, it doesn't overwrite it, but opens it in `$EDITOR` so you can quickly fix mistakes you notice while listening to the song.

`input-ipc-server=/tmp/mpv-socket` is assumed for the mpv instance that plays music, and jq and socat are required.

## lrc.vim

This provides the following keybindings:

* `F7` Prepend the current timestamp of a song to the current line.
* `F8` Seek backwards 2 seconds.
* `F6` Insert a timestamp equals to the one above minus 1/100th of a second in a blank line that is 2 lines above. When you have to synchronize a blank line between 2 lines with little delay between them, synchronize only the next filled line and use this.

It also increases `scrolloff` to keep the cursor in the center as you synchronize the lines.

To use this, add `autocmd BufNewFile,BufReadPost *.lrc setfiletype lrc` to your configuration file, then copy `lrc.vim` to `~/.config/nvim/ftplugin` or `~/.vimrc/ftplugin`.

I recommend https://github.com/vim-scripts/lrc.vim for syntax highlighting. It errors because of carriage returns, but you can remove them with `sed -i 's/\r//' lrc.vim`

## Overlay

If you use X11 with Nvidia proprietary drivers or Wayland, you can display lyrics in a transparent overlay with `--background=0/0 --alpha --ontop --input-cursor-passthrough`.

## Note on using LRC files from Minilyrics in mpv

ffmpeg doesn't detect LRC files if [id:...] is the first line. id tags can be removed with `sed -i '/\[id:/d' *.lrc`

ffmpeg doesn't detect LRC files encoded in UTF-16. They can be converted to UTF-8 with:
`for lrc in *.lrc; do if file $lrc | grep -q UTF-16; then iconv -f UTF-16 -t UTF-8 $lrc -o $lrc; fi; done`

ffmpeg doesn't detect LRC files missing the milliseconds. You can add them with `sed -i '/\[[0-9]/s/]/.00]/' foo.lrc`

ffmpeg also splits lines like `[01:00.00][02:00.00]foo` which mpv shows only the first time, and removes blank lines and Windows carriage returns.
