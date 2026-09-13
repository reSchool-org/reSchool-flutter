/* привязка браузера закрепляет личность сервера, срок сертификата tls на неё не влияет */
(() => {
  'use strict';
  const STORE = 'reschool_browser_servers_v1';
  const LIMIT = 32 * 1024 * 1024;
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const sessions = new Map();
  const from64 = value => Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4)), c => c.charCodeAt(0));
  const to64 = bytes => {
    let text = '';
    for (let i = 0; i < bytes.length; i += 8192) text += String.fromCharCode(...bytes.subarray(i, i + 8192));
    return btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };
  const digest = async text => [...new Uint8Array(await crypto.subtle.digest('SHA-256', typeof text === 'string' ? encoder.encode(text) : text))].map(b => b.toString(16).padStart(2, '0')).join('');
  const timeout = (promise, ms, message) => {
    let timer;
    return Promise.race([promise, new Promise((_, reject) => timer = setTimeout(() => reject(Error(message)), ms))]).finally(() => clearTimeout(timer));
  };
  function records() {
    const value = JSON.parse(localStorage.getItem(STORE) || '{}');
    if (!value || Array.isArray(value) || typeof value !== 'object') throw Error('Не удалось прочитать сохранённые подключения');
    return value;
  }
  function origin(value) {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) throw Error('Некорректный адрес сервера');
    return url.origin;
  }
  const isLoopback = hostname => ['localhost', '127.0.0.1', '[::1]'].includes(hostname);
  function validate(code) {
    if (!code || code.v !== 1 || !/^[0-9a-f]{64}$/.test(code.id) || typeof code.key !== 'string' || from64(code.key).length !== 65) throw Error('Некорректный код подключения');
    const signaling = new URL(code.signal);
    const local = signaling.protocol === 'ws:' && isLoopback(signaling.hostname);
    if (isLoopback(signaling.hostname) && !isLoopback(window.location.hostname)) throw Error('Код подключения указывает на localhost. Получите у администратора код с публичным адресом службы подключения.');
    if (!(signaling.protocol === 'wss:' || local) || signaling.username || signaling.password || signaling.search || signaling.hash || signaling.pathname !== '/signal') throw Error('В коде подключения указан неподдерживаемый адрес');
    code.server = origin(code.server);
    return code;
  }
  async function saveCode(value) {
    value = value.trim();
    if (!value.startsWith('rsc1.')) return value;
    if (value.length > 4096) throw Error('Слишком длинный код подключения');
    let code;
    try { code = validate(JSON.parse(decoder.decode(from64(value.slice(5))))); }
    catch (_) { throw Error('Некорректный код подключения. Скопируйте его целиком с сервера.'); }
    if (await digest(from64(code.key)) !== code.id) throw Error('Ключ сервера не соответствует коду подключения');
    const saved = records();
    const existing = saved[code.server];
    if (existing && existing.key !== code.key) throw Error('Ключ этого сервера изменился. Сверьте новый код у администратора, затем очистите данные веб-версии в браузере.');
    const old = sessions.get(code.server);
    if (old) { old.then(s => s.pc.close()).catch(() => {}); sessions.delete(code.server); }
    saved[code.server] = code;
    localStorage.setItem(STORE, JSON.stringify(saved));
    return code.server;
  }
  function hasServer(value) {
    try {
      const target = new URL(value);
      // адрес https уже доступен браузеру, старая привязка не должна увести запросы на локальный шлюз разработки
      if (target.protocol === 'https:' && target.origin === window.location.origin) return false;
      return Boolean(records()[target.origin]);
    } catch (_) { return false; }
  }
  async function connect(code) {
    if (!window.isSecureContext || !window.RTCPeerConnection || !crypto.subtle) throw Error('Для подключения откройте веб-версию по HTTPS в современном браузере');
    validate(code);
    if (await digest(from64(code.key)) !== code.id) throw Error('Сохранённый ключ сервера повреждён. Вставьте код подключения заново.');
    const ws = new WebSocket(code.signal);
    let pc;
    let completed = false;
    const challenge = to64(crypto.getRandomValues(new Uint8Array(32)));
    let offerSDP;
    let bootstrap;
    const peer = new Promise((resolve, reject) => {
      ws.onerror = () => reject(Error('Служба подключения недоступна. Проверьте интернет.'));
      ws.onclose = () => { if (!completed) reject(Error('Соединение с сервером прервано')); };
      let receivedChallenge = false, receivedAnswer = false;
      ws.onmessage = async event => {
        try {
          if (typeof event.data !== 'string' || event.data.length > 131072) throw Error('Некорректный ответ службы подключения');
          const data = JSON.parse(event.data);
          if (data.type === 'error') throw Error('Сервер сейчас недоступен. Проверьте, что он включён.');
          if (data.type === 'challenge' && !receivedChallenge) {
            receivedChallenge = true;
            pc = new RTCPeerConnection({iceServers: data.iceServers || []});
            bootstrap = pc.createDataChannel('reschool-http-v1');
            await pc.setLocalDescription(await pc.createOffer());
            if (pc.iceGatheringState !== 'complete') await timeout(new Promise(done => {
              const change = () => { if (pc.iceGatheringState === 'complete') { pc.removeEventListener('icegatheringstatechange', change); done(); } };
              pc.addEventListener('icegatheringstatechange', change); change();
            }), 15000, 'Не удалось подготовить сетевое подключение');
            offerSDP = pc.localDescription.sdp;
            ws.send(JSON.stringify({type: 'offer', serverId: code.id, challenge, sdp: offerSDP}));
          } else if (data.type === 'answer' && pc && offerSDP && !receivedAnswer) {
            receivedAnswer = true;
            const key = await crypto.subtle.importKey('raw', from64(code.key), {name: 'ECDSA', namedCurve: 'P-256'}, false, ['verify']);
            const valid = await crypto.subtle.verify({name: 'ECDSA', hash: 'SHA-256'}, key, from64(data.signature), encoder.encode(data.payload));
            if (!valid) throw Error('Ключ сервера не совпал. Подключение остановлено.');
            const answer = JSON.parse(data.payload);
            if (answer.v !== 1 || answer.serverId !== code.id || answer.challenge !== challenge || answer.offerHash !== await digest(offerSDP)) throw Error('Сервер вернул неподходящее подтверждение подключения');
            await pc.setRemoteDescription({type: 'answer', sdp: answer.sdp});
            const ready = () => { completed = true; bootstrap.close(); resolve({pc, createdAt: Date.now(), active: 0}); ws.close(); };
            if (bootstrap.readyState === 'open') ready();
            else { bootstrap.onopen = ready; bootstrap.onerror = () => reject(Error('Не удалось открыть защищённый канал')); }
          } else throw Error('Некорректная последовательность подключения');
        } catch (error) { reject(error); }
      };
    });
    try { return await timeout(peer, 40000, 'Сервер не отвечает. Для этой сети может потребоваться TURN на общей службе.'); }
    catch (error) { completed = true; ws.close(); pc?.close(); throw error; }
  }
  async function sessionFor(server) {
    let pending = sessions.get(server);
    if (pending) {
      const current = await pending.catch(() => null);
      if (current && current.pc.connectionState === 'connected' && (Date.now() - current.createdAt < 2700000 || current.active > 0)) return current;
      current?.pc.close();
      sessions.delete(server);
    }
    const code = records()[server];
    if (!code) throw Error('Сначала вставьте код подключения от администратора');
    pending = connect(code);
    sessions.set(server, pending);
    try { return await pending; }
    catch (error) { if (sessions.get(server) === pending) sessions.delete(server); throw error; }
  }
  async function request(serialized) {
    const input = JSON.parse(serialized);
    const target = new URL(input.url);
    if (target.username || target.password || target.hash) throw Error('Некорректный адрес запроса');
    const body = from64(input.body || '');
    if (body.length > LIMIT) throw Error('Файл слишком большой для браузерного подключения');
    const session = await sessionFor(target.origin);
    const channel = session.pc.createDataChannel('reschool-http-v1', {ordered: true});
    channel.binaryType = 'arraybuffer';
    session.active++;
    let done = false;
    const response = new Promise((resolve, reject) => {
      let metadata;
      let size = 0;
      const chunks = [];
      channel.onerror = () => reject(Error('Ошибка защищённого канала'));
      channel.onclose = () => { if (!done) reject(Error('Соединение прервалось. Проверьте результат перед повторной отправкой.')); };
      channel.onmessage = event => {
        try {
          if (!metadata) {
            if (typeof event.data !== 'string' || event.data.length > 65536) throw Error('Некорректный ответ сервера');
            metadata = JSON.parse(event.data);
            if (metadata.type !== 'response' || !Number.isInteger(metadata.bodyLength) || metadata.bodyLength < 0 || metadata.bodyLength > LIMIT || !Number.isInteger(metadata.status) || metadata.status < 100 || metadata.status > 599) throw Error('Некорректный ответ сервера');
          } else if (event.data === 'end') {
            if (size !== metadata.bodyLength) throw Error('Сервер передал неполный ответ');
            const result = new Uint8Array(size);
            let offset = 0;
            for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
            done = true;
            resolve(JSON.stringify({status: metadata.status, headers: metadata.headers, body: to64(result)}));
          } else {
            if (!(event.data instanceof ArrayBuffer)) throw Error('Некорректный формат ответа');
            const chunk = new Uint8Array(event.data);
            size += chunk.length;
            if (size > metadata.bodyLength) throw Error('Ответ сервера слишком большой');
            chunks.push(chunk);
          }
        } catch (error) { reject(error); }
      };
      channel.onopen = async () => {
        try {
          channel.send(JSON.stringify({method: input.method, path: target.pathname + target.search, headers: input.headers, bodyLength: body.length}));
          for (let offset = 0; offset < body.length; offset += 16384) {
            while (channel.bufferedAmount > 262144) {
              if (channel.readyState !== 'open') throw Error('Соединение прервано');
              await new Promise(resolve => setTimeout(resolve, 10));
            }
            channel.send(body.subarray(offset, offset + 16384));
          }
          channel.send('end');
        } catch (error) { reject(error); }
      };
    });
    try { return await timeout(response, 185000, 'Сервер долго не отвечает. Проверьте результат перед повторной отправкой.'); }
    finally { done = true; channel.close(); session.active--; }
  }
  window.addEventListener('pagehide', () => {
    for (const session of sessions.values()) session.then(value => value.pc.close()).catch(() => {});
    sessions.clear();
  });
  window.reSchoolTransport = {saveCode, hasServer, request};
})();
