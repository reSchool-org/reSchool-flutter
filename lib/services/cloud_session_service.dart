import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'reschool_http.dart';

class CloudESchoolSession {
  final String cookie;
  final int prsId;
  const CloudESchoolSession(this.cookie, this.prsId);
}

/// только получение существующей сессии. Этот запрос не запускает вход в eSchool
class CloudSessionService {
  Future<CloudESchoolSession?> fetch(String username, {int? prsId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('cloud_enabled') ??
              prefs.getBool('cf3_enabled') ??
              false) ||
          prefs.getString('cloud_role') == 'classmate') {
        return null;
      }
      final registration = prefs.getString('cf3_registration_id');
      final secret = prefs.getString('cf3_registration_secret');
      final token = prefs.getString('cloud_api_token');
      if (registration == null ||
          secret == null ||
          token == null ||
          registration.isEmpty ||
          secret.isEmpty ||
          token.isEmpty) {
        return null;
      }
      final url = AppConfig.normalizeServerUrl(
        prefs.getString('cloud_server_url') ??
            prefs.getString('cf3_registered_server') ??
            '',
      );
      final registeredUrl = prefs.getString('cf3_registered_server');
      if (registeredUrl != null &&
          AppConfig.normalizeServerUrl(registeredUrl) != url) {
        return null;
      }
      final uri = Uri.tryParse(url);
      if (!AppConfig.isValidServerUrl(url) ||
          uri == null ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.authority.contains('@') ||
          uri.hasQuery ||
          uri.hasFragment) {
        return null;
      }

      final request = http.Request('POST', Uri.parse('$url/cloud/session'))
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'Content-Type': 'application/json',
          'X-API-Token': token,
        })
        ..body = jsonEncode({
          'registrationId': registration,
          'registrationSecret': secret,
          'username': username,
          if (prsId != null) 'prsId': prsId,
        });
      final response = await reschoolHttp
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> ||
          data['available'] != true ||
          data['username'] != username) {
        return null;
      }
      final cookie = data['sessionCookie'];
      final receivedPrsId = data['prsId'];
      if (cookie is! String ||
          !RegExp(
            r'^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]{1,4096}$',
          ).hasMatch(cookie) ||
          receivedPrsId is! int ||
          receivedPrsId <= 0 ||
          (prsId != null && receivedPrsId != prsId)) {
        return null;
      }
      return CloudESchoolSession(cookie, receivedPrsId);
    } catch (_) {
      // старый/недоступный сервер не блокирует обычную авторизацию
      // сессионные данные и ответы сервера не попадают в логи
      return null;
    }
  }
}
