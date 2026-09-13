import re
from datetime import datetime, timedelta, timezone
from html import escape, unescape
from html.parser import HTMLParser


RICH_PAGE_BYTES = 24000
PLAIN_PAGE_UNITS = 3800
OFFICIAL_CHANNEL_URL = 'https://t.me/reSchool_off'
PLAIN_CHANNEL_FOOTER = f'reSchool ({OFFICIAL_CHANNEL_URL})'
_MONTHS = ('января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
           'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря')
_WEEKDAYS = ('понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье')
_DISPLAY_TIMEZONE = timezone(timedelta(hours=3), 'МСК')
_MD = re.compile(r'([\\`*_{}\[\]()#+\-.!|~=$>])')
_FORMULA = re.compile(r'\\\[(.+?)\\\]|\\\((.+?)\\\)|\$\$(.+?)\$\$|(?<!\\)\$([^$\n]+)\$', re.S)


def clean(value):
    text = str(value if value is not None else '')
    return ''.join(c for c in text if c in '\n\t' or (ord(c) >= 32 and not 0xD800 <= ord(c) <= 0xDFFF))


def md(value):
    return escape(_MD.sub(r'\\\1', clean(value)), quote=False)


def label(value, limit=240):
    text = ' '.join(clean(value).split())
    return text if len(text) <= limit else text[:limit - 1] + '…'


def chunks(text, limit, encoding='utf-8'):
    remaining = clean(text)
    while remaining:
        raw = remaining.encode(encoding)
        if len(raw) <= limit:
            yield remaining
            break
        piece = raw[:limit].decode(encoding, errors='ignore')
        boundary = max(piece.rfind('\n'), piece.rfind(' '))
        if boundary > len(piece) // 2:
            piece = piece[:boundary + 1]
        yield piece
        remaining = remaining[len(piece):]


class _SchoolText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden += 1
        if self.hidden:
            return
        attrs = dict(attrs)
        if tag in ('br', 'p', 'div', 'li', 'tr', 'blockquote'):
            self.parts.append('\n')
        if tag == 'li':
            self.parts.append('• ')
        if tag in ('td', 'th') and self.parts and not self.parts[-1].endswith('\n'):
            self.parts.append(' · ')
        if tag == 'img':
            self.parts.append(attrs.get('alt') or '[Изображение]')
        if tag == 'math' and attrs.get('alttext'):
            self.parts.append('\\(' + attrs['alttext'] + '\\)')

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)
        elif not self.hidden and tag in ('p', 'div', 'li', 'tr', 'blockquote'):
            self.parts.append('\n')

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def school_text(value):
    text = clean(value)
    # обычное неравенство не должно превратиться в незакрытый html тег
    if re.search(r'</?(?:p|div|br|span|b|i|strong|em|ul|ol|li|table|tr|td|th|img|math|script|style)\b[^>]*>', text, re.I):
        parser = _SchoolText()
        parser.feed(text)
        parser.close()
        text = ''.join(parser.parts)
    return re.sub(r'\n[ \t]*\n(?:[ \t]*\n)+', '\n\n', text).strip()


def math_text(text):
    return _math_markup(text, md)


def _math_markup(text, escape_text):
    parts, offset = [], 0
    for match in _FORMULA.finditer(text):
        parts.append(escape_text(text[offset:match.start()]))
        formula = next(group for group in match.groups() if group is not None)
        if len(formula) <= 2000:
            parts.append('<tg-math>' + escape(formula) + '</tg-math>')
        else:
            parts.append(escape_text(match.group()))
        offset = match.end()
    parts.append(escape_text(text[offset:]))
    return ''.join(parts)


class _SchoolMarkup(HTMLParser):
    allowed = {'p', 'b', 'strong', 'i', 'em', 'u', 's', 'sub', 'sup', 'code', 'pre',
               'ul', 'ol', 'li', 'table', 'tr', 'td', 'th', 'blockquote'}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.stack = [], []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden += 1
        if self.hidden:
            return
        if tag == 'br':
            self.parts.append('<br>')
        elif tag == 'img':
            self.parts.append(escape(dict(attrs).get('alt') or '[Изображение]'))
        elif tag in self.allowed and len(self.stack) < 8:
            self.parts.append('<table striped compact>' if tag == 'table' else f'<{tag}>')
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)
        elif not self.hidden and tag in self.stack:
            while self.stack:
                closed = self.stack.pop()
                self.parts.append(f'</{closed}>')
                if closed == tag:
                    break

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(escape(data) if any(tag in self.stack for tag in ('code', 'pre')) else _math_markup(data, escape))

    def rendered(self):
        return ''.join(self.parts) + ''.join(f'</{tag}>' for tag in reversed(self.stack))


