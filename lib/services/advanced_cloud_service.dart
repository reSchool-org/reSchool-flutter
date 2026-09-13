import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/cloud_connection.dart';
import 'api_service.dart';
import 'cloud_functions_service.dart';
import 'reschool_http.dart';
import 'analysis_service.dart';

class CloudException implements Exception {
  final String message;
  final int? statusCode;
  const CloudException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// режим подключения сохраняем только после ответа сервера
class AdvancedCloudService {
  static Future<void>? _pendingRestore;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const {},
    String? serverUrl,
    String? token,
    bool public = false,
    bool get = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl =
        prefs.getString('cloud_server_url') ??
        prefs.getString('cf3_registered_server') ??
        '';
    final url = AppConfig.normalizeServerUrl(serverUrl ?? savedUrl);
    final uri = Uri.tryParse(url);
    if (!AppConfig.isValidServerUrl(url) ||
        uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !['localhost', '127.0.0.1', '::1'].contains(uri.host))) {
      throw const CloudException('Для подключения нужен HTTPS адрес сервера');
    }
    final sameServer = url == AppConfig.normalizeServerUrl(savedUrl);
    if (path == '/cloud/status' && sameServer && !public && token == null) {
      await restoreAdminMonitoring();
    }
    final auth = public
        ? ''
        : token ?? (sameServer ? prefs.getString('cloud_api_token') ?? '' : '');
    final payload = <String, dynamic>{
      if (!public &&
          sameServer &&
          prefs.getString('cf3_registration_id') != null)
        'registrationId': prefs.getString('cf3_registration_id'),
      if (!public &&
          sameServer &&
          prefs.getString('cf3_registration_secret') != null)
        'registrationSecret': prefs.getString('cf3_registration_secret'),
      ...body,
    };
    try {
      final headers = {
        'Content-Type': 'application/json',
        if (auth.isNotEmpty) 'X-API-Token': auth,
      };
      final target = Uri.parse('$url$path');
      final outgoing = http.Request(get ? 'GET' : 'POST', target)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll(headers);
      if (!get) outgoing.body = jsonEncode(payload);
      final response = await reschoolHttp
          .send(outgoing)
          .then(http.Response.fromStream)
          .timeout(
            Duration(
              seconds: path == '/cloud/join' || path == '/cloud/account'
                  ? 180
                  : (kIsWeb ? 90 : 30),
            ),
          );
      final dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw const CloudException(
          'По этому адресу отвечает не Server Advanced',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const CloudException('Сервер вернул неожиданный ответ');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudException(
          response.statusCode == 404
              ? 'Обновите Server Advanced, на нём ещё нет новых режимов подключения'
              : decoded['error'] as String? ?? 'Не удалось выполнить запрос',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on TimeoutException {
      throw const CloudException(
        'Сервер долго не отвечает. Проверьте подключение и повторите попытку',
      );
    }
  }

  Future<void> connectAdmin(String serverUrl, String apiToken) async {
    if (apiToken.trim().isEmpty) {
      throw const CloudException('Введите API ключ сервера');
    }
    final result = await request(
      '/auth-check',
      serverUrl: serverUrl,
      token: apiToken.trim(),
      get: true,
    );
    if (result['role'] != 'admin') {
      throw const CloudException(
        'Нужен ключ администратора обновлённого Server Advanced',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final sameServer =
        AppConfig.normalizeServerUrl(serverUrl) ==
        AppConfig.normalizeServerUrl(prefs.getString('cloud_server_url') ?? '');
    final previous = <String, dynamic>{
      if (sameServer && prefs.getString('cloud_role') == 'admin') ...{
        'registrationId': prefs.getString('cf3_registration_id'),
        'registrationSecret': prefs.getString('cf3_registration_secret'),
        'verificationToken': prefs.getString('cf3_verification_token'),
        'checkIntervalMinutes': prefs.getInt('cloud_check_interval'),
        'checkIntervalMaxMinutes': prefs.getInt('cloud_check_interval_max'),
      },
    };
    await _save(serverUrl, CloudRole.admin, apiToken.trim(), previous);
  }

  /// подключаем только уже существующий мониторинг. Пароль и cookie не отправляем
  Future<void> restoreAdminMonitoring() async {
    final pending = _pendingRestore;
    if (pending != null) return pending;
    final restore = _restoreAdminMonitoring();
    _pendingRestore = restore;
    try {
      await restore;
    } finally {
      _pendingRestore = null;
    }
  }

  Future<void> _restoreAdminMonitoring() async {
    final prefs = await SharedPreferences.getInstance();
    final api = ApiService();
    final username = api.savedUsername;
    final password = api.savedPassword;
    if (prefs.getString('cloud_role') != 'admin' ||
        prefs.getBool('cloud_enabled') != true ||
        (prefs.getString('cf3_registration_id')?.isNotEmpty == true &&
            prefs.getString('cf3_registration_secret')?.isNotEmpty == true) ||
        api.isDemo ||
        username == null ||
        password == null) {
      return;
    }
    final url = prefs.getString('cloud_server_url');
    final token = prefs.getString('cloud_api_token');
    if (url == null || token == null || token.isEmpty) return;
    final requestId = await _attemptId('$url:admin:attach:$username');
    final proof = Hmac(
      sha256,
      utf8.encode(password),
    ).convert(utf8.encode('reschool:attach:$requestId:$username')).toString();
    Map<String, dynamic> result;
    try {
      result = await request(
        '/cloud/account/attach',
        body: {
          'username': username,
          'requestId': requestId,
          'accountCredentialProof': proof,
          'deviceName': api.deviceModel,
        },
      );
    } on CloudException catch (error) {
      if (error.statusCode == 404) {
        return; // старый сервер: доступно ручное включение
      }
      rethrow;
    }
    if (result['monitoring'] != true) return;
    if (result['role'] != 'admin' ||
        result['registrationId'] is! String ||
        (result['registrationId'] as String).isEmpty ||
        result['registrationSecret'] is! String ||
        (result['registrationSecret'] as String).isEmpty) {
      throw const CloudException(
        'Сервер не вернул данные подключения к мониторингу',
      );
    }
    if (prefs.getString('cloud_server_url') != url ||
        prefs.getString('cloud_api_token') != token ||
        prefs.getString('cloud_role') != 'admin' ||
        prefs.getBool('cloud_enabled') != true ||
        api.savedUsername != username) {
      return;
    }
    await _save(url, CloudRole.admin, token, result);
  }

  Future<void> join({
    required String serverUrl,
    required String inviteToken,
    required CloudRole role,
    String? telegramUserId,
  }) async {
    if (role == CloudRole.admin) {
      throw const CloudException('Для администратора нужен API ключ');
    }
    final body = <String, dynamic>{
      'mode': role.name,
      'requestId': await _attemptId('$serverUrl:${role.name}:$inviteToken'),
      'inviteToken': inviteToken.trim(),
      'fullName': ApiService().userProfile?.fullName ?? 'Пользователь',
      if (role == CloudRole.user) ..._credentials(),
      if (role == CloudRole.user && (telegramUserId ?? '').trim().isNotEmpty)
        'telegramUserId': telegramUserId!.trim(),
    };
    final result = await request(
      '/cloud/join',
      serverUrl: serverUrl,
      public: true,
      body: body,
    );
    final token = result['apiToken'];
    if (token is! String ||
        token.isEmpty ||
        result['role'] != role.name ||
        result['classmateId'] == null ||
        (role == CloudRole.user && result['registrationSecret'] == null)) {
      throw const CloudException('Сервер не вернул данные подключения');
    }
    await _save(serverUrl, role, token, result);
  }

  Map<String, String> _credentials() {
    final api = ApiService();
    if (api.isDemo || api.savedUsername == null || api.savedPassword == null) {
      throw const CloudException(
        'Войдите в настоящий аккаунт eSchool перед включением мониторинга',
      );
    }
    return {'username': api.savedUsername!, 'password': api.savedPassword!};
  }

  Future<void> enableAdminMonitoring({String? gradeClass}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('cf3_registration_id') != null) return;
    final selectedClass = (gradeClass ?? '').trim();
    final resolvedClass = selectedClass.isNotEmpty
        ? selectedClass
        : await ApiService().currentGradeClass(forceRefresh: true);
    final result = await request(
      '/cloud/account',
      body: {
        ..._credentials(),
        'requestId': await _attemptId(
          '${prefs.getString('cloud_server_url')}:admin',
        ),
        'gradeClass': resolvedClass,
        'checkIntervalMinutes': prefs.getInt('cloud_check_interval') ?? 10,
      },
    );
    if (result['registrationId'] == null ||
        result['registrationSecret'] == null) {
      throw const CloudException('Сервер не вернул данные регистрации');
    }
    await _save(
      prefs.getString('cloud_server_url')!,
      CloudRole.admin,
      prefs.getString('cloud_api_token')!,
      result,
    );
  }

  Future<String> _attemptId(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    var nonce = prefs.getString('cloud_installation_nonce');
    if (nonce == null) {
      final random = Random.secure();
      nonce = base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      await prefs.setString('cloud_installation_nonce', nonce);
    }
    return sha256.convert(utf8.encode('$nonce:$scope')).toString();
  }

  Future<void> _save(
    String serverUrl,
    CloudRole role,
    String token,
    Map<String, dynamic> result,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final url = AppConfig.normalizeServerUrl(serverUrl);
    for (final entry in {
      'cf3_registration_id': result['registrationId'],
      'cf3_registration_secret': result['registrationSecret'],
      'cf3_verification_token': result['verificationToken'],
      'classmate_id': result['classmateId'],
      'classmate_token': role.isAdmin ? null : token,
    }.entries) {
      if (entry.value is String && (entry.value as String).isNotEmpty) {
        await prefs.setString(entry.key, entry.value as String);
      } else {
        await prefs.remove(entry.key);
      }
    }
    await prefs.setString('cloud_server_url', url);
    await prefs.setString('cf3_registered_server', url);
    await prefs.setString('cloud_api_token', token);
    await prefs.setString('cloud_role', role.name);
    await prefs.setBool('is_classmate', role == CloudRole.classmate);
    await prefs.setBool('cloud_enabled', true);
    await prefs.setInt(
      'cloud_check_interval',
      result['checkIntervalMinutes'] as int? ?? 10,
    );
    final intervalMax = result['checkIntervalMaxMinutes'] as int?;
    if (intervalMax != null) {
      await prefs.setInt('cloud_check_interval_max', intervalMax);
    } else {
      await prefs.remove('cloud_check_interval_max');
    }
    // старый токен личного бота больше не нужен даже администратору
    await prefs.remove('cloud_telegram_bot_token');
    await prefs.remove('cf3_telegram_bot_token');
    AnalysisService().clearCache();
    await CloudFunctionsService().loadRegistrationState();
  }

  Future<void> disconnect({bool localOnly = false}) async {
    if (!localOnly) await request('/cloud/leave');
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('cf3_') ||
          (key.startsWith('cloud_') &&
              !key.startsWith('cloud_ssh_host:') &&
              key != 'cloud_promo_shown') ||
          key.startsWith('classmate_') ||
          key == 'is_classmate') {
        await prefs.remove(key);
      }
    }
    AnalysisService().clearCache();
    await CloudFunctionsService().loadRegistrationState();
  }
}
