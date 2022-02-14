local function shell_escape(string)
    return "'" .. string:gsub("'", "'\\''") .. "'"
end

mp.add_key_binding('Ctrl+o', 'offset-lrc', function()
    local lrc_path = mp.get_property('current-tracks/sub/external-filename')
    if not lrc_path then return end
    lrc_path = shell_escape(lrc_path)
    if not os.execute(
        'lrc=$(echo "[offset:' .. mp.get_property('sub-delay') * -1000 .. ']" | cat - '
        .. lrc_path .. '| ffmpeg -i - -f lrc - |'
        .. 'grep -Ev "\\[(re|ve):") && echo "$lrc" >' .. lrc_path
    ) then
        mp.osd_message('LRC update failed')
        return
    end
    mp.set_property('sub-delay', 0)
    mp.command('sub-reload 1')
    mp.osd_message('LRC updated')
end)
