#!/usr/bin/env python3
"""Play Hookshot in the box, with your own pad, watching over VNC.

The box stays offscreen, so a run can be watched without taking over the
screen: the game runs headless, `wayvnc` serves the box's output to a VNC
client you open and close like any window, and your physical pad drives the
box's virtual pad through wbox's proxy. Your desktop keeps its focus, and
with PAD_GRAB=1 (the default) your pad stops reaching anything else, so a
stick drift does not scroll the browser behind.

It is the by-hand half of a scenario: play the sequence yourself first,
watch where the game goes wrong, then write it down as a scenario and have
`wboxr run` play it again.

    scripts/play.py                    # 30 min, pad grabbed, VNC on 5900

    SESSION_MINUTES=5                  how long before the box is stopped
    PAD_GRAB=0                         share the pad with the desktop
    PAD_DEVICE=/dev/input/event4       a pad, instead of the first one found
    VNC_PORT=5901                      a port, instead of 5900
    VNC=0                              no VNC: a scripted or logged run
    HOOKSHOT_DIR=...                   the game, if not ~/Games/Hookshot
    WBOX_RENDERER=gles2                the compositor's renderer
    WBOX_RENDER_DEVICE=/dev/dri/renderD128   which GPU it draws on

In a container the last two matter: see docs/containers.md.
"""
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path

from wbox.config import load_config
from wbox.server import build_compositor

REPO = Path(__file__).resolve().parent.parent
MINUTES = float(os.environ.get("SESSION_MINUTES", "30"))
GRAB = os.environ.get("PAD_GRAB", "1") != "0"
DEVICE = os.environ.get("PAD_DEVICE", "auto")
VNC_ADDR = os.environ.get("VNC_ADDR", "127.0.0.1")
VNC_PORT = os.environ.get("VNC_PORT", "5900")
WANT_VNC = os.environ.get("VNC", "1") != "0"

cfg = load_config(REPO / "wbox" / "config.yaml")
if not cfg:
    sys.exit(f"no box config at {REPO / 'wbox' / 'config.yaml'}")
cfg["headless"] = True          # the point of this script
for key, var in (("renderer", "WBOX_RENDERER"),
                 ("render_device", "WBOX_RENDER_DEVICE")):
    if os.environ.get(var):
        cfg[key] = os.environ[var]

shots = Path(cfg.get("_config_dir", REPO / "wbox")) / cfg.get("screenshot_dir", "./screenshots")
shots.mkdir(parents=True, exist_ok=True)
logs = Path(cfg.get("_config_dir", REPO / "wbox")) / cfg.get("log", {}).get("dir", "./log")
logs.mkdir(parents=True, exist_ok=True)

box = build_compositor(cfg)
box.state.screenshot_dir = shots
vnc = None

try:
    print(f"the box: {cfg.get('compositor')} headless {cfg.get('screen')}"
          f"{' on ' + cfg['render_device'] if cfg.get('render_device') else ''}",
          flush=True)
    r = box.launch(shlex.split(cfg["app"]["command"]),
                   dict(cfg.get("app", {}).get("env", {})))
    if not r.get("gamepad"):
        print("  no virtual pad: /dev/uinput (scripts/setup-uinput.sh) and "
              "bwrap are what it needs", flush=True)
    else:
        print(f"  virtual pad  {r['gamepad'].get('node')}"
              f"{'  (the app is sandboxed to it)' if r['gamepad'].get('isolated') else ''}",
              flush=True)

    # your pad into the box's pad: nothing else in the box reads input
    p = box.pad_proxy(DEVICE, grab=GRAB)
    if p.get("error"):
        print(f"  no pad proxy: {p['error']}\n"
              "  the game will not see your pad — PAD_DEVICE=/dev/input/eventN "
              "picks one", flush=True)
    else:
        pad = p.get("proxy", {})
        print(f"  your pad     {pad.get('name')} on {pad.get('device')}"
              f"{'  grabbed: it drives the box only' if pad.get('grab') else '  shared with the desktop'}",
              flush=True)

    if WANT_VNC:
        vnc_log = logs / "wayvnc.log"
        env = dict(os.environ, WAYLAND_DISPLAY=r.get("wayland_display", "wayland-0"))
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        with open(vnc_log, "w") as fh:
            vnc = subprocess.Popen(["wayvnc", VNC_ADDR, VNC_PORT],
                                   env=env, stdout=subprocess.DEVNULL, stderr=fh)
        time.sleep(3)
        if vnc.poll() is not None:
            print(f"  no VNC: see {vnc_log}", flush=True)
            vnc = None
        else:
            print(f"  watch it    krdc vnc://{VNC_ADDR}:{VNC_PORT}"
                  "   (set the client to view only, and its quality to the highest)",
                  flush=True)

    print(f"\n{MINUTES:.0f} min, then the box is stopped and your pad is "
          "given back. Ctrl-C does the same.\n", flush=True)

    end = time.time() + MINUTES * 60
    minute = 0
    while time.time() < end:
        time.sleep(min(120, max(1, end - time.time())))
        minute += 2
        shot = box.screenshot(f"play-{minute:03d}")
        proxy = getattr(box, "_pad_proxy", None)
        events = proxy.status().get("events", "?") if proxy else "-"
        size = shot.get("size") if isinstance(shot, dict) else shot
        print(f"  t+{minute:3d} min   capture {size} bytes   pad events {events}",
              flush=True)
except KeyboardInterrupt:
    print("\nstopping", flush=True)
finally:
    if vnc and vnc.poll() is None:
        vnc.send_signal(signal.SIGTERM)
    try:
        box.pad_proxy_stop()
    except Exception as exc:          # your pad matters more than a clean exit
        print(f"  pad_proxy_stop: {exc}", flush=True)
    box.stop()
    print("stopped — your pad is yours again", flush=True)
