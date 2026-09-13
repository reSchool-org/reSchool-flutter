const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');

function setup(initial = { 'note.md': 'original' }) {
  const files = new Map();
  const writes = [], modals = [], notices = [], opened = [];
  class TFile { constructor(path) { this.path = path; } }
  class Element {
    constructor(tag, text) { this.tag = tag; this.text = text; this.children = []; this.style = {}; }
    createEl(tag, options = {}) {
      const child = new Element(tag, options.text);
      this.children.push(child);
      return child;
    }
    addEventListener(event, callback) { this[event] = callback; }
    focus() { this.focused = true; }
    empty() { this.children = []; }
  }
  class Modal {
    constructor(app) { this.app = app; this.contentEl = new Element('div'); }
    open() { modals.push(this); this.onOpen(); }
    close() { if (!this.closed) { this.closed = true; this.onClose(); } }
  }
  class Plugin {
    registerObsidianProtocolHandler(name, handler) { assert.equal(name, 'kmi'); this.handler = handler; }
  }
  const put = (path, text) => { const file = new TFile(path); files.set(path, { file, text }); return file; };
  for (const [path, text] of Object.entries(initial)) put(path, text);
  const vault = {
    getName: () => 'Personal vault',
    getAbstractFileByPath: path => files.get(path)?.file ?? null,
    createFolder: async path => { files.set(path, { file: { path } }); },
    read: async file => files.get(file.path).text,
    modify: async (file, text) => { writes.push(['modify', file.path, text]); files.get(file.path).text = text; },
    create: async (path, text) => {
      if (files.has(path)) throw Error('File already exists');
      writes.push(['create', path, text]); return put(path, text);
    },
  };
  const state = { response: 'incoming', status: 200 };
  const obsidian = {
    Plugin, Modal, TFile,
    Notice: class { constructor(message) { notices.push(message); } },
    normalizePath: path => path.replace(/\\/g, '/').replace(/\/+/g, '/').replace(/^\/+|\/+$/g, ''),
    requestUrl: async () => state.fetch ? state.fetch() : { status: state.status, text: state.response },
  };
  const sandbox = {
    module: { exports: {} }, require: name => { assert.equal(name, 'obsidian'); return obsidian; },
    crypto: webcrypto, TextEncoder, TextDecoder, atob, Uint8Array, URL,
  };
  vm.runInNewContext(readFileSync(process.env.KMI_TEST_BUNDLE || resolve(__dirname, '../main.js'), 'utf8'), sandbox);
  const plugin = new sandbox.module.exports.default();
  plugin.app = { vault, workspace: { getLeaf: () => ({ openFile: async file => opened.push(file.path) }) } };
  plugin.onload();
  return { plugin, vault, files, writes, modals, notices, opened, put, state,
    invoke: (params = {}) => plugin.handler({ file: 'note', url: 'https://source.example/text', ...params }) };
}
const tick = () => new Promise(resolve => setImmediate(resolve));
async function dialog(h, count = 1) {
  for (let i = 0; i < 200 && h.modals.length < count; i++) await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(h.modals.length, count, 'a review dialog is required');
  return h.modals[count - 1];
}
function click(modal, text) {
  const button = modal.contentEl.children.find(el => el.tag === 'button' && el.text === text);
  assert.ok(button, text); button.click();
}

test('external link cannot replace or append without approval', async () => {
  for (const append of [undefined, 'false', 'TRUE', 'true']) {
    const h = setup();
    const run = h.invoke({ append });
    await tick();
    assert.deepEqual(h.writes, [], 'opening the URI must not mutate an existing note');
    const modal = await dialog(h);
    click(modal, 'Cancel'); await run;
    assert.deepEqual(h.writes, []);
    assert.equal(h.files.get('note.md').text, 'original');
  }
});

test('closing review is fail-closed and text is rendered literally', async () => {
  const h = setup(); h.state.response = '<img src=x onerror=evil()>\nnew text';
  const run = h.invoke({ url: 'https://source.example/<script>', key: undefined });
  const modal = await dialog(h);
  const texts = modal.contentEl.children.map(el => el.text);
  for (const text of ['Source: https://source.example/<script>', 'Vault: Personal vault', 'Note: note.md', h.state.response]) {
    assert.ok(texts.includes(text));
  }
  assert.equal(modal.contentEl.children.find(el => el.focused).text, 'Save as a new note');
  modal.close(); await run; assert.deepEqual(h.writes, []);
});

test('explicit approval preserves plaintext replace and append', async () => {
  for (const append of [false, true]) {
    const h = setup(); const run = h.invoke({ append: String(append) });
    const modal = await dialog(h);
    h.files.get('note.md').text = 'latest text';
    click(modal, append ? 'Append to existing note' : 'Replace existing note'); await run;
    assert.equal(h.files.get('note.md').text, append ? 'latest text\nincoming' : 'incoming');
    assert.deepEqual(h.opened, ['note.md']);
  }
});

