const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../server_advanced/assets/open.js'), 'utf8');

function page(visibility = 'visible', navigator = { userAgent: '', platform: '', maxTouchPoints: 0 }) {
  let now = 0, nextId = 0;
  const timers = new Map();
  const events = {};
  const link = { href: 'reschool://diary?date=2026-09-14&subject=Math', textContent: 'Открыть приложение', addEventListener: (name, fn) => events[name] = fn };
  const download = { href: 'https://github.com/reSchool-org/reSchool-flutter/releases/latest' };
  const fallback = { hidden: true };
  const status = { textContent: 'Открывается автоматически…' };
  const document = { visibilityState: visibility, getElementById: id => ({ 'open-app': link, 'open-fallback': fallback, 'open-status': status, 'download-app': download })[id], addEventListener: (name, fn) => events[name] = fn };
  const window = { location: { href: '' }, addEventListener: (name, fn) => events[name] = fn };
  vm.runInNewContext(script, { document, window, navigator, setTimeout: (fn, delay) => { const id = ++nextId; timers.set(id, { fn, at: now + delay }); return id; }, clearTimeout: id => timers.delete(id) });
  function advance(ms) {
    const end = now + ms;
    while (true) {
      const next = [...timers].filter(([, t]) => t.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) break;
      now = next[1].at; timers.delete(next[0]); next[1].fn();
    }
    now = end;
  }
  return { link, download, fallback, status, window, advance, click: () => events.click(), hide: () => { document.visibilityState = 'hidden'; events.visibilitychange(); }, show: () => { document.visibilityState = 'visible'; events.visibilitychange(); }, pagehide: () => events.pagehide() };
}

test('a blocked launch shows alternatives only after the grace period', () => {
  const p = page(); p.advance(800);
  assert.equal(p.window.location.href, p.link.href);
  p.advance(2499); assert.equal(p.fallback.hidden, true);
  p.advance(1); assert.equal(p.fallback.hidden, false);
  assert.equal(p.link.textContent, 'Попробовать снова');
});
test('leaving for the app cancels fallback, including after returning', () => {
  const p = page(); p.advance(800); p.hide(); p.advance(5000); p.show(); p.advance(5000);
  assert.equal(p.fallback.hidden, true);
});
test('hiding before automatic launch cancels navigation', () => {
  const p = page(); p.hide(); p.advance(5000);
  assert.equal(p.window.location.href, '');
  assert.equal(p.fallback.hidden, true);
});
test('pagehide cancels outstanding launch and fallback timers', () => {
  for (const elapsed of [0, 800]) {
    const p = page(); p.advance(elapsed); p.pagehide(); p.advance(5000);
    assert.equal(p.fallback.hidden, true);
    if (!elapsed) assert.equal(p.window.location.href, '');
  }
});
test('manual launch before the timer prevents a second automatic launch', () => {
  const p = page(); p.click(); p.advance(800);
  assert.equal(p.window.location.href, '');
  p.advance(1700); assert.equal(p.fallback.hidden, false);
});
test('retry resets the grace period and cancels the previous timer', () => {
  const p = page(); p.advance(3300); p.click(); assert.equal(p.fallback.hidden, true);
  p.advance(2000); p.click(); p.advance(500); assert.equal(p.fallback.hidden, true);
  p.advance(2000); assert.equal(p.fallback.hidden, false);
});
test('a background page never launches automatically', () => {
  const p = page('hidden'); p.advance(5000); p.show(); p.advance(5000);
  assert.equal(p.window.location.href, '');
  assert.equal(p.fallback.hidden, true);
});

test('iPhone and desktop-mode iPad receive the TestFlight download', () => {
  for (const navigator of [{ userAgent: 'iPhone', platform: 'iPhone', maxTouchPoints: 5 }, { userAgent: 'Macintosh', platform: 'MacIntel', maxTouchPoints: 5 }]) {
    assert.equal(page('visible', navigator).download.href, 'https://testflight.apple.com/join/JqADzPK9');
  }
  assert.equal(page().download.href, 'https://github.com/reSchool-org/reSchool-flutter/releases/latest');
});
