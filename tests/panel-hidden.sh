#!/bin/sh
set -eu

panel_config=/etc/xdg/lxqt/panel.conf
if ! grep -q '^hidable=true$' "$panel_config" || ! grep -q '^show-delay=5000$' "$panel_config"; then
    echo "LXQt taskbar must be hidable with a 5-second show delay" >&2
    exit 1
fi

screen_height=$(xrandr --current | awk '/^Screen 0:/ { split($0, a, "current "); split(a[2], b, " x "); split(b[2], c, ","); print c[1]; exit }')
geometry=$(wmctrl -lG | awk '$0 ~ /LXQt Panel$/ { print $4, $6; exit }')

if [ -z "$screen_height" ] || [ -z "$geometry" ]; then
    echo "Could not read display or LXQt panel geometry" >&2
    exit 1
fi

set -- $geometry
panel_y=$1
panel_height=$2

if [ "$((panel_y + panel_height))" -le "$screen_height" ]; then
    printf 'LXQt taskbar is visible: y=%s height=%s screen_height=%s\n' \
        "$panel_y" "$panel_height" "$screen_height" >&2
    exit 1
fi

printf 'LXQt taskbar hidden beyond screen edge: y=%s height=%s screen_height=%s\n' \
    "$panel_y" "$panel_height" "$screen_height"
