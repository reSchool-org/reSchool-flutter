"""учебники: индексация pdf и нарезка картинок заданий
индекс лёгкий, в нём только состав страницы. Координаты задания считаются
при первой выдаче и кэшируются навсегда: упражнение 245 не переезжает,
второй раз за него платить незачем"""

import io
import json
import os
import re
from collections import Counter

from . import ai_prompts, gemini_client
from .config import ANALYSIS_IMAGE_FOLDER, TEXTBOOK_INDEX_CHUNK
from .database import get_db_connection
from .logging_utils import log

# на сколько страниц вперёд показываем модели продолжение задания
LOOKAHEAD_PAGES = 2
# страницы в учебниках это сканы, растеризатор mupdf тянет их мылом,
# поэтому увеличиваем сами: детали не появятся, но текст остаётся чётким
CROP_UPSCALE = 2
# запасной путь для настоящих векторных pdf, там рендер честный
CROP_DPI = 220
# запас вокруг бокса, модель округляет координаты до сетки от 0 до 1000
CROP_PADDING = 6
# приглушение соседних пунктов, когда нужен только один
DIM_ALPHA = 225
# страницы параграфа отдаём целиком, но не всю главу
MAX_PARAGRAPH_PAGES = 3


def _pymupdf():
    """импортим лениво: без разбора учебников серверу этот пакет не нужен"""
    import pymupdf
    return pymupdf


def page_image(doc, index):
    """байты страницы для модели
    в сканах внутри pdf лежит одна готовая картинка, её и берём: рендер
    в большем масштабе это апскейл, лишние мегабайты без новой информации"""
    page = doc[index]
    images = page.get_images(full=True)
    if len(images) == 1:
        extracted = doc.extract_image(images[0][0])
        if extracted["ext"] in ("jpeg", "jpg", "png"):
            mime = "image/png" if extracted["ext"] == "png" else "image/jpeg"
            return extracted["image"], mime
    return page.get_pixmap(dpi=150).tobytes("jpeg"), "image/jpeg"


def open_document(pdf_path):
    return _pymupdf().open(pdf_path)


def metadata_page_indices(page_count):
    """первые три и последние две страницы, без повторов у коротких PDF"""
    return sorted(set(range(min(3, page_count)))
                  | set(range(max(0, page_count - 2), page_count)))


def read_metadata(pdf_path):
    """один отдельный запрос по краям PDF; не создаёт индекс и не пишет в БД"""
    doc = open_document(pdf_path)
    try:
        if doc.needs_pass or not doc.page_count:
            raise ValueError("PDF защищён паролем или не содержит страниц")
        parts = [{"text": "Определи данные книги по приложенным страницам."}]
        for i in metadata_page_indices(doc.page_count):
            # на обложках текст может лежать поверх единственной картинки:
            # отправляем всю видимую страницу, включая текст и поворот PDF
            data = doc[i].get_pixmap(dpi=150).tobytes("jpeg")
            parts.append({"text": f"Страница PDF {i + 1} из {doc.page_count}"})
            parts.append(gemini_client.image_part(data, "image/jpeg"))
        meta, stats = gemini_client.generate(
            parts, schema=ai_prompts.META_SCHEMA, system=ai_prompts.META_SYSTEM)
        meta = _validate_metadata(meta)
        log(f"[Textbook] Метаданные: {meta.get('title')} ({stats['sec']}с)")
        return meta
    finally:
        doc.close()


def _validate_metadata(meta):
    """проверяем ответ до сохранения и дорогой индексации"""
    if not isinstance(meta, dict):
        raise ValueError("ИИ не вернул данные книги")
    result = {}
    for field, limit in (("subject", 256), ("title", 512), ("authors", 512), ("part", 32)):
        value = meta.get(field)
        if value is not None and not isinstance(value, str):
            raise ValueError(f"ИИ вернул неверное поле {field}")
        result[field] = (value or '').strip()[:limit] or None
    if not result['subject'] or not result['title']:
        raise ValueError("Не удалось определить предмет и название по первым трём "
                         "и последним двум страницам PDF")
    grade = meta.get('grade')
    if grade is not None and (type(grade) is not int or not 1 <= grade <= 12):
        raise ValueError("ИИ вернул неверный класс книги")
    kind = meta.get('kind')
    if kind not in ('textbook', 'workbook', 'other'):
        raise ValueError("ИИ вернул неверный тип книги")
    result.update(grade=grade, kind=kind)
    return result


