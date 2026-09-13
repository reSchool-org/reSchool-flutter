"""публичный шлюз передаёт только sdp, данные входа к api через него не идут"""
import asyncio
import base64
import hashlib
import hmac
import json
import ipaddress
import os
import secrets
import time
from collections import defaultdict, deque
from aiohttp import web, WSMsgType
from .identity import server_id, verify


def create_app():
    app = web.Application(client_max_size=131072)
    servers = {}
    pending = {}
    sockets = set()
    timers = set()
    rate = defaultdict(deque)
    origins = set(os.getenv('BROWSER_ALLOWED_ORIGINS', 'https://reschool.app').split(','))

    def limited(peer):
        now = time.monotonic()
        # ограничиваем число корзин источников, даже если клиент постоянно меняет адрес
        if len(rate) > 4096:
            for key in list(rate):
                if not rate[key] or rate[key][-1] < now - 60:
                    rate.pop(key, None)
            if len(rate) > 4096 and peer not in rate:
                return True
        hits = rate[peer]
        while hits and hits[0] < now - 60:
            hits.popleft()
        if len(hits) >= 30:
            return True
        hits.append(now)
        return False

    def ice_servers():
        urls = [x for x in os.getenv('BROWSER_STUN_URLS', '').split(',') if x]
        result = [{'urls': urls}] if urls else []
        turn_urls = [x for x in os.getenv('BROWSER_TURN_URLS', '').split(',') if x]
        secret = os.getenv('BROWSER_TURN_SECRET', '')
        if turn_urls and secret:
            username = f'{int(time.time()) + 3600}:reschool:{secrets.token_urlsafe(12)}'
            credential = base64.b64encode(hmac.new(secret.encode(), username.encode(), hashlib.sha1).digest()).decode()
            result.append({'urls': turn_urls, 'username': username, 'credential': credential})
        return result

    async def signal(request):
        origin = request.headers.get('Origin')
        # агенты не отправляют Origin, а браузеры должны приходить с адреса приложения
        if origin and origin not in origins:
            raise web.HTTPForbidden()
        peer = request.remote or 'unknown'
        # адрес клиента доверяем только обратному прокси на loopback
        if peer in ('127.0.0.1', '::1') and request.headers.get('X-Real-IP'):
            try:
                peer = str(ipaddress.ip_address(request.headers['X-Real-IP']))
            except ValueError:
                raise web.HTTPBadRequest()
        if len(sockets) >= 1024 or limited(peer):
            raise web.HTTPTooManyRequests()
        ws = web.WebSocketResponse(heartbeat=25, max_msg_size=131072, compress=False)
        await ws.prepare(request)
        sockets.add(ws)
        nonce = secrets.token_urlsafe(32)
        registered = None
        client_request = None
        async def handshake_deadline():
            await asyncio.sleep(15)
            if registered is None and client_request is None:
                await ws.close()
        handshake = asyncio.create_task(handshake_deadline())
        await ws.send_json({'type': 'challenge', 'nonce': nonce, 'iceServers': ice_servers()})
        try:
            async for message in ws:
                if message.type != WSMsgType.TEXT:
                    continue
                data = json.loads(message.data)
                if not isinstance(data, dict):
                    break
                kind = data.get('type')
                if kind == 'register' and not origin and registered is None and client_request is None:
                    public = data.get('key', '')
                    identity = server_id(public)
                    if not verify(public, 'reschool-register-v1\n' + nonce, data.get('signature', '')):
                        break
                    previous = servers.get(identity)
                    if previous:
                        await previous.close()
                    registered = identity
                    servers[identity] = ws
                    await ws.send_json({'type': 'registered', 'id': identity})
                elif kind == 'offer' and registered is None and client_request is None:
                    identity = data.get('serverId', '')
                    target = servers.get(identity)
                    sdp = data.get('sdp', '')
                    challenge = data.get('challenge', '')
                    if not isinstance(sdp, str) or len(sdp) > 100000 or not isinstance(challenge, str) or len(challenge) != 43:
                        break
                    if not target or target.closed:
                        await ws.send_json({'type': 'error', 'message': 'Сервер сейчас недоступен'})
                        break
                    if len(pending) >= 512 or limited(peer):
                        break
                    client_request = secrets.token_urlsafe(24)
                    pending[client_request] = (ws, identity)
                    # адрес источника определяем здесь, браузеру его задавать нельзя
                    await target.send_json({'type': 'offer', 'requestId': client_request, 'sdp': sdp, 'challenge': challenge, 'clientIp': peer, 'iceServers': ice_servers()})
                    async def expire(identifier):
                        await asyncio.sleep(45)
                        item = pending.pop(identifier, None)
                        if item:
                            await item[0].close()
                    timer = asyncio.create_task(expire(client_request))
                    timers.add(timer)
                    timer.add_done_callback(timers.discard)
                elif kind in ('answer', 'error') and registered:
                    identifier = data.get('requestId', '')
                    item = pending.get(identifier)
                    if not item or item[1] != registered:
                        continue
                    pending.pop(identifier, None)
                    if not item[0].closed:
                        await item[0].send_json(data)
                else:
                    break
        except (ValueError, TypeError, KeyError):
            pass
        finally:
            handshake.cancel()
            sockets.discard(ws)
            if registered and servers.get(registered) is ws:
                servers.pop(registered, None)
            if client_request:
                pending.pop(client_request, None)
            await ws.close()
        return ws

    async def shutdown(_):
        for timer in list(timers):
            timer.cancel()
        await asyncio.gather(*list(timers), return_exceptions=True)
        await asyncio.gather(*(ws.close() for ws in list(sockets)), return_exceptions=True)

    app.router.add_get('/signal', signal)
    async def health(request):
        return web.json_response({'ok': True})

    app.router.add_get('/health', health)
    app.on_shutdown.append(shutdown)
    return app


if __name__ == '__main__':
    web.run_app(create_app(), host=os.getenv('GATEWAY_HOST', '127.0.0.1'), port=int(os.getenv('GATEWAY_PORT', '8787')), access_log=None)
