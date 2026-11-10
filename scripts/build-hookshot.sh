#!/bin/sh
# Build Hookshot on Linux from a source checkout, without the AppImage:
# the environment nx2/make_game.py needs, pointed at what
# scripts/linux/deps.sh built into build-linux/deps.
#
#   scripts/build-hookshot.sh <Hookshot checkout> <game.nup | dump folder> [out] [language]
#
# out defaults to ~/Games/Hookshot, language to en-US (fr, de, es, ja, ...:
# LANGUAGES in nx2/make_game.py). Run scripts/linux/deps.sh in the checkout
# first. On Fedora it also needs: libstdc++-static, nasm, meson and the X11,
# Wayland, PulseAudio, PipeWire and ALSA development packages (README).
set -eu
SRC=$(cd "${1:?Hookshot checkout}" && pwd)
GAME=${2:?a .nup file or a folder with exefs/ and romfs/}
OUT=${3:-$HOME/Games/Hookshot}
LANG_CODE=${4:-en-US}
D=$SRC/build-linux/deps
[ -x "$D/python/bin/python3" ] || { echo "run $SRC/scripts/linux/deps.sh first" >&2; exit 1; }

export EMSDK="$D/emsdk"
export HOOKSHOT_FFMPEG="$D/ffmpeg"
export HOOKSHOT_SDL2="$D/sdl2/libSDL2-2.0.so.0"
export RX_CPM="$D/cpm"

if [ -d "$GAME" ]; then
    src_args="--romfs $GAME/romfs --exefs $GAME/exefs"
else
    src_args="--nup $GAME"
fi
cd "$SRC"
# shellcheck disable=SC2086  # (the two path arguments, split on purpose)
exec "$D/python/bin/python3" -I nx2/make_game.py $src_args --out "$OUT" --language "$LANG_CODE"
