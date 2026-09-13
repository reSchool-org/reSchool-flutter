import { App, Modal, Plugin, TFile, Notice, normalizePath, requestUrl } from "obsidian";

interface KmiParams {
	file: string;
	path?: string;
	append: boolean;
	url: string;
	key?: string;
}

type ImportChoice = "cancel" | "new" | "modify";

class ImportConfirmation extends Modal {
	private choice: ImportChoice = "cancel";

	constructor(
		app: App,
		private source: string,
		private filePath: string,
		private append: boolean,
		private content: string,
		private done: (choice: ImportChoice) => void,
	) {
		super(app);
	}

	onOpen() {
		const { contentEl } = this;
		contentEl.createEl("h2", { text: "KMI: review import" });
		contentEl.createEl("p", { text: `Source: ${this.source}` });
		contentEl.createEl("p", { text: `Vault: ${this.app.vault.getName()}` });
		contentEl.createEl("p", { text: `Note: ${this.filePath}` });
		contentEl.createEl("p", {
			text: this.append ? "Append to this existing note?" : "Replace all text in this existing note?",
		});
		contentEl.createEl("p", { text: "Save as a new note to keep the existing note unchanged." });
		const preview = contentEl.createEl("pre", { text: this.content });
		preview.style.maxHeight = "16em";
		preview.style.overflow = "auto";
		preview.style.whiteSpace = "pre-wrap";
		const addButton = (text: string, choice: ImportChoice) => {
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
}

async function decryptAesGcm(ciphertext: string, password: string): Promise<string> {
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
		{ name: "PBKDF2", salt, iterations: 100000, hash: "SHA-256" },
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

export default class KmiPastePlugin extends Plugin {
	private pendingImports = new Set<ImportConfirmation>();
	private unloaded = false;

	async onload() {
		this.registerObsidianProtocolHandler("kmi", async (params) => {
			await this.handleKmiUri(params as Record<string, string>);
		});
	}

	onunload() {
		this.unloaded = true;
		for (const modal of this.pendingImports) modal.close();
	}

	private confirmImport(params: KmiParams, filePath: string, content: string): Promise<ImportChoice> {
		return new Promise((resolve) => {
			const modal = new ImportConfirmation(this.app, params.url, filePath, params.append, content, (choice) => {
				this.pendingImports.delete(modal);
				resolve(choice);
			});
			this.pendingImports.add(modal);
			modal.open();
		});
	}

	private newImportPath(filePath: string): string {
		const stem = filePath.slice(0, -3);
		let candidate = `${stem} (import).md`;
		let suffix = 2;
		while (this.app.vault.getAbstractFileByPath(candidate)) {
			candidate = `${stem} (import ${suffix++}).md`;
		}
		return candidate;
	}

	private parseParams(raw: Record<string, string>): KmiParams | null {
		const url = raw["url"];
		if (!url) {
			new Notice("KMI: missing required parameter 'url'");
			return null;
		}

		const file = raw["file"];
		if (!file) {
			new Notice("KMI: missing required parameter 'file'");
			return null;
		}

		const path = raw["path"] ?? "";
		const append = raw["append"] === "true";
		const key = raw["key"];

		return { file, path, append, url, key };
	}

	private buildFilePath(params: KmiParams): string {
		let filename = params.file;
		if (!filename.endsWith(".md")) {
			filename += ".md";
		}

		if (params.path && params.path.trim() !== "") {
			return normalizePath(`${params.path}/${filename}`);
		}

		return normalizePath(filename);
	}

	private async fetchContent(url: string): Promise<string> {
		let fetchUrl = url;
		try {
			const parsed = new URL(url);
			parsed.search = "";
			fetchUrl = parsed.toString();
		} catch {}

		const response = await requestUrl({ url: fetchUrl, method: "GET" });
		if (response.status < 200 || response.status >= 300) {
			throw new Error(`HTTP ${response.status}`);
		}
		return response.text;
	}

	private async ensureFolderExists(folderPath: string): Promise<void> {
		if (!folderPath || folderPath === ".") return;

		const folder = this.app.vault.getAbstractFileByPath(folderPath);
		if (!folder) {
			await this.app.vault.createFolder(folderPath);
		}
	}

	async handleKmiUri(raw: Record<string, string>): Promise<void> {
		const params = this.parseParams(raw);
		if (!params) return;

		let content: string;
		try {
			content = await this.fetchContent(params.url);
		} catch (err) {
			const msg = err instanceof Error ? err.message : String(err);
			new Notice(`KMI: failed to fetch content - ${msg}`);
			return;
		}

		if (params.key) {
			try {
				content = await decryptAesGcm(content.trim(), params.key);
			} catch (err) {
				new Notice("KMI: decryption failed - wrong key or corrupted data");
				return;
			}
		}

		if (this.unloaded) return;
		let filePath = this.buildFilePath(params);

		const folderPath = filePath.includes("/")
			? filePath.substring(0, filePath.lastIndexOf("/"))
			: "";

		try {
			await this.ensureFolderExists(folderPath);
		} catch (err) {
			const msg = err instanceof Error ? err.message : String(err);
			new Notice(`KMI: failed to create folder - ${msg}`);
			return;
		}

		const existingFile = this.app.vault.getAbstractFileByPath(filePath);

		try {
			if (this.unloaded) return;
			if (existingFile instanceof TFile) {
				const choice = await this.confirmImport(params, filePath, content);
				if (this.unloaded || choice === "cancel") return;
				if (choice === "new") {
					filePath = this.newImportPath(filePath);
					await this.app.vault.create(filePath, content);
					new Notice(`KMI: created "${filePath}"`);
				} else {
					// подтверждение относится к найденному файлу и остаётся в силе после чтения для дозаписи
					const assertTarget = () => {
						if (this.unloaded || existingFile.path !== filePath ||
							this.app.vault.getAbstractFileByPath(filePath) !== existingFile) {
							throw new Error("Import target changed; open the link again to review it");
						}
					};
					assertTarget();
					const updated = params.append
						? (await this.app.vault.read(existingFile)) + "\n" + content
						: content;
					assertTarget();
					await this.app.vault.modify(existingFile, updated);
					new Notice(`KMI: ${params.append ? "appended to" : "overwrote"} "${filePath}"`);
				}
			} else {
				await this.app.vault.create(filePath, content);
				new Notice(`KMI: created "${filePath}"`);
			}

			const file = this.app.vault.getAbstractFileByPath(filePath);
			if (file instanceof TFile) {
				const leaf = this.app.workspace.getLeaf(false);
				await leaf.openFile(file);
			}
		} catch (err) {
			const msg = err instanceof Error ? err.message : String(err);
			new Notice(`KMI: failed to write file - ${msg}`);
		}
	}
}
