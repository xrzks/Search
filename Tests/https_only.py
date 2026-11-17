#!/usr/bin/env python3
"""HTTPS only (HTTPSOnly.swift), in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/https_only.py`. As
proxy_live.py: a copy of build/Search.app under a bundle id of its own,
hidden, in a world of its own, with this script's proxy set in Settings. The
hosts probe.test and frame.test exist only there, as the local page server.

WebKit asks a proxy for http and https alike with CONNECT, so the proxy
looks at the first bytes through each tunnel: a TLS handshake is https, and
is closed, since the page server speaks only http; anything else is plain
http, passed on. Checked:

- an http address typed is gone to over https, and the page that fails over
  it asks about http instead of saying it didn't load;
- a redirect to http, and a frame on http, go over https too;
- 127.0.0.1, this Mac, is left on http;
- a site let over http (the setting Load over HTTP writes) loads as it is;
- with the setting off, http loads as it is.
"""
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402
import proxy_live as pl  # noqa: E402

sv.use("https-only")
BUNDLE = "com.officecommun.search.httpsonly"
work = Path(tempfile.mkdtemp(prefix="search-httpsonly-"))

seen = []           # (host, "tls" or "plain") for each tunnel
seen_lock = threading.Lock()


def tunnels(host, kind):
    with seen_lock:
        return [s for s in seen if s == (host, kind)]


class Pages(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", f"http://probe.test:{PAGE_PORT}/redirected")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path == "/framed":
            body = f"<!doctype html><title>framed</title><iframe src='http://frame.test:{PAGE_PORT}/inner'></iframe>"
        else:
            body = f"<!doctype html><title>{self.path.strip('/')}</title><p>{self.path}"
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


pages = ThreadingHTTPServer(("127.0.0.1", 0), Pages)
threading.Thread(target=pages.serve_forever, daemon=True).start()
PAGE_PORT = pages.server_port


class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_CONNECT(self):
        host, _, port = self.path.rpartition(":")
        try:
            up = socket.create_connection(("127.0.0.1" if host.endswith(".test") else host, int(port)), timeout=5)
        except OSError:
            self.send_error(502)
            return
        self.send_response(200, "Connection established")
        self.end_headers()
        self.wfile.flush()
        down = self.connection
        first = down.recv(65536)
        tls = first[:1] == b"\x16"
        with seen_lock:
            seen.append((host, "tls" if tls else "plain"))
        if tls or not first:
            for s in (up, down):
                s.close()
            self.close_connection = True
            return
        up.sendall(first)
        upward = threading.Thread(target=pl.Proxy._pipe, args=(down, up), daemon=True)
        upward.start()
        pl.Proxy._pipe(up, down)
        upward.join(timeout=2)
        for s in (up, down):
            try:
                s.close()
            except OSError:
                pass
        self.close_connection = True

    def log_message(self, *a):
        pass


proxy = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
threading.Thread(target=proxy.serve_forever, daemon=True).start()
pl.PROXY_PORT = proxy.server_port


def start(**prefs):
    sv.setup(sidebar=True, **prefs)
    pl.set_proxy(True)


def waited(page_id):
    return sv.cmd({"do": "wait", "id": page_id, "seconds": 8})


def main():
    t = sv.T()
    pl.BUNDLE = BUNDLE
    shutil.rmtree(pl.work, ignore_errors=True)
    pl.work = work
    sv.APP = pl.probe_copy()
    probe = f"http://probe.test:{PAGE_PORT}"
    local = f"http://127.0.0.1:{PAGE_PORT}"
    try:
        start()
        sv.launch()

        page = pl.opened(f"{probe}/typed")
        got = waited(page)
        t.ok("an http address goes over https", bool(tunnels("probe.test", "tls")), seen)
        t.ok("and never over http", not tunnels("probe.test", "plain"), seen)
        t.ok("failing there, the page asks about http",
             "doesn't offer a secure connection" in got.get("failure", ""), got.get("failure"))

        seen.clear()
        page = pl.opened(f"{local}/redirect")
        waited(page)
        t.ok("a redirect to http goes over https",
             bool(tunnels("probe.test", "tls")) and not tunnels("probe.test", "plain"), seen)

        seen.clear()
        page = pl.opened(f"{local}/framed")
        got = waited(page)
        time.sleep(1.5)
        t.ok("127.0.0.1 is left on http", got.get("title") == "framed", got)
        t.ok("a frame on http goes over https",
             bool(tunnels("frame.test", "tls")) and not tunnels("frame.test", "plain"), seen)
        sv.quit()

        # Load over HTTP keeps the site, as this.
        seen.clear()
        start()
        subprocess.run(["defaults", "write", sv.SUITE, "https.allowed", "-array", "probe.test"], check=True)
        sv.launch()
        page = pl.opened(f"{probe}/allowed")
        t.ok("a site let over http loads on http", pl.title(page) == "allowed", (pl.title(page), seen))
        t.ok("and isn't tried over https first", not tunnels("probe.test", "tls"), seen)
        sv.quit()

        seen.clear()
        start(**{"https.only": False})
        sv.launch()
        page = pl.opened(f"{probe}/off")
        t.ok("turned off, http loads as it is", pl.title(page) == "off", (pl.title(page), seen))
    finally:
        sv.finish()
        for kind in ("WebKit", "Caches", "HTTPStorages"):
            shutil.rmtree(Path.home() / "Library" / kind / BUNDLE, ignore_errors=True)
        subprocess.run(["defaults", "delete", sv.SUITE], capture_output=True)
        shutil.rmtree(work, ignore_errors=True)
    return t


if __name__ == "__main__":
    t = main()
    t.done()
    sys.exit(1 if t.failed else 0)
