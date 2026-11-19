#!/usr/bin/env python3
"""Report a common screen size (CommonScreen.swift), in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/common_screen.py`. It uses the
split suite's harness in a world of its own: started hidden, no window made or
shown, everything removed afterwards. Checked:

- a page reads one of the common sizes, never smaller than its window, and
  the available area the same;
- a frame of the page's own, loaded, reads the same;
- the window resized, the next read follows it;
- with the switch off, from the next load, the page reads WebKit's own
  answer again.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("common-screen")

SIZES = [[1440, 900], [1920, 1080], [2560, 1440], [3840, 2160]]
READ = "[screen.width, screen.height, screen.availWidth, screen.availHeight, Math.max(outerWidth, innerWidth), Math.max(outerHeight, innerHeight)]"
FRAME = ("(function () { var f = document.createElement('iframe'); f.src = '/inner';"
         " document.body.appendChild(f); return 'made'; })()")
IN_FRAME = "(function () { var s = document.querySelector('iframe').contentWindow.screen; return [s.width, s.height]; })()"


def common(seen):
    w, h, aw, ah, ww, wh = seen
    return [w, h] in SIZES and [aw, ah] == [w, h] and ww <= w and wh <= h


def main():
    t = sv.T()
    try:
        sv.setup(); sv.launch()
        tab = sv.page("a"); sv.cmd({"do": "select", "id": tab}); sv.cmd({"do": "wait", "id": tab, "seconds": 5})

        seen = sv.ev(tab, READ)
        t.ok("a page reads a common screen that holds its window", common(seen), seen)

        sv.ev(tab, FRAME); time.sleep(1.5)
        inner = sv.ev(tab, IN_FRAME)
        t.ok("its frame reads the same screen", inner == seen[:2], (inner, seen))

        sv.cmd({"do": "windows", "action": "frame", "n": 1, "frame": [60, 80, 1000, 700]}); time.sleep(0.5)
        small = sv.ev(tab, READ)
        t.ok("a small window reads the smallest", small[:2] == SIZES[0] and common(small), small)
        sv.cmd({"do": "windows", "action": "frame", "n": 1, "frame": [0, 0, 1500, 1000]}); time.sleep(0.5)
        wide = sv.ev(tab, READ)
        t.ok("a wider one, the next that holds it", wide[:2] == SIZES[1] and common(wide), wide)

        sv.cmd({"do": "ui", "commonscreen": False})
        sv.cmd({"do": "go", "id": tab, "url": f"{sv.BASE}/b"}); sv.cmd({"do": "wait", "id": tab, "seconds": 5})
        plain = sv.ev(tab, READ)
        t.ok("switched off, the next page reads WebKit's own", plain[:2] != wide[:2], plain)
    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
