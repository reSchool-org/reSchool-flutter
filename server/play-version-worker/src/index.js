const DAY_SECONDS = 86400;
const PLAY_BASE_URL = "https://play.google.com/store/apps/details";

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...extraHeaders,
    },
  });
}

function cacheHeaders(ttl, cacheStatus) {
  return {
    "cache-control": `public, max-age=${ttl}`,
    "x-cache": cacheStatus,
  };
}

function getConfig(env) {
  const ttl = Number.parseInt(env.CACHE_TTL_SECONDS || "", 10);
  return {
    defaultAppId: env.DEFAULT_APP_ID || "ru.spb.itstrategy.mobilejournal",
    defaultLang: env.DEFAULT_LANG || "ru",
    defaultCountry: env.DEFAULT_COUNTRY || "ru",
    ttl: Number.isFinite(ttl) && ttl > 0 ? ttl : DAY_SECONDS,
  };
}

function buildCacheKey(requestUrl, appId, lang, country) {
  const cacheUrl = new URL(requestUrl);
  cacheUrl.pathname = "/play-version";
  cacheUrl.search = new URLSearchParams({ appId, lang, country }).toString();
  return new Request(cacheUrl.toString(), { method: "GET" });
}

function decodeHtmlEntities(value) {
  return value.replace(/&(#x?[0-9a-fA-F]+|amp|quot|#39|apos|lt|gt);/g, (entity, code) => {
    switch (code) {
      case "amp":
        return "&";
      case "quot":
        return '"';
      case "#39":
      case "apos":
        return "'";
      case "lt":
        return "<";
      case "gt":
        return ">";
      default: {
        const isHex = code.startsWith("#x");
        const raw = code.slice(isHex ? 2 : 1);
        const point = Number.parseInt(raw, isHex ? 16 : 10);
        return Number.isFinite(point) ? String.fromCodePoint(point) : entity;
      }
    }
  });
}

function decodeGoogleString(value) {
  try {
    return decodeHtmlEntities(JSON.parse(`"${value}"`));
  } catch {
    return decodeHtmlEntities(value);
  }
}

function getMetaContent(html, property) {
  const pattern = new RegExp(
    `<meta[^>]+(?:property|name)=["']${property}["'][^>]+content=["']([^"']*)["']`,
    "i",
  );
  const match = html.match(pattern);
  return match ? decodeGoogleString(match[1]) : null;
}

function normalizeTitle(title) {
  if (!title) {
    return null;
  }

  return title.replace(/^.*(?:Google Play|Play)\s*[\u2013-]\s*/i, "").trim() || title;
}

function findAppDataWindow(html, appId, versionPattern) {
  const marker = `"${appId}",7`;
  let startAt = 0;

  while (true) {
    const index = html.indexOf(marker, startAt);
    if (index === -1) {
      break;
    }

    const chunk = html.slice(Math.max(0, index - 10000), index + 2000);
    if (versionPattern.test(chunk)) {
      return chunk;
    }

    startAt = index + marker.length;
  }

  return null;
}

