"""общий клиент ИИ: Google (AI Studio/Vertex AI) или OpenRouter
имя модуля и исключения сохранены для существующих обработчиков заданий"""

import base64
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request

from .config import (
    AI_PROVIDER,
    GEMINI_API_KEY,
    GEMINI_MODEL,
    GEMINI_TIMEOUT_SECONDS,
    GEMINI_VERTEX_LOCATION,
    GEMINI_VERTEX_PROJECT,
    OPENROUTER_API_KEY,
    OPENROUTER_MODEL,
    OPENROUTER_TIMEOUT_SECONDS,
)
from .logging_utils import log

VERTEX_URL = ("https://aiplatform.googleapis.com/v1/projects/{project}/locations/{location}"
              "/publishers/google/models/{model}:generateContent")
STUDIO_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

# коды, на которых имеет смысл повторить: перегруз и упор в лимит
RETRY_CODES = {408, 429, 500, 502, 503, 504}
MAX_ATTEMPTS = 5


class GeminiError(RuntimeError):
    pass


class GeminiUnavailable(GeminiError):
    """модель недоступна прямо сейчас: лимит, перегруз, сеть. Стоит повторить позже"""


_token_lock = threading.Lock()
_token = {"value": None, "expires": 0.0}


def is_configured():
    if AI_PROVIDER == "openrouter":
        return bool(OPENROUTER_API_KEY)
    return AI_PROVIDER == "google" and bool(GEMINI_VERTEX_PROJECT or GEMINI_API_KEY)