def index_textbook(textbook_id, progress=None):
    """пройти книгу пачками и сложить лёгкий индекс в базу"""
    conn = get_db_connection()
    if not conn:
        raise RuntimeError("нет соединения с базой")
    cursor = conn.cursor()
    doc = None
    try:
        cursor.execute("SELECT pdf_path, subject FROM textbooks WHERE id = %s", (textbook_id,))
        row = cursor.fetchone()
        if not row:
            raise RuntimeError(f"учебник {textbook_id} не найден")
        pdf_path, subject = row
        # пустой предмет означает новую загрузку. Сохраняем метаданные отдельно,
        # чтобы повтор индексации не оплачивал их распознавание заново
        if not subject:
            cursor.execute(
                "UPDATE textbooks SET status = 'pending', status_detail = %s WHERE id = %s",
                ("ИИ определяет данные книги", textbook_id))
            conn.commit()
            meta = read_metadata(pdf_path)
            cursor.execute("""
                UPDATE textbooks SET subject = %s, grade = %s, title = %s,
                    authors = %s, part = %s, kind = %s, status_detail = NULL WHERE id = %s
            """, (meta['subject'], meta['grade'], meta['title'], meta['authors'],
                  meta['part'], meta['kind'], textbook_id))
            conn.commit()
            if not cursor.rowcount:
                return  # книгу удалили во время распознавания

        doc = open_document(pdf_path)
        total = doc.page_count
        cursor.execute(
            "UPDATE textbooks SET status = 'indexing', page_count = %s, indexed_pages = 0,"
            " status_detail = NULL WHERE id = %s", (total, textbook_id))
        conn.commit()
        collected = []
        for start in range(0, total, TEXTBOOK_INDEX_CHUNK):
            pages = list(range(start, min(start + TEXTBOOK_INDEX_CHUNK, total)))
            chunk = _index_chunk(doc, pages)
            _store_pages(cursor, textbook_id, chunk)
            conn.commit()
            collected.extend(chunk)
            cursor.execute(
                "UPDATE textbooks SET indexed_pages = %s WHERE id = %s",
                (min(start + TEXTBOOK_INDEX_CHUNK, total), textbook_id))
            conn.commit()
            if progress:
                progress(len(collected), total)

        offset = _printed_offset(collected)
        cursor.execute(
            "UPDATE textbooks SET status = 'ready', printed_offset = %s, indexed_pages = %s,"
            " status_detail = NULL WHERE id = %s",
            (offset, total, textbook_id))
        conn.commit()
        log(f"[Textbook] {textbook_id}: проиндексировано {total} страниц, сдвиг нумерации {offset}")
        return {"pages": total, "printed_offset": offset}
    finally:
        if doc is not None:
            doc.close()
        cursor.close()
        conn.close()


def _index_chunk(doc, pages, allow_split=True):
    """одна пачка страниц. Недостающие страницы переспрашиваем поштучно"""
    parts = []
    for i in pages:
        data, mime = page_image(doc, i)
        parts.append({"text": f"pdf_index = {i}"})
        parts.append(gemini_client.image_part(data, mime))

    try:
        result, stats = gemini_client.generate(
            parts, schema=ai_prompts.INDEX_SCHEMA, system=ai_prompts.INDEX_SYSTEM)
    except gemini_client.GeminiError:
        # обрыв по лимиту вывода лечится половинкой пачки
        if allow_split and len(pages) > 1:
            half = len(pages) // 2
            return (_index_chunk(doc, pages[:half], allow_split=False)
                    + _index_chunk(doc, pages[half:], allow_split=False))
        raise

    got = {p["pdf_index"] for p in result}
    missing = [i for i in pages if i not in got]
    if missing and allow_split:
        log(f"[Textbook] Модель пропустила страницы {missing}, переспрашиваем поштучно")
        for i in missing:
            result.extend(_index_chunk(doc, [i], allow_split=False))
    log(f"[Textbook] Пачка {pages[0]}-{pages[-1]}: {stats['sec']}с, якорей "
        f"{sum(len(p.get('exercises') or []) for p in result)}")
    return result