// шаблоны пробуем по порядку, побеждает первый совпавший
// структура: [[["1.2.3"]],[[[35]],[[[23,"6.0"]]]]]
// p1: текущий формат, числа вроде 35 и 23 меняются, но \d+ это переживёт
// p2: помягче, блок версии и следом любой вложенный массив со строкой андроида
// p3: только версия, minAndroid не трогаем
const VERSION_PATTERNS = [
  {
    re: /\[\[\["([0-9][^"]+)"\]\],\[\[\[\d+\]\],\[\[\[\d+,"([^"]+)"\]\]\]\]\]/,
    version: 1,
    minAndroid: 2,
  },
  {
    re: /\[\[\["([0-9][^"]+)"\]\],\[\[(?:\[.*?\],?)+\[\[\[\d+,"([0-9.]+)"\]\]\]\]\]\]/,
    version: 1,
    minAndroid: 2,
  },
  {
    re: /\[\[\["([0-9]+\.[0-9]+[^"]*?)"\]\]/,
    version: 1,
    minAndroid: null,
  },
];

function extractVersion(appData) {
  for (const { re, version, minAndroid } of VERSION_PATTERNS) {
    const m = appData.match(re);
    if (m) {
      return {
        match: m,
        version: decodeGoogleString(m[version]),
        minAndroidVersion: minAndroid ? decodeGoogleString(m[minAndroid]) : null,
      };
    }
  }
  return null;
}

export function parsePlayHtml(html, { appId, lang, country }) {
  // каждый шаблон версии пробуем как якорь для findAppDataWindow
  let appData = null;
  let versionResult = null;

  for (const { re } of VERSION_PATTERNS) {
    appData = findAppDataWindow(html, appId, re);
    if (appData) {
      versionResult = extractVersion(appData);
      if (versionResult) break;
    }
  }

  if (!appData) {
    throw new Error(`Google Play app data marker was not found for ${appId}`);
  }
  if (!versionResult) {
    throw new Error(`Google Play version marker was not found for ${appId}`);
  }

  const { match: versionMatch, version, minAndroidVersion } = versionResult;
  const afterVersion = appData.slice(versionMatch.index + versionMatch[0].length);

  const updatedMatch = afterVersion.match(/\[\["([^"]+)",\[(\d{9,}),(\d+)\]\]\]/);
  const releaseNotesMatch = afterVersion.match(/\[null,\[null,"((?:\\.|[^"\\])*)"\]\],\[\["/);
  const updatedSeconds = updatedMatch ? Number.parseInt(updatedMatch[2], 10) : null;
  const updatedNanos = updatedMatch ? Number.parseInt(updatedMatch[3], 10) : 0;
  const updated =
    Number.isFinite(updatedSeconds) && updatedSeconds > 0
      ? updatedSeconds * 1000 + Math.floor(updatedNanos / 1_000_000)
      : null;

  return {
    appId,
    lang,
    country,
    version,
    updated,
    updatedText: updatedMatch ? decodeGoogleString(updatedMatch[1]) : null,
    minAndroidVersion,
    releaseNotes: releaseNotesMatch ? decodeGoogleString(releaseNotesMatch[1]).replace(/<br\s*\/?>/gi, "\n") : null,
    title: normalizeTitle(getMetaContent(html, "og:title")),
    url: `${PLAY_BASE_URL}?id=${encodeURIComponent(appId)}&hl=${encodeURIComponent(lang)}`,
    fetchedAt: new Date().toISOString(),
    source: "play.google.com",
  };
}

export async function fetchPlayVersion({ appId, lang, country }) {
  const playUrl = new URL(PLAY_BASE_URL);
  playUrl.search = new URLSearchParams({
    id: appId,
    hl: lang,
    gl: country.toUpperCase(),
  }).toString();

  const response = await fetch(playUrl.toString(), {
    headers: {
      accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "accept-language": `${lang},en;q=0.8`,
      "user-agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36",
    },
    redirect: "follow",
  });

  if (!response.ok) {
    throw new Error(`Google Play returned HTTP ${response.status}`);
  }

  return parsePlayHtml(await response.text(), { appId, lang, country });
}

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET") {
      return json({ error: "Method not allowed" }, 405, {
        allow: "GET",
      });
    }

    const config = getConfig(env);
    const url = new URL(request.url);
    const appId = url.searchParams.get("appId") || config.defaultAppId;
    const lang = url.searchParams.get("lang") || config.defaultLang;
    const country = url.searchParams.get("country") || config.defaultCountry;

    const cacheKey = buildCacheKey(request.url, appId, lang, country);
    const cached = await caches.default.match(cacheKey);
    if (cached) {
      return new Response(cached.body, {
        status: cached.status,
        headers: {
          ...Object.fromEntries(cached.headers),
          ...cacheHeaders(config.ttl, "HIT"),
        },
      });
    }

    try {
      const payload = await fetchPlayVersion({ appId, lang, country });
      const response = json(payload, 200, cacheHeaders(config.ttl, "MISS"));
      ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
      return response;
    } catch (error) {
      return json(
        {
          error: "Failed to fetch Google Play app metadata",
          message: error instanceof Error ? error.message : String(error),
          appId,
          lang,
          country,
        },
        502,
        {
          "cache-control": "no-store",
          "x-cache": "BYPASS",
        },
      );
    }
  },
};
