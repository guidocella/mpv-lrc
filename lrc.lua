local options = {
    musixmatch_token = '220215b052d6aeaa3e9a410986f6c3ae7ea9f5238731cb918d05ea',
}
local utils = require 'mp.utils'

require 'mp.options'.read_options(options)

local function shell_escape(string)
    return "'" .. string:gsub("'", "'\\''") .. "'"
end

local function error_message(string)
    mp.msg.error(string)
    if mp.get_property_native('vo-configured') then
        mp.osd_message(string, 5)
    end
end

local function save_lyrics(lyrics)
    local current_sub_path = mp.get_property('current-tracks/sub/external-filename')

    if current_sub_path and lyrics:match('^%[') == nil then
        error_message("Only lyrics without timestamps are available, so the existing LRC file won't be overwritten")
        return
    end

    local success_message = 'LRC downloaded'
    if current_sub_path and utils.file_info('/tmp') then
        -- os.rename only works across the same filesystem
        local _, current_sub_filename = utils.split_path(current_sub_path)
        local current_sub = io.open(current_sub_path)
        local backup = io.open('/tmp/' .. current_sub_filename, 'w')
        if current_sub and backup then
            backup:write(current_sub:read('a'))
            success_message = success_message .. '. The old one has been backupped to /tmp.'
        end
        current_sub:close()
        backup:close()
    end

    local path = mp.get_property('path')
    local lrc_path = (path:match('(.*)%.[^/]*$') or path) .. '.lrc'
    local lrc = io.open(lrc_path, 'w')
    if lrc == nil then
        error_message('Failed writing to ' .. lrc_path)
        return
    end
    lrc:write(lyrics)
    lrc:close()

    if lyrics:match('^%[') then
        mp.command(current_sub_path and 'sub-reload 1' or 'rescan-external-files')
        mp.osd_message(success_message)
    else
        mp.osd_message('Lyrics without timestamps downloaded')
    end
end

mp.add_key_binding('Alt+m', 'musixmatch-download', function()
    local metadata = mp.get_property_native('metadata')
    -- The keys are lower case in ID3 tags and upper case in Vorbis comments.
    local title = metadata.title or metadata.TITLE
    local artist = metadata.artist or metadata.ARTIST

    if not title then
        error_message('This song has no title metadata')
        return
    end

    if not artist then
        error_message('This song has no artist metadata')
        return
    end

    mp.osd_message('Downloading lyrics')

    local r = mp.command_native({
        name = 'subprocess',
        capture_stdout = true,
        args = {
            'curl',
            '--silent',
            '--get',
            '--cookie', 'x-mxm-token-guid=' .. options.musixmatch_token, -- avoids a redirect
            'https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get',
            '--data', 'app_id=web-desktop-app-v1.0',
            '--data', 'usertoken=' .. options.musixmatch_token,
            '--data-urlencode', 'q_track=' .. title,
            '--data-urlencode', 'q_artist=' .. artist,
        }
    })

    if r.killed_by_us then
        -- don't print an error when curl fails because the playlist index was changed
        return
    end

    if r.status < 0 then
        error_message('The curl request to Musixmatch failed with code ' .. r.status)
        return
    end

    local response, error = utils.parse_json(r.stdout)

    if error then
        error_message('Unable to parse the JSON returned by Musixmatch')
        return
    end

    -- io.open('/tmp/musixmatch.json', 'w'):write(r.stdout)

    if response.message.header.status_code == 401 and response.message.header.hint == 'renew' then
        error_message('The Musixmatch token has been rate limited. script-opts/lrc.conf explains how to generate a new one.')
        return
    end

    if response.message.header.status_code ~= 200 then
        error_message('Request failed with status code ' .. response.message.header.status_code .. '. Hint: ' .. response.message.header.hint)
        return
    end

    local body = response.message.body.macro_calls

    local lyrics = ''
    if body['matcher.track.get'].message.header.status_code == 200 then
        if body['matcher.track.get'].message.body.track.has_subtitles == 1 then
            lyrics = body['track.subtitles.get'].message.body.subtitle_list[1].subtitle.subtitle_body
        elseif body['matcher.track.get'].message.body.track.has_lyrics == 1 then -- lyrics without timestamps
            lyrics = body['track.lyrics.get'].message.body.lyrics.lyrics_body
        elseif body['matcher.track.get'].message.body.track.instrumental == 1 then
            error_message('This is an instrumental track')
            return
        end
    end

    if lyrics == '' then
        error_message('Lyrics not found')
        return
    end

    save_lyrics(lyrics)
end)

mp.add_key_binding('Alt+n', 'netease-download', function()
    local metadata = mp.get_property_native('metadata')
    local title = metadata.title or metadata.TITLE
    local artist = metadata.artist or metadata.ARTIST

    if not title then
        error_message('This song has no title metadata')
        return
    end

    if not artist then
        error_message('This song has no artist metadata')
        return
    end

    mp.osd_message('Downloading lyrics')

    local r = mp.command_native({
        name = 'subprocess',
        capture_stdout = true,
        args = {
            'curl',
            '--silent',
            '--get',
            'https://music.xianqiao.wang/neteaseapiv2/search?limit=10',
            '--data-urlencode', 'keywords=' .. title .. ' ' .. artist,
        }
    })

    if r.killed_by_us then
        return
    end

    if r.status < 0 then
        error_message('The first curl request to NetEase failed with code ' .. r.status)
        return
    end

    local response, error = utils.parse_json(r.stdout)

    if error then
        error_message('Unable to parse the JSON returned by NetEase')
        return
    end

    -- io.open('/tmp/netease-search.json', 'w'):write(r.stdout)

    local songs = response.result.songs

    if #songs == 0 then
        error_message('Lyrics not found')
        return
    end

    local song = songs[1]
    local album = metadata.album or metadata.ALBUM
    if album then
        album = album:lower()

        for _, loop_song in pairs(songs) do
            if loop_song.album.name:lower() == album then
                song = loop_song
                break
            end
        end
    end

    mp.msg.verbose('Downloading NetEase lyrics for the song with id: ' .. song.id .. ', name: ' .. song.name .. ', artist: ' .. song.artists[1].name .. ', album: ' .. song.album.name)

    r = mp.command_native({
        name = 'subprocess',
        capture_stdout = true,
        args = {
            'curl',
            '--silent',
            'https://music.xianqiao.wang/neteaseapiv2/lyric?id=' .. song.id,
        }
    })

    if r.killed_by_us then
        return
    end

    if r.status < 0 then
        error_message('The second curl request to NetEase failed with code ' .. r.status)
        return
    end

    response, error = utils.parse_json(r.stdout)

    if error then
        error_message('Unable to parse the JSON returned by NetEase')
        return
    end

    -- io.open('/tmp/netease-song.json', 'w'):write(r.stdout)

    save_lyrics(response.lrc.lyric)
end)

mp.add_key_binding('Ctrl+o', 'offset-lrc', function()
    local lrc_path = mp.get_property('current-tracks/sub/external-filename')

    if not lrc_path then
        error_message('No LRC subtitle is loaded')
        return
    end

    lrc_path = shell_escape(lrc_path)
    if not os.execute(
        'lrc=$(echo "[offset:' .. mp.get_property('sub-delay') * -1000 .. ']" | cat - '
        .. lrc_path .. '| ffmpeg -i - -f lrc - |'
        .. 'grep -Ev "\\[(re|ve):") && echo "$lrc" >' .. lrc_path
    ) then
        error_message('LRC update failed')
        return
    end

    mp.set_property('sub-delay', 0)
    mp.command('sub-reload 1')
    mp.osd_message('LRC updated')
end)
