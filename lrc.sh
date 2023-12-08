#!/bin/sh

lrc_path=$(printf %s\\n '{ "command": ["get_property", "path"] }' | socat - /tmp/mpv-socket | jq -r .data)
[ "$lrc_path" ] || exit 1
lrc_path=${lrc_path%.*}.lrc
case $lrc_path in
    /*) ;;
    *) lrc_path=$(printf %s\\n '{ "command": ["get_property", "working-directory"] }' | socat - /tmp/mpv-socket | jq -r .data)/$lrc_path
esac

[ -e "$lrc_path" ] && exec $EDITOR "$lrc_path"

metadata=$(printf %s\\n '{ "command": ["get_property", "metadata"] }' \
    | socat - /tmp/mpv-socket | jq .data)
# The keys are lower case in ID3 tags and upper case in Vorbis comments.
artist=$(printf %s "$metadata" | jq -r 'if has("artist") then .artist else .ARTIST end')
title=$(printf %s "$metadata" | jq -r 'if has("title") then .title else .TITLE end')
album=$(printf %s "$metadata" | jq -r 'if has("album") then .album else .ALBUM end')
[ "$album" = null ] && album= || album="[album:$album]
"

printf %s "[ar:$artist]
[ti:$title]
$album[by:$1]


" > "$lrc_path"

query="$artist $title"

if printf %s "$query" | grep -Eiq '([ぁ-ヺ一-龢]|KOTOKO |Ceui )'; then
    # When sites try to block copying text, you can inspect the HTML element
    # with the lyrics and execute copy($0.innerText) in the console.
    query="$query 歌詞"
else
    query="$query lyrics"
fi

case ${BROWSER:=chromium} in
    *chrom*) query="? $query" ;;
    firefox) BROWSER="$BROWSER --search"
esac

$BROWSER "$query" 2>/dev/null &

exec $EDITOR + "$lrc_path"
