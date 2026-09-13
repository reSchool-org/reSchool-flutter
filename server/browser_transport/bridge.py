"""агент личного сервера подписывает сигнализацию и передаёт запросы webrtc во flask"""
import asyncio
import hashlib
import ipaddress
import json
import os
import time
from urllib.parse import urlsplit
from aiohttp import ClientSession, ClientTimeout, DummyCookieJar, WSMsgType
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCConfiguration, RTCIceServer
from .identity import load_identity, public_key, server_id, sign, connection_code

MAX_BODY = 32 * 1024 * 1024
CHUNK = 16 * 1024
DROP_HEADERS = {'host', 'connection', 'content-length', 'transfer-encoding', 'upgrade', 'forwarded', 'origin', 'referer', 'cookie', 'set-cookie', 'accept-encoding', 'proxy-authorization'}


def clean_request(metadata):
    method = metadata.get('method')
    path = metadata.get('path', '')
    if not isinstance(path, str) or len(path) > 16384:
        raise ValueError('Invalid API path')
    if method not in {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'}:
        raise ValueError('Method not allowed')
    parsed = urlsplit(path)
    if not path.startswith('/') or path.startswith('//') or parsed.scheme or parsed.netloc or parsed.fragment or '\\' in path or any(ord(c) < 32 for c in path):
        raise ValueError('Invalid API path')
    size = metadata.get('bodyLength', 0)
    if type(size) is not int or not 0 <= size <= MAX_BODY:
        raise ValueError('Request too large')
    raw_headers = metadata.get('headers', {})
    if not isinstance(raw_headers, dict) or len(raw_headers) > 64:
        raise ValueError('Invalid headers')
    headers = {}
    for name, value in raw_headers.items():
        if not isinstance(name, str) or not isinstance(value, str) or len(name) + len(value) > 16384 or '\r' in name + value or '\n' in name + value:
            raise ValueError('Invalid header')
        lower = name.lower()
        if lower not in DROP_HEADERS and not lower.startswith(('x-forwarded-', 'access-control-', 'sec-')):
            headers[name] = value
    return method, path, headers, size


async def run_bridge():
    signal = os.getenv('BROWSER_SIGNAL_URL', 'wss://reschool.app/signal')
    if urlsplit(signal).scheme != 'wss' and os.getenv('BROWSER_ALLOW_INSECURE_SIGNALING') != 'true':
        raise RuntimeError('Signaling requires WSS (except explicit local development)')
    backend = os.getenv('BROWSER_BACKEND_URL', 'http://127.0.0.1:20001').rstrip('/')
    if backend != 'http://127.0.0.1:20001':
        raise RuntimeError('Browser bridge may only access the local reSchool API')
    runtime = os.getenv('BROWSER_RUNTIME_DIR', '/app/runtime')
    key = load_identity(runtime)
    public = public_key(key)
    identity = server_id(public)
    public_signal = os.getenv('BROWSER_SIGNAL_PUBLIC_URL', signal)
    native_url = os.getenv('BROWSER_SERVER_URL', 'https://127.0.0.1:4443').rstrip('/')
    code = connection_code(key, public_signal, native_url)
    from pathlib import Path
    Path(runtime, 'connection-code.txt').write_text(code + '\n')
    print('Browser connection code (contains public identity only):\n' + code, flush=True)
    peers = set()
    tasks = set()
    buffered = 0
    forwarding = asyncio.Semaphore(4)

    def spawn(coro):
        task = asyncio.create_task(coro)
        tasks.add(task)
        def completed(result):
            tasks.discard(result)
            if not result.cancelled() and result.exception():
                print('Browser request failed:', type(result.exception()).__name__, flush=True)
        task.add_done_callback(completed)
        return task

    async with ClientSession(cookie_jar=DummyCookieJar(), auto_decompress=True, timeout=ClientTimeout(total=180)) as http:
        async def handle_offer(ws, offer):
            identifier = offer['requestId']
            if len(peers) >= 24:
                await ws.send_json({'type': 'error', 'requestId': identifier, 'message': 'Сервер занят, попробуйте позже'})
                return
            ice = [RTCIceServer(**entry) for entry in offer.get('iceServers', [])]
            pc = RTCPeerConnection(RTCConfiguration(iceServers=ice))
            peers.add(pc)
            channels = set()
            last_activity = time.monotonic()
            try:
                client_ip = str(ipaddress.ip_address(offer.get('clientIp', '0.0.0.0')))
            except ValueError:
                client_ip = '0.0.0.0'

            async def idle_close():
                while pc.connectionState not in ('closed', 'failed'):
                    await asyncio.sleep(15)
                    if time.monotonic() - last_activity > (300 if pc.connectionState == 'connected' else 45):
                        await pc.close()
                peers.discard(pc)
            spawn(idle_close())

            @pc.on('connectionstatechange')
            async def state_change():
                if pc.connectionState in ('failed', 'closed'):
                    peers.discard(pc)
                    if pc.connectionState == 'failed':
                        await pc.close()

            @pc.on('datachannel')
            def data_channel(channel):
                nonlocal last_activity, buffered
                last_activity = time.monotonic()
                if channel.label != 'reschool-http-v1' or len(channels) >= 8:
                    channel.close()
                    return
                channels.add(channel)
                metadata = None
                body = bytearray()
                done = False
                reserved = 0
                forwarding_task = None
                deadline = asyncio.get_running_loop().call_later(190, channel.close)

                def release():
                    nonlocal reserved, buffered
                    buffered -= reserved
                    reserved = 0
                    body.clear()

                @channel.on('close')
                def closed():
                    channels.discard(channel)
                    deadline.cancel()
                    if forwarding_task is None:
                        release()
                    else:
                        forwarding_task.cancel()

                async def send_response(status, headers, payload):
                    if channel.readyState != 'open':
                        return
                    channel.send(json.dumps({'type': 'response', 'status': status, 'headers': headers, 'bodyLength': len(payload)}))
                    for offset in range(0, len(payload), CHUNK):
                        while channel.bufferedAmount > 256 * 1024:
                            if channel.readyState != 'open':
                                return
                            await asyncio.sleep(0.01)
                        if channel.readyState != 'open':
                            return
                        channel.send(payload[offset:offset + CHUNK])
                    channel.send('end')

                async def forward(meta, payload):
                    nonlocal last_activity
                    try:
                        method, path, headers, expected = clean_request(meta)
                        if len(payload) != expected:
                            raise ValueError('Incomplete request')
                        # к туннельным запросам применяем лимиты api, они не считаются локальными
                        headers['X-Forwarded-For'] = client_ip
                        headers['Accept-Encoding'] = 'identity'
                        async with forwarding, http.request(method, backend + path, headers=headers, data=payload, allow_redirects=False) as response:
                            output = bytearray()
                            async for chunk in response.content.iter_chunked(CHUNK):
                                output.extend(chunk)
                                if len(output) > MAX_BODY:
                                    raise ValueError('Response too large')
                            response_headers = {k: v for k, v in response.headers.items() if k.lower() not in {'set-cookie', 'transfer-encoding', 'connection', 'content-length', 'content-encoding'}}
                            await send_response(response.status, response_headers, bytes(output))
                    except Exception:
                        await send_response(502, {'content-type': 'application/json'}, b'{"error":"Browser transport request failed"}')
                    finally:
                        release()
                        last_activity = time.monotonic()

                @channel.on('message')
                def message(data):
                    nonlocal metadata, done, last_activity, reserved, buffered, forwarding_task
                    last_activity = time.monotonic()
                    try:
                        if done:
                            raise ValueError('Request already complete')
                        if metadata is None:
                            if not isinstance(data, str) or len(data) > 65536:
                                raise ValueError('Invalid metadata')
                            metadata = json.loads(data)
                            _, _, _, size = clean_request(metadata)
                            if buffered + size > 64 * 1024 * 1024:
                                raise ValueError('Server busy')
                            reserved = size
                            buffered += size
                        elif isinstance(data, bytes):
                            if len(data) > CHUNK or len(body) + len(data) > reserved:
                                raise ValueError('Request too large')
                            body.extend(data)
                        elif data == 'end':
                            done = True
                            payload = bytes(body)
                            body.clear()
                            forwarding_task = spawn(forward(metadata, payload))
                            forwarding_task.add_done_callback(lambda _: release())
                        else:
                            raise ValueError('Invalid frame')
                    except (ValueError, TypeError, AttributeError):
                        done = True
                        body.clear()
                        channel.close()

            try:
                # подписываем ответ вместе с точным предложением и проверочным значением клиента, чтобы посредник не подменил отпечаток dtls
                await pc.setRemoteDescription(RTCSessionDescription(sdp=offer['sdp'], type='offer'))
                await pc.setLocalDescription(await pc.createAnswer())
                answer = json.dumps({'v': 1, 'serverId': identity, 'challenge': offer['challenge'], 'offerHash': hashlib.sha256(offer['sdp'].encode()).hexdigest(), 'sdp': pc.localDescription.sdp}, separators=(',', ':'))
                await ws.send_json({'type': 'answer', 'requestId': identifier, 'payload': answer, 'signature': sign(key, answer)})
            except Exception:
                await pc.close()
                peers.discard(pc)
                if not ws.closed:
                    await ws.send_json({'type': 'error', 'requestId': identifier, 'message': 'Не удалось установить соединение'})

        retry = 1
        try:
            while True:
                try:
                    async with http.ws_connect(signal, heartbeat=25, max_msg_size=131072, compress=0) as ws:
                        async for message in ws:
                            if message.type != WSMsgType.TEXT:
                                continue
                            data = json.loads(message.data)
                            if data.get('type') == 'challenge':
                                await ws.send_json({'type': 'register', 'key': public, 'signature': sign(key, 'reschool-register-v1\n' + data['nonce'])})
                            elif data.get('type') == 'registered':
                                retry = 1
                                print('Browser signaling connected', flush=True)
                            elif data.get('type') == 'offer':
                                # резервируем место до запуска согласования, чтобы ограничить параллельные подключения
                                if len(tasks) < 96:
                                    spawn(handle_offer(ws, data))
                except (OSError, ValueError, asyncio.TimeoutError):
                    pass
                except Exception as error:
                    print('Browser signaling unavailable:', type(error).__name__, flush=True)
                await asyncio.sleep(retry)
                retry = min(retry * 2, 30)
        finally:
            for task in list(tasks):
                task.cancel()
            await asyncio.gather(*(pc.close() for pc in list(peers)), return_exceptions=True)
            await asyncio.gather(*list(tasks), return_exceptions=True)


if __name__ == '__main__':
    asyncio.run(run_bridge())
