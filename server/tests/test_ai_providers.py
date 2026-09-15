"""проверяем форматы запросов google и openrouter без сети"""
import copy
import io
import json
import unittest
import urllib.error
from unittest.mock import Mock, patch

from test_backend_hardening import PACKAGE, load_module


def client(provider='openrouter', **overrides):
    config = dict(AI_PROVIDER=provider, GEMINI_API_KEY='google-secret',
                  GEMINI_MODEL='gemini-3.8-flash', GEMINI_TIMEOUT_SECONDS=900,
                  GEMINI_VERTEX_PROJECT='', GEMINI_VERTEX_LOCATION='global',
                  OPENROUTER_API_KEY='router-secret', OPENROUTER_MODEL='google/gemini-3.8-flash',
                  OPENROUTER_TIMEOUT_SECONDS=321)
    return load_module('gemini_client', {
        f'{PACKAGE}.config': {**config, **overrides},
        f'{PACKAGE}.logging_utils': {'log': Mock()},
    })


def response(content='{"ok": true}', **extra):
    return Mock(read=Mock(return_value=json.dumps({
        'choices': [{'message': {'content': content}, 'finish_reason': 'stop'}],
        'usage': {'prompt_tokens': 20, 'completion_tokens': 12,
                  'completion_tokens_details': {'reasoning_tokens': 4}}, **extra,
    }).encode()))


