local options = {
    musixmatch_token = '2501192ac605cc2e16b6b2c04fe43d1011a38d919fe802976084e7',
    mark_as_ja = false,
}
local utils = require 'mp.utils'

require 'mp.options'.read_options(options)

local function show_error(message)
    mp.msg.error(message)
    if mp.get_property_native('vo-configured') then
        mp.osd_message(message, 5)
    end
end

local function curl(args)
    local r = mp.command_native({name = 'subprocess', capture_stdout = true, args = args})

    if r.killed_by_us then
        -- don't print an error when curl fails because the playlist index was changed
        return
    end

    if r.status < 0 then
        show_error('subprocess error: ' .. r.error_string)
        return
    end

    if r.status > 0 then
        show_error('curl failed with code ' .. r.status)
        return
    end

    local response, error = utils.parse_json(r.stdout)

    if error then
        show_error('Unable to parse the JSON response')
        return
    end

    return response
end

local function get_metadata()
    local metadata = mp.get_property_native('metadata')

    if metadata == nil then
        return false, 'Metadata not yet loaded'
    end

    local title = metadata.title or metadata.TITLE or metadata.Title
    local artist = metadata.artist or metadata.ARTIST or metadata.Artist
    local album = metadata.album or metadata.ALBUM or metadata.Album

    return title, artist, album
end

local function is_japanese(lyrics)
    -- http://lua-users.org/wiki/LuaUnicode Lua patterns don't support Unicode
    -- ranges, and you can't even iterate over \u{XXX} sequences in Lua 5.1 and
    -- 5.2, so just search for some Hiragana characters.

    for _, kana in pairs({
        'あ', 'い', 'う', 'え', 'お',
        'か', 'き', 'く', 'け', 'こ',
        'さ', 'し', 'す', 'せ', 'そ',
        'た', 'ち', 'つ', 'て', 'と',
        'な', 'に', 'ぬ', 'ね', 'の',
        'は', 'ひ', 'ふ', 'へ', 'ほ',
        'ま', 'み', 'む', 'め', 'も',
        'や',       'ゆ',       'よ',
        'ら', 'り', 'る', 'れ', 'ろ',
        'わ',                   'を',
    }) do
        if lyrics:find(kana) then
            return true
        end
    end
end

local function save_lyrics(lyrics)
    if lyrics == '' or lyrics == nil then
        show_error('Lyrics not found')
        return
    end

    local current_sub_path = mp.get_property('current-tracks/sub/external-filename')

    if current_sub_path and lyrics:find('^%[') == nil then
        show_error("Only lyrics without timestamps are available, so the existing LRC file won't be overwritten")
        return
    end

    local path = mp.get_property('path')
    local lrc_path = (path:match('(.*)%.[^/]*$') or path)
    if is_japanese(lyrics) then
        if options.mark_as_ja then
            lrc_path = lrc_path .. '.ja'
        end
    end
    lrc_path = lrc_path .. '.lrc'

    if path:find('://') then
        if lyrics:find('^%[') then
            mp.commandv('sub-add', 'memory://' .. lyrics)
            mp.osd_message('LRC added')
        else
            mp.osd_message('These lyrics have no timestamps, so they can\'t be added as a subtitle track')
        end
        return
    end

    local success_message = 'LRC downloaded'
    if current_sub_path then
        -- os.rename only works across the same filesystem
        local _, current_sub_filename = utils.split_path(current_sub_path)
        local current_sub = io.open(current_sub_path)
        local backup = io.open('/tmp/' .. current_sub_filename, 'w')
        if current_sub and backup then
            backup:write(current_sub:read('*a'))
            success_message = success_message .. '. The old one has been backupped to /tmp.'
        end
        if current_sub then
            current_sub:close()
        end
        if backup then
            backup:close()
        end
    end

    local lrc, error = io.open(lrc_path, 'w')
    if lrc == nil then
        show_error(error)
        return
    end
    lrc:write(lyrics)
    lrc:close()

    if lyrics:find('^%[') then
        mp.command(current_sub_path and 'sub-reload' or 'rescan-external-files')
        mp.osd_message(success_message)
    else
        mp.osd_message('Lyrics without timestamps downloaded')
    end
end

