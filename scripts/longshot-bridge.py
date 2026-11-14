#!/usr/bin/env python3
"""Talk to a running Longshot over its control bridge.

Longshot opens a Unix socket inside the game process when HOS_CONTROL names one
(Longshot's docs/control.md). The protocol is newline-delimited JSON: one object
a line, replies carrying back the request's `id` and the game's current frame.
Replies may come out of order, so they are matched by `id`; a line with `event`
and no `ok` is a subscription event.

This is a small client for the few things a measured run needs -- the game's own
`scripts/longshot_ctl.py` is the complete one. Nothing here needs a package.

    scripts/longshot-bridge.py status
    scripts/longshot-bridge.py option get                    # every setting
    scripts/longshot-bridge.py option set fps_counter true   # through the menu's setter
    scripts/longshot-bridge.py teleport                      # list the destinations
    scripts/longshot-bridge.py teleport InsideTheDekuTree
    scripts/longshot-bridge.py watch --events present,map --count 5
    scripts/longshot-bridge.py shot /tmp/kokiri.png

The socket: --socket, else $HOS_CONTROL, else $XDG_RUNTIME_DIR/longshot/control.sock
(what scripts/../longshot sets up). Exit status is 0 on ok, 1 on the game's
error, 2 on a usage or connection problem.
"""
import argparse
import json
import os
import socket
import sys

LIMIT = 64 * 1024          # the bridge's own line limit


def default_socket():
    if os.environ.get("HOS_CONTROL"):
        return os.environ["HOS_CONTROL"]
    run = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    return os.path.join(run, "longshot", "control.sock")


class Bridge:
    def __init__(self, path):
        self.path = path
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.connect(path)
        except OSError as exc:
            raise SystemExit("%s: %s\n(the game must run with HOS_CONTROL=%s; "
                             "`longshot play` sets it)" % (path, exc.strerror, path))
        self.f = self.sock.makefile("rwb")
        self.id = 0

    def send(self, cmd, **args):
        self.id += 1
        line = json.dumps(dict(args, id=self.id, cmd=cmd)).encode() + b"\n"
        if len(line) > LIMIT:
            raise SystemExit("request over the bridge's 64 KB line limit")
        self.f.write(line)
        self.f.flush()
        return self.id

    def lines(self):
        for raw in self.f:
            try:
                yield json.loads(raw)
            except ValueError:
                print("not JSON from the bridge: %r" % raw[:200], file=sys.stderr)

    def call(self, cmd, **args):
        """One request, its reply -- skipping events and other ids."""
        want = self.send(cmd, **args)
        for msg in self.lines():
            if msg.get("id") == want and "ok" in msg:
                return msg
        raise SystemExit("the bridge closed before answering %s" % cmd)


def show(msg):
    print(json.dumps(msg, indent=2, sort_keys=True, ensure_ascii=False))
    return 0 if msg.get("ok") else 1