class AIProviderTests(unittest.TestCase):
    def test_configuration_uses_only_selected_provider(self):
        for provider, overrides, expected in [
            ('google', {}, True), ('openrouter', {}, True),
            ('openrouter', {'OPENROUTER_API_KEY': ''}, False),
            ('google', {'GEMINI_API_KEY': ''}, False),
            ('google', {'GEMINI_API_KEY': '', 'GEMINI_VERTEX_PROJECT': 'project'}, True),
            ('unknown', {}, False),
        ]:
            with self.subTest(provider=provider, overrides=overrides):
                self.assertEqual(client(provider, **overrides).is_configured(), expected)

    def test_no_fallback_to_google_if_router_key_missing(self):
        c = client(OPENROUTER_API_KEY='', GEMINI_VERTEX_PROJECT='project')
        with patch.object(c.urllib.request, 'urlopen') as send, patch.object(c, '_access_token') as token:
            with self.assertRaisesRegex(c.GeminiError, 'OPENROUTER_API_KEY'):
                c.generate([{'text': 'hello'}])
        send.assert_not_called()
        token.assert_not_called()

    def test_router_text_images_system_schema_and_usage(self):
        c = client(GEMINI_VERTEX_PROJECT='existing-project')
        schema = {'type': 'object', 'properties': {'ok': {'type': 'boolean', 'nullable': True}},
                  'required': ['ok'], 'propertyOrdering': ['ok']}
        original = copy.deepcopy(schema)
        with patch.object(c.urllib.request, 'urlopen', return_value=response()) as send, patch.object(c, '_access_token') as token:
            result, stats = c.generate([{'text': 'Read page'}, c.image_part(b'page', 'image/png')], schema=schema, system='Tutor')
        request = send.call_args.args[0]
        body = json.loads(request.data)
        self.assertEqual(request.full_url, 'https://openrouter.ai/api/v1/chat/completions')
        self.assertEqual(request.get_header('Authorization'), 'Bearer router-secret')
        self.assertEqual(send.call_args.kwargs['timeout'], 321)
        self.assertNotIn('google-secret', str(request.header_items()) + str(body))
        self.assertEqual(body['model'], 'google/gemini-3.8-flash')
        self.assertEqual(body['messages'][0], {'role': 'system', 'content': 'Tutor'})
        self.assertEqual(body['messages'][1]['content'], [
            {'type': 'text', 'text': 'Read page'},
            {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,cGFnZQ==', 'detail': 'high'}},
        ])
        converted = body['response_format']['json_schema']['schema']
        self.assertEqual(converted['properties']['ok'], {'anyOf': [{'type': 'boolean'}, {'type': 'null'}]})
        self.assertNotIn('propertyOrdering', converted)
        self.assertEqual(schema, original)
        self.assertEqual(body['provider'], {'require_parameters': True})
        self.assertEqual(body['reasoning'], {'effort': 'low', 'exclude': True})
        self.assertEqual(result, {'ok': True})
        self.assertEqual({k: stats[k] for k in ('in', 'out', 'think', 'finish')}, {'in': 20, 'out': 12, 'think': 4, 'finish': 'stop'})
        token.assert_not_called()

    def test_every_production_schema_converts_without_mutation(self):
        c = client()
        prompts = load_module('ai_prompts', {})
        for name, schema in vars(prompts).items():
            if name.endswith('_SCHEMA'):
                with self.subTest(name=name):
                    original = copy.deepcopy(schema)
                    converted = c._json_schema(schema)
                    self.assertEqual(schema, original)
                    self.assertNotIn('nullable', json.dumps(converted))
                    self.assertNotIn('propertyOrdering', json.dumps(converted))
                    self.assertEqual(converted['type'], schema['type'])

    def test_array_result_and_plain_text(self):
        c = client()
        for text, schema, expected in [('[{"page": 1}]', {'type': 'array'}, [{'page': 1}]),
                                        ('hello', None, 'hello'),
                                        ([{'type': 'text', 'text': 'hello'}], None, 'hello')]:
            with self.subTest(text=text), patch.object(c.urllib.request, 'urlopen', return_value=response(text)) as send:
                result, _ = c.generate([{'text': 'hello'}], schema=schema, thinking=None, media_resolution=None)
                self.assertEqual(result, expected)
                self.assertNotIn('reasoning', json.loads(send.call_args.args[0].data))

    def test_google_studio_contract_unchanged(self):
        c = client('google')
        payload = {'candidates': [{'content': {'parts': [{'text': '{"ok":true}'}]}, 'finishReason': 'STOP'}],
                   'usageMetadata': {'promptTokenCount': 10}}
        schema = {'type': 'object'}
        with patch.object(c.urllib.request, 'urlopen', return_value=Mock(read=Mock(return_value=json.dumps(payload).encode()))) as send:
            result, stats = c.generate([{'text': 'hello'}], schema=schema, system='Tutor')
        request = send.call_args.args[0]
        self.assertIn('gemini-3.8-flash:generateContent?key=google-secret', request.full_url)
        self.assertEqual(json.loads(request.data)['generationConfig']['responseSchema'], schema)
        self.assertNotIn('router-secret', str(request.header_items()) + str(request.data))
        self.assertEqual(result, {'ok': True})
        self.assertEqual(stats['in'], 10)

    def test_vertex_still_takes_precedence_within_google(self):
        c = client('google', GEMINI_VERTEX_PROJECT='project')
        with patch.object(c, '_access_token', return_value='vertex-token'):
            url, headers = c._endpoint()
        self.assertIn('/projects/project/locations/global/', url)
        self.assertEqual(headers, {'Authorization': 'Bearer vertex-token'})

    def test_http_errors_retry_only_transient_failures(self):
        for code in [401, 402, 429, 503, 504]:
            c = client()
            c.MAX_ATTEMPTS = 2
            error = urllib.error.HTTPError(c.OPENROUTER_URL, code, 'failure', {}, io.BytesIO(b'failure'))
            self.addCleanup(error.close)
            with self.subTest(code=code), patch.object(c.urllib.request, 'urlopen', side_effect=error) as send, patch.object(c.time, 'sleep'):
                expected = c.GeminiUnavailable if code in c.RETRY_CODES else c.GeminiError
                with self.assertRaises(expected):
                    c.generate([{'text': 'hello'}])
                self.assertEqual(send.call_count, 2 if code in c.RETRY_CODES else 1)

    def test_vertex_replaces_rejected_cached_token_and_repeats_same_request(self):
        c = client('google', GEMINI_VERTEX_PROJECT='project')
        c._token.update(value='expired-token', expires=c.time.time() + 1800)
        failure = urllib.error.HTTPError('https://vertex', 401, 'expired', {}, io.BytesIO(b'expired'))
        self.addCleanup(failure.close)
        reply = Mock(read=Mock(return_value=json.dumps({
            'candidates': [{'content': {'parts': [{'text': 'ok'}]}, 'finishReason': 'STOP'}],
        }).encode()))
        with patch.object(c, '_print_access_token', return_value=('fresh-token', '')) as refresh, \
                patch.object(c.urllib.request, 'urlopen', side_effect=[failure, reply]) as send:
            self.assertEqual(c.generate([{'text': 'Read page'}])[0], 'ok')
        refresh.assert_called_once()
        requests = [call.args[0] for call in send.call_args_list]
        self.assertEqual([r.get_header('Authorization') for r in requests],
                         ['Bearer expired-token', 'Bearer fresh-token'])
        self.assertEqual(requests[0].data, requests[1].data)

    def test_vertex_repeated_401_stops_after_one_auth_retry(self):
        c = client('google', GEMINI_VERTEX_PROJECT='project')
        failure = urllib.error.HTTPError('https://vertex', 401, 'invalid', {}, io.BytesIO(b'invalid'))
        self.addCleanup(failure.close)
        with patch.object(c, '_print_access_token', return_value=('invalid-token', '')), \
                patch.object(c.urllib.request, 'urlopen', side_effect=failure) as send:
            with self.assertRaisesRegex(c.GeminiError, 'HTTP 401'):
                c.generate([{'text': 'Read page'}])
        self.assertEqual(send.call_count, 2)

    def test_rejected_old_request_does_not_clear_new_token(self):
        c = client('google', GEMINI_VERTEX_PROJECT='project')
        c._token.update(value='fresh-token', expires=12345)
        c._invalidate_access_token('Bearer old-token')
        self.assertEqual(c._token, {'value': 'fresh-token', 'expires': 12345})

    def test_studio_401_does_not_refresh_vertex_auth(self):
        c = client('google')
        failure = urllib.error.HTTPError('https://studio', 401, 'invalid', {}, io.BytesIO(b'invalid'))
        self.addCleanup(failure.close)
        with patch.object(c, '_print_access_token') as refresh, \
                patch.object(c.urllib.request, 'urlopen', side_effect=failure) as send:
            with self.assertRaises(c.GeminiError):
                c.generate([{'text': 'Read page'}])
        refresh.assert_not_called()
        self.assertEqual(send.call_count, 1)

    def test_http_200_provider_error_retries_and_recovers(self):
        c = client()
        failure = response(error={'code': 503, 'message': 'busy'})
        with patch.object(c.urllib.request, 'urlopen', side_effect=[failure, response('ok')]) as send, patch.object(c.time, 'sleep'):
            self.assertEqual(c.generate([{'text': 'hello'}])[0], 'ok')
        self.assertEqual(send.call_count, 2)

    def test_network_errors_exhaust_retries(self):
        c = client()
        c.MAX_ATTEMPTS = 2
        with patch.object(c.urllib.request, 'urlopen', side_effect=urllib.error.URLError('offline')) as send, patch.object(c.time, 'sleep'):
            with self.assertRaises(c.GeminiUnavailable):
                c.generate([{'text': 'hello'}])
        self.assertEqual(send.call_count, 2)

    def test_malformed_empty_refusal_and_truncated_responses(self):
        c = client()
        for reply in [Mock(read=Mock(return_value=b'bad json')), response(None), response(''),
                      response('{'), response(choices=[]), response(error={'code': 402, 'message': 'credits'}),
                      response(choices=[{'message': {'refusal': 'no', 'content': 'no'}}])]:
            with self.subTest(reply=reply), patch.object(c.urllib.request, 'urlopen', return_value=reply):
                with self.assertRaises(c.GeminiError):
                    c.generate([{'text': 'hello'}], schema={'type': 'object'})


if __name__ == '__main__':
    unittest.main()
