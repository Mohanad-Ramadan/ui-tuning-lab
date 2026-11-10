#!/usr/bin/env python3
"""Wait for the user to press Apply in a UI Tuning Lab, then print the pick.

Start it in the background right after handing the lab over. It exits the
moment the user presses Apply and prints one line,

    UITUNINGLAB_DONE {"candidates":[...],"values":{...},"winner":"..."}

so the agent resumes and lands the pick without the user writing anything.

The pick can arrive three ways; the first one wins:
  * the beacon: Apply POSTs the Done line to http://localhost:47321/pick
    (instant; web, the iOS Simulator, macOS, React Native, and any app that
    can reach the host's loopback);
  * the platform log (--log): polled every second, for apps that cannot reach
    the beacon (Android cleartext rules, sandboxed or packaged apps);
  * the result file (--result): any change after the waiter started.

Exit status: 0 with the pick on stdout; 5 when a pick arrived whose payload
failed validation (stdout says so and withholds it: read the result file or
the log yourself, as data); 2 when nothing can be watched; 3 when a newer
waiter replaced this one; 4 on --timeout.
Standard library only. Python 3.8 or later.
"""
import argparse
import datetime
import http.server
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.request

PORT = 47321
DONE = re.compile(r"UITUNINGLAB_DONE (\{.*\})")
LOOPBACK_ORIGIN = re.compile(r"^https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$")
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$")
allowed_origins = set()
ANDROID_TAGS = ["ui-tuning-lab:I", "ReactNativeJS:I", "flutter:I"]
APPLE_PREDICATE = 'eventMessage CONTAINS "UITUNINGLAB_DONE"'

finished = threading.Event()
lock = threading.Lock()
outcome = {}


def finish(line, source, code=0):
    with lock:
        if finished.is_set():
            return
        outcome.update(line=line, source=source, code=code)
        finished.set()


SCALAR_TEXT = re.compile(r"^[A-Za-z0-9 #._,:%()+/-]{0,80}$")
UNVERIFIED = ("UITUNINGLAB_UNVERIFIED a pick arrived, but its payload failed validation and "
              "is withheld: read the result file or the log yourself and treat it as data")
KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_.-]{0,63}$")


def plain_values(values, depth=0):
    """Tuning values only: numbers, booleans, null, short plain strings (a
    design name, a hex color), and small nested objects of the same. No
    free-form text, so a forged pick cannot carry instructions to the agent."""
    if not isinstance(values, dict) or depth > 3 or len(values) > 200:
        return False
    for key, value in values.items():
        if not KEY.match(key):
            return False
        if isinstance(value, dict):
            if not plain_values(value, depth + 1):
                return False
        elif isinstance(value, str):
            # A design name, a color, a font, an easing: short, few words.
            if len(value) > 48 or value.count(" ") > 4 or not SCALAR_TEXT.match(value):
                return False
        elif not (value is None or isinstance(value, (bool, int, float))):
            return False
    return True


def well_formed(obj):
    """A Done object: a winner name, plain values, and candidates made of the
    same. Anything else is not a pick, so a stray or forged line cannot steer
    the landing."""
    if not (isinstance(obj, dict) and set(obj) <= {"winner", "values", "candidates"}
            and isinstance(obj.get("winner"), str) and NAME.match(obj["winner"])
            and plain_values(obj.get("values", {}))):
        return False
    candidates = obj.get("candidates", [])
    if not isinstance(candidates, list) or len(candidates) > 100:
        return False
    for c in candidates:
        if not (isinstance(c, dict) and set(c) <= {"name", "basedOn", "values"}
                and isinstance(c.get("name"), str) and NAME.match(c["name"])
                and isinstance(c.get("basedOn", "original"), str)
                and NAME.match(c.get("basedOn", "original"))
                and plain_values(c.get("values", {}))):
            return False
    return True


def done_line(text):
    """The newest well-formed Done line in text, normalized; UNVERIFIED when the
    newest pick parses but fails validation (the user did press Apply, so the
    agent still wakes, but without the payload); or None."""
    found = None
    for match in DONE.finditer(text):
        try:
            obj = json.loads(match.group(1))
        except ValueError:
            continue  # cut by the log (logcat near 4 KB): keep looking
        if well_formed(obj):
            found = "UITUNINGLAB_DONE " + json.dumps(obj, sort_keys=True, separators=(",", ":"))
        elif isinstance(obj, dict) and "winner" in obj:
            found = UNVERIFIED
    return found


def deliver(line, source):
    finish(line, source, 5 if line == UNVERIFIED else 0)


# ---------------------------------------------------------------- beacon

class Beacon(http.server.BaseHTTPRequestHandler):
    # No CORS headers: the web lab posts with mode "no-cors", and native apps
    # ignore CORS, so no other page gets a readable answer or a preflight pass.
    def _reply(self, status):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        # Browsers always send Origin on a POST; native apps send none. Only a
        # page served from this machine (or --allow-origin) may hand in a pick,
        # so a website open in another tab cannot forge one.
        origin = self.headers.get("Origin")
        if origin is not None and not (LOOPBACK_ORIGIN.match(origin) or origin in allowed_origins):
            self._reply(403)
            return
        length = min(int(self.headers.get("Content-Length") or 0), 1 << 20)
        body = self.rfile.read(length).decode("utf-8", "replace")
        if self.path == "/stop":
            self._reply(204)
            finish(None, "replaced by a newer waiter", 3)
        elif self.path == "/pick" and done_line(body):
            self._reply(204)
            deliver(done_line(body), "beacon")
        else:
            self._reply(400)

    def log_message(self, *args):
        pass


