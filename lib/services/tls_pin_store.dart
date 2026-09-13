import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// доверие к серверу без домена и без let's encrypt
/// сертификат у такого сервера самоподписанный, системным корням он не известен,
/// поэтому проверяем его сами: сверяем sha256 от публичного ключа с тем,
/// что владелец сервера принёс ссылкой или сверил глазами. это тот же принцип,
/// что в ssh: ключ один раз подтвердили, дальше подмена сразу видна
class TlsPinStore {
  TlsPinStore._();

  static final TlsPinStore instance = TlsPinStore._();

  static const _prefsKey = 'tls_pins';

  final Map<String, String> _pins = {};
  bool _loaded = false;

  /// последний отвергнутый сертификат, экран привязки показывает его отпечаток
  RejectedCertificate? lastRejected;

  /// клиент подписывается сюда, чтобы рвать уже открытые соединения при смене пина
  VoidCallback? onPinsChanged;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value is String) _pins[key] = value;
          });
        }
      }
    } catch (e) {
      debugPrint('[TLS] Не удалось прочитать пины: $e');
    }
    _loaded = true;
  }

  /// ключ пина это хост и порт, один сервер на двух портах это два разных доверия
  static String keyFor(Uri uri) {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return '${uri.host.toLowerCase()}:$port';
  }

  String? pinForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return _pins[keyFor(uri)];
  }

  bool hasPinForUrl(String url) => (pinForUrl(url) ?? '').isNotEmpty;

  Future<void> savePin(String url, String pin) async {
    final uri = Uri.tryParse(url);
    final normalized = normalizePin(pin);
    if (uri == null || uri.host.isEmpty || normalized.isEmpty) return;

    if (_pins[keyFor(uri)] == normalized) return;

    _pins[keyFor(uri)] = normalized;
    await _persist();
  }

  Future<void> removePin(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return;
    _pins.remove(keyFor(uri));
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_pins));
    } catch (e) {
      debugPrint('[TLS] Не удалось сохранить пины: $e');
    }
    // соединение из пула уже проверено старым пином, новый на него не подействует
    onPinsChanged?.call();
  }

  /// сюда приходит всё, что не прошло системную проверку
  /// пускаем дальше только точное совпадение с закреплённым ключом
  bool acceptCertificate(X509Certificate cert, String host, int port) {
    final key = '${host.toLowerCase()}:$port';
    final pin = pinOf(cert);
    final expected = _pins[key];

    if (expected != null && expected.isNotEmpty && pin.isNotEmpty && expected == pin) {
      return true;
    }

    lastRejected = RejectedCertificate(
      host: host,
      port: port,
      pin: pin,
      fingerprint: fingerprintOf(cert),
      hadPin: expected != null && expected.isNotEmpty,
    );
    debugPrint('[TLS] Сертификат $host:$port не закреплён, соединение отклонено');
    return false;
  }

  /// приводим пин к виду sha256/base64, руками его вводят как угодно
  static String normalizePin(String value) {
    var pin = value.trim();
    if (pin.isEmpty) return '';
    if (pin.toLowerCase().startsWith('sha256/')) {
      pin = pin.substring(7).trim();
    }
    pin = pin.replaceAll(' ', '');
    if (pin.isEmpty) return '';
    try {
      final decoded = base64.decode(base64.normalize(pin));
      if (decoded.length != 32) return '';
    } catch (_) {
      return '';
    }
    return 'sha256/${base64.normalize(pin)}';
  }

  /// sha256 от SubjectPublicKeyInfo, ровно как считает сервер
  static String pinOf(X509Certificate cert) {
    final spki = _extractSpki(Uint8List.fromList(cert.der));
    if (spki == null) return '';
    return 'sha256/${base64.encode(sha256.convert(spki).bytes)}';
  }

  /// отпечаток всего сертификата, его показывают браузеры и openssl
  static String fingerprintOf(X509Certificate cert) {
    final digest = sha256.convert(cert.der).toString().toUpperCase();
    final parts = <String>[];
    for (var i = 0; i < digest.length; i += 2) {
      parts.add(digest.substring(i, i + 2));
    }
    return parts.join(':');
  }

  /// в der сертификате SubjectPublicKeyInfo лежит седьмым полем tbsCertificate,
  /// поэтому просто отсчитываем элементы, разбирать весь x509 незачем
  static Uint8List? _extractSpki(Uint8List der) {
    final cert = _readTlv(der, 0);
    if (cert == null || cert.tag != 0x30) return null;

    final tbs = _readTlv(der, cert.contentStart);
    if (tbs == null || tbs.tag != 0x30) return null;

    var offset = tbs.contentStart;
    final tbsEnd = tbs.end;

    // необязательный explicit тег версии, если его нет, сразу идёт серийник
    final first = _readTlv(der, offset);
    if (first == null) return null;
    if (first.tag == 0xA0) offset = first.end;

    // пропускаем серийный номер, подпись, издателя, срок действия и владельца
    for (var i = 0; i < 5; i++) {
      final field = _readTlv(der, offset);
      if (field == null || field.end > tbsEnd) return null;
      offset = field.end;
    }

    final spki = _readTlv(der, offset);
    if (spki == null || spki.tag != 0x30 || spki.end > tbsEnd) return null;
    return Uint8List.sublistView(der, spki.start, spki.end);
  }

  static _Tlv? _readTlv(Uint8List data, int offset) {
    if (offset + 2 > data.length) return null;

    final tag = data[offset];
    var cursor = offset + 1;
    var length = data[cursor];
    cursor++;

    if (length & 0x80 != 0) {
      final lengthBytes = length & 0x7F;
      // такой длины в сертификате не бывает, значит перед нами мусор
      if (lengthBytes == 0 || lengthBytes > 4 || cursor + lengthBytes > data.length) {
        return null;
      }
      length = 0;
      for (var i = 0; i < lengthBytes; i++) {
        length = (length << 8) | data[cursor + i];
      }
      cursor += lengthBytes;
    }

    if (cursor + length > data.length) return null;
    return _Tlv(tag: tag, start: offset, contentStart: cursor, length: length);
  }
}

class _Tlv {
  const _Tlv({
    required this.tag,
    required this.start,
    required this.contentStart,
    required this.length,
  });

  final int tag;
  final int start;
  final int contentStart;
  final int length;

  int get end => contentStart + length;
}

class RejectedCertificate {
  const RejectedCertificate({
    required this.host,
    required this.port,
    required this.pin,
    required this.fingerprint,
    required this.hadPin,
  });

  final String host;
  final int port;
  final String pin;
  final String fingerprint;

  /// несовпадение пина означает смену ключа сервера или вмешательство в соединение
  final bool hadPin;
}