mp.add_key_binding('Alt+m', 'musixmatch-download', function()
    local title, artist = get_metadata()

    if title == false then
        show_error(artist)
        return
    end

    if not title then
        show_error('This song has no title metadata')
        return
    end

    if not artist then
        show_error('This song has no artist metadata')
        return
    end

    mp.osd_message('Downloading lyrics')

    local response = curl({
        'curl',
        '--silent',
        '--get',
        '--cookie', 'x-mxm-token-guid=' .. options.musixmatch_token, -- avoids a redirect
        'https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get',
        '--data', 'app_id=web-desktop-app-v1.0',
        '--data', 'usertoken=' .. options.musixmatch_token,
        '--data-urlencode', 'q_track=' .. title,
        '--data-urlencode', 'q_artist=' .. artist,
    })

    if not response then
        return
    end

    if response.message.header.status_code == 401 and response.message.header.hint == 'renew' then
        show_error('The Musixmatch token has been rate limited. script-opts/lrc.conf explains how to generate a new one.')
        return
    end

    if response.message.header.status_code ~= 200 then
        show_error('Request failed with status code ' .. response.message.header.status_code .. '. Hint: ' .. response.message.header.hint)
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
            show_error('This is an instrumental track')
            return
        end
    end

    save_lyrics(lyrics)
end)

local songs
local _, input = pcall(require, 'mp.input')

local function get_song_type(song)
    if song.syncedLyrics then
        return 'Synced'
    end

    if song.plainLyrics then
        return 'Plain'
    end

    return 'Instrumental'
end

local function select_lrclib_lyrics()
    local items = {}

    for i, song in ipairs(songs) do
        items[i] = song.artistName .. ' - ' .. song.trackName ..
        ' (' .. song.albumName .. ')' ..
        mp.format_time(song.duration, ' %M:%S ') ..
        get_song_type(song)
    end

    input.select({
        prompt = 'Select lyrics:',
        items = items,
        submit = function (i)
            save_lyrics(songs[i].syncedLyrics or songs[i].plainLyrics)
        end
    })
end

local function lrclib_search(title, artist)
    if songs then
        return select_lrclib_lyrics()
    end

    local args = {
        'curl',
        '--silent',
        '--get',
        '--user-agent', 'mpv-lrc (https://github.com/guidocella/mpv-lrc)',
        'https://lrclib.net/api/search',
        '--data', 'duration=' .. mp.get_property_native('duration'),
    }

    if title and artist then
        args[#args + 1] = '--data-urlencode'
        args[#args + 1] = 'track_name=' .. title
        args[#args + 1] = '--data-urlencode'
        args[#args + 1] = 'artist_name=' .. artist
    else
        title = mp.get_property('media-title')

        if not title then
            show_error('No title available')
            return
        end

        args[#args+1] = '--data-urlencode'
        args[#args+1] = 'q=' .. title
    end

    local response = curl(args)

    if not response then
        return
    end

    if response.code then
        show_error(response.message)
        return
    end

    songs = response

    select_lrclib_lyrics()
end

mp.add_key_binding('Alt+l', 'lrclib-download', function()
    local title, artist, album = get_metadata()

    mp.osd_message('Downloading lyrics')

    if not title or not artist or not album then
        lrclib_search(title, artist)
        return
    end

    local response = curl({
        'curl',
        '--silent',
        '--get',
        '--user-agent', 'mpv-lrc (https://github.com/guidocella/mpv-lrc)',
        'https://lrclib.net/api/get',
        '--data-urlencode', 'track_name=' .. title,
        '--data-urlencode', 'artist_name=' .. artist,
        '--data-urlencode', 'album_name=' .. album,
        '--data', 'duration=' .. mp.get_property_native('duration'),
    })

    if not response then
        return
    end

    if response.code then
        show_error(response.message)
        return
    end

    save_lyrics(response.syncedLyrics or response.plainLyrics)
end)

mp.register_event('end-file', function()
    songs = nil
end)

-- Allow retrieving different lyrics after changing media-title in the
-- console.
mp.observe_property('force-media-title', 'native', function()
    songs = nil
end)

mp.add_key_binding('Alt+o', 'offset-sub', function()
    local sub_path = mp.get_property('current-tracks/sub/external-filename')

    if not sub_path then
        show_error('No external subtitle is loaded')
        return
    end

    local r = mp.command_native({
        name = 'subprocess',
        capture_stdout = true,
        args = {'ffmpeg', '-loglevel', 'quiet', '-itsoffset', mp.get_property('sub-delay'), '-i', sub_path, '-f', sub_path:match('[^%.]+$'), '-fflags', '+bitexact', '-'}
    })

    if r.status < 0 then
        show_error('subprocess error: ' .. r.error_string)
        return
    end

    if r.status > 0 then
        show_error('ffmpeg failed with code ' .. r.status)
        return
    end

    local sub_file, error = io.open(sub_path, 'w')
    if sub_file == nil then
        show_error(error)
        return
    end
    -- ffmpeg leaves a blank line at the top if there is no metadata, so strip it.
    sub_file:write((r.stdout:gsub('^\n', '')))
    sub_file:close()

    mp.set_property('sub-delay', 0)
    mp.command('sub-reload')
    mp.osd_message('Subtitles updated')
end)
