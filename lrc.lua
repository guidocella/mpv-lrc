local utils = require 'mp.utils'

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

mp.add_key_binding('Alt+l', 'show-lyrics', function()
    utils.shared_script_property_set('showed-lyrics', 1)
    mp.set_property('osd-align-x', 'center')
    local connection = require 'socket.unix'()
    connection:connect('/tmp/mpv-socket')
    connection:send('{"command": ["observe_property", 1, "sub-text"]}\n')
    while true do
        local line = connection:receive()
        if line == nil then break end
        line = utils.parse_json(line)
        if line.id == 1 and line.data then
            mp.osd_message(line.data, 20000)
        end
    end
end)