def _store_pages(cursor, textbook_id, pages):
    for page in pages:
        cursor.execute("""
            INSERT INTO textbook_pages
                (textbook_id, pdf_index, printed_page, page_kind, paragraph_num,
                 paragraph_title, topic_summary, rules)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (textbook_id, pdf_index) DO UPDATE SET
                printed_page = EXCLUDED.printed_page,
                page_kind = EXCLUDED.page_kind,
                paragraph_num = EXCLUDED.paragraph_num,
                paragraph_title = EXCLUDED.paragraph_title,
                topic_summary = EXCLUDED.topic_summary,
                rules = EXCLUDED.rules
        """, (textbook_id, page["pdf_index"], page.get("printed_page"), page.get("page_kind"),
              _clean_paragraph(page.get("paragraph_num")), page.get("paragraph_title"),
              page.get("topic_summary"), json.dumps(page.get("rules") or [], ensure_ascii=False)))

        for exercise in page.get("exercises") or []:
            label = str(exercise.get("label", "")).strip()
            if not label:
                continue
            cursor.execute("""
                INSERT INTO textbook_exercises
                    (textbook_id, label, pdf_index, starts_here, continues_next_page)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (textbook_id, label, pdf_index) DO UPDATE SET
                    starts_here = EXCLUDED.starts_here,
                    continues_next_page = EXCLUDED.continues_next_page
            """, (textbook_id, label[:32], page["pdf_index"],
                  bool(exercise.get("starts_here", True)),
                  bool(exercise.get("continues_next_page", False))))


def _clean_paragraph(value):
    if not value:
        return None
    return str(value).replace("§", "").strip(" .") or None


def _printed_offset(pages):
    """сдвиг печатной нумерации берём по большинству, один битый колонтитул ничего не решает"""
    diffs = [p["printed_page"] - p["pdf_index"] for p in pages if p.get("printed_page")]
    if not diffs:
        return 0
    return Counter(diffs).most_common(1)[0][0]


def subject_key(value):
    """ключ предмета для сравнения: регистр, ё и пробелы роли не играют"""
    return re.sub(r"[^0-9a-zа-я]+", "", str(value or "").lower().replace("ё", "е"))


def find_textbook(cursor, grade_class, subject, kind="textbook"):
    """книга класса по предмету, общая книга школы тоже подойдёт
    в дневнике и в загруженном учебнике предмет пишут по разному
    ("Русский Язык" против "Русский язык"), поэтому сверяем не строки,
    а нормализованные ключи, иначе книга просто не находится и разбор
    молча остаётся без вырезок"""
    key = subject_key(subject)
    if not key:
        return None
    cursor.execute("""
        SELECT id, pdf_path, printed_offset, title, subject FROM textbooks
        WHERE status = 'ready' AND kind = %s
          AND (grade_class = %s OR grade_class IS NULL)
        ORDER BY (grade_class IS NULL), id DESC
    """, (kind, grade_class))
    rows = cursor.fetchall()

    row = next((r for r in rows if subject_key(r[4]) == key), None)
    if not row:
        # "Русский язык" и "Русский язык (родной)" это всё ещё одна книга,
        # но на коротких ключах такое совпадение уже случайное
        row = next((r for r in rows if len(subject_key(r[4])) >= 4
                    and (subject_key(r[4]).startswith(key) or key.startswith(subject_key(r[4])))), None)
    if not row:
        return None
    return {"id": row[0], "pdf_path": row[1], "printed_offset": row[2], "title": row[3]}


def exercise_page(cursor, textbook_id, label):
    """страница, где упражнение начинается"""
    cursor.execute("""
        SELECT pdf_index FROM textbook_exercises
        WHERE textbook_id = %s AND label = %s AND starts_here = TRUE
        ORDER BY pdf_index LIMIT 1
    """, (textbook_id, str(label)))
    row = cursor.fetchone()
    if row:
        return row[0]
    # номера в учебнике монотонны, так что дыру в индексе закрываем интерполяцией
    return _guess_page(cursor, textbook_id, label)


def _guess_page(cursor, textbook_id, label):
    if not str(label).isdigit():
        return None
    target = int(label)
    cursor.execute("""
        SELECT label, pdf_index FROM textbook_exercises
        WHERE textbook_id = %s AND starts_here = TRUE AND label ~ '^[0-9]+$'
    """, (textbook_id,))
    known = sorted((int(r[0]), r[1]) for r in cursor.fetchall())
    lower = [k for k in known if k[0] < target]
    upper = [k for k in known if k[0] > target]
    if not lower or not upper:
        return None
    (n0, p0), (n1, p1) = lower[-1], upper[0]
    if n1 == n0:
        return p0
    return round(p0 + (p1 - p0) * (target - n0) / (n1 - n0))


def paragraph_page(cursor, textbook_id, number):
    pages = paragraph_pages(cursor, textbook_id, number)
    return pages[0] if pages else None


