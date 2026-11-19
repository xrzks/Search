import WebKit

// A common screen size, for a page that asks.
//
// A page reading `screen.width` and `height` in a WKWebView is told the
// display's size as macOS scales it: 1710×1112 is a 15-inch MacBook Air at
// its default, and a Mac's model and its scaling are few enough to tell
// apart. Safari's Advanced Fingerprinting Protection, which a WKWebView
// doesn't get, answers with the window instead, and that is worse: Cover
// Your Tracks put a Safari window's 1407×1048 at 1 in 183,324 browsers, 17.5
// of its 18.5 identifying bits.
//
// So the screen a page reads is the smallest of a few of the most common
// ones that still holds the window: 1440×900 or 1920×1080, mostly. Never
// smaller than the window, as no real screen is. What it leaves: the
// window's own size (`innerWidth`, `outerWidth`), which a page lays itself
// out by and only letterboxing would hide; CSS's `device-width`; and a frame
// a page makes without loading anything into it, which has a `Screen` of its
// own that no user script reaches.
//
// On unless turned off in Settings › Privacy. A private tab always has it.
// A switch moved reaches a page from its next load.

enum CommonScreen {
    @MainActor static var on = true

    /// In the page's own world, every frame, before any of the page's
    /// scripts. The screen is picked again at each read, so a window
    /// resized reads true from then on.
    static let script = """
    (function () {
      var proto = window.Screen && Screen.prototype;
      if (!proto) return;
      var sizes = [[1440, 900], [1920, 1080], [2560, 1440], [3840, 2160]];
      function pick() {
        var w = Math.max(outerWidth, innerWidth), h = Math.max(outerHeight, innerHeight);
        for (var i = 0; i < sizes.length; i++) {
          if (w <= sizes[i][0] && h <= sizes[i][1]) return sizes[i];
        }
        return sizes[sizes.length - 1];
      }
      var common = {
        get width() { return pick()[0]; },
        get height() { return pick()[1]; },
        get availWidth() { return pick()[0]; },
        get availHeight() { return pick()[1]; },
        get availLeft() { return 0; },
        get availTop() { return 0; }
      };
      Object.keys(common).forEach(function (name) {
        var plain = Object.getOwnPropertyDescriptor(proto, name);
        if (!plain || !plain.get) return;
        Object.defineProperty(proto, name, {
          get: Object.getOwnPropertyDescriptor(common, name).get,
          set: plain.set, enumerable: plain.enumerable, configurable: true
        });
      });
    })();
    """
}