def _print_access_token():
    try:
        out = subprocess.run(
            ["gcloud", "auth", "print-access-token"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as e:
        return None, str(e)
    return (out.stdout or "").strip() or None, (out.stderr or "").strip()[:200]


def _activate_service_account():
    """поднять учётку gcloud самим
    на старте контейнера активация иногда не проходит, и без этого разбор
    оставался без модели до тех пор, пока внутрь не зайдут руками"""
    key = os.environ.get("VERTEX_SA_KEY_PATH")
    if not key or not os.path.exists(key):
        return False
    try:
        out = subprocess.run(
            ["gcloud", "auth", "activate-service-account", "--key-file", key, "--quiet"],
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as e:
        log(f"[Gemini] Сервисный аккаунт активировать не вышло: {e}")
        return False
    if out.returncode:
        log(f"[Gemini] Сервисный аккаунт активировать не вышло: {(out.stderr or '').strip()[:200]}")
        return False
    log("[Gemini] Сервисный аккаунт vertex активирован")
    return True


def _access_token():
    """токен gcloud живёт час, обновляем с запасом"""
    with _token_lock:
        if _token["value"] and time.time() < _token["expires"]:
            return _token["value"]
        value, error = _print_access_token()
        if not value and _activate_service_account():
            value, error = _print_access_token()
        if not value:
            raise GeminiError(f"gcloud не отдал токен: {error}")
        _token["value"] = value
        _token["expires"] = time.time() + 1800
        return value


def _endpoint():
    if AI_PROVIDER == "openrouter":
        if not OPENROUTER_API_KEY:
            raise GeminiError("OpenRouter не настроен: задайте OPENROUTER_API_KEY")
        return OPENROUTER_URL, {"Authorization": "Bearer " + OPENROUTER_API_KEY}
    if AI_PROVIDER != "google":
        raise GeminiError(f"Неизвестный провайдер ИИ: {AI_PROVIDER}")
    if GEMINI_VERTEX_PROJECT:
        url = VERTEX_URL.format(project=GEMINI_VERTEX_PROJECT,
                                location=GEMINI_VERTEX_LOCATION,
                                model=GEMINI_MODEL)
        return url, {"Authorization": "Bearer " + _access_token()}
    if GEMINI_API_KEY:
        return STUDIO_URL.format(model=GEMINI_MODEL) + "?key=" + GEMINI_API_KEY, {}
    raise GeminiError("Gemini не настроен: задайте GEMINI_VERTEX_PROJECT или GEMINI_API_KEY")


def _json_schema(schema):
    """адаптируем схему gemini, не меняя общие схемы подсказок"""
    result = {key: value for key, value in schema.items()
              if key not in {"nullable", "propertyOrdering"}}
    if "properties" in result:
        result["properties"] = {key: _json_schema(value)
                                for key, value in result["properties"].items()}
        result["additionalProperties"] = False
    if "items" in result:
        result["items"] = _json_schema(result["items"])
    if schema.get("nullable"):
        return {"anyOf": [result, {"type": "null"}]}
    return result


def _openrouter_body(parts, schema, system, thinking, media_resolution, temperature):
    content = []
    for part in parts:
        if "text" in part:
            content.append({"type": "text", "text": part["text"]})
        elif "inlineData" in part:
            inline = part["inlineData"]
            if not inline["mimeType"].startswith("image/"):
                raise GeminiError("OpenRouter: ожидается изображение")
            image = {"url": f"data:{inline['mimeType']};base64,{inline['data']}"}
            if media_resolution:
                image["detail"] = "low" if media_resolution == "MEDIA_RESOLUTION_LOW" else "high"
            content.append({"type": "image_url", "image_url": image})
        else:
            raise GeminiError("OpenRouter: неподдерживаемый формат материала")
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": content})
    body = {"model": OPENROUTER_MODEL, "messages": messages,
            "temperature": temperature, "stream": False}
    if thinking:
        body["reasoning"] = {"effort": thinking, "exclude": True}
    if schema:
        # часть полей существующих схем намеренно необязательна
        body["response_format"] = {"type": "json_schema", "json_schema": {
            "name": "reschool_result", "schema": _json_schema(schema),
        }}
        body["provider"] = {"require_parameters": True}
    return body


def _google_body(parts, schema, system, thinking, media_resolution, temperature):
    generation_config = {"temperature": temperature}
    if schema:
        generation_config["responseMimeType"] = "application/json"
        generation_config["responseSchema"] = schema
    if thinking:
        generation_config["thinkingConfig"] = {"thinkingLevel": thinking}
    if media_resolution:
        generation_config["mediaResolution"] = media_resolution

    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": generation_config,
    }
    if system:
        body["systemInstruction"] = {"parts": [{"text": system}]}
    return body


def generate(parts, schema=None, system=None, thinking="low",
             media_resolution="MEDIA_RESOLUTION_HIGH", temperature=0.0):
    """один запрос к выбранной модели: (разобранный json или текст, статистика)"""
    openrouter = AI_PROVIDER == "openrouter"
    build = _openrouter_body if openrouter else _google_body
    body = build(parts, schema, system, thinking, media_resolution, temperature)
    encoded = json.dumps(body).encode()
    timeout = OPENROUTER_TIMEOUT_SECONDS if openrouter else GEMINI_TIMEOUT_SECONDS
    provider = "OpenRouter" if openrouter else "Gemini"

    started = time.time()
    last_error = None
    for attempt in range(MAX_ATTEMPTS):
        url, headers = _endpoint()
        request = urllib.request.Request(
            url, data=encoded,
            headers={"Content-Type": "application/json", **headers},
        )
        try:
            raw = urllib.request.urlopen(request, timeout=timeout).read()
            try:
                payload = json.loads(raw)
            except (ValueError, UnicodeDecodeError) as error:
                raise GeminiError(f"{provider}: некорректный JSON ответа") from error
            if not isinstance(payload, dict):
                raise GeminiError(f"{provider}: некорректный формат ответа")
            # openrouter может вернуть ошибку провайдера внутри ответа 200
            if openrouter and payload.get("error"):
                error = payload["error"]
                code = error.get("code") if isinstance(error, dict) else None
                message = error.get("message", "Ошибка провайдера") if isinstance(error, dict) else str(error)
                detail = f"{provider}: {message}"[:300]
                if str(code) in {str(value) for value in RETRY_CODES}:
                    if attempt < MAX_ATTEMPTS - 1:
                        time.sleep(5 * (attempt + 1))
                        continue
                    raise GeminiUnavailable(detail)
                raise GeminiError(detail)
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            last_error = f"HTTP {e.code}: {detail}"
            if e.code in RETRY_CODES and attempt < MAX_ATTEMPTS - 1:
                delay = 5 * (attempt + 1)
                log(f"[{provider}] {e.code}, повтор через {delay} с")
                time.sleep(delay)
                continue
            if e.code in RETRY_CODES:
                raise GeminiUnavailable(last_error)
            raise GeminiError(last_error)
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last_error = f"сеть: {e}"
            if attempt < MAX_ATTEMPTS - 1:
                time.sleep(5 * (attempt + 1))
                continue
            raise GeminiUnavailable(last_error)
    else:
        raise GeminiUnavailable(last_error or "неизвестная ошибка")

    if openrouter:
        return _openrouter_result(payload, schema, started)
    candidates = payload.get("candidates") or [{}]
    candidate = candidates[0]
    text = "".join(p.get("text", "") for p in candidate.get("content", {}).get("parts", []))

    usage = payload.get("usageMetadata", {})
    stats = {
        "sec": round(time.time() - started, 1),
        "in": usage.get("promptTokenCount", 0),
        "out": usage.get("candidatesTokenCount", 0),
        "think": usage.get("thoughtsTokenCount", 0),
        "finish": candidate.get("finishReason"),
    }

    if not text:
        raise GeminiError(f"пустой ответ, finishReason={candidate.get('finishReason')}")
    if schema:
        try:
            return json.loads(text), stats
        except json.JSONDecodeError as e:
            # обрыв по лимиту вывода выглядит именно так, вызывающий может разбить запрос
            raise GeminiError(f"ответ не разобрался как json ({e}), finishReason={stats['finish']}")
    return text, stats


def _openrouter_result(payload, schema, started):
    choice = (payload.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    text = message.get("content")
    if isinstance(text, list):
        text = "".join(part.get("text", "") for part in text if part.get("type") == "text")
    usage = payload.get("usage") or {}
    stats = {
        "sec": round(time.time() - started, 1),
        "in": usage.get("prompt_tokens", 0),
        "out": usage.get("completion_tokens", 0),
        "think": (usage.get("completion_tokens_details") or {}).get("reasoning_tokens", 0),
        "finish": choice.get("finish_reason"),
    }
    if message.get("refusal") or not isinstance(text, str) or not text.strip():
        raise GeminiError(f"OpenRouter: пустой ответ или отказ, finishReason={stats['finish']}")
    if schema:
        try:
            return json.loads(text), stats
        except json.JSONDecodeError as error:
            raise GeminiError(f"OpenRouter: ответ не разобрался как json, finishReason={stats['finish']}") from error
    return text, stats


def image_part(data, mime_type="image/jpeg"):
    return {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(data).decode()}}


def image_part_from_file(path):
    mime = "image/png" if path.lower().endswith(".png") else "image/jpeg"
    with open(path, "rb") as f:
        return image_part(f.read(), mime)
