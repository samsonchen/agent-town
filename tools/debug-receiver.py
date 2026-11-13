"""agent-town debug receiver: a stand-in for the app that prints incoming events.

It does what the app's loopback server does (docs/protocol.md):
- binds 127.0.0.1 on a random port (or --port);
- writes the endpoint file with a fresh token, mode 0600, and deletes it on exit;
- checks the bearer token and the protocol version (401 / 426);
- validates each batch against protocol/schema/v1.schema.json and prints it.

Standard library only. Usage:

    python3 tools/debug-receiver.py [--port N] [--endpoint PATH] [--log FILE] [--quiet] [--forward]

--log appends every accepted batch as one JSON line, so real event timing can be
studied later or turned into fixtures.

--forward keeps the running app working: each batch is also sent on to the app found in
the endpoint file at start, and that app's endpoint file is put back on exit.
"""

import argparse
import base64
import json
import os
import secrets
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from protocol_check import check_batch, load_schema  # noqa: E402

DEFAULT_ENDPOINT = (
    os.path.join(os.environ["APPDATA"], "agent-town-claude-code", "endpoint.json")
    if os.name == "nt" and os.environ.get("APPDATA")
    else os.path.expanduser("~/Library/Application Support/agent-town-claude-code/endpoint.json")
)
PROTOCOL = 1
APP_VERSION = "0.0.0-debug"


def write_endpoint(path, port, token):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(
            {
                "protocol": PROTOCOL,
                "port": port,
                "token": token,
                "pid": os.getpid(),
                "app": "agent-town",
                "appVersion": APP_VERSION,
            },
            fh,
        )
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def forward_batch(app, body):
    req = urllib.request.Request(
        f"http://127.0.0.1:{app['port']}/v1/events",
        data=body,
        headers={"Authorization": f"Bearer {app['token']}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=2).read()
    except Exception as e:  # noqa: BLE001 - report and go on
        print(f"! forward failed: {e}")


def write_endpoint_raw(path, content):
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(content, fh)
    os.replace(tmp, path)


def make_handler(token, schema, log_path, quiet, app=None):
    class Handler(BaseHTTPRequestHandler):
        server_version = "agent-town-debug"

        def log_message(self, format, *args):  # noqa: A002 - silence access log
            pass

        def _reply(self, status):
            self.send_response(status)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_POST(self):
            if self.path != "/v1/events":
                return self._reply(404)
            if self.headers.get("Authorization") != f"Bearer {token}":
                print("! 401 wrong or missing token")
                return self._reply(401)
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length)
            try:
                batch = json.loads(body)
            except ValueError:
                print("! 400 body is not JSON")
                return self._reply(400)
            if batch.get("protocol") != PROTOCOL:
                print(f"! 426 protocol {batch.get('protocol')!r}")
                return self._reply(426)
            self._reply(204)
            if app:
                forward_batch(app, body)

            received = int(time.time() * 1000)
            errs = check_batch(batch, schema)
            if log_path:
                with open(log_path, "a") as fh:
                    fh.write(json.dumps({"receivedTs": received, "batch": batch}) + "\n")
            for ev in batch.get("events", []):
                lag = received - ev.get("ts", received)
                extra = {
                    k: v
                    for k, v in ev.items()
                    if k not in ("type", "sessionId", "seq", "ts", "projectId")
                }
                line = (
                    f"{time.strftime('%H:%M:%S')} "
                    f"{str(ev.get('sessionId', '?'))[:8]:8} #{ev.get('seq', '?'):<4} "
                    f"{ev.get('type', '?'):16} +{lag}ms"
                )
                print(line if quiet else f"{line}  {json.dumps(extra, ensure_ascii=False)}")
            for e in errs:
                print(f"  ! schema: {e}")
            sys.stdout.flush()

    return Handler


def main():
    ap = argparse.ArgumentParser(description="agent-town debug receiver")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    ap.add_argument("--log")
    ap.add_argument("--quiet", action="store_true", help="hide event fields")
    ap.add_argument("--forward", action="store_true", help="also send each batch to the running app")
    args = ap.parse_args()

    app = None
    if args.forward:
        try:
            with open(args.endpoint) as fh:
                app = json.load(fh)
        except (OSError, ValueError):
            sys.exit("--forward: no app endpoint file to forward to; start the app first")
        print(f"forwarding to the app on port {app['port']}")

    token = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode()
    schema = load_schema()
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port), make_handler(token, schema, args.log, args.quiet, app)
    )
    port = server.server_address[1]
    write_endpoint(args.endpoint, port, token)
    print(f"agent-town debug receiver on http://127.0.0.1:{port}/v1/events")
    print(f"endpoint file: {args.endpoint}")
    sys.stdout.flush()

    def stop(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        try:
            with open(args.endpoint) as fh:
                mine = json.load(fh).get("pid") == os.getpid()
        except (OSError, ValueError):
            mine = False
        if mine and app:
            write_endpoint_raw(args.endpoint, app)
            print("stopped; the app's endpoint file is back")
        else:
            if mine:
                os.remove(args.endpoint)
            print("stopped; endpoint file removed")


if __name__ == "__main__":
    main()
