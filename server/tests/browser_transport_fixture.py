"""локальная заглушка api нужна для браузерных проверок двоичных данных и post"""
from aiohttp import web

async def config(request):
    return web.json_response({'cloudProtocolVersion': 2})

async def auth(request):
    return web.json_response({'error': 'Unauthorized'}, status=401)

async def echo(request):
    if request.headers.get('X-API-Token') != 'fixture-only-token':
        return web.json_response({'error': 'Unauthorized'}, status=401)
    data = await request.read()
    return web.Response(body=data, headers={'Content-Type': 'application/octet-stream', 'X-Test-Source': request.headers.get('X-Forwarded-For', '')})

app = web.Application(client_max_size=32 * 1024 * 1024)
app.router.add_get('/config', config)
app.router.add_route('*', '/auth-check', auth)
app.router.add_post('/echo', echo)
web.run_app(app, host='127.0.0.1', port=20001)
