# On a handheld, or any image-based system

Bazzite, SteamOS, Silverblue and Kinoite ship a read-only base image: installing
wbox's dependencies into it means layering them and rebooting. The usual answer
is a container, and everything here works from one — including the GPU.

This matters because the Steam Deck and the ROG Ally are where an offscreen box
is most useful, and both run an image-based system.

Measured on a ROG Ally X (Ryzen Z1 Extreme, RADV, Mesa 26.2.6) under Bazzite 45,
in a Fedora 41 distrobox.

## The box

```sh
distrobox create --name wbox --image ghcr.io/ublue-os/fedora-toolbox:latest -Y
distrobox enter wbox -- sudo dnf install -y --skip-unavailable \
    labwc grim wlrctl cage weston wtype xdotool ydotool wlr-randr \
    wl-clipboard xclip xsel setxkbmap xev bubblewrap uv python3 git
```

`--skip-unavailable` matters: dnf drops the whole transaction when one package
name is unknown, so a single rename leaves every other dependency uninstalled.

Three of those are easy to miss and each fails in its own way:

| Package | Without it |
|---|---|
| `bubblewrap` | the virtual pad cannot isolate the app, and `launch` fails |
| `setxkbmap` | wbox's setup refuses to install |
| `xev` | optional, but its Fedora name is `xev`, not `xorg-x11-utils` |

## `/tmp/.X11-unix`: the first wall

A container shares the host's `/tmp`, where `.X11-unix` belongs to another user
through the user namespace. XWayland refuses it, labwc or cage exits at launch,
and `WLR_XWAYLAND=` does not turn XWayland off. Give the container its own, once
per container:

```sh
distrobox enter wbox -- sudo mount -t tmpfs -o mode=1777 tmpfs /tmp/.X11-unix
```

## The GPU does pass through

Nothing special to do: `/dev/dri/renderD128` is world-writable inside the
container, and `mesa-vulkan-drivers` provides RADV there. Point the compositor at
the render node and the game renders on the real GPU:

```yaml
renderer: gles2                     # the compositor; the game talks Vulkan itself
render_device: /dev/dri/renderD128
```

Note the container's Mesa is its own version — 25.0.1 here against the host's
26.2.6. That is a free extra variable when a bug is suspected to be driver-side:
the same game, the same GPU, another Mesa.

## Do not launch the AppImage inside the box

With `gamepad:` set, wbox runs the app under `bwrap` so the pad is its only input
device. An AppImage mounts a FUSE filesystem, which fails inside that namespace:
the launch leaves a `bwrap <defunct>`, the screen stays black, and the game never
writes a line to its log. Twelve screenshots of exactly 3075 bytes over four
minutes, and `record` reporting 0 changed frames out of 160.

Launch the built game instead, the way Hookshot's own `builder/linux/hookshot-launch`
does:

```python
box.launch(["sh", "-c", f'cd "{HOOKSHOT_DIR}" && exec ./bin/hookshot'],
           {"HOOKSHOT_NO_UPDATE_CHECK": "1"})
```

`bin/hookshot` is the game; the AppImage is the builder, and the folder's
`hookshot` script is a launcher that starts the builder again. Checked with
`ldd`: `bin/hookshot` has no missing library in the container.

## Watching a headless run from a container

Watching a box over VNC is in the README; one thing is specific to a container:

```sh
distrobox enter wbox -- sudo dnf install -y wayvnc spirv-tools
```

`spirv-tools` is not optional here. The image ships `spirv-tools-libs` from an
older build, and wayvnc dies on `undefined symbol:
spvValidatorOptionsSetAllowOffsetTextureOperand` in `libshaderc` — a symbol
error, with nothing about VNC in it.

The port is reachable from the host as usual: distrobox shares its network
namespace, so a VNC client outside the container connects to `127.0.0.1:5900`.

## What a handheld's memory does

The iGPU's VRAM is the system's RAM, and the UEFI takes its share before Linux
boots. On this machine 8 GiB of 24 GB are reserved, so the OS sees 15.3 GiB —
below Hookshot's recommended 16 GB while the sticker says otherwise. Lowering the
UMA frame buffer in the UEFI is the fix; GTT lets the GPU borrow system RAM
anyway.

Peaks measured on Hookshot v2.0.11:

| Moment | Resident |
|---|---|
| compiling the 11,333 pipelines, first start | **9.19 GB** |
| playing, afterwards | 2.71 GB |
| under gamescope as well | 8.2 GB |

The first start is the dangerous one: a run that survives for hours can still be
killed in its first four minutes. `record` also slows to 13.7 captures a second
while that compilation runs, against the ~27 wbox manages on an idle GPU.

## Finding a flicker: let the game do it

For the white flashes, stray HUD pieces and shimmering shadows reported on AMD
iGPUs, Hookshot's own detector beats capturing from outside:

```sh
RX_VK_FLASH=1 RX_VK_SHOT_EVERY=1 ./bin/hookshot
```

It compares each frame with **both its neighbours** inside the renderer and writes
the frames around what it finds — no GPU-to-CPU copy, no compositor, no encoder,
and nothing to synchronise. `RX_VK_FLASH_DIFF` sets the threshold (48),
`RX_VK_FLASH_CELLS` says how many cells went up and where, `RX_VK_FLASH_DUMPS`
how many dumps to keep, and `RX_VK_FLASH_RECORD=<key>,...` logs the draws of
those programs around a flash.

It is also the instrument the maintainer uses, so a report built on it reads in
the terms the project already thinks in.

wbox stays the right tool for the other half of the job: playing the same
sequence again on another version, driver or compositor, and comparing the runs.
