#!/bin/sh
set -eu

gio launch "/usr/share/applications/Deepseek Harness Desktop.desktop"

i=0
while [ "$i" -lt 100 ]; do
    if wmctrl -x -r deepseek-harness-desktop.Deepseek-harness-desktop -b add,maximized_vert,maximized_horz 2>/dev/null; then
        exit 0
    fi
    i=$((i + 1))
    sleep 0.2
done

echo "DeepSeek Harness window did not open" >&2
exit 1