def date_label(value):
    if isinstance(value, datetime):
        return f'{value.day} {_MONTHS[value.month - 1]}, {_WEEKDAYS[value.weekday()]}'
    try:
        parsed = datetime.fromisoformat(str(value))
        return f'{parsed.day} {_MONTHS[parsed.month - 1]} {parsed.year}'
    except (ValueError, TypeError):
        return clean(value) or 'Дата не указана'


def moment(value, *, plain=False):
    if not value:
        return 'Ещё не было'
    try:
        dt = value if isinstance(value, datetime) else datetime.fromtimestamp(float(value) / 1000, timezone.utc)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        unix = int(dt.timestamp())
        text = dt.astimezone(_DISPLAY_TIMEZONE).strftime('%d.%m.%Y %H:%M %Z')
        return text if plain else f'<tg-time unix="{unix}" format="dT">{escape(text)}</tg-time>'
    except (ValueError, TypeError, OverflowError, OSError):
        return clean(value) if plain else md(value)


class Card:
    def __init__(self, title):
        self.title = label(title)
        self.parts = []

    def add(self, rich, plain):
        self.parts.append((rich, clean(plain)))
        return self

    def text(self, value, *, quote=False, formulas=False, collapse=None, keep_lines=False):
        raw = clean(value)
        if formulas and not quote and not collapse and len(raw.encode()) <= 6000 and re.search(r'<(?:p|ul|ol|table|b|strong|pre)\b', raw):
            parser = _SchoolMarkup()
            parser.feed(raw)
            parser.close()
            rich = parser.rendered()
            if len(rich.encode()) < 16000 and len(re.findall(r'<\w', rich)) < 100:
                return self.add(rich, school_text(raw))
        text = school_text(value) if formulas else clean(value).strip()
        for piece in chunks(text, 4500):
            rich = math_text(piece) if formulas else md(piece)
            if keep_lines:
                # rich markdown склеивает переносы на телефоне, поэтому сохраняем строки учителя отдельно от формул
                rich = re.sub(r'(<tg-math>.*?</tg-math>)|\n',
                              lambda match: match.group(1) or '<br>', rich, flags=re.S)
            if quote:
                rich = '<blockquote expandable>' + escape(piece).replace('\n', '<br>') + '</blockquote>'
            if collapse:
                rich = f'<details><summary>{md(collapse)}</summary>\n\n{rich}\n\n</details>'
            self.add(rich, piece)
        return self

    def section(self, title):
        return self.add('### ' + md(label(title)), label(title))

    def fact(self, name, value, *, marked=False):
        value = label(value, 1000)
        rich = ('==' + md(value) + '==') if marked else md(value)
        return self.add(f'**{md(name)}** · {rich}', f'{name}: {value}')

    def table(self, headers, rows):
        rows = list(rows)
        # небольшие таблицы помещаются на телефон и делятся только между строками
        for start in range(0, len(rows), 12):
            batch = [[label(v, 600) for v in row] for row in rows[start:start + 12]]
            rich = '<table striped compact><tr>' + ''.join('<th>' + escape(str(h)) + '</th>' for h in headers) + '</tr>'
            for row in batch:
                rich += '<tr>' + ''.join('<td>' + escape(v) + '</td>' for v in row) + '</tr>'
            rich += '</table>'
            plain = '\n\n'.join('\n'.join(f'{h}: {v}' for h, v in zip(headers, row)) for row in batch)
            self.add(rich, plain)
        return self

    def footer(self, value='reSchool'):
        value = label(value, 1000)
        link = f'<a href="{OFFICIAL_CHANNEL_URL}">reSchool</a>'
        rich = escape(value).replace('reSchool', link, 1)
        plain = value.replace('reSchool', PLAIN_CHANNEL_FOOTER, 1)
        return self.add('<footer>' + rich + '</footer>', plain)

    def pages(self):
        header = '## ' + md(self.title)
        pages, current = [], []
        size, block_count = len(header.encode('utf-8')), 1
        for rich, plain in self.parts:
            part_size = len(rich.encode('utf-8')) + 2
            if part_size > RICH_PAGE_BYTES - 2000:
                # длинный внешний фрагмент сохраняем целиком, без разрезанных тегов
                pieces = [(md(p), p) for p in chunks(plain, 4500)]
            else:
                pieces = [(rich, plain)]
            for item in pieces:
                item_size = len(item[0].encode('utf-8')) + 2
                item_blocks = 1 + len(re.findall(r'<(?:tr|li|details|blockquote)\b|^#{1,6} ', item[0], re.M))
                if current and (size + item_size > RICH_PAGE_BYTES or block_count + item_blocks > 300 or len(current) >= 60):
                    pages.append(current)
                    current, size = [], len(header.encode('utf-8'))
                    block_count = 1
                current.append(item)
                size += item_size
                block_count += item_blocks
        pages.append(current)
        return [(header + (f' · {i + 1}/{len(pages)}' if len(pages) > 1 else '') + '\n\n' + '\n\n'.join(p[0] for p in page),
                 self.title + '\n\n' + '\n\n'.join(p[1] for p in page)) for i, page in enumerate(pages)]


