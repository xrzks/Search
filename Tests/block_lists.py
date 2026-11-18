#!/usr/bin/env python3
"""The bigger block lists and campaign tags, in a hidden probe.

Build first (`./build.sh`, which brings in the lists), then
`python3 Tests/block_lists.py`. A copy of build/Search.app
under a bundle id of its own, hidden, in a world of its own. One page server
on 127.0.0.1 notes every request it is asked; the page asks for a pixel
EasyPrivacy blocks anywhere (/1x1.gif?), an image EasyList blocks anywhere
(/ad_pos=), one neither knows, and has a box EasyList hides everywhere
(#AD_160). Checked:

- by default, EasyPrivacy's pixel is never asked for, EasyList's image is,
  and the box shows;
- with Block more ads on, the image isn't asked for and the box is hidden;
- with Block ads and trackers off, everything is asked for;
- a page's address loses its utm_ tags before it loads, and keeps the rest;
- a site that sends the clean address back to the tagged one gets its way,
  once, rather than going round;
- with Remove campaign tags off, the tags stay.
"""
import shutil
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

sv.use("block-lists")
BUNDLE = "io.github.xrzks.search.blocklists"
work = Path(tempfile.mkdtemp(prefix="search-blocklists-"))

asked = []
asked_lock = threading.Lock()
PAGE = """<!doctype html><title>page</title>
<img src="/1x1.gif?probe=1"><img src="/ad_pos=1"><img src="/plain.gif">
<div id="AD_160" style="height:40px">box</div>"""


class Pages(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        with asked_lock:
            asked.append(self.path)
        if self.path == "/loop":
            # The clean address sent straight back to the tagged one.
            self.send_response(302)
            self.send_header("Location", "/loop?utm_source=back")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        name = self.path.split("?")[0].strip("/")
        body = PAGE if name == "page" else f"<!doctype html><title>{name}</title>"
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "image/gif" if name.endswith(".gif") or "=" in name else "text/html")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


pages = ThreadingHTTPServer(("127.0.0.1", 0), Pages)
threading.Thread(target=pages.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{pages.server_port}"


def was_asked(prefix):
    with asked_lock:
        return any(p.startswith(prefix) for p in asked)


def box_shown(page_id):
    return sv.ev(page_id, "document.getElementById('AD_160').offsetHeight") or 0


def load_page(blocked="/1x1.gif"):
    """The page, once the lists are ready: the first launch compiles them,
    a few seconds in which pages load unblocked."""
    page = None
    for _ in range(15):
        with asked_lock:
            asked.clear()
        page = pl.opened(f"{BASE}/page")
        if was_asked("/plain.gif") and not was_asked(blocked):
            return page
        time.sleep(2)
    return page


def main():
    t = sv.T()
    pl.BUNDLE = BUNDLE
    shutil.rmtree(pl.work, ignore_errors=True)
    pl.work = work
    sv.APP = pl.probe_copy()
    try:
        sv.setup(sidebar=True)
        sv.launch()
        page = load_page()
        t.ok("EasyPrivacy's pixel is never asked for", not was_asked("/1x1.gif"), asked)
        t.ok("what no list names is", was_asked("/plain.gif"), asked)
        t.ok("EasyList is off by default: its image is asked for", was_asked("/ad_pos="), asked)
        t.ok("…and its box shows", box_shown(page) > 0)

        with asked_lock:
            asked.clear()
        page = pl.opened(f"{BASE}/tagged?utm_source=news&id=7&utm_medium=mail")
        t.ok("campaign tags go before the page loads", "/tagged?id=7" in asked, asked)
        t.ok("…and the address never went out with them", not any("utm_" in p for p in asked), asked)

        with asked_lock:
            asked.clear()
        page = pl.opened(f"{BASE}/loop?utm_source=first")
        t.ok("a site that wants its tags back gets them", pl.title(page) == "loop", (pl.title(page), asked))
        t.ok("…without going round", len([p for p in asked if p.startswith("/loop")]) <= 4, asked)
        sv.quit()

        sv.setup(sidebar=True, **{"shield.easylist": True})
        sv.launch()
        page = load_page(blocked="/ad_pos=")
        time.sleep(1)
        t.ok("with Block more ads on, EasyList's image isn't asked for", not was_asked("/ad_pos="), asked)
        t.ok("…and its box is hidden", box_shown(page) == 0)
        sv.quit()

        sv.setup(sidebar=True, shield=False, **{"privacy.campaignTags": False})
        sv.launch()
        with asked_lock:
            asked.clear()
        page = pl.opened(f"{BASE}/page")
        t.ok("with blocking off, the pixel is asked for", was_asked("/1x1.gif"), asked)
        with asked_lock:
            asked.clear()
        pl.opened(f"{BASE}/tagged?utm_source=news&id=7")
        t.ok("with Remove campaign tags off, the tags stay", "/tagged?utm_source=news&id=7" in asked, asked)
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