test('fresh-note choice avoids existing notes and suffix collisions', async () => {
  const h = setup({ 'note.md': 'original', 'note (import).md': 'keep' });
  const run = h.invoke(); click(await dialog(h), 'Save as a new note'); await run;
  assert.deepEqual(h.writes, [['create', 'note (import 2).md', 'incoming']]);
  assert.equal(h.files.get('note.md').text, 'original');
  assert.equal(h.files.get('note (import).md').text, 'keep');
  assert.deepEqual(h.opened, ['note (import 2).md']);
});

test('new nested destination still creates directly', async () => {
  const h = setup({}); await h.invoke({ path: 'Notes/Work', file: 'day.md' });
  assert.deepEqual(h.writes, [['create', 'Notes/Work/day.md', 'incoming']]);
  assert.equal(h.modals.length, 0);
});

test('approval cannot follow a renamed, deleted, or replaced target', async () => {
  for (const change of ['rename', 'delete', 'replace']) {
    const h = setup(); const run = h.invoke(); const modal = await dialog(h);
    const entry = h.files.get('note.md');
    h.files.delete('note.md');
    if (change === 'rename') { entry.file.path = 'other.md'; h.files.set('other.md', entry); }
    if (change === 'replace') h.put('note.md', 'replacement');
    click(modal, 'Replace existing note'); await run;
    assert.deepEqual(h.writes, []);
    assert.ok(h.notices.some(text => text.includes('Import target changed')));
  }
});

test('target identity is checked again after an asynchronous append read', async () => {
  const h = setup();
  h.vault.read = async () => { h.put('note.md', 'replacement'); return 'original'; };
  const run = h.invoke({ append: 'true' });
  click(await dialog(h), 'Append to existing note'); await run;
  assert.deepEqual(h.writes, []); assert.equal(h.files.get('note.md').text, 'replacement');
});

test('creation races never fall back to modification', async () => {
  for (const existing of [false, true]) {
    const h = setup(existing ? undefined : {});
    h.vault.create = async path => { h.put(path, 'racing note'); throw Error('File already exists'); };
    const run = h.invoke();
    if (existing) click(await dialog(h), 'Save as a new note');
    await run; assert.deepEqual(h.writes, []);
    assert.ok(h.notices.some(text => text.includes('File already exists')));
  }
});

test('concurrent imports require independent approval', async () => {
  const h = setup(); const first = h.invoke(); await dialog(h);
  h.state.response = 'second'; const second = h.invoke(); await dialog(h, 2);
  click(h.modals[0], 'Replace existing note'); await first;
  assert.equal(h.files.get('note.md').text, 'incoming');
  h.modals[1].close(); await second;
  assert.equal(h.writes.length, 1);
});

test('unload cancels dialogs and pending fetches', async () => {
  const h = setup(); const run = h.invoke(); await dialog(h); h.plugin.onunload(); await run;
  assert.deepEqual(h.writes, []);
  const later = setup(); let release;
  later.state.fetch = () => new Promise(resolve => { release = resolve; });
  const pending = later.invoke(); later.plugin.onunload();
  release({ status: 200, text: 'incoming' }); await pending;
  assert.deepEqual(later.writes, []); assert.equal(later.modals.length, 0);
});

test('failed fetch and decryption do not write or request approval', async () => {
  for (const fail of ['fetch', 'decrypt']) {
    const h = setup();
    if (fail === 'fetch') h.state.status = 500;
    await h.invoke(fail === 'decrypt' ? { key: 'wrong' } : {});
    assert.deepEqual(h.writes, []); assert.equal(h.modals.length, 0);
  }
});

test('encrypted daily re-export previews plaintext and replaces only on approval', async () => {
  const h = setup(); const password = 'export-secret';
  const salt = webcrypto.getRandomValues(new Uint8Array(16));
  const iv = webcrypto.getRandomValues(new Uint8Array(12));
  const material = await webcrypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
  const key = await webcrypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' }, material, { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
  const ciphertext = await webcrypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode('Daily lesson note'));
  h.state.response = Buffer.concat([salt, iv, Buffer.from(ciphertext)]).toString('base64');
  const run = h.invoke({ key: password }); const modal = await dialog(h);
  assert.ok(modal.contentEl.children.some(el => el.tag === 'pre' && el.text === 'Daily lesson note'));
  assert.deepEqual(h.writes, []);
  click(modal, 'Replace existing note'); await run;
  assert.equal(h.files.get('note.md').text, 'Daily lesson note');
});
