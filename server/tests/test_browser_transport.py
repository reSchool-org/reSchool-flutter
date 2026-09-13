"""тесты протокола идут в образе browser_transport без рабочей базы"""
import asyncio
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from aiohttp import ClientSession, web
from browser_transport.identity import load_identity, public_key, sign, verify, connection_code, decode, server_id
from browser_transport.bridge import clean_request, MAX_BODY
from browser_transport.gateway import create_app


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.key = load_identity(self.tmp.name)
        self.public = public_key(self.key)

    def test_identity_survives_restart_and_stays_private(self):
        self.assertEqual(self.public, public_key(load_identity(self.tmp.name)))
        self.assertEqual(Path(self.tmp.name, 'browser-identity.pem').stat().st_mode & 0o777, 0o600)

    def test_signatures_bind_every_byte_and_server(self):
        message = json.dumps({'challenge': 'unique-client-nonce', 'offerHash': 'offer', 'sdp': 'fingerprint'})
        signature = sign(self.key, message)
        self.assertTrue(verify(self.public, message, signature))
        for old in ('unique-client-nonce', 'offer', 'fingerprint'):
            self.assertFalse(verify(self.public, message.replace(old, 'tampered'), signature))
        with tempfile.TemporaryDirectory() as other:
            self.assertFalse(verify(public_key(load_identity(other)), message, signature))
        self.assertFalse(verify(self.public, message, 'invalid'))

    def test_code_contains_only_public_identity(self):
        code = connection_code(self.key, 'wss://reschool.app/signal', 'https://192.168.1.54:4443')
        payload = json.loads(decode(code[5:]))
        self.assertEqual(set(payload), {'v', 'id', 'key', 'signal', 'server'})
        self.assertEqual(payload['id'], server_id(self.public))

    def test_forwarding_cannot_change_origin_or_spoof_source(self):
        for path in ('https://example.org/', '//example.org/', '/\\example.org', '/x#fragment', '/\r\nHost:x', 5):
            with self.subTest(path=path), self.assertRaises(ValueError):
                clean_request({'method': 'GET', 'path': path})
        _, path, headers, size = clean_request({'method': 'POST', 'path': '/proxy?x=1', 'bodyLength': 7,
            'headers': {'Host': 'example.org', 'X-Forwarded-For': '127.0.0.1', 'Cookie': 'secret', 'X-API-Token': 'test', 'Content-Type': 'application/json'}})
        self.assertEqual((path, size), ('/proxy?x=1', 7))
        self.assertEqual(headers, {'X-API-Token': 'test', 'Content-Type': 'application/json'})
        for size in (-1, MAX_BODY + 1, True, '0'):
            with self.assertRaises(ValueError):
                clean_request({'method': 'GET', 'path': '/', 'bodyLength': size})


class GatewayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.env = patch.dict(os.environ, {'BROWSER_ALLOWED_ORIGINS': 'http://localhost:8765'})
        self.env.start()
        self.runner = web.AppRunner(create_app())
        await self.runner.setup()
        site = web.TCPSite(self.runner, '127.0.0.1', 0)
        await site.start()
        self.url = f'http://127.0.0.1:{site._server.sockets[0].getsockname()[1]}'
        self.http = ClientSession()
        self.tmp = tempfile.TemporaryDirectory()
        self.key = load_identity(self.tmp.name)

    async def asyncTearDown(self):
        await self.http.close()
        await self.runner.cleanup()
        self.tmp.cleanup()
        self.env.stop()

    async def register(self):
        ws = await self.http.ws_connect(self.url + '/signal')
        challenge = await ws.receive_json()
        await ws.send_json({'type': 'register', 'key': public_key(self.key), 'signature': sign(self.key, 'reschool-register-v1\n' + challenge['nonce'])})
        self.assertEqual((await ws.receive_json())['type'], 'registered')
        return ws

    async def test_origin_is_checked(self):
        async with self.http.get(self.url + '/signal', headers={'Origin': 'https://evil.example'}) as response:
            self.assertEqual(response.status, 403)

    async def test_forged_registration_is_closed(self):
        ws = await self.http.ws_connect(self.url + '/signal')
        await ws.receive_json()
        await ws.send_json({'type': 'register', 'key': public_key(self.key), 'signature': sign(self.key, 'wrong nonce')})
        result = await asyncio.wait_for(ws.receive(), 2)
        self.assertNotEqual(result.type.name, 'TEXT')

    async def test_offer_routing_uses_registered_identity_and_observed_ip(self):
        server = await self.register()
        browser = await self.http.ws_connect(self.url + '/signal', headers={'Origin': 'http://localhost:8765'})
        await browser.receive_json()
        await browser.send_json({'type': 'offer', 'serverId': server_id(public_key(self.key)), 'sdp': 'test-offer', 'challenge': 'a' * 43, 'clientIp': 'attacker-controlled'})
        offer = await server.receive_json()
        self.assertEqual(offer['clientIp'], '127.0.0.1')
        self.assertEqual(offer['sdp'], 'test-offer')
        await server.send_json({'type': 'answer', 'requestId': offer['requestId'], 'payload': 'signed-answer', 'signature': 'signature'})
        self.assertEqual((await browser.receive_json())['payload'], 'signed-answer')
        await browser.close()
        await server.close()

    async def test_unknown_server_returns_actionable_error(self):
        ws = await self.http.ws_connect(self.url + '/signal', headers={'Origin': 'http://localhost:8765'})
        await ws.receive_json()
        await ws.send_json({'type': 'offer', 'serverId': '0' * 64, 'sdp': 'offer', 'challenge': 'a' * 43})
        self.assertEqual((await ws.receive_json())['type'], 'error')
        await ws.close()

    async def test_turn_credentials_are_short_lived_and_authenticated(self):
        with patch.dict(os.environ, {'BROWSER_TURN_URLS': 'turn:turn.example:3478?transport=udp', 'BROWSER_TURN_SECRET': 'test-secret'}):
            ws = await self.http.ws_connect(self.url + '/signal')
            ice = (await ws.receive_json())['iceServers'][0]
            expected = base64.b64encode(hmac.new(b'test-secret', ice['username'].encode(), hashlib.sha1).digest()).decode()
            self.assertEqual(ice['credential'], expected)
            import time
            self.assertTrue(3590 < int(ice['username'].split(':')[0]) - time.time() <= 3600)
            await ws.close()


if __name__ == '__main__':
    unittest.main()
