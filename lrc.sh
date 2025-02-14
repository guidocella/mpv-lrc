#!/bin/sh

lrc_path=$(printf %s\\n '{ "command": ["get_property", "path"] }' | socat - UNIX-CONNECT:/tmp/mpv-socket) || exit 1

lrc_path=$(printf %s "$lrc_path" | jq -r .data)
[ "$lrc_path" = null ] && exit 1

lrc_path=${lrc_path%.*}.lrc
case $lrc_path in
    /*) ;;
    *) lrc_path=$(printf %s\\n '{ "command": ["get_property", "working-directory"] }' | socat - /tmp/mpv-socket | jq -r .data)/$lrc_path
esac

[ -e "$lrc_path" ] && exec $EDITOR "$lrc_path"
[ -e "${lrc_path%.*}.ja.lrc" ] && exec $EDITOR "${lrc_path%.*}.ja.lrc"

metadata=$(printf %s\\n '{ "command": ["get_property", "metadata"] }' \
    | socat - /tmp/mpv-socket | jq .data)
# The keys are lower case in ID3 tags and upper case in Vorbis comments.
artist=$(printf %s "$metadata" | jq -r 'if has("artist") then .artist else .ARTIST end')
title=$(printf %s "$metadata" | jq -r 'if has("title") then .title else .TITLE end')

query="$artist $title"

# grep -P can be unavailable
if printf %s "$query" | perl -nC -e 'exit(not /[\p{Hiragana}\p{Katakana}\p{Han}]/)'; then
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
