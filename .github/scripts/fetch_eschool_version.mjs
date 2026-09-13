// тянет версию клиента eSchool из google play и кладёт в файл для релиза
// разбор html берём из play-version-worker, чтобы шаблоны жили в одном месте
import { writeFile } from "node:fs/promises";

import { fetchPlayVersion } from "../../server/play-version-worker/src/index.js";

const APP_ID = process.env.ESCHOOL_APP_ID || "ru.spb.itstrategy.mobilejournal";
const LANG = process.env.ESCHOOL_LANG || "ru";
const COUNTRY = process.env.ESCHOOL_COUNTRY || "ru";
const OUTPUT = process.env.ESCHOOL_VERSION_FILE || "eschool-version.txt";

const info = await fetchPlayVersion({ appId: APP_ID, lang: LANG, country: COUNTRY });

// пустой или мусорный разбор лучше уронить, чем затереть рабочий файл в релизе
if (!/^\d+\.\d+/.test(info.version || "")) {
    throw new Error(`play отдал версию, которая не похожа на версию: ${JSON.stringify(info.version)}`);
}

await writeFile(OUTPUT, `${info.version}\n`, "utf8");
console.log(`${APP_ID}: ${info.version} (обновлено ${info.updatedText || "неизвестно когда"})`);