def paragraph_pages(cursor, textbook_id, number):
    """все страницы параграфа подряд, но не больше трёх
    внутри параграфа искать нечего, теория занимает страницу целиком,
    поэтому и отдаём страницы как есть, без модели"""
    cursor.execute("""
        SELECT pdf_index FROM textbook_pages
        WHERE textbook_id = %s AND paragraph_num = %s
        ORDER BY pdf_index
    """, (textbook_id, str(number).strip(" §.")))
    return [row[0] for row in cursor.fetchall()][:MAX_PARAGRAPH_PAGES]


def printed_page(cursor, textbook_id, pdf_index):
    cursor.execute(
        "SELECT printed_page FROM textbook_pages WHERE textbook_id = %s AND pdf_index = %s",
        (textbook_id, pdf_index))
    row = cursor.fetchone()
    return row[0] if row else None


def locate(doc, textbook_id, label, pdf_index):
    """спросить у модели границы задания. Один запрос на упражнение, навсегда"""
    parts = [{"text": f"Страница 1. Найди упражнение {label}."}]
    data, mime = page_image(doc, pdf_index)
    parts.append(gemini_client.image_part(data, mime))
    for step in range(1, LOOKAHEAD_PAGES + 1):
        if pdf_index + step >= doc.page_count:
            break
        parts.append({"text": f"Страница {step + 1}."})
        data, mime = page_image(doc, pdf_index + step)
        parts.append(gemini_client.image_part(data, mime))

    result, stats = gemini_client.generate(
        parts, schema=ai_prompts.LOCATE_SCHEMA, system=ai_prompts.LOCATE_SYSTEM)
    log(f"[Textbook] Локализация {label} на стр. {pdf_index}: {stats['sec']}с, "
        f"хвостов {len(result.get('tails') or [])}")
    return result if result.get("found") else None


def get_box(cursor, doc, textbook_id, label, pdf_index):
    """границы задания из кэша, а если их там нет, считаем и кладём в кэш"""
    cursor.execute("""
        SELECT pdf_index, box, tails, subitems FROM textbook_boxes
        WHERE textbook_id = %s AND label = %s AND subitem = ''
    """, (textbook_id, str(label)))
    row = cursor.fetchone()
    if row:
        return {"pdf_index": row[0], "box_2d": row[1], "tails": row[2] or [],
                "subitems": row[3] or []}

    located = locate(doc, textbook_id, label, pdf_index)
    if not located:
        return None
    cursor.execute("""
        INSERT INTO textbook_boxes (textbook_id, label, subitem, pdf_index, box, tails, subitems)
        VALUES (%s, %s, '', %s, %s, %s, %s)
        ON CONFLICT (textbook_id, label, subitem) DO UPDATE SET
            pdf_index = EXCLUDED.pdf_index, box = EXCLUDED.box,
            tails = EXCLUDED.tails, subitems = EXCLUDED.subitems
    """, (textbook_id, str(label)[:32], pdf_index,
          json.dumps(located["box_2d"]),
          json.dumps(located.get("tails") or []),
          json.dumps(located.get("subitems") or [])))
    return {"pdf_index": pdf_index, "box_2d": located["box_2d"],
            "tails": located.get("tails") or [], "subitems": located.get("subitems") or []}


def _to_rect(page, box):
    pymupdf = _pymupdf()
    ymin, xmin, ymax, xmax = box
    rect = page.rect
    return pymupdf.Rect(xmin / 1000 * rect.width, ymin / 1000 * rect.height,
                        xmax / 1000 * rect.width, ymax / 1000 * rect.height)


def _embedded_scan(doc, page):
    """скан страницы как есть, если вся страница это одна вставленная картинка
    через него и режем: пережимать скан растеризатором незачем, он от этого
    только теряет чёткость"""
    from PIL import Image
    images = page.get_images(full=True)
    if len(images) != 1:
        return None
    try:
        bbox = page.get_image_bbox(images[0])
    except Exception:
        return None
    # картинка может стоять не на всю страницу, тогда координаты не сойдутся
    if (abs(bbox.x0) > 2 or abs(bbox.y0) > 2
            or abs(bbox.x1 - page.rect.width) > 2 or abs(bbox.y1 - page.rect.height) > 2):
        return None
    extracted = doc.extract_image(images[0][0])
    if extracted["ext"] not in ("jpeg", "jpg", "png"):
        return None
    return Image.open(io.BytesIO(extracted["image"])).convert("RGB")


