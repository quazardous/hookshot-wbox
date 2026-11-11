#!/bin/sh
# Run scenarios/deku-tree.yaml and send the one thing a scenario cannot send
# by itself: the game's teleport.
#
# The teleport is a line appended to the game's live input file while it runs
# (HOS_INPUT_LIVE, "!cheat <1000 + destination>"), and wbox has no step that
# writes a file. This asks for it once Link is in the world, and asks again
# until the game logs that it arrived: a teleport sent while an arrival event
# is playing is dropped silently.
#
#   scripts/deku-tree.sh            # inside the Deku Tree
#   DEST=1 SCENE=HyruleField_Child scripts/deku-tree.sh
#
# Destinations are host/hos_main.c's oot_destinations[] in Hookshot's source:
# 0 Kokiri Forest, 1 Hyrule Field, 2 Kakariko, 3 Market, 9 Death Mountain
# Trail, 19 Inside the Deku Tree, 20 Dodongo's Cavern. SCENE is the name the
# game logs for it, which is what tells us it arrived.
set -eu
cd "$(dirname "$0")/.."
WBOXR=${WBOXR:-wboxr}
DEST=${DEST:-19}
SCENE=${SCENE:-InsideTheDekuTree}
SETTLE=${SETTLE:-10}        # seconds after Link appears before the first ask
RETRY=${RETRY:-15}          # seconds between asks
TRIES=${TRIES:-8}

LIVE=runs/live-deku.txt
mkdir -p runs
: > "$LIVE"                 # the game reads it from the start: it must be empty

# the virtual pad needs /dev/uinput; sg gives the group to this command only,
# before you log in again after scripts/setup-uinput.sh
run() { if [ -w /dev/uinput ]; then "$@"; else sg input -c "$*"; fi; }

before=$(ls -d runs/deku-tree/*/ 2>/dev/null | wc -l)

ask() {
    # wait for this run's log to exist
    log=
    while [ -z "$log" ]; do
        if [ "$(ls -d runs/deku-tree/*/ 2>/dev/null | wc -l)" -gt "$before" ]; then
            log=$(ls -dt runs/deku-tree/*/ | head -1)app.log
        fi
        sleep 1
    done
    # Link is in the world when the debug tools print his inventory
    while ! grep -qa "cheats: inventory probe" "$log" 2>/dev/null; do
        sleep 1
        [ -e "$log" ] || return 0
    done
    sleep "$SETTLE"
    n=0
    while [ "$n" -lt "$TRIES" ]; do
        printf '!cheat %s\n' "$((1000 + DEST))" >> "$LIVE"
        echo "deku-tree.sh: asked for destination $DEST (try $((n + 1)))"
        i=0
        while [ "$i" -lt "$RETRY" ]; do
            if grep -qa "current \"$SCENE\"" "$log" 2>/dev/null; then
                echo "deku-tree.sh: the game says it is in $SCENE"
                return 0
            fi
            sleep 1
            i=$((i + 1))
        done
        n=$((n + 1))
    done
    echo "deku-tree.sh: no arrival in $SCENE after $TRIES asks" >&2
}

ask &
asker=$!
trap 'kill "$asker" 2>/dev/null || true' EXIT INT TERM
run "$WBOXR" run scenarios/deku-tree.yaml --runs runs
