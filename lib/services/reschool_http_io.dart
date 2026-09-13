import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'tls_pin_store.dart';

/// клиент для своего сервера reSchool
/// от обычного http отличается одним: самоподписанный сертификат проходит,
/// только если его публичный ключ совпал с закреплённым. домен и сертификат
/// от let's encrypt при этом не нужны, а от подмены защищает пин
final http.Client reschoolHttp = _PinnedClient();

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

class _PinnedClient extends http.BaseClient {
  _PinnedClient() {
    TlsPinStore.instance.onPinsChanged = _dropConnections;
  }

  IOClient? _inner;

  IOClient get _client => _inner ??= IOClient(_createHttpClient());

  /// пин поменялся, старые соединения проверены по прежнему ключу и больше не годятся
  void _dropConnections() {
    _inner?.close();
    _inner = null;
  }

  static HttpClient _createHttpClient() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..badCertificateCallback = TlsPinStore.instance.acceptCertificate;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // тесты подменяют транспорт через http.runWithClient, такую подмену уважаем
    final zoneClient = http.Client();
    if (zoneClient is! IOClient) return zoneClient.send(request);
    zoneClient.close();

    try {
      return await _client.send(request);
    } on HandshakeException {
      // рукопожатие рвётся и когда пин не совпал, и когда его просто нет
      final uri = request.url;
      final port = uri.hasPort ? uri.port : 443;
      throw TlsPinException(uri.host, port, TlsPinStore.instance.lastRejected);
    }
  }

  @override
  void close() {
    _inner?.close();
    _inner = null;
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

/// смотрит, чем сервер отвечает на tls, ничего ему при этом не отправляя
/// нужно, чтобы показать отпечаток до того, как на сервер уедут логин с паролем
Future<ServerTrustResult> inspectServerTrust(
  String url, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) {
    return const ServerTrustResult(trust: ServerTrust.unreachable);
  }
  if (uri.scheme != 'https') {
    // http допустим только внутри локальной сети, там подтверждать нечего
    return const ServerTrustResult(trust: ServerTrust.system);
  }

  await TlsPinStore.instance.load();
  final port = uri.hasPort ? uri.port : 443;
  X509Certificate? untrusted;
  SecureSocket? socket;

  try {
    socket = await SecureSocket.connect(
      uri.host,
      port,
      timeout: timeout,
      onBadCertificate: (certificate) {
        // соглашаемся только чтобы дочитать сертификат, никаких данных не шлём
        untrusted = certificate;
        return true;
      },
    );
    final certificate = untrusted ?? socket.peerCertificate;
    if (certificate == null) {
      return const ServerTrustResult(trust: ServerTrust.unreachable);
    }

    if (untrusted == null) {
      return const ServerTrustResult(trust: ServerTrust.system);
    }

    final pin = TlsPinStore.pinOf(certificate);
    final fingerprint = TlsPinStore.fingerprintOf(certificate);
    final saved = TlsPinStore.instance.pinForUrl(url);

    if (saved == null || saved.isEmpty) {
      return ServerTrustResult(
        trust: ServerTrust.unknown,
        pin: pin,
        fingerprint: fingerprint,
      );
    }
    if (saved == pin) {
      return ServerTrustResult(
        trust: ServerTrust.pinned,
        pin: pin,
        fingerprint: fingerprint,
      );
    }
    return ServerTrustResult(
      trust: ServerTrust.changed,
      pin: pin,
      fingerprint: fingerprint,
    );
  } catch (e) {
    return ServerTrustResult(trust: ServerTrust.unreachable, error: e);
  } finally {
    socket?.destroy();
  }
}