def _render(doc, pdf_index, box):
    """кадр по боксу и его прямоугольник на странице"""
    from PIL import Image, ImageFilter
    pymupdf = _pymupdf()
    page = doc[pdf_index]
    clip = _to_rect(page, box)
    clip = pymupdf.Rect(max(0, clip.x0 - CROP_PADDING), max(0, clip.y0 - CROP_PADDING),
                        min(page.rect.width, clip.x1 + CROP_PADDING),
                        min(page.rect.height, clip.y1 + CROP_PADDING))

    scan = _embedded_scan(doc, page)
    if scan is not None:
        scale = scan.width / page.rect.width
        crop = scan.crop((max(0, round(clip.x0 * scale)), max(0, round(clip.y0 * scale)),
                          min(scan.width, round(clip.x1 * scale)),
                          min(scan.height, round(clip.y1 * scale))))
        if crop.width and crop.height:
            image = crop.resize((crop.width * CROP_UPSCALE, crop.height * CROP_UPSCALE),
                                Image.LANCZOS)
            # после увеличения буквы плывут, лёгкая резкость возвращает им края
            return image.filter(ImageFilter.UnsharpMask(radius=1.4, percent=110, threshold=2)), clip

    pixmap = page.get_pixmap(dpi=CROP_DPI, clip=clip)
    return Image.open(io.BytesIO(pixmap.tobytes("png"))).convert("RGB"), clip


def _stitch(images, gap=14):
    from PIL import Image
    width = max(i.width for i in images)
    height = sum(i.height for i in images) + gap * (len(images) - 1)
    canvas = Image.new("RGB", (width, height), "white")
    y = 0
    for image in images:
        canvas.paste(image, (0, y))
        y += image.height + gap
    return canvas


def _focus(doc, pdf_index, box, focus_box):
    """приглушаем всё кроме нужного пункта
    гасим кадр целиком и возвращаем обратно нужный кусок: если вместо этого
    закрашивать соседей по их боксам, у последних строк остаются непрокрашенные хвосты"""
    from PIL import ImageDraw
    image, clip = _render(doc, pdf_index, box)
    original = image.copy()
    scale = image.width / clip.width

    page = doc[pdf_index]
    focus = _to_rect(page, focus_box)
    x0 = max(0, int((focus.x0 - clip.x0) * scale) - 4)
    y0 = max(0, int((focus.y0 - clip.y0) * scale) - 4)
    x1 = min(image.width, int((focus.x1 - clip.x0) * scale) + 4)
    y1 = min(image.height, int((focus.y1 - clip.y0) * scale) + 4)
    if x1 <= x0 or y1 <= y0:
        return original

    ImageDraw.Draw(image, "RGBA").rectangle(
        [0, 0, image.width, image.height], fill=(255, 255, 255, DIM_ALPHA))
    image.paste(original.crop((x0, y0, x1, y1)), (x0, y0))
    ImageDraw.Draw(image).rectangle([x0, y0, x1 - 1, y1 - 1], outline=(103, 80, 164), width=3)
    return image


def _save(image, out_path):
    """кладём jpeg: исходник всё равно скан, а png раздувает его в разы"""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    if out_path.lower().endswith((".jpg", ".jpeg")):
        image.save(out_path, quality=92, optimize=True, progressive=True)
    else:
        image.save(out_path, optimize=True)


def crop_exercise(doc, box_info, out_path, subitem=None):
    """собрать картинку задания, склеив хвосты с соседних страниц"""
    pdf_index = box_info["pdf_index"]
    subitems = {s["label"]: s["box_2d"] for s in box_info.get("subitems") or []}

    if subitem and subitem in subitems:
        head = _focus(doc, pdf_index, box_info["box_2d"], subitems[subitem])
    else:
        head, _ = _render(doc, pdf_index, box_info["box_2d"])

    pieces = [head]
    for tail in sorted(box_info.get("tails") or [], key=lambda t: t.get("page_offset", 0)):
        index = pdf_index + int(tail.get("page_offset", 0))
        if index >= doc.page_count or index == pdf_index:
            continue
        piece, _ = _render(doc, index, tail["box_2d"])
        pieces.append(piece)

    result = pieces[0] if len(pieces) == 1 else _stitch(pieces)
    _save(result, out_path)
    return out_path


def render_page(doc, pdf_index, out_path):
    """страница целиком: так показываем параграф, который надо прочитать"""
    image, _ = _render(doc, pdf_index, [0, 0, 1000, 1000])
    _save(image, out_path)
    return out_path


def analysis_image_path(analysis_id, label, subitem=None, page=None):
    suffix = ("_" + subitem if subitem else "") + (f"_p{page}" if page is not None else "")
    safe = re.sub(r"[^0-9A-Za-zА-Яа-яЁё_-]+", "", f"{label}{suffix}") or "item"
    return os.path.join(ANALYSIS_IMAGE_FOLDER, str(analysis_id), f"{safe}.jpg")
