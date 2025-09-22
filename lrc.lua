local options = {
    musixmatch_token = '2501192ac605cc2e16b6b2c04fe43d1011a38d919fe802976084e7',
    mark_as_ja = false,
    chinese_to_kanji_path = '',
    strip_artists = false,
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

    if not title then
        return false, 'This song has no title metadata'
    end

    if not artist then
        return false, 'This song has no artist metadata'
    end

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

local function chinese_to_kanji(lyrics)
    local mappings, error = io.open(
        mp.command_native({'expand-path', options.chinese_to_kanji_path})
    )

    if mappings == nil then
        show_error(error)
        return lyrics
    end

    -- Save the original lyrics to compare them.
    local original = io.open('/tmp/original.lrc', 'w')
    if original then
        original:write(lyrics)
        original:close()
    end

    for mapping in mappings:lines() do
        local num_matches

        -- gsub on Unicode lyrics seems to stop at the first match. I have
        -- no idea why this works.
        repeat
            lyrics, num_matches = lyrics:gsub(
                mapping:gsub(' .*', ''),
                mapping:gsub('.* ', '')
            )
        until num_matches == 0
    end

    mappings:close()

    -- Also remove the pointless owari line when present.
    for _, pattern in pairs({
        'おわり',
        '【 おわり 】',
        ' ?終わり',
        '終わる',
        'END',
    }) do
        lyrics = lyrics:gsub(']' .. pattern .. '\n', ']\n')
    end

    return lyrics
end

local function strip_artists(lyrics)
    for _, pattern in pairs({'作词', '作詞', '作曲', '制作人', '编曲', '編曲', '詞', '曲'}) do
        lyrics = lyrics:gsub('%[[%d:%.]*] ?' .. pattern .. ' ?[:：] ?.-\n', '')
    end

    return lyrics
end


local function save_lyrics(lyrics)
    -- NetEase can return 2-line LRCs with just the names of the artists, treat them as not found.
    if lyrics == '' or select(2, lyrics:gsub('\n', '')) == 2 then
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
        if options.chinese_to_kanji_path ~= '' then
            lyrics = chinese_to_kanji(lyrics)
        end
    end
    if options.strip_artists then
        lyrics = strip_artists(lyrics)
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

local function select_netease_lyrics()
    local items = {}
    for _, song in ipairs(songs) do
        items[#items+1] = song.artists[1].name .. ' - ' .. song.name .. ' (' ..
                          song.album.name .. ')'
    end

    input.select({
        prompt = 'Select a song:',
        items = items,
        submit = function(id)
            local response = curl({
                'curl',
                '--silent',
                'https://music.xianqiao.wang/neteaseapiv2/lyric?id=' .. songs[id].id,
            })

            if response then
                save_lyrics(response.lrc.lyric)
            end
        end
    })
end

mp.add_key_binding('Alt+n', 'netease-download', function()
    if songs then
        select_netease_lyrics()

        return
    end

    local title, artist, album = get_metadata()
    local keywords
    if title then
        keywords = title .. ' ' .. artist
    else
        keywords = mp.get_property('media-title')
        if not keywords then
            show_error('No metadata or media-title are loaded')
            return
        end
    end

    mp.osd_message('Downloading lyrics')

    local response = curl({
        'curl',
        '--silent',
        '--get',
        'https://music.xianqiao.wang/neteaseapiv2/search?limit=9',
        '--data-urlencode', 'keywords=' .. keywords,
    })

    if not response then
        return
    end

    if not response.result then
        show_error('Lyrics not found')
        return
    end

    songs = response.result.songs

    if songs == nil or #songs == 0 then
        show_error('Lyrics not found')
        return
    end

    if #songs == 1 then
        response = curl({
            'curl',
            '--silent',
            'https://music.xianqiao.wang/neteaseapiv2/lyric?id=' .. songs[1].id,
        })

        if response then
            save_lyrics(response.lrc.lyric)
        end

        return
    end

    select_netease_lyrics()
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