def notice(text):
    head, _, body = clean(text).partition('\n')
    if len(head) > 160:
        return Card('reSchool').text(text)
    card = Card(head)
    return card.text(body)


def homework(items, target_date):
    card = Card('📚 Домашние задания').text(date_label(target_date))
    if not items:
        return card.text('На этот день заданий нет.').footer('reSchool · Дневник')
    for item in items:
        card.section(item.get('subject') or 'Предмет')
        card.text(item.get('text') or ('Задание во вложении.' if item.get('hasFiles') else 'Текст задания не указан.'), formulas=True)
        if item.get('hasFiles'):
            card.add('<footer>📎 Вложения доступны в reSchool</footer>', '📎 Вложения доступны в reSchool')
    return card.footer('reSchool · Дневник')


def grades(items, period_name=None, limit=20):
    card = Card('📝 Оценки').text(period_name or 'Текущий период')
    if not items:
        return card.text('За этот период оценок пока нет.').footer('reSchool · Успеваемость')
    rows = []
    for item in items[:limit]:
        avg = item.get('average')
        avg_text = f'{avg:.2f}' if isinstance(avg, (int, float)) else avg
        rows.append((item.get('subject') or 'Предмет', avg_text if avg is not None else '-', item.get('final') or '-'))
    card.table(('Предмет', 'Средний', 'Итог'), rows)
    for item in items[:limit]:
        values = ' · '.join(str(g) for g in item.get('grades', [])) or 'Оценок пока нет'
        if item.get('rating') is not None:
            values += f'\nРейтинг: {item["rating"]}'
        card.text(values, collapse=label(item.get('subject') or 'Предмет') + ' · все оценки')
    if len(items) > limit:
        card.text(f'Ещё {len(items) - limit} предметов доступны в reSchool.')
    return card.add('/period · Выбрать другой период', '/period · Выбрать другой период').footer('reSchool · Успеваемость')


def periods(items, selected_id=None):
    card = Card('📅 Учебные периоды')
    if not items:
        return card.text('Учебные периоды пока не найдены.')
    years = {}
    for item in items:
        years.setdefault(str(item.get('schoolYear') or 'Учебный год'), []).append(item)
    for year in sorted(years, reverse=True):
        card.section(year)
        for item in sorted(years[year], key=lambda p: p.get('date1') or 0):
            name = label(item.get('name') or 'Период')
            flags = ' · выбран' if item.get('id') == selected_id else ' · текущий' if item.get('isCurrent') else ''
            command = '/period ' + label(item.get('id'), 30)
            card.add(f'**{md(name + flags)}**\n\n<code>{escape(command)}</code>', f'{name}{flags}\n{command}')
    return card.footer('Нажмите на команду, чтобы скопировать её и выбрать период')


def _conversation_text(value, limit):
    text = unescape(school_text(value)).replace('\u200b', '').replace('\ufeff', '')
    return label(text, limit)


