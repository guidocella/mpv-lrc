This is a collection of scripts for Unix-like systems to manage lrc synchronized lyrics of songs playings in mpv. Keybindings to synchronize lyrics with Vim are provided.

`input-ipc-server=/tmp/mpv-socket` is assumed for the mpv instance that plays music and socat is required.

## lrc.vim

This provides the following keybindings:

* `F7` Prepend the current timestamp of a song to the current line.
* `F8` Seek backwards 2 seconds.
* `F6` Insert a timestamp equals to the one above minus 1/100th of a second in a blank line that is 2 lines above. When you have to synchronize a blank line between 2 lines with little delay between them, synchronize only the next filled line and use this.

It also increases `scrolloff` to keep the cursor in the center as you synchronize the lines.

To use this, add
``vim
autocmd BufNewFile,BufReadPost *.lrc setfiletype lrc
``
to your configuration file, then just copy `lrc.vim` to `~/.config/nvim/ftplugin`/`~/.vimrc/ftplugin`. It's a tiny file anyway and you may want to change the mappings or the socket path.

I recommend https://github.com/vim-scripts/lrc.vim for syntax highlighting. It errors because of carriage returns, but you can remove them with `sed -i 's/\r//' lrc.vim`

## lrc.sh

This POSIX script creates the skeleton of a new lrc file by fetching the metadata of the song playing in mpv and your nickname from the first argument to it, and opens it in `$EDITOR`. It also opens `$BROWSER`, falling back to chromium if that is not defined, pointing it to a page to copy the lyrics from as determined from the top DuckDuckGo search result. If `xclip` or `wl-copy` are installed, it copies the search query to the clipboard, so that when the top result isn't good, you can paste the query in your browser and browse more search results, possibly in a different search engine. When it detects Japanese characters in the song path, it searches for lyrics in Japanese.

If the current song already has an lrc file, it doesn't overwrite it, but opens it in `$EDITOR` so you can quickly fix mistakes you notice while listening to the song.

Requires jq.

## lrc.lua

This provides 2 keybindings:

### offset-lrc

After adjusting `sub-delay` in mpv, this offsets the timestamps in the current lrc file accordingly (using ffmpeg). It then resets `sub-delay` and reloads the sub track so you can update the lrc again if necessary.

The default keybinding is `Ctrl+o` and it can be changed by binding `script-message offset-lrc`

### show-lyrics

If you use X11 with Nvidia proprietary drivers or Wayland, you can display lyrics in a transparent overlay with `--background=0/0 --alpha` instead of bothering with this.

While another mpv instance is playing songs, this shows their lyrics on the OSD of the current mpv instance which is playing videos or images.

The default keybinding is `Alt+l` and it can be changed by binding `script-message show-lyrics`. This function requires lua-socket, which can be installed with `pacman -S lua51-socket` on Arch or `apt install lua-socket` on Debian.

This unfortunately prevents mpv from quitting unless you press `Ctrl+c` twice in the terminal, so we need to register a shutdown handler that instructs mpv to terminate again in `lrc-shutdown.lua`; this must be in a different script. This is done only if `show-lyrics` was started to reduce the chances of `end-file` handlers not completing.

You can alternatively break out of the loop when the `playback-abort` property is `true`, but that still delays quitting until the next line is fetched.

I used to have this functionality in a shell script that communicated between the sockets of the 2 mpv instances, but that was also problematic because the socket I use for videos and images changes at runtime and may be missing.

## Note on using lrc files from Minilyrics in mpv

ffmpeg doesn't detect lrc files if [id:...] is the first line. id tags can be removed with `sed -i '/\[id:/d' *.lrc`

ffmpeg doesn't detect lrc files encoded in UTF-16. They can be converted to UTF-8 with:
`for lrc in *.lrc; do if file $lrc | grep -q UTF-16; then iconv -f UTF-16 -t UTF-8 $lrc -o $lrc; fi; done`

ffmpeg doesn't detect lrc files missing the milliseconds. You can add them with `sed -i '/\[[0-9]/s/]/.00]/' foo.lrc`

ffmpeg also splits lines like `[01:00.00][02:00.00]foo` which mpv shows only the first time, and removes blank lines and Windows carriage returns.
