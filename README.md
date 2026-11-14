# longshot-wbox

Run [Longshot](https://git.magicbean.dev/MagicBeanDev/Longshot) — the Ocarina of Time
(Switch 2) static recompilation — in a [wbox](https://github.com/quazardous/wbox-mcp):
offscreen, isolated from your desktop, driven by a script or an AI agent, and
played the same way again and again so runs can be compared.

> [!NOTE]
> This was `hookshot-wbox`. Hookshot's repository and its issue tracker were
> taken down in November 2026, and its maintainers continue the work as
> **Longshot** on [git.magicbean.dev](https://git.magicbean.dev/MagicBeanDev/Longshot).
> Every Hookshot link here now points at Longshot, and the runs under `runs/`
> made before the move name Hookshot versions.

- **A box for the game** ([wbox/config.yaml](wbox/config.yaml)): headless
  labwc, the game fullscreen in 1280x720, its sound kept inside, a virtual
  Xbox pad as its only input device. Your screen, mouse, keyboard and pads
  stay yours.
- **Scenarios** ([scenarios/](scenarios/)): a run written down — waits on the
  game's log and on what the screen shows, checkpoints, frame times — that
  `wboxr run` plays into `runs/<name>/<date>/` and `wboxr compare` sets side
  by side.
- **For an agent**: the same box over MCP, so Claude (or any MCP client) can
  launch the game, press buttons, take screenshots and run scenarios.

> [!IMPORTANT]
> **Nothing made from the game goes in this repository.** Captures,
> reference images, image masks drawn on captures, runs and logs are made
> from your copy of the game: they stay on your PC (`.gitignore` keeps them
> out). This repository holds only configuration, scenarios, rectangle masks
> and scripts. Same rule as Longshot's
> [CONTRIBUTING.md](https://git.magicbean.dev/MagicBeanDev/Longshot/src/branch/main/CONTRIBUTING.md).

## What a run gives

`boot-title` played three times on a Radeon 780M (Ryzen Z1 Extreme), Hookshot
v2.0.13, before the move to Longshot:

| checkpoint | run 1 | run 2 | run 3 |
|---|---|---|---|
| renderer up | 1.87 s | 1.86 s | 1.86 s |
| Nintendo logo over | 5.50 s | 5.70 s | 5.69 s |
| intro movie starts | 5.75 s | 5.74 s | 5.72 s |
| **title shown** | **27.87 s** | **28.33 s** | **28.70 s** |
| title vs run 1 (shield) | — | 0.00 % | 0.00 % |
| frame time p95 / p99 | 17.9 / 20.4 ms | 17.9 / 22.9 ms | 17.8 / 22.0 ms |

Each run also keeps a `manifest.json` — kernel, CPU, the GPU and driver
`vulkaninfo` reports, the Longshot version, hashes of the scenario and the
config — and `compare` lists what differs between them: a driver update shows
up there next to the times it changed.

Two of those cost us a wrong conclusion once, so they are worth knowing.
`host.gpus` is empty wherever `vulkaninfo` is not installed, which is the
normal state of a fresh container, and the driver the game loads is the one
where the **game** runs, not the host's. The scenarios therefore record
`vulkan_driver` themselves, from
[scripts/vulkan-driver.sh](scripts/vulkan-driver.sh), which reads the version
out of the driver library the loader will open and honours
`VK_DRIVER_FILES`:

```
$ scripts/vulkan-driver.sh                       # on this host
26.2.6 (/usr/lib/libvulkan_radeon.so)
$ distrobox enter wbox -- .../vulkan-driver.sh   # where the game actually runs
25.0.7 (/usr/lib64/libvulkan_radeon.so)
```

Seven releases apart on the same machine. A comparison that assumes the host's
driver measures something no run ever used.

## Setup

You need your own copy of the game at the version Longshot supports, and:

1. **Longshot**, built: the [releases](https://git.magicbean.dev/MagicBeanDev/Longshot/releases)'
   AppImage builds it into `~/Games/Longshot`, or from a checkout:
   ```sh
   git clone https://git.magicbean.dev/MagicBeanDev/Longshot && cd Longshot
   scripts/linux/deps.sh
   ../longshot-wbox/scripts/build-longshot.sh . ~/game.nup ~/Games/Longshot en-US
   ```
   On Fedora the build also needs `libstdc++-static nasm meson` and the
   development packages of X11, Wayland, xkbcommon, libdecor, EGL, PulseAudio,
   PipeWire and ALSA. Nothing needs patching any more: this repository carried
   one patch, for `deps.sh` looking up libXft, libXrender and their licences at
   Debian's paths only, and Longshot dropped Tcl/Tk altogether — its builder has
   no window — so those lines are gone.
2. **wbox** with scenarios and the virtual pad, `pip install "wbox-mcp[scenario]"`
   (or its [setup script](https://github.com/quazardous/wbox-mcp#install)),
   and `bwrap` (bubblewrap).
3. **Write access to `/dev/uinput`** for the pad: `scripts/setup-uinput.sh`,
   then log in again (until then, `sg input -c '...'`).
4. Where the game is, if not `~/Games/Longshot`: `export LONGSHOT_DIR=...`
   (and `LONGSHOT_SRC` for the checkout, recorded in each run's manifest).

On **Bazzite, SteamOS, Silverblue or Kinoite** — a Steam Deck or a ROG Ally —
the base image is read-only and steps 1 and 2 belong in a container instead:
[docs/containers.md](docs/containers.md) has that path, the GPU through it, and
the two traps it sets (a shared `/tmp`, and the AppImage inside the pad's
sandbox).

## Playing it yourself

Before a sequence is worth writing down, you have to play it. `scripts/play.py`
opens the box, puts **your own pad** through to the game's virtual one, and
serves the box's screen over VNC so you can watch it in a window:

```sh
scripts/play.py                     # 30 min, your pad, VNC on 127.0.0.1:5900
SESSION_MINUTES=5 scripts/play.py   # shorter
PAD_GRAB=0 scripts/play.py          # let your pad reach the desktop as well
```

It reads [wbox/config.yaml](wbox/config.yaml), so the box is the one the
scenarios use, and it prints which pad it found and where to point a VNC
client. By default your pad is **grabbed**: it drives the box and nothing
else, so a stick drift does not scroll the window behind. Whatever ends the
session — the timer, Ctrl-C — gives it back.

`PAD_DEVICE=/dev/input/eventN` picks a pad when the first one found is the
wrong one, `VNC=0` skips the VNC server for a logged run, and
`WBOX_RENDERER` / `WBOX_RENDER_DEVICE` point the compositor at a GPU
(needed in a container: [docs/containers.md](docs/containers.md)).

## Running scenarios

```sh
scripts/make-refs.sh                                   # once: refs/ from your game
wboxr run scenarios/boot-title.yaml --repeat 3 --runs runs
wboxr compare runs/boot-title/*/
wboxr mask suggest runs/boot-title/*/                  # what varies between runs
```

| Scenario | What it does |
|---|---|
| [boot-title](scenarios/boot-title.yaml) | Launch to the title screen: when the renderer, the logo, the movie and the title come; frame times |
| [deku-tree](scenarios/deku-tree.yaml) | Launch to inside the Deku Tree: the save loaded, the game's own teleport, a walk in the first room; frame times |
| [make-refs](scenarios/make-refs.yaml) | Makes `refs/title.png`, which boot-title waits for |

Steps wait for **states**, not durations: a line in the game's log, the
screen holding still, or a zone matching a reference. The intro movie runs
for a different time on each PC; a fixed delay catches it at a different
moment each run, a wait on the title catches the title. The title is
recognised by the centre of the logo's shield, which the movie behind never
shows through ([boot-title.yaml](scenarios/boot-title.yaml) has the
measurements).

Useful Longshot switches for scenarios (in `setup.env`; the full list is in
Longshot's [development guide](https://git.magicbean.dev/MagicBeanDev/Longshot/src/branch/main/docs/development.md)):
`RX_VK_FRAME_LOG` (a CSV line per frame), `HOS_INPUT_FRAME_CLOCK=1` with
`HOS_INPUT_SCRIPT` (inputs timed in game frames: the most reproducible way to
play a sequence), `HOS_DYNRES=0`, `RX_VK_FRAMEGEN=0`.

## Driving the game instead of guessing

Longshot opens a control bridge when `HOS_CONTROL` names a socket (its
[`docs/control.md`](https://git.magicbean.dev/MagicBeanDev/Longshot/src/branch/main/docs/control.md)):
newline-delimited JSON over a Unix socket, local only, 0600, the client checked
by `SO_PEERCRED`. [scripts/longshot-bridge.py](scripts/longshot-bridge.py) is a
small client for it — the game's own `scripts/longshot_ctl.py` is the complete
one:

```sh
HOS_CONTROL=$XDG_RUNTIME_DIR/longshot/control.sock ./bin/longshot &
scripts/longshot-bridge.py status                     # fps, draws, state, map
scripts/longshot-bridge.py option set fps_counter true
scripts/longshot-bridge.py teleport InsideTheDekuTree
scripts/longshot-bridge.py watch --events present,map --count 5
```

It matters for measuring: the scenarios here wait on log lines and on what the
screen shows, because that was all there was. The bridge answers with the frame
each thing happened at, so a step no longer has to be inferred from a picture.

## Watching a run

The box is headless: the game draws nowhere, which is the point, but it also
means a run that goes wrong gives you a log and nothing to look at. `wayvnc`
serves the box's screen to a VNC client you open, move and close like any
window — the box stays offscreen and nothing takes your focus or your pads.

```sh
WAYLAND_DISPLAY=wayland-0 wayvnc 127.0.0.1 5900     # beside the running box
krdc vnc://127.0.0.1:5900                           # or any VNC client
```

It listens on the loopback only, so nothing is exposed on your network. Set the
client's quality to its highest: a lossy stream smooths away the flickers and
one-frame artefacts you are most likely watching for.

Set it to **view only** as well. Nothing in the box listens to the client — the
game's only input device is the virtual pad — so a client sending pointer and
key events gains you nothing, and krdc in its default mode showed a blank blue
view of a box that `grim` proved was drawing the game perfectly. View only
cleared it.

**Watch over VNC, capture with `grim`.** Screenshotting the VNC client would add
an encode and a decode to the chain, and VNC drops frames and favours what
changes — the opposite of what a one-frame artefact needs kept. The scenarios'
own captures come straight from the box's output.

Useful while the game is still compiling its pipelines on a first start: VNC
shows the progress bar, where a scenario waiting on the title screen only shows
you a timeout several minutes later.

In a container, `wayvnc` needs `spirv-tools` installed or it dies on a missing
symbol — [docs/containers.md](docs/containers.md) has that and the rest.

### A client that outlives the box

`wayvnc` serves one box, so it dies with it, and a scenario builds a fresh box
for every run: a client you opened by hand closes two minutes later, when the
run ends. Watching several runs then means reopening it between each.

[scripts/watch-vnc.sh](scripts/watch-vnc.sh) answers that with
[noVNC](https://novnc.com/noVNC/docs/EMBEDDING.html), a VNC client in the
browser that reconnects by itself:

```sh
scripts/watch-vnc.sh          # serves the page, and a wayvnc per box
```

Open the URL it prints once and leave the tab. It starts `wayvnc` on each box
as it appears and retries every two seconds in between, so a run shows up in
the tab as it starts and the tab is still there for the next one. The URL
carries `view_only=1` for the reason above.

It needs `novnc`, `python3-websockify` and `wayvnc` — in a container, there
(the host's browser still opens `127.0.0.1`: distrobox shares the network).

## With an agent (MCP)

Copy [.mcp.json.example](.mcp.json.example) to `.mcp.json` in your project
with the absolute path to `wbox/config.yaml`. `sg input` gives the server the
input group before you have logged in again; it is harmless after. Then ask:
*"Launch Longshot, wait for the title screen, and show me a screenshot."* —
or *"run the boot-title scenario three times and compare the runs."*

## License

MIT for this repository's files. Longshot and wbox have their own licences;
the game is Nintendo's.