def messages(items, limit=5, offset=0):
    card = Card('💬 Беседы eSchool')
    if not items:
        return card.text('Бесед пока нет.').footer('reSchool · Сообщения')
    limit = max(1, min(int(limit), 10))
    offset = max(0, min(int(offset), ((len(items) - 1) // limit) * limit))
    card.text(f'Беседы {offset + 1}-{min(offset + limit, len(items))} из {len(items)}')
    for index, item in enumerate(items[offset:offset + limit], offset + 1):
        subject = _conversation_text(item.get('subject'), 160)
        contact = _conversation_text(item.get('contactName'), 160) if str(item.get('dlgType')) == '1' else ''
        title = contact or subject or ('Групповая беседа без названия' if str(item.get('dlgType')) == '2' else 'Личная беседа')
        preview = _conversation_text(item.get('preview'), 240)
        if not preview:
            preview = f'Вложения: {item["attachmentCount"]}' if item.get('attachmentCount') else 'Текст сообщения недоступен.'
        meta_rich, meta_plain = [], []
        if item.get('unreadCount'):
            unread = 'Непрочитанных: ' + label(item['unreadCount'], 20)
            meta_rich.append(md(unread))
            meta_plain.append(unread)
        date = item.get('displayDate') or item.get('date')
        if date:
            meta_rich.append(moment(date))
            meta_plain.append(moment(date, plain=True))
        heading = f'{index}. {title}'
        rich = '**' + md(heading) + '**\n\n' + md(preview)
        plain = heading + '\n' + preview
        if meta_rich:
            rich += '\n\n<footer>' + ' · '.join(meta_rich) + '</footer>'
            plain += '\n' + ' · '.join(meta_plain)
        # название и текст одной беседы должны оставаться на одной странице
        card.add(rich, plain)
    return card.footer('reSchool · Сообщения')


def notification(title, body, kind=None, data=None, analysis=None):
    data = data or {}
    if kind == 'message' and data.get('sender'):
        card = Card('💬 ' + (data.get('subject') or 'Новое сообщение'))
        card.fact('От', data['sender']).text(body, quote=True)
        if data.get('sent_at'):
            card.add(moment(data['sent_at']), date_label(data['sent_at']))
        return card.footer('reSchool · Сообщения')
    if kind == 'grade' and data.get('value') is not None:
        title = '✏️ Оценка изменена' if 'измен' in title.lower() else '📝 Новая оценка'
    card = Card(title)
    if kind == 'homework':
        if data.get('date'):
            card.fact('К уроку', date_label(data['date']))
        if data.get('author'):
            card.fact('Автор', data['author'])
        if data.get('attachmentCount'):
            card.fact('📎 Вложений', data['attachmentCount'])
        lines = clean(body).splitlines()
        if lines and (lines[0].startswith('Дата:') or lines[0].startswith('Дата урока:')):
            if not data.get('date'):
                card.text(lines[0])
            lines = lines[1:]
        if analysis:
            summary_start = next((i for i, line in enumerate(lines) if line.startswith(('⏱ примерно', '📎 Оценить не получилось'))), len(lines))
            lines = lines[:summary_start]
        card.section('📝 Задание')
        card.text('\n'.join(lines), formulas=True, keep_lines=True)
        if analysis and analysis.get('estimable') is not False and (analysis.get('total_minutes') or analysis.get('items')):
            card.section('⏱ План работы')
            if analysis.get('total_minutes'):
                span = ''
                low, high = analysis.get('range_min'), analysis.get('range_max')
                if low and high and low != high:
                    span = f' · диапазон {low}-{high} мин'
                card.fact('Примерное время', f'{analysis["total_minutes"]} мин{span}')
            # вертикальные блоки заданий читаются и на узких экранах
            for number, item in enumerate(analysis.get('items', []), 1):
                heading = f'{number}. ' + label(item.get('label') or 'Задание', 600)
                facts = []
                if item.get('minutes'):
                    facts.append(f'⏱ {item["minutes"]} мин')
                if item.get('difficulty'):
                    facts.append(f'Сложность: {item["difficulty"]}/5')
                detail = ' · '.join(facts)
                card.add('**' + md(heading) + '**' + ('<br>' + md(detail) if detail else ''),
                         heading + ('\n' + detail if detail else ''))
                if item.get('note'):
                    card.text(item['note'], keep_lines=True)
                if item.get('mode_conflict'):
                    card.text('⚠️ ' + str(item['mode_conflict']))
        elif analysis:
            card.text('Оценка времени недоступна. ' + str(analysis.get('unestimable_reason') or 'Недостаточно данных о задании.'))
    elif kind == 'grade':
        if data.get('value') is not None:
            card.fact('Оценка', data['value'], marked=True)
        rows = []
        for line in clean(body).splitlines():
            key, separator, value = line.partition(': ')
            if separator:
                rows.append((key, value))
            else:
                card.text(line)
        card.table(('Об уроке', 'Значение'), rows)
    else:
        card.text(body)
    return card.footer('reSchool')


def welcome(help_page=False):
    card = Card('reSchool · Справка' if help_page else '👋 reSchool')
    card.text('Домашние задания, оценки и сообщения из eSchool в одном чате.')
    card.table(('Что посмотреть', 'Команда'), [
        ('Домашние задания', '/dz'), ('Оценки за период', '/grades'),
        ('Учебные периоды', '/period'), ('Беседы eSchool', '/messages'),
    ])
    card.text('Домашние задания на выбранную дату: /dz 04.03 или /dz 04.03.2026. Кнопки под заданием переключают день.')
    card.text('/status · Состояние уведомлений\n/retry · Восстановить подключение\n/passwd · Обновить пароль eSchool\n/cancel · Отменить ввод', collapse='Подключение и уведомления')
    card.text('/gen · Получить код подключения группы\n/activate КОД · Отправить в группе\n/l · Узнать номера предметов\n/t ID_ПРЕДМЕТА ID_ТЕМЫ · Привязать предмет к теме\n\nДомашние задания и уведомления об оценках поступают в настроенные темы. Значения оценок остаются в личном чате. Пересылка бесед включается отдельно в reSchool.', collapse='Группа класса')
    if help_page:
        card.text('/homework и /dz · Домашние задания\n/grades, /marks и /ocenki · Оценки\n/messages и /msg · Беседы\n/start · Главное меню\n/help · Эта справка', collapse='Все короткие команды')
    return card.footer('Настройки бота: reSchool → Облачные функции → Telegram')
