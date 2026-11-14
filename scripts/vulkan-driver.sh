#!/bin/sh
# One line naming the Vulkan driver this environment will load, for a run's manifest.
#
# Why not the host's driver: the game loads the Mesa of wherever it runs. In a
# container (docs/containers.md) that is the container's, which can be several
# releases behind the host's -- and comparing two runs without it has already
# blamed a driver for a regression that was the game's.
#
# It reads the version out of the driver the loader will open, so it is the same
# string whether the driver is installed or unpacked, and an A/B against an
# unpacked driver (VK_DRIVER_FILES / VK_ICD_FILENAMES) is recorded as that one.
#
#   scripts/vulkan-driver.sh          -> 25.0.7 (/usr/lib64/libvulkan_radeon.so)
set -eu

override=${VK_DRIVER_FILES:-${VK_ICD_FILENAMES:-}}

# The driver library the loader opens. An override names the ICD files itself;
# otherwise the search path the Vulkan loader uses, RADV first -- the game takes
# the discrete or integrated GPU, never llvmpipe.
icd=
lib=
for candidate in $(
        if [ -n "$override" ]; then
            printf '%s\n' "$override" | tr ':' '\n'
        else
            for d in "${XDG_CONFIG_HOME:-$HOME/.config}/vulkan/icd.d" /etc/vulkan/icd.d \
                     /usr/local/share/vulkan/icd.d /usr/share/vulkan/icd.d; do
                for f in "$d"/*radeon*.json "$d"/*amd*.json "$d"/*intel*.json \
                         "$d"/*nvidia*.json "$d"/*.json; do
                    [ -f "$f" ] && printf '%s\n' "$f"
                done
            done
        fi); do
    [ -f "$candidate" ] || continue
    path=$(sed -n 's/.*"library_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$candidate" | head -1)
    [ -n "$path" ] || continue
    case $path in
        /*) ;;                                   # absolute, as our A/B rewrite leaves it
        *)  path=$(dirname "$candidate")/$path ;; # relative to the json, as the spec says
    esac
    case $candidate in *lvp*|*lavapipe*) continue ;; esac   # software, not what a run measures
    if [ -f "$path" ]; then icd=$candidate; lib=$path; break; fi
done

# The version Mesa compiled in, which no package name can contradict. grep -a,
# not strings: a container often has no binutils, and falling back to the
# installed package there would name a driver that is not the one loaded.
version=
if [ -n "$lib" ]; then
    version=$(LC_ALL=C grep -aoE 'Mesa (2[0-9]|3[0-9])\.[0-9]+\.[0-9]+' "$lib" 2>/dev/null |
              head -1 | sed 's/^Mesa //')
    [ -n "$version" ] || version=$(LC_ALL=C grep -aoE '[0-9]+\.[0-9]+\.[0-9]+' "$lib" 2>/dev/null | head -1)
fi

# No driver found at all: say so. Naming the installed package here would name a
# driver the loader is not going to open -- the error this script exists to stop.
if [ -z "$lib" ]; then
    printf 'unknown'
    [ -n "$override" ] && printf ' (no readable ICD)'
else
    printf '%s (%s)' "${version:-unknown}" "$lib"
fi
if [ -n "${VK_DRIVER_FILES:-}" ]; then printf ' [VK_DRIVER_FILES=%s]' "$VK_DRIVER_FILES"
elif [ -n "${VK_ICD_FILENAMES:-}" ]; then printf ' [VK_ICD_FILENAMES=%s]' "$VK_ICD_FILENAMES"
fi
printf '\n'
