#!/bin/sh
# Make refs/: the reference captures the scenarios wait for, taken from your
# own game. They are made from the game, so they stay on this PC: refs/ is
# git-ignored, and they must not be shared (Longshot's CONTRIBUTING.md).
set -eu
cd "$(dirname "$0")/.."
WBOXR=${WBOXR:-wboxr}

# the virtual pad needs /dev/uinput; sg gives the group to this command only,
# before you log in again after scripts/setup-uinput.sh
run() { if [ -w /dev/uinput ]; then "$@"; else sg input -c "$*"; fi; }

run "$WBOXR" run scenarios/make-refs.yaml --runs runs
last=$(ls -d runs/make-refs/*/ | sort | tail -1)
if ! grep -q '"status": "ok"' "$last/results.json"; then
    echo "make-refs failed: see $last/results.json" >&2
    exit 1
fi
mkdir -p refs
cp "$last/checkpoints/title.png" refs/title.png
echo "refs/title.png made from $last"
echo "Look at it: it must show the title (logo and menu). If the logo is still"
echo "fading in, raise the sleep in scenarios/make-refs.yaml and run this again."
