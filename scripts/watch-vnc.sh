#!/bin/sh
# Watch headless runs from a browser tab that never goes away.
#
# A VNC client dies with the box: wayvnc serves the box's compositor, and a
# scenario builds a fresh box for every run, so a client has nothing stable to
# hold on to -- krdc closes the moment a run ends, and a run is two minutes.
#
# noVNC is a VNC client in the browser, and it reconnects by itself
# (`reconnect`, `reconnect_delay`: novnc.com/noVNC/docs/EMBEDDING.html). Leave
# the tab open: each run appears in it as it starts, and between runs the tab
# sits there and retries. This serves that page, and keeps a wayvnc on
# whichever box is up.
#
#   scripts/watch-vnc.sh               # then open the URL it prints
#   PORT=7080 VNC_PORT=5901 scripts/watch-vnc.sh
#   BIND=0.0.0.0 scripts/watch-vnc.sh   # from your phone, on your network
#
# Needs `novnc`, `python3-websockify` and `wayvnc`. In a container, install
# them there: it shares the host's network, so the browser on the host opens
# 127.0.0.1 all the same (docs/containers.md).
#
# The page is view-only on purpose: nothing in the box listens to a VNC
# client, and a key or click sent to it goes nowhere (README).
set -eu
PORT=${PORT:-6080}
BIND=${BIND:-127.0.0.1}                      # 0.0.0.0 serves your network: the
                                             # captures are made from the game
VNC_PORT=${VNC_PORT:-5900}
WEB=${WEB:-/usr/share/novnc}
DESKTOP=${WAYLAND_DISPLAY:-wayland-0}        # your own session: never serve it
RUNTIME=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

[ -d "$WEB" ] || { echo "no noVNC in $WEB (dnf install novnc)" >&2; exit 1; }
for c in websockify wayvnc; do
    command -v "$c" >/dev/null || { echo "$c is missing (dnf install python3-websockify wayvnc)" >&2; exit 1; }
done

websockify --web="$WEB" "$BIND:$PORT" "127.0.0.1:$VNC_PORT" >/dev/null 2>&1 &
proxy=$!
trap 'kill "$proxy" 2>/dev/null || true' EXIT INT TERM

echo "open http://$BIND:$PORT/vnc.html?autoconnect=1&reconnect=1&reconnect_delay=2000&view_only=1&resize=scale"
echo "  the tab stays open and retries every 2 s while no box is up (Ctrl+C here to stop)"

# One wayvnc per box, for as long as that box lives. A box's compositor makes
# its own wayland socket next to your session's, so the new name is the box.
while kill -0 "$proxy" 2>/dev/null; do
    box=
    for s in "$RUNTIME"/wayland-*; do
        [ -S "$s" ] || continue
        name=${s##*/}
        [ "$name" = "$DESKTOP" ] && continue
        box=$name
    done
    if [ -n "$box" ]; then
        echo "a box is up on $box: serving it on 127.0.0.1:$VNC_PORT"
        WAYLAND_DISPLAY="$box" wayvnc 127.0.0.1 "$VNC_PORT" >/dev/null 2>&1 || true
        echo "the box on $box is gone; waiting for the next run"
    fi
    sleep 1
done