def value_of(text):
    """A setting's value: true/false, else a number, else refuse -- the bridge
    takes only those, and a quietly-wrong type is worse than an error here."""
    low = text.strip().lower()
    if low in ("true", "on", "yes"):
        return True
    if low in ("false", "off", "no"):
        return False
    try:
        return int(low)
    except ValueError:
        pass
    try:
        return float(low)
    except ValueError:
        raise SystemExit("value: a number, or true/false (got %r)" % text)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--socket", default=None, help="the bridge's socket (default: $HOS_CONTROL)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="frame, fps, draws, state, map, OoT snapshot, version")

    q = sub.add_parser("option", help="the Insert menu's settings, live")
    q.add_argument("action", choices=["get", "set"])
    q.add_argument("name", nargs="?", help="the ini key (text_speed) or the row's name")
    q.add_argument("value", nargs="?", help="set: a number, or true/false")

    q = sub.add_parser("press", help="buttons, for a number of game frames")
    q.add_argument("buttons", help="A B X Y L R ZL ZR PLUS MINUS LS RS LEFT UP RIGHT DOWN, as A+B")
    q.add_argument("--frames", type=int, default=8)
    q.add_argument("--at", type=int, default=0, help="frames to wait first")
    q.add_argument("--exclusive", action="store_true", help="keep the player's own pad out")

    q = sub.add_parser("wait", help="until the game reaches something")
    q.add_argument("--map")
    q.add_argument("--state", choices=["boot", "intro", "menu", "loading", "play", "unknown"])
    q.add_argument("--in-play", action="store_true")
    q.add_argument("--frames", type=int, help="this many more presents")
    q.add_argument("--timeout", type=float, default=60)

    q = sub.add_parser("shot", help="a PNG of the next present")
    q.add_argument("path", nargs="?", help="default: shots/ in the socket's folder")
    q.add_argument("--timeout", type=float, default=30)

    q = sub.add_parser("teleport", help="(OoT) the debug teleport; no argument lists the destinations")
    q.add_argument("to", nargs="?", help="an index, or a map name")
    q.add_argument("--timeout", type=float, default=10)

    q = sub.add_parser("watch", help="a stream of events until --count or Ctrl-C")
    q.add_argument("--events", default="present,state", help="present,state,log,map,oot")
    q.add_argument("--every", type=int, default=60, help="frames between present samples")
    q.add_argument("--log", help="only log lines containing this")
    q.add_argument("--count", type=int, help="stop after this many events")

    q = sub.add_parser("raw", help="send one JSON request as it is")
    q.add_argument("json", help='e.g. {"cmd":"status"}')

    a = p.parse_args(argv)
    b = Bridge(a.socket or default_socket())

    if a.cmd == "status":
        return show(b.call("status"))

    if a.cmd == "option":
        if a.action == "get":
            return show(b.call("option_get", **({"name": a.name} if a.name else {})))
        if not a.name or a.value is None:
            raise SystemExit("option set <name> <value>")
        return show(b.call("option_set", name=a.name, value=value_of(a.value)))

    if a.cmd == "press":
        args = {"buttons": a.buttons, "frames": a.frames}
        if a.at:
            args["at"] = a.at
        if a.exclusive:
            args["exclusive"] = True
        return show(b.call("press", **args))

    if a.cmd == "wait":
        args = {"timeout": a.timeout}
        if a.map:
            args.update(until="map", map=a.map)
        elif a.state:
            args.update(until="state", state=a.state)
        elif a.in_play:
            args.update(until="in_play")
        elif a.frames:
            args.update(until="present", frames=a.frames)
        else:
            raise SystemExit("wait: --map, --state, --in-play or --frames")
        return show(b.call("wait", **args))

    if a.cmd == "shot":
        args = {"timeout": a.timeout}
        if a.path:
            args["path"] = os.path.abspath(a.path)
        return show(b.call("shot", **args))

    if a.cmd == "teleport":
        return show(b.call("teleport", **({"to": a.to, "timeout": a.timeout} if a.to else {})))

    if a.cmd == "watch":
        args = {"events": [e for e in a.events.split(",") if e], "every": a.every}
        if a.log:
            args["log"] = a.log
        reply = b.call("subscribe", **args)
        if not reply.get("ok"):
            return show(reply)
        seen = 0
        try:
            for msg in b.lines():
                if "event" not in msg or "ok" in msg:
                    continue
                print(json.dumps(msg, sort_keys=True, ensure_ascii=False), flush=True)
                seen += 1
                if a.count and seen >= a.count:
                    break
        except KeyboardInterrupt:
            pass
        return 0

    if a.cmd == "raw":
        try:
            req = json.loads(a.json)
        except ValueError as exc:
            raise SystemExit("not JSON: %s" % exc)
        if not isinstance(req, dict) or "cmd" not in req:
            raise SystemExit('raw: an object with a "cmd"')
        cmd = req.pop("cmd")
        req.pop("id", None)
        return show(b.call(cmd, **req))

    return 2


if __name__ == "__main__":
    sys.exit(main())
