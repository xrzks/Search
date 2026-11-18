#!/usr/bin/env python3
"""YT Tweaks' options page, made small, in a hidden probe: buttons and
inputs made into the extension's own elements with `is=`.

Build first (`./build.sh`), then `python3 Tests/extension_builtins.py`.
It runs a copy of build/Search.app under a bundle id of its own, in a world
of its own with split_view.py's harness, started hidden; the copy, its
WebKit folders and the world are removed afterwards.

YT Tweaks writes its menus as `<button is="select-button">` and its search
field as `<input is="search-box">`, defined with `customElements.define(…,
{ extends: "button" })`: customized built-in elements, which Chrome has and
WebKit doesn't. Its theme menus were empty rows that did nothing when
clicked. Search puts @ungap/custom-elements in such an extension's pages
(ExtensionBuiltIns.swift). What is checked:

- an element in the page itself gets its class, constructor and all;
- so does one in a fragment loaded later with insertAdjacentHTML, as YT
  Tweaks loads its tabs, and one made with createElement's `is`;
- clicking one calls what its class gave it;
- an ordinary custom element still works beside them;
- a page of an extension that uses none doesn't carry the polyfill.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("hub-sp-builtins")
BUNDLE = "com.officecommun.search.hubspbuiltins"
work = Path(tempfile.mkdtemp(prefix="search-builtins-"))

FILES = {
    "manifest.json": json.dumps({
        "manifest_version": 3, "name": "Built In", "version": "1.0",
        "options_ui": {"page": "options/options.html", "open_in_tab": True},
    }),
    "options/options.html": (
        '<html lang="en"><head><meta charset="utf-8"></head><body>'
        '<input is="search-box">'
        '<button is="select-button" id="theme"><ul><li value="default">Default</li><li value="rose">Rose</li></ul></button>'
        '<div id="tab"></div><plain-thing></plain-thing>'
        '<script src="options.js" type="module"></script>'
        '</body></html>'),
    "options/tabs/themes.html": '<button is="select-button" id="later"><ul><li value="a">A</li></ul></button>',
    "options/options.js": """
window.__clicked = [];
class SelectButton extends HTMLButtonElement {
  constructor() {
    super();
    const span = document.createElement('span');
    const first = this.querySelector('li');
    span.textContent = first ? first.textContent : 'new';
    this.appendChild(span);
    this.action = () => window.__clicked.push(this.id);
  }
}
customElements.define('select-button', SelectButton, { extends: 'button' });
class SearchBox extends HTMLInputElement {
  constructor() { super(); this.placeholder = 'Search'; }
}
customElements.define('search-box', SearchBox, { extends: 'input' });
class PlainThing extends HTMLElement {
  connectedCallback() { this.textContent = 'plain'; }
}
customElements.define('plain-thing', PlainThing);
document.addEventListener('click', (e) => e.target.closest('button')?.action?.());
const html = await (await fetch(chrome.runtime.getURL('options/tabs/themes.html'))).text();
document.getElementById('tab').insertAdjacentHTML('afterbegin', html);
const made = document.createElement('button', { is: 'select-button' });
made.id = 'made';
document.body.append(made);
window.__ready = true;
""",
}

PLAIN = {
    "manifest.json": json.dumps({"manifest_version": 3, "name": "No Built In", "version": "1.0",
                                 "options_ui": {"page": "options.html", "open_in_tab": True}}),
    "options.html": '<html><head></head><body><p>plain</p></body></html>',
}


def probe_copy():
    """build/Search.app (or the app the harness was pointed at) under a
    bundle id of its own, signed ad hoc."""
    app = work / "Search.app"
    shutil.copytree(sv.APP, app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def value(tid, js, within=6):
    end = time.time() + within
    got = None
    while time.time() < end:
        got = json.loads(sv.ev(tid, f"JSON.stringify({js})") or "null")
        if got:
            return got
        time.sleep(0.25)
    return got


def install(folder, files, name):
    for path, body in files.items():
        (folder / path).parent.mkdir(parents=True, exist_ok=True)
        (folder / path).write_text(body)
    sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
    for _ in range(60):
        ext = next((x for x in sv.cmd({"do": "extensions"})["extensions"] if x["name"] == name and x["loaded"]), None)
        if ext:
            return ext
        time.sleep(0.25)
    return None


def main():
    t = sv.T()
    sv.APP = probe_copy()
    try:
        sv.setup()
        sv.launch()
        ext = install(work / "ext", FILES, "Built In")
        t.ok("the extension loads", ext is not None)
        if not ext:
            return t

        tid = sv.cmd({"do": "ext-page", "id": ext["id"], "path": "options/options.html"})["id"]
        t.ok("the page's script runs to the end", value(tid, "window.__ready || null") is True)
        got = value(tid, "document.querySelector('#theme > span') && document.querySelector('#theme > span').textContent")
        t.ok("a button in the page gets its class's constructor", got == "Default", got)
        got = value(tid, "document.querySelector('[is=search-box]').placeholder || null")
        t.ok("an input in the page too", got == "Search", got)
        got = value(tid, "document.querySelector('#later > span') && document.querySelector('#later > span').textContent")
        t.ok("a button in a fragment loaded later too", got == "A", got)
        got = value(tid, "document.querySelector('#made > span') && document.querySelector('#made > span').textContent")
        t.ok("one made with createElement's is too", got == "new", got)
        sv.ev(tid, "document.getElementById('theme').click(); document.getElementById('later').click(); 1")
        got = value(tid, "window.__clicked.length ? window.__clicked : null")
        t.ok("clicking them calls what their class gave them", got == ["theme", "later"], got)
        got = value(tid, "document.querySelector('plain-thing').textContent || null")
        t.ok("an ordinary custom element works beside them", got == "plain", got)

        plain = install(work / "plain", PLAIN, "No Built In")
        installed = Path(sv.SUPPORT, "Extensions")
        t.ok("the extension that uses them carries the polyfill",
             "search-builtins.js" in (installed / ext["id"] / "options/options.html").read_text())
        t.ok("one that doesn't, doesn't",
             plain is not None and "search-builtins.js" not in (installed / plain["id"] / "options.html").read_text()
             and not (installed / plain["id"] / "search-builtins.js").exists())
    finally:
        sv.finish()
        for kind in ("WebKit", "Caches", "HTTPStorages"):
            shutil.rmtree(Path.home() / "Library" / kind / BUNDLE, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    return t


if __name__ == "__main__":
    t = main()
    t.done()
    sys.exit(1 if t.failed else 0)
