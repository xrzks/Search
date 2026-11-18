import Foundation

// Customized built-in elements, which WebKit doesn't have: an element that
// is a <button> or an <input> made into one of the page's own, written
// `<button is="select-button">` and defined with
// `customElements.define("select-button", SelectButton, { extends: "button" })`.
// Chrome has them; Safari never took them up. In WebKit the definition
// fails, and the element stays a plain button with nothing in it: YT
// Tweaks' options page, the same Web Store package as in Chrome, showed its
// theme menus as empty rows that did nothing when clicked, and its search
// field as a bare white box.
//
// So an extension that uses them gets @ungap/custom-elements 1.3.0
// (Andrea Giammarchi, ISC, notice below), put beside the shim as
// `search-builtins.js` and named in each of its pages right after it,
// before the page's own scripts define anything. It does nothing where
// they work, and in WebKit carries them out itself: it watches the page for
// `[is=…]` elements and gives each its class. Only an extension that uses
// them carries it, as it puts its own class in place of every HTML…Element
// a page's scripts see.

@available(macOS 15.4, *)
enum ExtensionBuiltIns {
    nonisolated static let file = "search-builtins.js"
    nonisolated static let tag = "<script src=\"/\(file)\"></script>"

    /// An element written with `is="name-with-a-dash"`, as a page or a
    /// fragment it loads names one.
    nonisolated private static let attribute = try! NSRegularExpression(pattern: #"<[a-zA-Z][^>]*\sis\s*=\s*["']?[a-z][\w.]*-"#)
    /// A definition's `extends` option: `{ extends: "button" }`, as written
    /// or minified.
    nonisolated private static let option = try! NSRegularExpression(pattern: #"["']?\bextends["']?\s*:\s*["'][a-z]"#)

    /// Whether a file of the package uses customized built-ins: an HTML file
    /// with an element marked `is`, or a script that defines one.
    nonisolated static func used(in text: String, html: Bool) -> Bool {
        let whole = NSRange(text.startIndex..., in: text)
        if html { return attribute.firstMatch(in: text, range: whole) != nil }
        return text.contains("customElements") && option.firstMatch(in: text, range: whole) != nil
    }

    /// A page with the shim tag gets this one right after it; one without,
    /// at the top of its head, as the shim's is put.
    nonisolated static func named(in html: String) -> String? {
        guard !html.contains(file) else { return nil }
        var html = html
        let shim = "<script src=\"/\(ExtensionShims.file)\"></script>"
        if let after = html.range(of: shim) {
            html.insert(contentsOf: tag, at: after.upperBound)
        } else if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            html.insert(contentsOf: tag, at: head.upperBound)
        } else {
            html = tag + html
        }
        return html
    }

    /// Run once in a page, however many times it is named: a second run
    /// would wrap the first one's classes in its own.
    nonisolated static let script = "if (typeof document !== \"undefined\" && !self.__searchBuiltIns) {\nself.__searchBuiltIns = true;\n" + polyfill + "\n}\n"

    // ISC License
    //
    // Copyright (c) 2020, Andrea Giammarchi, @WebReflection
    //
    // Permission to use, copy, modify, and/or distribute this software for any
    // purpose with or without fee is hereby granted, provided that the above
    // copyright notice and this permission notice appear in all copies.
    //
    // THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
    // REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
    // AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
    // INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
    // LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
    // OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
    // PERFORMANCE OF THIS SOFTWARE.
    //
    // @ungap/custom-elements 1.3.0, min.js as published on npm
    // (sha256 cc14433db77c53e92706d93a0c8e3df870d9826c6c334044c9fe976c2726cb22).
    nonisolated private static let polyfill = #"""
/*! (c) Andrea Giammarchi @webreflection ISC */
!function(){"use strict";var e=function(e,t){var n=function(e){for(var t=0,n=e.length;t<n;t++)r(e[t])},r=function(e){var t=e.target,n=e.attributeName,r=e.oldValue;t.attributeChangedCallback(n,r,t.getAttribute(n))};return function(o,a){var l=o.constructor.observedAttributes;return l&&e(a).then((function(){new t(n).observe(o,{attributes:!0,attributeOldValue:!0,attributeFilter:l});for(var e=0,a=l.length;e<a;e++)o.hasAttribute(l[e])&&r({target:o,attributeName:l[e],oldValue:null})})),o}};function t(e,t){(null==t||t>e.length)&&(t=e.length);for(var n=0,r=new Array(t);n<t;n++)r[n]=e[n];return r}function n(e,n){var r="undefined"!=typeof Symbol&&e[Symbol.iterator]||e["@@iterator"];if(!r){if(Array.isArray(e)||(r=function(e,n){if(e){if("string"==typeof e)return t(e,n);var r=Object.prototype.toString.call(e).slice(8,-1);return"Object"===r&&e.constructor&&(r=e.constructor.name),"Map"===r||"Set"===r?Array.from(e):"Arguments"===r||/^(?:Ui|I)nt(?:8|16|32)(?:Clamped)?Array$/.test(r)?t(e,n):void 0}}(e))||n&&e&&"number"==typeof e.length){r&&(e=r);var o=0,a=function(){};return{s:a,n:function(){return o>=e.length?{done:!0}:{done:!1,value:e[o++]}},e:function(e){throw e},f:a}}throw new TypeError("Invalid attempt to iterate non-iterable instance.\nIn order to be iterable, non-array objects must have a [Symbol.iterator]() method.")}var l,i=!0,c=!1;return{s:function(){r=r.call(e)},n:function(){var e=r.next();return i=e.done,e},e:function(e){c=!0,l=e},f:function(){try{i||null==r.return||r.return()}finally{if(c)throw l}}}}
/*! (c) Andrea Giammarchi - ISC */var r=!0,o=!1,a="querySelectorAll",l="querySelectorAll",i=self,c=i.document,u=i.Element,s=i.MutationObserver,f=i.Set,d=i.WeakMap,h=function(e){return l in e},v=[].filter,p=function(e){var t=new d,i=function(n,r){var o;if(r)for(var a,l=function(e){return e.matches||e.webkitMatchesSelector||e.msMatchesSelector}(n),i=0,c=y.length;i<c;i++)l.call(n,a=y[i])&&(t.has(n)||t.set(n,new f),(o=t.get(n)).has(a)||(o.add(a),e.handle(n,r,a)));else t.has(n)&&(o=t.get(n),t.delete(n),o.forEach((function(t){e.handle(n,r,t)})))},p=function(e){for(var t=!(arguments.length>1&&void 0!==arguments[1])||arguments[1],n=0,r=e.length;n<r;n++)i(e[n],t)},y=e.query,g=e.root||c,m=function(e){var t=arguments.length>1&&void 0!==arguments[1]?arguments[1]:document,l=arguments.length>2&&void 0!==arguments[2]?arguments[2]:MutationObserver,i=arguments.length>3&&void 0!==arguments[3]?arguments[3]:["*"],c=function t(o,l,i,c,u,s){var f,d=n(o);try{for(d.s();!(f=d.n()).done;){var h=f.value;(s||a in h)&&(u?i.has(h)||(i.add(h),c.delete(h),e(h,u)):c.has(h)||(c.add(h),i.delete(h),e(h,u)),s||t(h[a](l),l,i,c,u,r))}}catch(e){d.e(e)}finally{d.f()}},u=new l((function(e){if(i.length){var t,a=i.join(","),l=new Set,u=new Set,s=n(e);try{for(s.s();!(t=s.n()).done;){var f=t.value,d=f.addedNodes,h=f.removedNodes;c(h,a,l,u,o,o),c(d,a,l,u,r,o)}}catch(e){s.e(e)}finally{s.f()}}})),s=u.observe;return(u.observe=function(e){return s.call(u,e,{subtree:r,childList:r})})(t),u}(i,g,s,y),w=u.prototype.attachShadow;return w&&(u.prototype.attachShadow=function(e){var t=w.call(this,e);return m.observe(t),t}),y.length&&p(g[l](y)),{drop:function(e){for(var n=0,r=e.length;n<r;n++)t.delete(e[n])},flush:function(){for(var e=m.takeRecords(),t=0,n=e.length;t<n;t++)p(v.call(e[t].removedNodes,h),!1),p(v.call(e[t].addedNodes,h),!0)},observer:m,parse:p}},y=self,g=y.document,m=y.Map,w=y.MutationObserver,b=y.Object,E=y.Set,S=y.WeakMap,A=y.Element,M=y.HTMLElement,O=y.Node,N=y.Error,C=y.TypeError,T=y.Reflect,q=b.defineProperty,D=b.keys,I=b.getOwnPropertyNames,P=b.setPrototypeOf,k=!self.customElements,L=function(e){for(var t=D(e),n=[],r=new E,o=t.length,a=0;a<o;a++){n[a]=e[t[a]];try{delete e[t[a]]}catch(e){r.add(a)}}return function(){for(var a=0;a<o;a++)r.has(a)||(e[t[a]]=n[a])}};if(k){var x=function(){var e=this.constructor;if(!$.has(e))throw new C("Illegal constructor");var t=$.get(e);if(W)return F(W,t);var n=H.call(g,t);return F(P(n,e.prototype),t)},H=g.createElement,$=new m,_=new m,j=new m,R=new m,V=[],U=p({query:V,handle:function(e,t,n){var r=j.get(n);if(t&&!r.isPrototypeOf(e)){var o=L(e);W=P(e,r);try{new r.constructor}finally{W=null,o()}}var a="".concat(t?"":"dis","connectedCallback");a in r&&e[a]()}}).parse,W=null,B=function(e){if(!_.has(e)){var t,n=new Promise((function(e){t=e}));_.set(e,{$:n,_:t})}return _.get(e).$},F=e(B,w);self.customElements={define:function(e,t){if(R.has(e))throw new N('the name "'.concat(e,'" has already been used with this registry'));$.set(t,e),j.set(e,t.prototype),R.set(e,t),V.push(e),B(e).then((function(){U(g.querySelectorAll(e))})),_.get(e)._(t)},get:function(e){return R.get(e)},whenDefined:B},q(x.prototype=M.prototype,"constructor",{value:x}),self.HTMLElement=x,g.createElement=function(e,t){var n=t&&t.is,r=n?R.get(n):R.get(e);return r?new r:H.call(g,e)},"isConnected"in O.prototype||q(O.prototype,"isConnected",{configurable:!0,get:function(){return!(this.ownerDocument.compareDocumentPosition(this)&this.DOCUMENT_POSITION_DISCONNECTED)}})}else if(k=!self.customElements.get("extends-br"))try{var z=function e(){return self.Reflect.construct(HTMLBRElement,[],e)};z.prototype=HTMLLIElement.prototype;var G="extends-br";self.customElements.define("extends-br",z,{extends:"br"}),k=g.createElement("br",{is:G}).outerHTML.indexOf(G)<0;var J=self.customElements,K=J.get,Q=J.whenDefined;self.customElements.whenDefined=function(e){var t=this;return Q.call(this,e).then((function(n){return n||K.call(t,e)}))}}catch(e){}if(k){var X=function(e){var t=ae.get(e);ve(t.querySelectorAll(this),e.isConnected)},Y=self.customElements,Z=g.createElement,ee=Y.define,te=Y.get,ne=Y.upgrade,re=T||{construct:function(e){return e.call(this)}},oe=re.construct,ae=new S,le=new E,ie=new m,ce=new m,ue=new m,se=new m,fe=[],de=[],he=function(e){return se.get(e)||te.call(Y,e)},ve=p({query:de,handle:function(e,t,n){var r=ue.get(n);if(t&&!r.isPrototypeOf(e)){var o=L(e);we=P(e,r);try{new r.constructor}finally{we=null,o()}}var a="".concat(t?"":"dis","connectedCallback");a in r&&e[a]()}}).parse,pe=p({query:fe,handle:function(e,t){ae.has(e)&&(t?le.add(e):le.delete(e),de.length&&X.call(de,e))}}).parse,ye=A.prototype.attachShadow;ye&&(A.prototype.attachShadow=function(e){var t=ye.call(this,e);return ae.set(this,t),t});var ge=function(e){if(!ce.has(e)){var t,n=new Promise((function(e){t=e}));ce.set(e,{$:n,_:t})}return ce.get(e).$},me=e(ge,w),we=null;I(self).filter((function(e){return/^HTML.*Element$/.test(e)})).forEach((function(e){var t=self[e];function n(){var e=this.constructor;if(!ie.has(e))throw new C("Illegal constructor");var n=ie.get(e),r=n.is,o=n.tag;if(r){if(we)return me(we,r);var a=Z.call(g,o);return a.setAttribute("is",r),me(P(a,e.prototype),r)}return oe.call(this,t,[],e)}q(n.prototype=t.prototype,"constructor",{value:n}),q(self,e,{value:n})})),g.createElement=function(e,t){var n=t&&t.is;if(n){var r=se.get(n);if(r&&ie.get(r).tag===e)return new r}var o=Z.call(g,e);return n&&o.setAttribute("is",n),o},Y.get=he,Y.whenDefined=ge,Y.upgrade=function(e){var t=e.getAttribute("is");if(t){var n=se.get(t);if(n)return void me(P(e,n.prototype),t)}ne.call(Y,e)},Y.define=function(e,t,n){if(he(e))throw new N("'".concat(e,"' has already been defined as a custom element"));var r,o=n&&n.extends;ie.set(t,o?{is:e,tag:o}:{is:"",tag:e}),o?(r="".concat(o,'[is="').concat(e,'"]'),ue.set(r,t.prototype),se.set(e,t),de.push(r)):(ee.apply(Y,arguments),fe.push(r=e)),ge(e).then((function(){o?(ve(g.querySelectorAll(r)),le.forEach(X,[r])):pe(g.querySelectorAll(r))})),ce.get(e)._(t)}}}();
"""#
}

