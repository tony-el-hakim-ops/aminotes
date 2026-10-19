// Runs before editor.js, written in plain ES5 so that any WebView runs it.
//
// 1. Adds the few built-ins the bundle uses that are newer than its syntax
//    (Tiptap calls Array.prototype.findLast on every edit): with them, any
//    WebView from Chrome 80 runs the editor, e.g. an Android 7 phone whose
//    WebView hasn't been updated in a while.
// 2. A WebView too old even for the syntax can't load editor.js at all: tell
//    the app, instead of leaving a blank editor.
(function () {
  function define(target, name, value) {
    if (!target[name]) Object.defineProperty(target, name, { value: value, writable: true, configurable: true });
  }
  function at(index) {
    var n = Math.trunc(index) || 0;
    if (n < 0) n += this.length;
    return n < 0 || n >= this.length ? undefined : this[n];
  }
  define(Array.prototype, 'at', at);
  define(String.prototype, 'at', at);
  define(Array.prototype, 'findLast', function (test, thisArg) {
    for (var i = this.length - 1; i >= 0; i--) if (test.call(thisArg, this[i], i, this)) return this[i];
    return undefined;
  });
  define(Array.prototype, 'findLastIndex', function (test, thisArg) {
    for (var i = this.length - 1; i >= 0; i--) if (test.call(thisArg, this[i], i, this)) return i;
    return -1;
  });
  define(Object, 'hasOwn', function (object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
  });
  define(String.prototype, 'replaceAll', function (search, replacement) {
    var pattern = search instanceof RegExp ? search : new RegExp(String(search).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
    return this.replace(pattern, replacement);
  });

  var supported = true;
  try {
    // The newest syntax in the bundle (target es2020).
    new Function('var a = {}; return a?.b ?? 1n');
  } catch (error) {
    supported = false;
  }
  if (supported) return;
  window.aminotesUnsupported = true;
  var message = JSON.stringify({ type: 'error', message: 'unsupported-webview: ' + navigator.userAgent });
  if (window.TiptapBridge) window.TiptapBridge.postMessage(message);
  else if (window.parent !== window) window.parent.postMessage('tiptap-bridge:' + message, window.location.origin);
})();
