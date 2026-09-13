import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;

import 'tls_pin_store.dart';
import 'browser_server.dart';

@JS('reSchoolTransport.request')
external JSPromise<JSString> _rtcRequest(JSString request);

final http.Client reschoolHttp = _BrowserClient();

class _BrowserClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!hasBrowserServer(request.url.toString())) {
      final client = http.Client();
      try {
        final response = await client.send(request);
        final bytes = await response.stream.toBytes();
        return http.StreamedResponse(
          Stream.value(bytes),
          response.statusCode,
          headers: response.headers,
          request: request,
          reasonPhrase: response.reasonPhrase,
          isRedirect: response.isRedirect,
        );
      } finally {
        client.close();
      }
    }
    final bytes = await request.finalize().toBytes();
    final json = jsonEncode({
      'url': request.url.toString(),
      'method': request.method,
      'headers': request.headers,
      'body': base64UrlEncode(bytes),
    });
    try {
      final response = jsonDecode(
        (await _rtcRequest(json.toJS).toDart).toDart,
      ) as Map<String, dynamic>;
      return http.StreamedResponse(
        Stream.value(
          base64Url.decode(base64Url.normalize(response['body'] as String)),
        ),
        response['status'] as int,
        headers: (response['headers'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k.toLowerCase(), v.toString()),
        ),
        request: request,
      );
    } catch (error) {
      throw http.ClientException('$error', request.url);
    }
  }
}

class TlsPinException implements Exception {
  TlsPinException(this.host, this.port, this.rejected);

  final String host;
  final int port;
  final RejectedCertificate? rejected;

  bool get keyChanged => rejected?.hadPin ?? false;

  @override
  String toString() {
    if (keyChanged) {
      return 'Сертификат сервера $host:$port изменился. '
          'Если сервер не переустанавливали, соединение кто-то перехватывает.';
    }
    return 'Сертификат сервера $host:$port не подтверждён. '
        'Откройте настройки облачных функций и подтвердите отпечаток сервера.';
  }
}

enum ServerTrust {
  /// обычный сертификат, подтверждён системными корнями
  system,

  /// самоподписанный, но его ключ уже закреплён в приложении
  pinned,

  /// самоподписанный и незнакомый, отпечаток надо сверить с сервером
  unknown,

  /// ключ закреплён, но сервер показал другой, это либо переустановка, либо подмена
  changed,

  /// до сервера не достучались
  unreachable,
}

class ServerTrustResult {
  const ServerTrustResult({
    required this.trust,
    this.pin = '',
    this.fingerprint = '',
    this.error,
  });

  final ServerTrust trust;
  final String pin;
  final String fingerprint;
  final Object? error;

  bool get needsConfirmation =>
      trust == ServerTrust.unknown || trust == ServerTrust.changed;
  bool get isReady =>
      trust == ServerTrust.system || trust == ServerTrust.pinned;
}

Future<ServerTrustResult> inspectServerTrust(
  String url, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  // webrtc сверяет личность сервера с кодом подключения; без кода сертификат https проверяет браузер
  return ServerTrustResult(
    trust: hasBrowserServer(url) ? ServerTrust.pinned : ServerTrust.system,
  );
}
