# hookshot-wbox

Run [Hookshot](https://github.com/NotRexed/Hookshot) — the Ocarina of Time
(Switch 2) static recompilation — in a [wbox](https://github.com/quazardous/wbox-mcp):
offscreen, isolated from your desktop, driven by a script or an AI agent, and
played the same way again and again so runs can be compared.

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
> and scripts. Same rule as Hookshot's
> [CONTRIBUTING.md](https://github.com/NotRexed/Hookshot/blob/main/CONTRIBUTING.md).

## What a run gives

`boot-title` played three times on a Radeon 780M (Mesa 26.2.6):

| checkpoint | run 1 | run 2 | run 3 |
|---|---|---|---|
| renderer up | 1.87 s | 1.86 s | 1.86 s |
| Nintendo logo over | 5.50 s | 5.70 s | 5.69 s |
| intro movie starts | 5.75 s | 5.74 s | 5.72 s |
| **title shown** | **27.87 s** | **28.33 s** | **28.70 s** |
| title vs run 1 (shield) | — | 0.00 % | 0.00 % |
| frame time p95 / p99 | 17.9 / 20.4 ms | 17.9 / 22.9 ms | 17.8 / 22.0 ms |

Each run also keeps a `manifest.json` — GPU, driver, kernel, CPU, the
Hookshot commit, hashes of the scenario and the config — and `compare` lists
what differs between them: a driver update shows up there next to the times
it changed.

## Setup

You need your own copy of the game at the version Hookshot supports, and:

1. **Hookshot**, built: the [releases](https://github.com/NotRexed/Hookshot/releases)'
   AppImage builds it into `~/Games/Hookshot`, or from a checkout:
   ```sh
   git clone https://github.com/NotRexed/Hookshot && cd Hookshot
   scripts/linux/deps.sh
   ../hookshot-wbox/scripts/build-hookshot.sh . ~/game.nup ~/Games/Hookshot en-US
   ```
   On Fedora the build also needs `libstdc++-static nasm meson` and the
   development packages of X11, Xft, Wayland, xkbcommon, libdecor, EGL,
   PulseAudio, PipeWire and ALSA. On Fedora and Arch, apply
   [patches/0001](patches/) to the checkout before `deps.sh`: it looks for
   libXft, libXrender and their licences at Debian's paths only
   (`git -C Hookshot apply ../hookshot-wbox/patches/0001-*.patch`).
2. **wbox** with scenarios and the virtual pad, `pip install "wbox-mcp[scenario]"`
   (or its [setup script](https://github.com/quazardous/wbox-mcp#install)),
   and `bwrap` (bubblewrap).
3. **Write access to `/dev/uinput`** for the pad: `scripts/setup-uinput.sh`,
   then log in again (until then, `sg input -c '...'`).
4. Where the game is, if not `~/Games/Hookshot`: `export HOOKSHOT_DIR=...`
   (and `HOOKSHOT_SRC` for the checkout, recorded in each run's manifest).

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
| [make-refs](scenarios/make-refs.yaml) | Makes `refs/title.png`, which boot-title waits for |

Steps wait for **states**, not durations: a line in the game's log, the
screen holding still, or a zone matching a reference. The intro movie runs
for a different time on each PC; a fixed delay catches it at a different
moment each run, a wait on the title catches the title. The title is
recognised by the centre of the logo's shield, which the movie behind never
shows through ([boot-title.yaml](scenarios/boot-title.yaml) has the
measurements).

Useful Hookshot switches for scenarios (in `setup.env`; the full list is in
Hookshot's [development guide](https://github.com/NotRexed/Hookshot/blob/main/docs/development.md)):
`RX_VK_FRAME_LOG` (a CSV line per frame), `HOS_INPUT_FRAME_CLOCK=1` with
`HOS_INPUT_SCRIPT` (inputs timed in game frames: the most reproducible way to
play a sequence), `HOS_DYNRES=0`, `RX_VK_FRAMEGEN=0`.

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

**Watch over VNC, capture with `grim`.** Screenshotting the VNC client would add
an encode and a decode to the chain, and VNC drops frames and favours what
changes — the opposite of what a one-frame artefact needs kept. The scenarios'
own captures come straight from the box's output.

Useful while the game is still compiling its pipelines on a first start: VNC
shows the progress bar, where a scenario waiting on the title screen only shows
you a timeout several minutes later.

In a container, `wayvnc` needs `spirv-tools` installed or it dies on a missing
symbol — [docs/containers.md](docs/containers.md) has that and the rest.

## With an agent (MCP)

Copy [.mcp.json.example](.mcp.json.example) to `.mcp.json` in your project
with the absolute path to `wbox/config.yaml`. `sg input` gives the server the
input group before you have logged in again; it is harmless after. Then ask:
*"Launch Hookshot, wait for the title screen, and show me a screenshot."* —
or *"run the boot-title scenario three times and compare the runs."*

## License

MIT for this repository's files. Hookshot and wbox have their own licences;
the game is Nintendo's.
