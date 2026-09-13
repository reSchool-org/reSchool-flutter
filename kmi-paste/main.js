"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

var main_exports = {};
__export(main_exports, {
  default: () => KmiPastePlugin
});
module.exports = __toCommonJS(main_exports);
var import_obsidian = require("obsidian");
var ImportConfirmation = class extends import_obsidian.Modal {
  constructor(app, source, filePath, append, content, done) {
    super(app);
    this.source = source;
    this.filePath = filePath;
    this.append = append;
    this.content = content;
    this.done = done;
    this.choice = "cancel";
  }
  onOpen() {
    const { contentEl } = this;
    contentEl.createEl("h2", { text: "KMI: review import" });
    contentEl.createEl("p", { text: `Source: ${this.source}` });
    contentEl.createEl("p", { text: `Vault: ${this.app.vault.getName()}` });
    contentEl.createEl("p", { text: `Note: ${this.filePath}` });
    contentEl.createEl("p", {
      text: this.append ? "Append to this existing note?" : "Replace all text in this existing note?"
    });
    contentEl.createEl("p", { text: "Save as a new note to keep the existing note unchanged." });
    const preview = contentEl.createEl("pre", { text: this.content });
    preview.style.maxHeight = "16em";
    preview.style.overflow = "auto";
    preview.style.whiteSpace = "pre-wrap";
    const addButton = (text, choice) => {
      const button = contentEl.createEl("button", { text });
      button.addEventListener("click", () => {
        this.choice = choice;
        this.close();
      });
      return button;
    };
    addButton("Cancel", "cancel");
    addButton("Save as a new note", "new").focus();
    addButton(this.append ? "Append to existing note" : "Replace existing note", "modify");
  }
  onClose() {
    this.contentEl.empty();
    this.done(this.choice);
  }
};
async function decryptAesGcm(ciphertext, password) {
  const raw = Uint8Array.from(atob(ciphertext), (c) => c.charCodeAt(0));
  const salt = raw.slice(0, 16);
  const iv = raw.slice(16, 28);
  const data = raw.slice(28);
  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveKey"]
  );
  const aesKey = await crypto.subtle.deriveKey(
    { name: "PBKDF2", salt, iterations: 1e5, hash: "SHA-256" },
    keyMaterial,
    { name: "AES-GCM", length: 256 },
    false,
    ["decrypt"]
  );
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    aesKey,
    data
  );
  return new TextDecoder().decode(decrypted);
}
var KmiPastePlugin = class extends import_obsidian.Plugin {
  constructor() {
    super(...arguments);
    this.pendingImports = /* @__PURE__ */ new Set();
    this.unloaded = false;
  }
  async onload() {
    this.registerObsidianProtocolHandler("kmi", async (params) => {
      await this.handleKmiUri(params);
    });
  }
  onunload() {
    this.unloaded = true;
    for (const modal of this.pendingImports) modal.close();
  }
  confirmImport(params, filePath, content) {
    return new Promise((resolve) => {
      const modal = new ImportConfirmation(this.app, params.url, filePath, params.append, content, (choice) => {
        this.pendingImports.delete(modal);
        resolve(choice);
      });
      this.pendingImports.add(modal);
      modal.open();
    });
  }
  newImportPath(filePath) {
    const stem = filePath.slice(0, -3);
    let candidate = `${stem} (import).md`;
    let suffix = 2;
    while (this.app.vault.getAbstractFileByPath(candidate)) {
      candidate = `${stem} (import ${suffix++}).md`;
    }
    return candidate;
  }
  parseParams(raw) {
    var _a;
    const url = raw["url"];
    if (!url) {
      new import_obsidian.Notice("KMI: missing required parameter 'url'");
      return null;
    }
    const file = raw["file"];
    if (!file) {
      new import_obsidian.Notice("KMI: missing required parameter 'file'");
      return null;
    }
    const path = (_a = raw["path"]) != null ? _a : "";
    const append = raw["append"] === "true";
    const key = raw["key"];
    return { file, path, append, url, key };
  }
  buildFilePath(params) {
    let filename = params.file;
    if (!filename.endsWith(".md")) {
      filename += ".md";
    }
    if (params.path && params.path.trim() !== "") {
      return (0, import_obsidian.normalizePath)(`${params.path}/${filename}`);
    }
    return (0, import_obsidian.normalizePath)(filename);
  }
  async fetchContent(url) {
    let fetchUrl = url;
    try {
      const parsed = new URL(url);
      parsed.search = "";
      fetchUrl = parsed.toString();
    } catch (e) {
    }
    const response = await (0, import_obsidian.requestUrl)({ url: fetchUrl, method: "GET" });
    if (response.status < 200 || response.status >= 300) {
      throw new Error(`HTTP ${response.status}`);
    }
    return response.text;
  }
  async ensureFolderExists(folderPath) {
    if (!folderPath || folderPath === ".") return;
    const folder = this.app.vault.getAbstractFileByPath(folderPath);
    if (!folder) {
      await this.app.vault.createFolder(folderPath);
    }
  }
  async handleKmiUri(raw) {
    const params = this.parseParams(raw);
    if (!params) return;
    let content;
    try {
      content = await this.fetchContent(params.url);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      new import_obsidian.Notice(`KMI: failed to fetch content - ${msg}`);
      return;
    }
    if (params.key) {
      try {
        content = await decryptAesGcm(content.trim(), params.key);
      } catch (err) {
        new import_obsidian.Notice("KMI: decryption failed - wrong key or corrupted data");
        return;
      }
    }
    if (this.unloaded) return;
    let filePath = this.buildFilePath(params);
    const folderPath = filePath.includes("/") ? filePath.substring(0, filePath.lastIndexOf("/")) : "";
    try {
      await this.ensureFolderExists(folderPath);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      new import_obsidian.Notice(`KMI: failed to create folder - ${msg}`);
      return;
    }
    const existingFile = this.app.vault.getAbstractFileByPath(filePath);
    try {
      if (this.unloaded) return;
      if (existingFile instanceof import_obsidian.TFile) {
        const choice = await this.confirmImport(params, filePath, content);
        if (this.unloaded || choice === "cancel") return;
        if (choice === "new") {
          filePath = this.newImportPath(filePath);
          await this.app.vault.create(filePath, content);
          new import_obsidian.Notice(`KMI: created "${filePath}"`);
        } else {
          const assertTarget = () => {
            if (this.unloaded || existingFile.path !== filePath || this.app.vault.getAbstractFileByPath(filePath) !== existingFile) {
              throw new Error("Import target changed; open the link again to review it");
            }
          };
          assertTarget();
          const updated = params.append ? await this.app.vault.read(existingFile) + "\n" + content : content;
          assertTarget();
          await this.app.vault.modify(existingFile, updated);
          new import_obsidian.Notice(`KMI: ${params.append ? "appended to" : "overwrote"} "${filePath}"`);
        }
      } else {
        await this.app.vault.create(filePath, content);
        new import_obsidian.Notice(`KMI: created "${filePath}"`);
      }
      const file = this.app.vault.getAbstractFileByPath(filePath);
      if (file instanceof import_obsidian.TFile) {
        const leaf = this.app.workspace.getLeaf(false);
        await leaf.openFile(file);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      new import_obsidian.Notice(`KMI: failed to write file - ${msg}`);
    }
  }
};