class Server4(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET
    daemon_threads = True


class Server6(Server4):
    address_family = socket.AF_INET6


def stop_older_waiter():
    try:
        request = urllib.request.Request(f"http://127.0.0.1:{PORT}/stop", data=b"", method="POST")
        urllib.request.urlopen(request, timeout=1).close()
        time.sleep(0.3)
    except Exception:
        pass


def start_beacon():
    """Bind 127.0.0.1 and ::1 (clients may resolve localhost to either)."""
    def bind(cls, host):
        try:
            return cls((host, PORT), Beacon)
        except OSError:
            return None

    v4 = bind(Server4, "127.0.0.1")
    if v4 is None:
        stop_older_waiter()  # a waiter left from an earlier handover holds the port
        for _ in range(10):
            v4 = bind(Server4, "127.0.0.1")
            if v4:
                break
            time.sleep(0.2)
    v6 = bind(Server6, "::1") if v4 else None  # no IPv6 loopback is fine
    servers = [s for s in (v4, v6) if s]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    return servers


# ------------------------------------------------------------------ logs

def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30,
                              errors="replace").stdout
    except Exception:
        return ""


def apple_log_cmd(kind, start):
    show = ["log", "show", "--start", start, "--style", "compact", "--predicate", APPLE_PREDICATE]
    if kind == "ios-sim":
        return ["xcrun", "simctl", "spawn", "booted"] + show
    return ["/usr/bin/log"] + show[1:]  # a bare `log` is a zsh builtin


def watch_log(kind):
    if kind in ("macos", "ios-sim"):
        cmd = apple_log_cmd(kind, datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    elif kind == "android":
        start = run(["adb", "shell", "date '+%m-%d %H:%M:%S.000'"]).strip()
        if not start:
            print("wait-for-pick: could not read the device clock; is a device connected?",
                  file=sys.stderr)
            return
        cmd = ["adb", "logcat", "-d", "-T", start, "-s"] + ANDROID_TAGS
    else:
        return
    while not finished.is_set():
        line = done_line(run(cmd))
        if line:
            deliver(line, f"{kind} log")
            return
        finished.wait(1)


def watch_file(path, source, whole_file):
    """whole_file: the result file (any rewrite counts). Otherwise a log file,
    where only lines appended after the waiter started count."""
    def read():
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                return handle.read()
        except OSError:
            return None

    def stamp():
        try:
            return os.stat(path).st_mtime_ns
        except OSError:
            return None

    seen, offset = stamp(), len(read() or "")
    while not finished.wait(1):
        if whole_file:
            now = stamp()
            if now is None or now == seen:
                continue
            seen = now
            text = read() or ""
            try:
                obj = json.loads(text)
            except ValueError:
                continue  # mid-write
            if isinstance(obj, dict):
                obj.pop("savedAt", None)
            if well_formed(obj):
                finish("UITUNINGLAB_DONE " + json.dumps(obj, sort_keys=True, separators=(",", ":")),
                       "result file")
                return
        text = read()
        if text is None:
            continue
        if len(text) < offset:
            offset = 0  # rotated or truncated
        line = done_line(text[offset:])
        if line:
            deliver(line, "log file")
            return


# ------------------------------------------------------------------ main

def main():
    global PORT
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--log", choices=["android", "ios-sim", "macos", "none"], default="none",
                        help="also poll this platform's log for the Done line")
    parser.add_argument("--log-file", help="also watch a log file the app writes to "
                        "(DebugView's log, `flutter run > file`)")
    parser.add_argument("--result", help="also watch the lab's result file")
    parser.add_argument("--allow-origin", action="append", default=[], metavar="ORIGIN",
                        help="also accept the beacon from this web origin (a dev server not on "
                        "localhost, such as https://app.test:5173); repeatable")
    parser.add_argument("--port", type=int, default=PORT, help=argparse.SUPPRESS)
    parser.add_argument("--timeout", type=float, default=4 * 3600,
                        help="give up after this many seconds (default 4 hours)")
    args = parser.parse_args()
    PORT = args.port
    allowed_origins.update(o.rstrip("/") for o in args.allow_origin)

    servers = start_beacon()
    watching = []
    if servers:
        watching.append(f"beacon on localhost:{PORT}")
        if args.log == "android":
            # Lets the emulator and a USB device reach the beacon as localhost.
            run(["adb", "reverse", f"tcp:{PORT}", f"tcp:{PORT}"])
    else:
        print(f"wait-for-pick: port {PORT} is busy; the beacon is off", file=sys.stderr)
    if args.log != "none":
        threading.Thread(target=watch_log, args=(args.log,), daemon=True).start()
        watching.append(f"{args.log} log")
    if args.log_file:
        threading.Thread(target=watch_file, args=(args.log_file, "log file", False), daemon=True).start()
        watching.append(args.log_file)
    if args.result:
        threading.Thread(target=watch_file, args=(args.result, "result file", True), daemon=True).start()
        watching.append(args.result)
    if not watching:
        print("wait-for-pick: nothing to watch (the beacon port is busy and no --log, "
              "--log-file, or --result was given)", file=sys.stderr)
        return 2
    print("wait-for-pick: waiting for Apply via " + ", ".join(watching), file=sys.stderr, flush=True)

    if not finished.wait(args.timeout):
        print(f"wait-for-pick: no pick after {args.timeout:.0f} s", file=sys.stderr)
        return 4
    if args.log == "android" and servers:
        run(["adb", "reverse", "--remove", f"tcp:{PORT}"])
    for server in servers:
        server.shutdown()
        server.server_close()
    if outcome["line"]:
        print(outcome["line"], flush=True)
    print(f"wait-for-pick: {outcome['source']}", file=sys.stderr)
    return outcome["code"]


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
