import json
from html import escape
from types import SimpleNamespace

from telebot import apihelper
from telebot.types import InputRichMessage

from .telegram_formatting import Card, PLAIN_PAGE_UNITS, PLAIN_CHANNEL_FOOTER, OFFICIAL_CHANNEL_URL, chunks, notice
from .logging_utils import log
from .telegram_diagnostics import delivery_log, error_details


def _format_rejected(error):
    code = getattr(error, 'error_code', None)
    description = str(getattr(error, 'description', '')).lower()
    if code == 404 and ('method' in description or 'not found' in description):
        return True
    return code == 400 and any(word in description for word in (
        'rich', 'parse', 'entit', 'block', 'too long', 'media', 'file', 'photo', 'document',
        'failed to get http url content',
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
              reply_parameters=None, media=None, files=None, delivery_id=None,
              progress=None, checkpoint=None):
    card = content if isinstance(content, Card) else notice(content)
    progress = progress if progress is not None else {}
    save = checkpoint or (lambda value: None)
    # сохраняем разбиение, чтобы обновление форматтера между попытками
    # не меняло номера страниц уже отправленного сообщения
    if 'rendered_pages' not in progress:
        progress['rendered_pages'] = card.pages()
        save(progress)
    pages = progress['rendered_pages']
    states = progress.setdefault('pages', {})
    result = None
    for index, (rich, plain) in enumerate(pages):
        state = states.setdefault(str(index), {'message_ids': [], 'next_part': 0})
        if state.get('done'):
            continue
        last = index == len(pages) - 1
        has_media = bool(media) and any(f'tg://{kind}?id=' in rich for kind in ('photo', 'document'))
        kwargs = {'chat_id': chat_id}
        if message_thread_id is not None:
            kwargs['message_thread_id'] = message_thread_id
        if reply_parameters is not None and index == 0:
            kwargs['reply_parameters'] = reply_parameters
        if reply_markup is not None and last:
            kwargs['reply_markup'] = reply_markup
        if state.get('mode') != 'plain':
            try:
                if has_media:
                    payload = {k: v.to_json() if hasattr(v, 'to_json') else v for k, v in kwargs.items()}
                    payload['rich_message'] = json.dumps({'markdown': rich, 'media': media}, ensure_ascii=False)
                    result = apihelper._make_request(bot.token, 'sendRichMessage', params=payload,
                                                     files=files or None, method='post')
                else:
                    result = bot.send_rich_message(rich_message=InputRichMessage(markdown=rich), **kwargs)
            except apihelper.ApiTelegramException as error:
                delivery_log(log, 'rich_rejected', delivery_id=delivery_id, chat_id=str(chat_id),
                             topic_id=message_thread_id, page=index + 1,
                             fallback=_format_rejected(error), **error_details(error, (bot.token,)))
                if not _format_rejected(error):
                    raise
                state['mode'] = 'plain'
                save(progress)
            else:
                message_id = result.get('message_id') if isinstance(result, dict) else result.message_id
                state.update(done=True, mode='rich', media_sent=has_media, message_ids=[message_id])
                delivery_log(log, 'page_delivered', delivery_id=delivery_id, chat_id=str(chat_id),
                             topic_id=message_thread_id, page=index + 1, message_ids=[message_id], media_sent=has_media)
                save(progress)
        if not state.get('done'):
            plain_pages = list(_plain_pages(plain))
            for part_index in range(state['next_part'], len(plain_pages)):
                fallback = dict(kwargs)
                if part_index:
                    fallback.pop('reply_parameters', None)
                if part_index != len(plain_pages) - 1:
                    fallback.pop('reply_markup', None)
                result = bot.send_message(text=plain_pages[part_index], parse_mode='HTML', disable_web_page_preview=True, **fallback)
                state['message_ids'].append(result.message_id)
                state['next_part'] = part_index + 1
                state['done'] = state['next_part'] == len(plain_pages)
                delivery_log(log, 'page_delivered', delivery_id=delivery_id, chat_id=str(chat_id),
                             topic_id=message_thread_id, page=index + 1, part=part_index + 1,
                             message_ids=[result.message_id], media_sent=False)
                save(progress)
    progress['card_complete'] = True
    save(progress)
    return SimpleNamespace(message=result,
                           rich=all(s.get('mode') == 'rich' for s in states.values()),
                           media_sent=any(s.get('media_sent') for s in states.values()),
                           message_ids=[mid for s in states.values() for mid in s['message_ids']])


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
