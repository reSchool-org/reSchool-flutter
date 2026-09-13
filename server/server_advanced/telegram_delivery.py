import json
from html import escape
from types import SimpleNamespace

from telebot import apihelper
from telebot.types import InputRichMessage

from .telegram_formatting import Card, PLAIN_PAGE_UNITS, PLAIN_CHANNEL_FOOTER, OFFICIAL_CHANNEL_URL, chunks, notice


def _format_rejected(error):
    code = getattr(error, 'error_code', None)
    description = str(getattr(error, 'description', '')).lower()
    if code == 404 and ('method' in description or 'not found' in description):
        return True
    return code == 400 and any(word in description for word in (
        'rich', 'parse', 'entit', 'block', 'too long', 'media', 'file', 'photo', 'document',
    ))


def _plain_pages(text):
    for piece in chunks(text, PLAIN_PAGE_UNITS * 2, 'utf-16-le'):
        title, separator, body = piece.partition('\n')
        rendered = '<b>' + escape(title) + '</b>' + ('\n' + escape(body) if separator else '')
        # в запасном формате html сохраняем только нашу фиксированную ссылку
        # разметку школьного текста всегда экранируем
        yield rendered.replace(escape(PLAIN_CHANNEL_FOOTER),
                               f'<a href="{OFFICIAL_CHANNEL_URL}">reSchool</a>')


def send_card(bot, chat_id, content, *, reply_markup=None, message_thread_id=None,
              reply_parameters=None, media=None, files=None):
    card = content if isinstance(content, Card) else notice(content)
    pages = card.pages()
    media_sent, all_rich, result = False, True, None
    for index, (rich, plain) in enumerate(pages):
        last = index == len(pages) - 1
        has_media = bool(media) and any(f'tg://{kind}?id=' in rich for kind in ('photo', 'document'))
        kwargs = {'chat_id': chat_id}
        if message_thread_id is not None:
            kwargs['message_thread_id'] = message_thread_id
        if reply_parameters is not None and index == 0:
            kwargs['reply_parameters'] = reply_parameters
        if reply_markup is not None and last:
            kwargs['reply_markup'] = reply_markup
        try:
            if has_media:
                # sdk пока теряет файлы при отправке rich, передаём multipart через его транспорт
                payload = {k: v.to_json() if hasattr(v, 'to_json') else v for k, v in kwargs.items()}
                payload['rich_message'] = json.dumps({'markdown': rich, 'media': media}, ensure_ascii=False)
                result = apihelper._make_request(bot.token, 'sendRichMessage', params=payload,
                                                 files=files or None, method='post')
                media_sent = True
            else:
                result = bot.send_rich_message(rich_message=InputRichMessage(markdown=rich), **kwargs)
        except apihelper.ApiTelegramException as error:
            # только явный отказ api разрешает запасную отправку, таймаут мог прийти уже после доставки
            if not _format_rejected(error):
                raise
            all_rich = False
            plain_pages = list(_plain_pages(plain))
            for part_index, text in enumerate(plain_pages):
                fallback = dict(kwargs)
                if part_index:
                    fallback.pop('reply_parameters', None)
                if part_index != len(plain_pages) - 1:
                    fallback.pop('reply_markup', None)
                result = bot.send_message(text=text, parse_mode='HTML', disable_web_page_preview=True, **fallback)
    return SimpleNamespace(message=result, rich=all_rich, media_sent=media_sent)


def edit_card(bot, chat_id, message_id, content, *, reply_markup=None):
    card = content if isinstance(content, Card) else notice(content)
    pages = card.pages()
    rich, plain = pages[0]
    try:
        result = bot.edit_message_text(chat_id=chat_id, message_id=message_id,
                                       rich_message=InputRichMessage(markdown=rich), reply_markup=reply_markup)
    except apihelper.ApiTelegramException as error:
        if error.error_code == 400 and 'message is not modified' in error.description.lower():
            return None
        if not _format_rejected(error):
            raise
        plain_pages = list(_plain_pages(plain))
        result = bot.edit_message_text(chat_id=chat_id, message_id=message_id, text=plain_pages[0],
                                       parse_mode='HTML', disable_web_page_preview=True, reply_markup=reply_markup)
        for text in plain_pages[1:]:
            bot.send_message(chat_id=chat_id, text=text, parse_mode='HTML', disable_web_page_preview=True)
    for rich_part, plain_part in pages[1:]:
        continuation = Card(card.title)
        continuation.add(rich_part.partition('\n\n')[2], plain_part.partition('\n\n')[2])
        send_card(bot, chat_id, continuation)
    return result
