"""agent-town debug receiver: a stand-in for the app that prints incoming events.

It does what the app's loopback server does (docs/protocol.md):
- binds 127.0.0.1 on a random port (or --port);
- writes the endpoint file with a fresh token, mode 0600, and deletes it on exit;
- checks the bearer token and the protocol version (401 / 426);
- validates each batch against protocol/schema/v1.schema.json and prints it.

Standard library only. Usage:

    python3 tools/debug-receiver.py [--port N] [--endpoint PATH] [--log FILE] [--quiet]

--log appends every accepted batch as one JSON line, so real event timing can be
studied later or turned into fixtures.
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from protocol_check import check_batch, load_schema  # noqa: E402

DEFAULT_ENDPOINT = os.path.expanduser(
    "~/Library/Application Support/agent-town/endpoint.json"
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


def make_handler(token, schema, log_path, quiet):
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
            try:
                batch = json.loads(self.rfile.read(length))
            except ValueError:
                print("! 400 body is not JSON")
                return self._reply(400)
            if batch.get("protocol") != PROTOCOL:
                print(f"! 426 protocol {batch.get('protocol')!r}")
                return self._reply(426)
            self._reply(204)

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
    args = ap.parse_args()

    token = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode()
    schema = load_schema()
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port), make_handler(token, schema, args.log, args.quiet)
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
                if json.load(fh).get("pid") == os.getpid():
                    os.remove(args.endpoint)
        except (OSError, ValueError):
            pass
        print("stopped; endpoint file removed")


if __name__ == "__main__":
    main()
