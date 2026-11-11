#!/bin/sh
# Run scenarios/village-flash.yaml: a minute in Kokiri Forest with the
# renderer's flash detector on, then the counts it logged.
#
#   scripts/village-flash.sh
#   DIFF=32 CELLS=16 scripts/village-flash.sh   # find subtler flashes
#
# The detector writes into a fixed folder (the run's own does not exist when the
# scenario's env is expanded); this empties it first, and the scenario collects
# it into the run.
set -eu
cd "$(dirname "$0")/.."
WBOXR=${WBOXR:-wboxr}
SHOTS=runs/village-flash-shots

rm -rf "$SHOTS"
mkdir -p "$SHOTS"

[ -n "${DIFF:-}" ] && export RX_VK_FLASH_DIFF="$DIFF"
[ -n "${CELLS:-}" ] && export RX_VK_FLASH_CELLS="$CELLS"

# the virtual pad needs /dev/uinput; sg gives the group to this command only
run() { if [ -w /dev/uinput ]; then "$@"; else sg input -c "$*"; fi; }
run "$WBOXR" run scenarios/village-flash.yaml --runs runs

LOG=$(ls -dt runs/village-flash/*/ | head -1)app.log
echo
echo "--- what the renderer saw ---"
grep -ac 'vk: flash at present' "$LOG" | sed 's/^/one-frame flashes: /'
grep -ac 'vk: region flash at present' "$LOG" | sed 's/^/region flashes:   /'
grep -a 'vk: flash at present\|vk: region flash at present' "$LOG" | head -20
echo "shots: $(ls runs/village-flash-shots | wc -l) files"
