import AppKit
import SwiftUI
import WebKit

// The whole window see-through, as a terminal with background-opacity and
// background-blur has it: Settings › Appearance › Window › Transparency.
// The window is clear, the Mac blurs what is behind it, and over that lies
// the window's own colour at Opacity, with the space's wash on it as on a
// solid window (TransparentGround). Glass or this, not both; not in full
// screen, where there is nothing behind the window to see.
//
// The blur is the window server's own (CGSSetWindowBackgroundBlurRadius,
// private, looked up rather than linked, as Ghostty does): a plain blur of
// what is behind, with none of a material's tint or vibrancy, so the colour
// over it is the colour you see. Without it there is no blur, the colour
// still lies over what is behind the window.
//
// The column and the bars leave their own ground out, as on the glass (see
// Browser.glassy), and the pages lose theirs. A page loses three things:
// WebKit's own background behind it (`_setDrawsBackground:`, private,
// checked for first, as PaneStage uses it), the colour of its root and
// body, and the colour of its boxes.
// Each box at least about 96 points each way (or a strip the window's whole
// width or half its height, as a rail) is weighed against the colour it
// lies on: the page's, or the box under it. A page with a bare root and
// body has its ground on a box (claude.ai's column): the one behind the
// middle of the window, covering half of it each way. In that colour or a shade of
// it (a card, a column, a footer, a box of notes), it is cleared, the
// page's ground in another tone gone with the ground; so is one covering
// half the window each way, whatever its colour. A bar across the window
// that stays put as the page scrolls (fixed or sticky, a header or a
// footer) blurs what scrolls under it, so its writing isn't read through
// the page's; a rail down the side has nothing passing under it, and is
// cleared as any other box, however long it is. A gradient that only fades one
// colour in or out, drawn to blend into the ground that is gone, goes with
// it. Anything else keeps its colour, and so does what lies on it, as do
// buttons, fields, menus, dialogs and pictures, and anything else floating
// over the page (fixed or absolute) and not a strip, which is a menu or a
// dialog more often than not; a strip floating so is the page itself laid
// out so (claude.ai's column and side bar). Only colours: a picture drawn as a background stays. Only the page,
// not the frames in it: a frame keeps what it draws. Search's own pages keep
// theirs.
//
// Text is left to the frame: a site with a dark look goes dark with it, and
// with the frame dark, a light page is darkened (Dusk.swift) whatever
// Settings › Appearance › Darken pages says, since its dark writing would
// be lost on a dark window. Dusk measures a page by its colours, so it
// reads them with this set aside (`aside`), and on a page without its
// ground the picture Dusk takes from outside is no use: it measures from
// inside instead (see Browser.duskLook).
//
// A site that looks wrong this way is kept opaque from its card (click the
// tab you're on), or in Settings under Transparency. Kept by site, the
// registrable domain, as Forget keeps sign-ins; not from a private tab,
// which remembers nothing.

@MainActor
enum Transparency {
    static let opaqueKey = "window.transparent.opaque"

    /// A terminal's usual background-opacity.
    static let defaultOpacity = 0.8
    /// Below this, writing on a page is lost in whatever is behind it.
    static let leastOpacity = 0.3
    /// The blur's radius, in points: Ghostty's for background-blur = true.
    static let blurRadius: Int32 = 20

    /// A stored opacity, in range, or nil for none.
    nonisolated static func opacity(_ stored: Double?) -> Double? {
        stored.map { min(1, max(leastOpacity, $0)) }
    }

    /// The page views drawing no background of their own now, for PaneStage
    /// not to give one back after a resize.
    private static let clear = NSHashTable<WKWebView>.weakObjects()

    /// Whether pages at `url` are see-through: Transparency on, a website,
    /// and its site not kept opaque.
    static func clears(_ url: URL?) -> Bool {
        let prefs = Shared.prefs
        guard prefs.transparent, let url, let site = Forget.site(of: url) else { return false }
        return !Forget.keeps(site, in: prefs.opaqueSites)
    }

    static func isClear(_ web: WKWebView) -> Bool { clear.contains(web) }

    /// The view's own background, off for a see-through page, back on for
    /// any other. Under the page, where a scroll past its end shows, the
    /// same: nothing, or WebKit's own again (or Dusk's, which its relay
    /// sets as the page says).
    static func ground(_ web: WKWebView, clear on: Bool) {
        guard on != clear.contains(web) else { return }
        guard web.responds(to: NSSelectorFromString("_setDrawsBackground:")) else { return }
        web.setValue(!on, forKey: "drawsBackground")
        if on {
            clear.add(web)
            web.underPageBackgroundColor = .clear
        } else {
            clear.remove(web)
            web.underPageBackgroundColor = nil
        }
    }

