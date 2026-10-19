// webview/compat.js on a WebView without the newer built-ins: run it in a
// fresh JS realm where they've been removed. Run: npm test
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';

const source = readFileSync(new URL('../webview/compat.js', import.meta.url), 'utf8');

function oldWebView({ syntaxOk = true } = {}) {
  const posted = [];
  const context = vm.createContext({
    navigator: { userAgent: 'Chrome/80' },
    TiptapBridge: { postMessage: (m) => posted.push(m) },
  });
  context.window = context;
  vm.runInContext(
    `delete Array.prototype.at; delete String.prototype.at; delete Array.prototype.findLast;
     delete Array.prototype.findLastIndex; delete Object.hasOwn; delete String.prototype.replaceAll;`,
    context,
  );
  if (!syntaxOk) context.Function = function () { throw new SyntaxError('Unexpected token ?'); };
  vm.runInContext(source, context);
  return { run: (code) => vm.runInContext(code, context), posted };
}

test('compat adds the missing built-ins, behaving like the real ones', () => {
  const { run, posted } = oldWebView();
  assert.equal(run('typeof Array.prototype.findLast'), 'function');
  assert.equal(run('[1, 2, 3, 4].findLast((n) => n % 2 === 1)'), 3);
  assert.equal(run('[1, 2, 3].findLast((n) => n > 5)'), undefined);
  assert.equal(run('[1, 2, 3, 4].findLastIndex((n) => n < 3)'), 1);
  assert.equal(run('[1, 2, 3].at(-1)'), 3);
  assert.equal(run('"abc".at(0)'), 'a');
  assert.equal(run('[1].at(5)'), undefined);
  assert.equal(run('Object.hasOwn({ a: 1 }, "a")'), true);
  assert.equal(run('Object.hasOwn(Object.create({ a: 1 }), "a")'), false);
  assert.equal(run('"Unsupported ({type}) ({type})".replaceAll("{type}", "x")'), 'Unsupported (x) (x)');
  assert.equal(run('"a.b.c".replaceAll(".", "$&$&")'), 'a..b..c');
  assert.equal(run('"aXbX".replaceAll(/X/g, (m) => m.toLowerCase())'), 'axbx');
  assert.deepEqual(posted, [], 'a WebView with ES2020 syntax runs the editor');
});

test('compat never replaces built-ins that exist', () => {
  const native = Array.prototype.findLast;
  const context = vm.createContext({ navigator: {}, Array });
  context.window = context;
  vm.runInContext(source, context);
  assert.equal(Array.prototype.findLast, native);
});

test('a WebView too old for the syntax tells the app', () => {
  const { posted, run } = oldWebView({ syntaxOk: false });
  assert.equal(posted.length, 1);
  assert.match(JSON.parse(posted[0]).message, /^unsupported-webview: Chrome\/80/);
  assert.equal(run('window.aminotesUnsupported'), true);
});
