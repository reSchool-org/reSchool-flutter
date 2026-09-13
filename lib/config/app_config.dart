class AppConfig {
  AppConfig._();

  static const String eSchoolBaseUrl = 'https://app.eschool.center/ec-server';

  // версию клиента eSchool раз в три дня обновляет actions и кладёт
  // в последний релиз, ссылка на latest не протухает
  static const String eSchoolVersionUrl =
      'https://github.com/reSchool-org/reSchool-flutter/releases/latest/download/eschool-version.txt';

  // если сеть недоступна, а кэша ещё нет
  static const String eSchoolVersionFallback = '8.1.0';

  static final RegExp _urlSchemeRegex = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

  // 4443 слушает caddy со своим сертификатом, 443 обычный https
  static const Set<int> _tlsPorts = {443, 4443};

  // пользователь может ввести и полный url, и просто домен или ip
  // публичным хостам подставляем https, локальным http
  static String normalizeServerUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) return '';

    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (!_urlSchemeRegex.hasMatch(url)) {
      final probe = Uri.tryParse('https://$url');
      // на порту tls всегда https, даже в локальной сети: там сервер отдаёт
      // самоподписанный сертификат, а не голый http
      final tlsPort =
          probe != null && probe.hasPort && _tlsPorts.contains(probe.port);
      final scheme = probe != null && isLocalAddress(probe.host) && !tlsPort
          ? 'http'
          : 'https';
      url = '$scheme://$url';
    }

    url = url.replaceAll(RegExp(r'/+$'), '');
    return url;
  }

  // проверка, что строка вообще похожа на адрес сервера
  static bool isValidServerUrl(String url) {
    final normalized = normalizeServerUrl(url);
    if (normalized.isEmpty) return false;
    try {
      final uri = Uri.parse(normalized);
      return uri.hasScheme &&
          uri.host.isNotEmpty &&
          (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  // ios пропускает http только на локальные адреса
  static bool isHttpsUrl(String url) {
    try {
      final uri = Uri.parse(normalizeServerUrl(url));
      if (uri.scheme == 'https') return true;

      // на локалку http разрешаем
      if (uri.scheme == 'http') {
        return isLocalAddress(uri.host);
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  // локальные адреса: localhost, 127.x.x.x, 10.x.x.x, 172.16..172.31.x.x, 192.168.x.x
  static bool isLocalAddress(String host) {
    if (host == 'localhost' || host == '::1') return true;

    // дальше разбираем только ipv4
    final parts = host.split('.');
    if (parts.length != 4) return false;

    try {
      final octets = parts.map(int.parse).toList();

      // петля
      if (octets[0] == 127) return true;

      // частная сеть rfc1918 с маской /8
      if (octets[0] == 10) return true;

      // частная сеть rfc1918 с маской /12
      if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;

      // частная сеть rfc1918 с маской /16
      if (octets[0] == 192 && octets[1] == 168) return true;

      return false;
    } catch (e) {
      return false;
    }
  }
}