    /// Opaque from now on: the site's card, or the list in Settings.
    static func keepOpaque(_ site: String) {
        guard let site = SpaceRoutes.site(site), !Shared.prefs.opaqueSites.contains(site) else { return }
        Shared.prefs.opaqueSites.append(site)
    }

    /// See-through again: every entry that kept it opaque.
    static func letThrough(_ site: String) {
        guard let site = SpaceRoutes.site(site) else { return }
        Shared.prefs.opaqueSites.removeAll { SpaceRoutes.same($0, site) }
    }

    // MARK: - the window

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetBlur = @convention(c) (Int32, UInt32, Int32) -> Int32
    private static let blurCalls: (MainConnection, SetBlur)? = {
        let any = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connection = dlsym(any, "CGSMainConnectionID"),
              let set = dlsym(any, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return (unsafeBitCast(connection, to: MainConnection.self), unsafeBitCast(set, to: SetBlur.self))
    }()

    /// What is behind `window` blurred by the window server, or not.
    /// A window not yet on screen has no number: once it has.
    static func blur(_ window: NSWindow, _ on: Bool) {
        guard let (connection, set) = blurCalls else { return }
        guard window.windowNumber > 0 else {
            DispatchQueue.main.async { [weak window] in
                if let window, window.windowNumber > 0 { blur(window, on) }
            }
            return
        }
        _ = set(connection(), UInt32(window.windowNumber), on ? blurRadius : 0)
    }

    // MARK: - into the page

    /// For each new document at `url`: nothing for a page that keeps its
    /// ground.
    static func script(for url: URL?) -> String? {
        clears(url) ? page(on: true) : nil
    }

    /// For the page up now: see-through, or let go.
    static func update(for url: URL?) -> String {
        clears(url) ? page(on: true) : "window.__searchSeeThrough && window.__searchSeeThrough.update({ on: false })"
    }

    private static func page(on: Bool) -> String {
        "(\(source))({ on: \(on) });"
    }

    /// Run as a function of its settings, once per page; again, it only
    /// takes the new ones.
    ///
    /// The ground comes off by a sheet of the document's own, not an element
    /// in it, so a framework has nothing in its markup to take out again:
    /// the root and the body by name, a panel by a mark. Panels are looked
    /// for as the page draws itself, at most once a second, with the sheet
    /// set aside so they are measured in their own colours; set aside and
    /// back in one go, so no frame falls between.
    static let source = #"""
    function (config) {
      if (window.__searchSeeThrough) { window.__searchSeeThrough.update(config); return; }
      if (!config.on) return;

      var doc = document, root = doc.documentElement;
      var MARK = 'data-search-through';
      var BAR = 'data-search-through-bar';
      var FADE = 'data-search-through-fade';
      var sheet = new CSSStyleSheet();
      // Past Dusk's colours (see DuskColours: two ids nobody has) and any
      // twin of a page rule it makes important: three ids nobody has.
      var ids = ':not(#search-through):not(#search-through):not(#search-through)';
      // A bar that stays put while the page scrolls blurs what passes under
      // it, so its writing isn't read through the page's. By a layer behind
      // its contents rather than on the bar itself: a backdrop filter on the
      // bar would hold anything fixed inside it (a menu filling the window)
      // to the bar.
      sheet.replaceSync('@media screen {'
        + ':root' + ids + ', :root' + ids + ' > body { background-color: transparent !important; }'
        + '[' + MARK + ']' + ids + ', [' + BAR + ']' + ids + ' { background-color: transparent !important; }'
        + '[' + BAR + ']' + ids + '::before { content: "" !important; position: absolute !important; inset: 0 !important;'
        + ' z-index: -1 !important; pointer-events: none !important; border-radius: inherit !important;'
        + ' -webkit-backdrop-filter: blur(20px) !important; backdrop-filter: blur(20px) !important; }'
        // A fade into the page's ground, as a column's foot has, fades
        // into nothing: gone with the ground.
        + '[' + FADE + '~="self"]' + ids + ' { background-image: none !important; }'
        + '[' + FADE + '~="before"]' + ids + '::before { background-image: none !important; }'
        + '[' + FADE + '~="after"]' + ids + '::after { background-image: none !important; }'
        + '}');
      var on = false;

      var attach = function () {
        if (doc.adoptedStyleSheets.indexOf(sheet) < 0) doc.adoptedStyleSheets = doc.adoptedStyleSheets.concat([sheet]);
      };
      var detach = function () {
        var i = doc.adoptedStyleSheets.indexOf(sheet);
        if (i < 0) return;
        var sheets = doc.adoptedStyleSheets.slice();
        sheets.splice(i, 1);
        doc.adoptedStyleSheets = sheets;
      };

      // Any colour the page can name, as rgba: drawn once into a pixel and
      // read back.
      var pixel = doc.createElement('canvas');
      pixel.width = pixel.height = 1;
      var pen = pixel.getContext('2d', { willReadFrequently: true });
      var colours = {};
      var rgba = function (colour) {
        if (colours[colour]) return colours[colour];
        pen.clearRect(0, 0, 1, 1);
        pen.fillStyle = 'rgba(0, 0, 0, 0)';
        pen.fillStyle = colour;
        pen.fillRect(0, 0, 1, 1);
        var d = pen.getImageData(0, 0, 1, 1).data;
        return (colours[colour] = [d[0], d[1], d[2], d[3] / 255]);
      };
      var opaque = function (colour) { return rgba(colour)[3] >= 0.5; };
      var same = function (a, b) {
        var p = rgba(a), q = rgba(b);
        return Math.abs(p[0] - q[0]) + Math.abs(p[1] - q[1]) + Math.abs(p[2] - q[2]) <= 12;
      };
      // A shade either way: a fade's stops.
      var near = function (a, b) {
        var p = rgba(a), q = rgba(b);
        var d = [Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1]), Math.abs(p[2] - q[2])];
        return Math.max(d[0], d[1], d[2]) <= 16 && d[0] + d[1] + d[2] <= 40;
      };
      // A shade of what it lies on, a little or somewhat darker, lighter or
      // warmer: a card, a column, a footer, a box of notes.
      var close = function (a, b) {
        var p = rgba(a), q = rgba(b);
        return Math.max(Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1]), Math.abs(p[2] - q[2])) <= 48;
      };
      var inside = function (list, el) {
        for (var i = 0; i < list.length; i++) if (list[i] !== el && list[i].contains(el)) return true;
        return false;
      };
      // A bar's blur needs the layer behind its contents (::before) to
      // itself: one the page draws there keeps the bar as it is.
      var free = function (el) { return !drawn(el, '::before'); };
      // `values`, if given, what each of `found` is marked with.
      var mark = function (name, found, values) {
        var marked = doc.querySelectorAll('[' + name + ']');
        for (var i = 0; i < marked.length; i++) if (found.indexOf(marked[i]) < 0) marked[i].removeAttribute(name);
        for (var j = 0; j < found.length; j++) {
          var value = values ? values[j] : '';
          if (found[j].getAttribute(name) !== value) found[j].setAttribute(name, value);
        }
      };

      // A gradient of one colour only, fading in or out: drawn to blend
      // into an opaque ground, which a see-through page hasn't got.
      var fading = function (image) {
        if (!image || image.indexOf('gradient(') < 0 || image.indexOf('url(') >= 0) return false;
        var stops = image.match(/rgba?\([^)]*\)|transparent/g);
        if (!stops || stops.length < 2) return false;
        var seen = null, faint = false;
        for (var i = 0; i < stops.length; i++) {
          var alpha = rgba(stops[i])[3];
          if (alpha < 0.5) faint = true;
          // Too faint to tell its colour by.
          if (alpha < 0.3) continue;
          if (seen && !near(seen, stops[i])) return false;
          seen = seen || stops[i];
        }
        return faint && !!seen;
      };
      var drawn = function (el, part) {
        var content = getComputedStyle(el, part).content;
        return content && content !== 'none' && content !== 'normal';
      };
      // Which of the element and its two layers fade: 'self', 'before',
      // 'after', or nothing.
      var fades = function (el, style) {
        var which = [];
        if (fading(style.backgroundImage)) which.push('self');
        if (drawn(el, '::before') && fading(getComputedStyle(el, '::before').backgroundImage)) which.push('before');
        if (drawn(el, '::after') && fading(getComputedStyle(el, '::after').backgroundImage)) which.push('after');
        return which.join(' ');
      };

      // What keeps its colour, and everything in it.
      var kept = 'button, input, select, textarea, dialog, img, video, canvas, iframe, embed, object, picture, svg, '
        + '[role="button"], [role="dialog"], [role="alertdialog"], [role="menu"], [role="listbox"], '
        + '[role="tooltip"], [popover], [contenteditable="true"]';
      var skip = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEMPLATE: 1, HEAD: 1, LINK: 1, META: 1 };

      var scan = function () {
        if (!on || !doc.body) return;
        var was = sheet.disabled;
        sheet.disabled = true;
        var w = innerWidth, h = innerHeight;
        var top = getComputedStyle(root).backgroundColor;
        var body = getComputedStyle(doc.body).backgroundColor;
        var ground = opaque(top) ? top : (opaque(body) ? body : null);
        // A bare root and body: the ground is on a box, the first under the
        // middle of the window covering half of it each way and wearing a
        // colour, and what lies beside it (a side bar) is weighed on it too.
        for (var e = ground ? null : doc.elementFromPoint(w / 2, h / 2); e && e !== doc.body; e = e.parentElement) {
          var b = e.getBoundingClientRect(), c = getComputedStyle(e).backgroundColor;
          if (b.width >= w / 2 && b.height >= h / 2 && opaque(c)) { ground = c; break; }
        }
        var found = [], bars = [], faded = [], fadedHow = [];
        // Bars across the window that stay put as the page scrolls, whether
        // or not they wear a colour: the one a panel of the page's colour is
        // in blurs what passes under it, and the panel goes plain.
        var lifted = [], blocked = [];
        // What keeps a colour of its own: what is in it is on that colour,
        // not on the page's, and keeps its own too.
        var held = [];
        // Each box cleared, in the page's order, and the colour it wore.
        var taken = [], under = new Map();
        var walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_ELEMENT, {
          acceptNode: function (el) {
            if (skip[el.tagName]) return NodeFilter.FILTER_REJECT;
            var r = el.getBoundingClientRect();
            // No box of its own (display: contents, or a wrapper that only
            // holds what floats): what is in it may still be a panel.
            if (r.width * r.height === 0) return NodeFilter.FILTER_SKIP;
            // A strip: the window's whole width, as a header or a footer,
            // or half its height, as a rail or a column down the side.
            var strip = r.width >= w * 0.9 || r.height >= h / 2;
            // Too small to be a panel, and so is all that it holds.
            if (!strip && (r.width < 96 || r.height < 96)) return NodeFilter.FILTER_REJECT;
            if (el.matches(kept)) return NodeFilter.FILTER_REJECT;
            var style = getComputedStyle(el);
            // Floating over the page, a menu or a dialog more often than
            // not; but not a strip, which is the page itself laid out so
            // (claude.ai's column and side bar).
            var big = r.width >= w / 2 && r.height >= h / 2;
            if ((style.position === 'absolute' || style.position === 'fixed') && !strip) return NodeFilter.FILTER_REJECT;
            var how = fades(el, style);
            if (how) { faded.push(el); fadedHow.push(how); }
            var colour = style.backgroundColor;
            // The colour it lies on: the box cleared under it, or the
            // page's.
            var base = ground;
            for (var k = taken.length - 1; k >= 0; k--) {
              if (taken[k].contains(el)) { base = under.get(taken[k]); break; }
            }
            // Only across the window: a rail down the side (a sticky
            // contents list) has nothing scrolling under it, and blurred it
            // would look other than a shorter one beside it, which isn't a
            // strip at all.
            var stays = r.width >= w * 0.9 && (style.position === 'fixed' || style.position === 'sticky');
            // Its blur needs the layer behind its contents (::before) to
            // itself: one the page draws there keeps it, and what is in it,
            // as they are.
            if (stays && !inside(lifted, el)) {
              lifted.push(el);
              if (!free(el)) blocked.push(el);
            }
            if (!opaque(colour)) return NodeFilter.FILTER_SKIP;
            // Cleared: half the window each way, whatever its colour, or
            // the colour it lies on or a shade of it, wholly that (a dimmed
            // veil over the page, behind a dialog, is not), at any size
            // worth a look: the page's own ground in another tone, as a
            // card or a column or a footer, gone with the ground. Not on a
            // colour that stays.
            var onGround = base && !inside(held, el);
            var clear = big
              || onGround && (same(colour, base) || rgba(colour)[3] >= 0.9 && close(colour, base));
            if (!clear) { held.push(el); return NodeFilter.FILTER_SKIP; }
            for (var i = 0; i < lifted.length; i++) {
              var bar = lifted[i];
              if (bar !== el && !bar.contains(el)) continue;
              if (blocked.indexOf(bar) >= 0) return NodeFilter.FILTER_REJECT;
              if (bars.indexOf(bar) < 0) bars.push(bar);
            }
            found.push(el);
            taken.push(el);
            under.set(el, colour);
            return NodeFilter.FILTER_SKIP;
          }
        });
        while (walker.nextNode()) {}
        sheet.disabled = was;
        mark(MARK, found);
        mark(BAR, bars);
        mark(FADE, faded, fadedHow);
      };

      // While the page loads, and for a few seconds after, in the frame
      // after it changes, before that frame is drawn, and at most ten times
      // a second: a panel the page draws as it builds itself (a header, a
      // column of results) is never seen in its colour. After, at most once
      // a second, and a moment after it last changed, so what settles is
      // looked at too. A page in the background gets no frames: a timer
      // stands in.
      var timer = 0, frame = 0, last = -Infinity, settled = false;
      var run = function () {
        clearTimeout(timer);
        cancelAnimationFrame(frame);
        timer = frame = 0;
        last = performance.now();
        scan();
      };
      var soon = function () {
        if (!on || timer || frame) return;
        if (settled) {
          timer = setTimeout(run, Math.max(150, 1000 - (performance.now() - last)));
          return;
        }
        var wait = 100 - (performance.now() - last);
        if (wait > 0) { timer = setTimeout(run, wait); return; }
        frame = requestAnimationFrame(run);
        timer = setTimeout(run, 100);
      };
      var growing = new MutationObserver(soon);

      var apply = function () {
        if (config.on === on) return;
        on = config.on;
        if (on) {
          attach();
          growing.observe(root, { childList: true, subtree: true });
          soon();
        } else {
          growing.disconnect();
          clearTimeout(timer);
          cancelAnimationFrame(frame);
          timer = frame = 0;
          detach();
          mark(MARK, []);
          mark(BAR, []);
          mark(FADE, []);
        }
      };

      addEventListener('resize', soon);
      addEventListener('load', function () {
        soon();
        setTimeout(function () { settled = true; }, 3000);
      });
      // A page whose load never comes (a stream, a request left hanging).
      setTimeout(function () { settled = true; }, 15000);
      doc.addEventListener('DOMContentLoaded', soon);

      window.__searchSeeThrough = {
        update: function (next) { config = next; apply(); },
        // What the page wears in its own colours, for Dusk to measure.
        aside: function (read) {
          var was = sheet.disabled;
          sheet.disabled = true;
          try { return read(); } finally { sheet.disabled = was; }
        },
        state: function () {
          return { on: on, panels: doc.querySelectorAll('[' + MARK + ']').length,
                   bars: doc.querySelectorAll('[' + BAR + ']').length };
        }
      };
      apply();
    }
    """#
}

extension Browser {
    /// Whether this window is see-through right now: what sits on the
    /// window's ground (the card, Search's own pages, a blank tab) leaves
    /// out a ground of its own.
    var seeThrough: Bool { glassy && prefs.transparent }

    /// Pages see-through, or not, as the settings now stand: every tab's
    /// next page, and the page each is showing now.
    func reseeThrough() {
        for tab in tabs + parkedTabs {
            tab.arm(hiding: curtain.css(on: curtain.host(of: tab.address)))
            guard let web = tab.built else { continue }
            let on = Transparency.clears(tab.pageAddress)
            Transparency.ground(web, clear: on)
            web.evaluateInSearch(Transparency.update(for: tab.pageAddress))
        }
    }
}

/// The ground of a see-through window: its own colour at Opacity, and the
/// space's wash on it as on a solid window, so writing on a page reads as
/// it does on its own ground. Over nothing: the blur is the window server's
/// (Transparency.blur).
struct TransparentGround: View {
    @ObservedObject var prefs: Preferences
    let look: SpaceLook?

    var body: some View {
        ZStack {
            Palette.ground.opacity(prefs.opacity)
            SpaceWash(look: look)
        }
        .allowsHitTesting(false)
    }
}

/// Settings › Appearance › Window, under Transparency: each site kept opaque,
/// and a line to add one.
struct OpaqueSiteList: View {
    @ObservedObject var prefs: Preferences
    @State private var typed = ""

    var body: some View {
        ForEach(prefs.opaqueSites, id: \.self) { site in
            Rule()
            Line(site, "Keeps its own background") {
                Pill("Remove") { prefs.opaqueSites.removeAll { $0 == site } }
            }
        }
        Rule()
        HStack(spacing: 10) {
            TextField("github.com", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onSubmit(add)
            Pill("Keep Opaque", action: add)
                .disabled(SpaceRoutes.site(typed) == nil)
                .opacity(SpaceRoutes.site(typed) == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func add() {
        guard let site = SpaceRoutes.site(typed) else { return }
        if !prefs.opaqueSites.contains(site) { prefs.opaqueSites.append(site) }
        typed = ""
    }
}
