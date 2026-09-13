"""материалы, из которых складывается задание
задание бывает где угодно: номера в учебнике, фотография доски от учителя,
листочек, который приложил одноклассник, или всё это разом. Модуль собирает
такие материалы в одном виде, чтобы оценка видела картину целиком"""

import os
import zipfile
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit

import requests

from .config import ANALYSIS_IMAGE_FOLDER
from .logging_utils import log

IMAGE_EXTENSIONS = ('.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic')
DOCUMENT_EXTENSIONS = ('.docx', '.pdf', '.txt')
# картинок берём немного: больше в оценку всё равно не поместится осмысленно
MAX_ATTACHMENT_IMAGES = 4
MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024
DOWNLOAD_TIMEOUT = 25
MAX_DOCUMENT_TEXT = 60000


def is_image(name, url=None):
    candidate = (name or url or '').lower().split('?', 1)[0]
    return candidate.endswith(IMAGE_EXTENSIONS)


def mime_for(path):
    lower = path.lower()
    if lower.endswith('.pdf'):
        return 'application/pdf'
    if lower.endswith('.png'):
        return 'image/png'
    if lower.endswith('.webp'):
        return 'image/webp'
    if lower.endswith('.gif'):
        return 'image/gif'
    return 'image/jpeg'


def is_supported(name, url=None):
    candidate = (name or url or '').lower().split('?', 1)[0]
    return is_image(name, url) or candidate.endswith(DOCUMENT_EXTENSIONS)


def material_parts(material):
    """читаем документ локально, модель не может открыть ссылку eschool"""
    from .gemini_client import image_part

    path = material['path']
    if os.path.getsize(path) > MAX_ATTACHMENT_BYTES:
        raise ValueError('Вложение слишком большое для анализа')
    if path.lower().endswith('.docx'):
        with zipfile.ZipFile(path) as document:
            info = document.getinfo('word/document.xml')
            if info.file_size > MAX_ATTACHMENT_BYTES:
                raise ValueError('Текст DOCX слишком большой для анализа')
            root = ET.fromstring(document.read(info))
            ns = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
            paragraphs = []
            for paragraph in root.iter(ns + 'p'):
                text = ''.join(
                    node.text or '' if node.tag == ns + 't' else
                    '\t' if node.tag == ns + 'tab' else '\n'
                    for node in paragraph.iter()
                    if node.tag in (ns + 't', ns + 'tab', ns + 'br', ns + 'cr'))
                if text.strip():
                    paragraphs.append(text)
            text = '\n'.join(paragraphs)
            parts = [{'text': text[:MAX_DOCUMENT_TEXT]}] if text.strip() else []
            for info in document.infolist():
                if (info.filename.startswith('word/media/') and is_image(info.filename)
                        and info.file_size <= MAX_ATTACHMENT_BYTES):
                    parts.append(image_part(document.read(info), mime_for(info.filename)))
                    if len(parts) >= MAX_ATTACHMENT_IMAGES + 1:
                        break
            if not parts:
                raise ValueError('В DOCX не найдено текста или изображений')
            return parts
    if path.lower().endswith('.txt'):
        with open(path, encoding='utf-8-sig') as document:
            return [{'text': document.read(MAX_DOCUMENT_TEXT)}]
    with open(path, 'rb') as document:
        return [image_part(document.read(), mime_for(path))]


def source_dir(analysis_id):
    return os.path.join(ANALYSIS_IMAGE_FOLDER, str(analysis_id), 'src')


def fetch_teacher_attachments(analysis_id, attachments, headers=None, cookies=None):
    """скачать вложения учителя, пока жива сессия eSchool
    тянем сразу в мониторе, а не в воркере: к моменту разбора куки могут
    протухнуть, а ссылки eSchool отдаёт только своим. Другие источники
    и перенаправления пропускаем: школьная сессия не должна покидать eSchool"""
    saved = []
    if not attachments:
        return saved

    directory = source_dir(analysis_id)
    os.makedirs(directory, exist_ok=True)

    for attachment in attachments:
        if len(saved) >= MAX_ATTACHMENT_IMAGES:
            break
        if not isinstance(attachment, dict):
            continue
        name = str(attachment.get('name') or 'attachment')
        url = attachment.get('url')
        if not url:
            continue
        if not (attachment.get('isImage') or is_supported(name, url)):
            continue
        try:
            # ограничиваем источники как при скачивании из телеграма, произвольные адреса допускают ssrf даже без куки
            if (not isinstance(url, str) or "\\" in url
                    or any(ord(char) <= 32 or ord(char) == 127 for char in url)):
                raise ValueError("Authenticated attachment origin is not allowed")
            parts = urlsplit(url)
            if (parts.scheme != "https" or parts.hostname != "app.eschool.center"
                    or parts.port not in (None, 443)
                    or parts.username is not None or parts.password is not None):
                raise ValueError("Authenticated attachment origin is not allowed")
            with requests.get(url, headers=headers or {},
                              cookies=cookies if cookies is not None else {},
                              timeout=DOWNLOAD_TIMEOUT, stream=True,
                              allow_redirects=False) as response:
                if response.status_code != 200:
                    log(f"[Analysis] Вложение {name}: HTTP {response.status_code}")
                    continue
                body = response.raw.read(MAX_ATTACHMENT_BYTES + 1, decode_content=True)
            if len(body) > MAX_ATTACHMENT_BYTES:
                log(f"[Analysis] Вложение {name} слишком большое, пропускаем")
                continue
            path = os.path.join(directory, f"{len(saved)}_{_safe(name)}")
            with open(path, 'wb') as f:
                f.write(body)
            saved.append({'name': name, 'path': path, 'origin': 'teacher'})
        except Exception as e:
            log(f"[Analysis] Вложение {name} не скачалось: {e}")
    if saved:
        log(f"[Analysis] {analysis_id}: забрали вложений учителя {len(saved)}")
    return saved


def custom_homework_files(cursor, homework_id):
    """файлы, приложенные одноклассником, лежат уже у нас на диске"""
    if not homework_id:
        return []
    cursor.execute("""
        SELECT file_name, storage_path FROM custom_homework_files
        WHERE homework_id = %s ORDER BY id
    """, (homework_id,))
    files = []
    for name, path in cursor.fetchall():
        if len(files) >= MAX_ATTACHMENT_IMAGES:
            break
        if is_supported(name, path) and path and os.path.exists(path):
            files.append({'name': name, 'path': path, 'origin': 'classmate'})
    return files


def _safe(name):
    keep = ''.join(c if c.isalnum() or c in '._-' else '_' for c in name)
    stem, ext = os.path.splitext(keep)
    return (stem[:60] + ext[:10]) or 'file'
