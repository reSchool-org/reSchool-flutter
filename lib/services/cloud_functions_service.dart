import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'reschool_http.dart';
import 'api_service.dart';

/// работа с облаком: пуши про новые домашние задания и оценки
/// логин с паролем уезжают на свой сервер, который сам следит за обновлениями
class CloudFunctionsService {
  static final CloudFunctionsService _instance =
      CloudFunctionsService._internal();
  factory CloudFunctionsService() => _instance;
  CloudFunctionsService._internal();

  final ApiService _apiService = ApiService();

  bool _isRegistered = false;
  String? _registeredServerUrl;

  bool get isRegistered => _isRegistered;
  String? get registeredServerUrl => _registeredServerUrl;

  /// сохранённые токены привязаны к настроенному серверу, а не к тому, что передали сейчас
  Future<Map<String, String>> _authHeaders(
    String serverUrl, {
    String? apiToken,
  }) async {
    final origin = _serverOrigin(serverUrl);
    if (origin == null) throw const FormatException('Invalid server URL');
    final prefs = await SharedPreferences.getInstance();
    // порядок тот же, что в SettingsProvider: сначала новый ключ, потом старый
    // у древних регистраций есть только cf3_registered_server, но настроенный url важнее
    final savedServerUrl =
        prefs.getString('cloud_server_url') ??
        prefs.getString('cf3_custom_server_url') ??
        prefs.getString('cf3_registered_server');
    final token =
        apiToken ??
        (savedServerUrl != null && origin == _serverOrigin(savedServerUrl)
            ? prefs.getString('cloud_api_token') ?? ''
            : '');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token.isNotEmpty) headers['X-API-Token'] = token;
    return headers;
  }

  String? _serverOrigin(String serverUrl) {
    try {
      final normalized = _normalizeServerUrl(serverUrl);
      final uri = Uri.parse(normalized);
      if (uri.host.isEmpty ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.userInfo.isNotEmpty ||
          RegExp(r'^[^:]+://[^/?#]*@').hasMatch(normalized) ||
          uri.hasQuery ||
          uri.hasFragment) {
        return null;
      }
      // класс Uri приводит хост к нижнему регистру и убирает порт по умолчанию, а путь к origin не относится
      return uri.origin;
    } on FormatException {
      return null;
    }
  }

  String _normalizeServerUrl(String serverUrl) {
    return AppConfig.normalizeServerUrl(serverUrl);
  }

  String? _credentialServerUrlError(String serverUrl) {
    if (_serverOrigin(serverUrl) == null) return 'Invalid server URL';
    final uri = Uri.tryParse(serverUrl);
    if (uri == null || uri.host.isEmpty) return 'Invalid server URL';
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' && _isLocalhost(uri.host)) return null;
    return 'Server URL must use HTTPS when sending eSchool credentials';
  }

  bool _isLocalhost(String host) {
    final lower = host.toLowerCase();
    return lower == 'localhost' || lower == '127.0.0.1' || lower == '::1';
  }

  Map<String, dynamic>? _decodeJsonObject(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _unexpectedJsonResponseMessage(http.Response response) {
    final body = response.body.trimLeft().toLowerCase();
    if (body.startsWith('<!doctype') || body.startsWith('<html')) {
      return 'По этому адресу отвечает веб-страница, а не server_advanced. '
          'Проверьте IP, порт 20001 и что запущен сервер из папки server/server_advanced.';
    }
    return 'Сервер вернул неожиданный ответ. Проверьте, что URL ведёт на server_advanced.';
  }

  /// запрашивает у сервера код подтверждения,
  /// сервер отправит его в чат eSchool
  Future<CloudFunctionsResult> requestVerification({
    required String serverUrl,
  }) async {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    if (normalizedServerUrl.isEmpty) {
      return CloudFunctionsResult(
        success: false,
        error: 'Server URL is required',
      );
    }
    final urlError = _credentialServerUrlError(normalizedServerUrl);
    if (urlError != null) {
      return CloudFunctionsResult(success: false, error: urlError);
    }

    try {
      final url = Uri.parse('$normalizedServerUrl/request-verification');
      debugPrint(
        '[CloudFunctions] Requesting verification from: $normalizedServerUrl',
      );

      final response = await reschoolHttp.post(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: true,
          verificationCode: data['code'],
          targetPrsId: data['targetPrsId'],
        );
      } else {
        debugPrint(
          '[CloudFunctions] Request verification failed: ${response.statusCode} - ${response.body}',
        );
        return CloudFunctionsResult(
          success: false,
          error: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Request verification error: $e');
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// проверяет подтверждение и забирает токен
  Future<CloudFunctionsResult> checkVerification({
    required String serverUrl,
    required String code,
    required int threadId,
    String? deviceName,
    String? fullName,
    String? gradeClass,
  }) async {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    if (normalizedServerUrl.isEmpty) {
      return CloudFunctionsResult(
        success: false,
        error: 'Server URL is required',
      );
    }
    final urlError = _credentialServerUrlError(normalizedServerUrl);
    if (urlError != null) {
      return CloudFunctionsResult(success: false, error: urlError);
    }

    try {
      final url = Uri.parse('$normalizedServerUrl/check-verification');
      final headers = {'Content-Type': 'application/json'};
      final bodyMap = <String, dynamic>{'code': code, 'threadId': threadId};

      if (deviceName != null) bodyMap['deviceName'] = deviceName;
      if (fullName != null) bodyMap['fullName'] = fullName;
      if (gradeClass != null) bodyMap['gradeClass'] = gradeClass;

      final body = jsonEncode(bodyMap);
      debugPrint(
        '[CloudFunctions] Checking verification at: $normalizedServerUrl',
      );

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['verified'] == true) {
          return CloudFunctionsResult(
            success: true,
            verificationToken: data['token'],
          );
        } else {
          return CloudFunctionsResult(
            success: false,
            error: 'Verification failed',
          );
        }
      } else {
        debugPrint(
          '[CloudFunctions] Check verification failed: ${response.statusCode} - ${response.body}',
        );
        return CloudFunctionsResult(
          success: false,
          error: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Check verification error: $e');
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// регистрирует устройство на пуши
  /// шлёт на сервер токен, логин, пароль и интервал опроса
  Future<CloudFunctionsResult> register({
    required String serverUrl,
    required int checkIntervalMinutes,
    required String verificationToken,
    String? apiToken,
    String? deviceName,
    String? fullName,
    String? gradeClass,
  }) async {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    if (normalizedServerUrl.isEmpty) {
      return CloudFunctionsResult(
        success: false,
        error: 'Server URL is required',
      );
    }
    final urlError = _credentialServerUrlError(normalizedServerUrl);
    if (urlError != null) {
      return CloudFunctionsResult(success: false, error: urlError);
    }

    // креды берём из ApiService
    final username = _apiService.savedUsername;
    final password = _apiService.savedPassword;

    if (username == null || password == null) {
      return CloudFunctionsResult(
        success: false,
        error: 'User credentials not available. Please re-login.',
      );
    }

    try {
      final url = Uri.parse('$normalizedServerUrl/register');
      final headers = await _authHeaders(
        normalizedServerUrl,
        apiToken: apiToken,
      );
      final bodyMap = <String, dynamic>{
        'token': verificationToken,
        'username': username,
        'password': password,
        'checkIntervalMinutes': checkIntervalMinutes,
      };

      if (deviceName != null) {
        bodyMap['deviceName'] = deviceName;
      }

      // класс сервер сам узнать не может, чужой класс eSchool по prsId не отдаёт
      final gradeClass = await _apiService.currentGradeClass();
      if (gradeClass != null) {
        bodyMap['gradeClass'] = gradeClass;
      }
      if (fullName != null) {
        bodyMap['fullName'] = fullName;
      }
      if (gradeClass != null) {
        bodyMap['gradeClass'] = gradeClass;
      }

      final body = jsonEncode(bodyMap);

      debugPrint(
        '[CloudFunctions] Registering with server: $normalizedServerUrl',
      );

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final registrationId = data['registrationId'];
        final registrationSecret = data['registrationSecret'] as String?;

        // запоминаем регистрацию
        await _saveRegistration(
          normalizedServerUrl,
          registrationId,
          verificationToken,
          registrationSecret,
        );

        _isRegistered = true;
        _registeredServerUrl = normalizedServerUrl;

        debugPrint(
          '[CloudFunctions] Registration successful. ID: $registrationId',
        );

        return CloudFunctionsResult(
          success: true,
          registrationId: registrationId,
        );
      } else {
        debugPrint(
          '[CloudFunctions] Registration failed: ${response.statusCode} - ${response.body}',
        );
        return CloudFunctionsResult(
          success: false,
          error: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Registration error: $e');
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// отписка от сервера
  Future<CloudFunctionsResult> unregister() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');

    if (serverUrl == null || registrationId == null) {
      _isRegistered = false;
      _registeredServerUrl = null;
      return CloudFunctionsResult(success: true);
    }

    try {
      final url = Uri.parse('$serverUrl/unregister');
      final headers = await _authHeaders(serverUrl);
      final body = jsonEncode(
        await _registrationBody({'registrationId': registrationId}),
      );

      debugPrint('[CloudFunctions] Unregistering from server: $serverUrl');

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      // локальную регистрацию чистим независимо от ответа сервера
      await _clearRegistration();
      _isRegistered = false;
      _registeredServerUrl = null;

      if (response.statusCode == 200) {
        debugPrint('[CloudFunctions] Unregistration successful');
        return CloudFunctionsResult(success: true);
      } else {
        debugPrint(
          '[CloudFunctions] Unregistration response: ${response.statusCode}',
        );
        // локально всё почищено, так что для вызывающего это успех
        return CloudFunctionsResult(success: true);
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Unregistration error: $e');
      // даже на ошибке локальную регистрацию убираем
      await _clearRegistration();
      _isRegistered = false;
      _registeredServerUrl = null;
      return CloudFunctionsResult(success: true);
    }
  }

  /// поменять интервал опроса на сервере
  Future<CloudFunctionsResult> updateInterval(int checkIntervalMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');

    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(success: false, error: 'Not registered');
    }

    try {
      final url = Uri.parse('$serverUrl/update-interval');
      final headers = await _authHeaders(serverUrl);
      final body = jsonEncode(
        await _registrationBody({
          'registrationId': registrationId,
          'checkIntervalMinutes': checkIntervalMinutes,
        }),
      );

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        debugPrint(
          '[CloudFunctions] Interval updated to $checkIntervalMinutes min',
        );
        return CloudFunctionsResult(success: true);
      } else {
        return CloudFunctionsResult(
          success: false,
          error: 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// поднять сохранённое состояние регистрации
  Future<void> loadRegistrationState() async {
    final prefs = await SharedPreferences.getInstance();
    _registeredServerUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    final isClassmate = prefs.getBool('is_classmate') ?? false;
    final classmateId = prefs.getString('classmate_id');
    // у одноклассников нет cf3_registration_id, вместо него classmate_id
    _isRegistered =
        _registeredServerUrl != null &&
        (registrationId != null ||
            (isClassmate && classmateId != null) ||
            prefs.getString('cloud_role') == 'admin');
  }

  Future<void> _saveRegistration(
    String serverUrl,
    String? registrationId,
    String? verificationToken,
    String? registrationSecret,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cf3_registered_server', serverUrl);
    if (registrationId != null) {
      await prefs.setString('cf3_registration_id', registrationId);
    }
    if (registrationSecret != null && registrationSecret.isNotEmpty) {
      await prefs.setString('cf3_registration_secret', registrationSecret);
    }
    if (verificationToken != null && verificationToken.isNotEmpty) {
      await prefs.setString('cf3_verification_token', verificationToken);
    }
  }

  Future<Map<String, dynamic>> _registrationBody(
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final registrationSecret = prefs.getString('cf3_registration_secret');
    if (registrationSecret != null && registrationSecret.isNotEmpty) {
      body['registrationSecret'] = registrationSecret;
    }
    return body;
  }

  Future<void> _clearRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cf3_registered_server');
    await prefs.remove('cf3_registration_id');
    await prefs.remove('cf3_registration_secret');
    await prefs.remove('cf3_verification_token');
  }

  /// обновить настройки телеграма на сервере
  Future<CloudFunctionsResult> updateTelegramSettings({
    required bool telegramEnabled,
    String? telegramBotToken,
    String? telegramUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');

    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(
        success: false,
        error: 'Not registered with server',
      );
    }

    try {
      final url = Uri.parse('$serverUrl/update-telegram');
      final headers = await _authHeaders(serverUrl);
      final body = jsonEncode(
        await _registrationBody({
          'registrationId': registrationId,
          'telegramEnabled': telegramEnabled,
          'telegramBotToken': telegramBotToken,
          'telegramUserId': telegramUserId,
        }),
      );

      debugPrint('[CloudFunctions] Updating Telegram settings');

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        debugPrint('[CloudFunctions] Telegram settings updated');
        return CloudFunctionsResult(success: true);
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Telegram update error: $e');
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// проверка связи с телеграмом: шлём тестовое сообщение
  Future<CloudFunctionsResult> testTelegram({
    required String telegramBotToken,
    required String telegramUserId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');

    if (serverUrl == null) {
      return CloudFunctionsResult(
        success: false,
        error: 'Not registered with server',
      );
    }

    try {
      final url = Uri.parse('$serverUrl/test-telegram');
      final headers = await _authHeaders(serverUrl);
      final body = jsonEncode({
        'telegramBotToken': telegramBotToken,
        'telegramUserId': telegramUserId,
      });

      debugPrint('[CloudFunctions] Testing Telegram connection');

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        debugPrint('[CloudFunctions] Telegram test successful');
        return CloudFunctionsResult(success: true);
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Telegram test error: $e');
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// забрать текущие настройки телеграма с сервера
  Future<CloudFunctionsTelegramStatus?> getTelegramStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');

    if (serverUrl == null || registrationId == null) {
      return null;
    }

    try {
      final url = Uri.parse('$serverUrl/get-telegram-status');
      final headers = await _authHeaders(serverUrl);
      final body = jsonEncode(
        await _registrationBody({'registrationId': registrationId}),
      );

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // карта топиков приходит то строкой с json, то объектом
        Map<String, int> topicMap = {};
        final rawTopicMap = data['telegramTopicMap'];
        if (rawTopicMap != null) {
          Map<String, dynamic> parsed = {};
          if (rawTopicMap is String && rawTopicMap.isNotEmpty) {
            try {
              parsed = jsonDecode(rawTopicMap);
            } catch (_) {}
          } else if (rawTopicMap is Map) {
            parsed = Map<String, dynamic>.from(rawTopicMap);
          }
          topicMap = parsed.map((k, v) => MapEntry(k, (v as num).toInt()));
        }
        return CloudFunctionsTelegramStatus(
          telegramEnabled: data['telegramEnabled'] ?? false,
          telegramBotToken: data['telegramBotToken'] ?? '',
          telegramUserId: data['telegramUserId'] ?? '',
          groupEnabled: data['telegramGroupEnabled'] ?? false,
          groupChatId: data['telegramGroupChatId'] ?? '',
          groupTitle: data['telegramGroupTitle'] ?? '',
          topicMap: topicMap,
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Get Telegram status error: $e');
    }
    return null;
  }

  /// обновить настройки телеграм группы на сервере
  Future<CloudFunctionsResult> updateTelegramGroup({
    required bool groupEnabled,
    String? groupChatId,
    String? groupTitle,
    Map<String, int>? topicMap,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');

    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(
        success: false,
        error: 'Not registered with server',
      );
    }

    try {
      final url = Uri.parse('$serverUrl/update-telegram-group');
      final headers = await _authHeaders(serverUrl);
      final bodyMap = await _registrationBody(<String, dynamic>{
        'registrationId': registrationId,
        'telegramGroupEnabled': groupEnabled,
        'telegramGroupChatId': groupChatId ?? '',
        'telegramGroupTitle': groupTitle ?? '',
      });
      if (topicMap != null) {
        bodyMap['telegramTopicMap'] = topicMap;
      }
      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: jsonEncode(bodyMap),
      );

      if (response.statusCode == 200) {
        return CloudFunctionsResult(success: true);
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// инфа о группе (название, топики, предметы) прямо из базы, без похода в телеграм
  Future<CloudFunctionsGroupInfo?> getGroupInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) return null;
    try {
      final url = Uri.parse('$serverUrl/get-group-info');
      final response = await reschoolHttp.post(
        url,
        headers: await _authHeaders(serverUrl),
        body: jsonEncode(
          await _registrationBody({'registrationId': registrationId}),
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawTopicMap =
            (data['topicMap'] as Map?)?.cast<String, dynamic>() ?? {};
        final topicMap = rawTopicMap.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
        final rawSubjects =
            (data['subjects'] as Map?)?.cast<String, dynamic>() ?? {};
        final subjects = rawSubjects.map((k, v) => MapEntry(k, v as String));
        return CloudFunctionsGroupInfo(
          groupEnabled: data['groupEnabled'] ?? false,
          groupChatId: data['groupChatId'] ?? '',
          groupTitle: data['groupTitle'] ?? '',
          topicMap: topicMap,
          subjects: subjects,
        );
      }
    } catch (e) {
      return CloudFunctionsGroupInfo(
        groupEnabled: false,
        groupChatId: '',
        groupTitle: '',
        topicMap: {},
        subjects: {},
        error: '$e',
      );
    }
    return null;
  }

  /// настройки пересылки чатов с сервера,
  /// отдаёт threadId → topicId, где topicId пустой, если топик не задан
  Future<Map<int, int?>?> getChatForwardSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) return null;

    try {
      final url = Uri.parse('$serverUrl/get-chat-forward');
      final response = await reschoolHttp.post(
        url,
        headers: await _authHeaders(serverUrl),
        body: jsonEncode(
          await _registrationBody({'registrationId': registrationId}),
        ),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw =
            (data['chatForwardMap'] as Map?)?.cast<String, dynamic>() ?? {};
        return raw.map(
          (k, v) =>
              MapEntry(int.parse(k), v == null ? null : (v as num).toInt()),
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] getChatForwardSettings error: $e');
    }
    return null;
  }

  /// код активации телеграм группы, живёт 15 минут
  Future<CloudFunctionsGroupCodeResult> generateGroupCode() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsGroupCodeResult(
        success: false,
        error: 'Not registered',
      );
    }
    try {
      final url = Uri.parse('$serverUrl/generate-group-code');
      final response = await reschoolHttp.post(
        url,
        headers: await _authHeaders(serverUrl),
        body: jsonEncode(
          await _registrationBody({'registrationId': registrationId}),
        ),
      );
      if (response.statusCode == 200) {
        final d = jsonDecode(response.body);
        return CloudFunctionsGroupCodeResult(
          success: true,
          code: d['code'] as String,
          command: d['command'] as String,
          expiresInMinutes: d['expiresInMinutes'] as int,
        );
      }
      final d = jsonDecode(response.body);
      return CloudFunctionsGroupCodeResult(
        success: false,
        error: d['error'] ?? 'Server error',
      );
    } catch (e) {
      return CloudFunctionsGroupCodeResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// запускает на сервере автоопределение топика,
  /// дальше пользователь должен написать 'п' в нужный топик группы
  Future<CloudFunctionsResult> requestTopicDetect() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(success: false, error: 'Not registered');
    }
    try {
      final url = Uri.parse('$serverUrl/request-topic-detect');
      final response = await reschoolHttp.post(
        url,
        headers: await _authHeaders(serverUrl),
        body: jsonEncode(
          await _registrationBody({'registrationId': registrationId}),
        ),
      );
      if (response.statusCode == 200) {
        return CloudFunctionsResult(success: true);
      }
      final d = jsonDecode(response.body);
      return CloudFunctionsResult(
        success: false,
        error: d['error'] ?? 'Server error: ${response.statusCode}',
      );
    } catch (e) {
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// спрашиваем, определился ли топик, пусто значит ещё нет
  Future<int?> pollDetectedTopic() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) return null;
    try {
      final url = Uri.parse('$serverUrl/poll-detected-topic');
      final response = await reschoolHttp.post(
        url,
        headers: await _authHeaders(serverUrl),
        body: jsonEncode(
          await _registrationBody({'registrationId': registrationId}),
        ),
      );
      if (response.statusCode == 200) {
        final d = jsonDecode(response.body);
        final v = d['topicId'];
        return v == null ? null : (v as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  /// обновить настройки пересылки чатов на сервере
  /// chatForwardMap: threadId → topicId, пустой topicId значит писать в основной чат
  Future<CloudFunctionsResult> updateChatForwardSettings(
    Map<int, int?> chatForwardMap,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');

    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(
        success: false,
        error: 'Not registered with server',
      );
    }

    try {
      final url = Uri.parse('$serverUrl/update-chat-forward');
      final headers = await _authHeaders(serverUrl);
      final mapForJson = chatForwardMap.map(
        (k, v) => MapEntry(k.toString(), v),
      );
      final body = jsonEncode(
        await _registrationBody({
          'registrationId': registrationId,
          'chatForwardMap': mapForJson,
        }),
      );
      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        debugPrint('[CloudFunctions] Chat forward settings updated');
        return CloudFunctionsResult(success: true);
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] updateChatForwardSettings error: $e');
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// разослать название каждого предмета в привязанный к нему топик
  Future<CloudFunctionsResult> sendTopicLabels() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(
        success: false,
        error: 'Not registered with server',
      );
    }

    try {
      final url = Uri.parse('$serverUrl/send-topic-labels');
      final headers = await _authHeaders(serverUrl);
      final body = jsonEncode(
        await _registrationBody({'registrationId': registrationId}),
      );
      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
          '[CloudFunctions] sendTopicLabels sent=${data['sent']} errors=${data['errors']}',
        );
        return CloudFunctionsResult(success: true);
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] sendTopicLabels error: $e');
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// одноразовый инвайт для одноклассника, только для админа
  /// отдаёт токен и его срок годности, при ошибке пусто
  Future<ClassmateInviteResult> generateClassmateInvite({
    required String serverUrl,
  }) async {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    final prefs = await SharedPreferences.getInstance();
    final registrationId = prefs.getString('cf3_registration_id');

    if (registrationId == null) {
      return ClassmateInviteResult(success: false, error: 'Not registered');
    }

    try {
      final url = Uri.parse('$normalizedServerUrl/generate-classmate-invite');
      final headers = await _authHeaders(normalizedServerUrl);
      final body = jsonEncode(
        await _registrationBody({'registrationId': registrationId}),
      );

      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ClassmateInviteResult(
          success: true,
          inviteToken: data['inviteToken'] as String,
          expiresInMinutes: data['expiresInMinutes'] as int? ?? 60,
        );
      } else {
        final data = jsonDecode(response.body);
        return ClassmateInviteResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return ClassmateInviteResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// регистрация одноклассника по инвайту,
  /// креды eSchool на сервер при этом не уходят
  Future<CloudFunctionsResult> classmateJoin({
    required String serverUrl,
    required String inviteToken,
    required String verificationToken,
    required int checkIntervalMinutes,
    String? deviceName,
    String? fullName,
  }) async {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    if (normalizedServerUrl.isEmpty) {
      return CloudFunctionsResult(
        success: false,
        error: 'Server URL is required',
      );
    }
    final urlError = _credentialServerUrlError(normalizedServerUrl);
    if (urlError != null) {
      return CloudFunctionsResult(success: false, error: urlError);
    }

    try {
      final url = Uri.parse('$normalizedServerUrl/classmate-join');
      final bodyMap = <String, dynamic>{
        'inviteToken': inviteToken,
        'verificationToken': verificationToken,
        'checkIntervalMinutes': checkIntervalMinutes,
      };
      if (deviceName != null) bodyMap['deviceName'] = deviceName;
      if (fullName != null) bodyMap['fullName'] = fullName;

      final response = await reschoolHttp.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyMap),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final classmateId = data['classmateId'] as String?;
        final classmateToken = data['classmateToken'] as String?;
        // складываем ключи одноклассника, чтобы потом узнать эту регистрацию
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cf3_registered_server', normalizedServerUrl);
        if (classmateId != null) {
          await prefs.setString('classmate_id', classmateId);
        }
        if (classmateToken != null) {
          await prefs.setString('classmate_token', classmateToken);
        }
        await prefs.setBool('is_classmate', true);
        _isRegistered = true;
        _registeredServerUrl = normalizedServerUrl;
        return CloudFunctionsResult(
          success: true,
          registrationId: classmateId,
          // отдаём classmateToken как verificationToken, вызывающий положит его в cloudApiToken
          verificationToken: classmateToken,
        );
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// выйти из класса, дёргает на сервере classmate leave
  Future<CloudFunctionsResult> classmateLeave() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    if (serverUrl == null) {
      _isRegistered = false;
      _registeredServerUrl = null;
      return CloudFunctionsResult(success: true);
    }
    try {
      final url = Uri.parse('$serverUrl/classmate-leave');
      final headers = await _authHeaders(serverUrl);
      await reschoolHttp.post(url, headers: headers, body: jsonEncode({}));
    } catch (e) {
      debugPrint('[CloudFunctions] classmateLeave error: $e');
    }
    await _clearRegistration();
    _isRegistered = false;
    _registeredServerUrl = null;
    return CloudFunctionsResult(success: true);
  }

  /// проверить, не протухла ли сессия аккаунта на сервере
  Future<CloudFunctionsAccountStatus?> getAccountStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) return null;

    try {
      final url = Uri.parse('$serverUrl/get-account-status');
      final response = await http
          .post(
            url,
            headers: await _authHeaders(serverUrl),
            body: jsonEncode(
              await _registrationBody({'registrationId': registrationId}),
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CloudFunctionsAccountStatus(
          sessionInvalid: data['sessionInvalid'] ?? false,
          reason: data['reason'],
          invalidAt: data['invalidAt'],
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] getAccountStatus error: $e');
    }
    return null;
  }

  /// перелогиниться сохранёнными кредами и поднять остановленную сессию
  Future<CloudFunctionsResult> retrySession() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(success: false, error: 'Not registered');
    }
    final urlError = _credentialServerUrlError(serverUrl);
    if (urlError != null) {
      return CloudFunctionsResult(success: false, error: urlError);
    }

    try {
      final url = Uri.parse('$serverUrl/retry-session');
      final response = await http
          .post(
            url,
            headers: await _authHeaders(serverUrl),
            body: jsonEncode(
              await _registrationBody({'registrationId': registrationId}),
            ),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return CloudFunctionsResult(success: true);
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// обновить сохранённый пароль и восстановить сессию
  Future<CloudFunctionsResult> updatePassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    final registrationId = prefs.getString('cf3_registration_id');
    if (serverUrl == null || registrationId == null) {
      return CloudFunctionsResult(success: false, error: 'Not registered');
    }
    final urlError = _credentialServerUrlError(serverUrl);
    if (urlError != null) {
      return CloudFunctionsResult(success: false, error: urlError);
    }

    try {
      final url = Uri.parse('$serverUrl/update-password');
      final response = await http
          .post(
            url,
            headers: await _authHeaders(serverUrl),
            body: jsonEncode(
              await _registrationBody({
                'registrationId': registrationId,
                'password': password,
              }),
            ),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return CloudFunctionsResult(success: true);
      } else {
        final data = jsonDecode(response.body);
        return CloudFunctionsResult(
          success: false,
          error: data['error'] ?? 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  /// конфиг сервера: интервалы и прочее
  Future<CloudFunctionsConfig?> getConfig(String serverUrl) async {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    if (normalizedServerUrl.isEmpty) return null;

    try {
      final url = Uri.parse('$normalizedServerUrl/config');

      final response = await reschoolHttp.get(url);

      if (response.statusCode == 200) {
        final data = _decodeJsonObject(response);
        if (data == null) {
          debugPrint(
            '[CloudFunctions] Config returned non-JSON: ${response.statusCode}',
          );
          return null;
        }
        return CloudFunctionsConfig(
          minCheckIntervalMinutes: data['minCheckIntervalMinutes'] ?? 10,
          defaultCheckIntervalMinutes:
              data['defaultCheckIntervalMinutes'] ?? 10,
          serverDomain: data['domain'] as String? ?? '',
          publicBaseUrl: data['publicBaseUrl'] as String? ?? '',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Get config error: $e');
    }
    return null;
  }

  Future<CloudFunctionsResult> checkApiToken({
    required String serverUrl,
    required String apiToken,
  }) async {
    final normalizedServerUrl = _normalizeServerUrl(serverUrl);
    if (normalizedServerUrl.isEmpty) {
      return CloudFunctionsResult(
        success: false,
        error: 'Server URL is required',
      );
    }

    try {
      final url = Uri.parse('$normalizedServerUrl/auth-check');
      final response = await reschoolHttp.get(
        url,
        headers: await _authHeaders(normalizedServerUrl, apiToken: apiToken),
      );
      final data = _decodeJsonObject(response);

      if (response.statusCode == 200) {
        return CloudFunctionsResult(success: true);
      }

      if (response.statusCode == 404) {
        // совместимость со старыми сборками server_advanced: авторизация там
        // отрабатывает до роутинга, поэтому 404 значит, что токен приняли
        return CloudFunctionsResult(success: true);
      }

      return CloudFunctionsResult(
        success: false,
        error: response.statusCode == 401
            ? 'Неверный API Token. Проверьте API_TOKEN в .env на сервере.'
            : data == null
            ? _unexpectedJsonResponseMessage(response)
            : data['error'] as String? ??
                  'Server error: ${response.statusCode}',
      );
    } catch (e) {
      return CloudFunctionsResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<CloudFunctionsDomainStatus?> getServerDomainStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final serverUrl = prefs.getString('cf3_registered_server');
    if (serverUrl == null) return null;

    try {
      final url = Uri.parse('${_normalizeServerUrl(serverUrl)}/server-domain');
      final response = await reschoolHttp.get(
        url,
        headers: await _authHeaders(serverUrl),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CloudFunctionsDomainStatus(
          domain: data['domain'] as String? ?? '',
          publicBaseUrl: data['publicBaseUrl'] as String? ?? '',
        );
      }
    } catch (e) {
      debugPrint('[CloudFunctions] Get server domain error: $e');
    }
    return null;
  }

  Future<CloudFunctionsIpBlacklistResult> getIpBlacklist({
    String? serverUrl,
    String? apiToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final targetServerUrl =
        serverUrl ?? prefs.getString('cf3_registered_server');
    if (targetServerUrl == null || targetServerUrl.trim().isEmpty) {
      return CloudFunctionsIpBlacklistResult(
        success: false,
        error: 'Server URL is required',
      );
    }

    try {
      final url = Uri.parse(
        '${_normalizeServerUrl(targetServerUrl)}/ip-blacklist',
      );
      final response = await reschoolHttp.get(
        url,
        headers: await _authHeaders(targetServerUrl, apiToken: apiToken),
      );
      final data = _decodeJsonObject(response);
      if (data == null) {
        return CloudFunctionsIpBlacklistResult(
          success: false,
          error: _unexpectedJsonResponseMessage(response),
        );
      }

      if (response.statusCode == 200) {
        final rawEntries = data['entries'];
        return CloudFunctionsIpBlacklistResult(
          success: true,
          entries: rawEntries is List
              ? rawEntries.map((e) => e.toString()).toList()
              : const [],
        );
      }

      return CloudFunctionsIpBlacklistResult(
        success: false,
        error: response.statusCode == 401
            ? 'Неверный API Token. Проверьте API_TOKEN в .env на сервере.'
            : data['error'] as String? ??
                  'Server error: ${response.statusCode}',
      );
    } catch (e) {
      return CloudFunctionsIpBlacklistResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<CloudFunctionsIpBlacklistResult> updateIpBlacklist({
    required List<String> entries,
    String? serverUrl,
    String? apiToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final targetServerUrl =
        serverUrl ?? prefs.getString('cf3_registered_server');
    if (targetServerUrl == null || targetServerUrl.trim().isEmpty) {
      return CloudFunctionsIpBlacklistResult(
        success: false,
        error: 'Server URL is required',
      );
    }

    try {
      final url = Uri.parse(
        '${_normalizeServerUrl(targetServerUrl)}/ip-blacklist',
      );
      final response = await reschoolHttp.post(
        url,
        headers: await _authHeaders(targetServerUrl, apiToken: apiToken),
        body: jsonEncode({'entries': entries}),
      );
      final data = _decodeJsonObject(response);
      if (data == null) {
        return CloudFunctionsIpBlacklistResult(
          success: false,
          error: _unexpectedJsonResponseMessage(response),
        );
      }

      if (response.statusCode == 200) {
        final rawEntries = data['entries'];
        return CloudFunctionsIpBlacklistResult(
          success: true,
          entries: rawEntries is List
              ? rawEntries.map((e) => e.toString()).toList()
              : const [],
        );
      }

      return CloudFunctionsIpBlacklistResult(
        success: false,
        error: response.statusCode == 401
            ? 'Неверный API Token. Проверьте API_TOKEN в .env на сервере.'
            : data['error'] as String? ??
                  'Server error: ${response.statusCode}',
      );
    } catch (e) {
      return CloudFunctionsIpBlacklistResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<CloudFunctionsDomainResult> updateServerDomain(
    String domain, {
    String? serverUrl,
    String? apiToken,
    ValueChanged<CloudFunctionsDomainJob>? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final targetServerUrl =
        serverUrl ?? prefs.getString('cf3_registered_server');
    if (targetServerUrl == null || targetServerUrl.trim().isEmpty) {
      return CloudFunctionsDomainResult(
        success: false,
        error: 'Server URL is required',
      );
    }

    try {
      final url = Uri.parse(
        '${_normalizeServerUrl(targetServerUrl)}/server-domain',
      );
      final response = await reschoolHttp.post(
        url,
        headers: await _authHeaders(targetServerUrl, apiToken: apiToken),
        body: jsonEncode({'domain': domain}),
      );
      final data = _decodeJsonObject(response);
      if (data == null) {
        return CloudFunctionsDomainResult(
          success: false,
          error: _unexpectedJsonResponseMessage(response),
        );
      }

      if (response.statusCode == 202 && data['jobId'] != null) {
        final jobId = data['jobId'] as String;
        onProgress?.call(CloudFunctionsDomainJob.fromJson(data));

        for (var i = 0; i < 120; i++) {
          await Future.delayed(const Duration(seconds: 1));
          final statusUrl = Uri.parse(
            '${_normalizeServerUrl(targetServerUrl)}/server-domain/status/$jobId',
          );
          final statusResponse = await reschoolHttp.get(
            statusUrl,
            headers: await _authHeaders(targetServerUrl, apiToken: apiToken),
          );
          final statusData = _decodeJsonObject(statusResponse);
          if (statusData == null) {
            return CloudFunctionsDomainResult(
              success: false,
              error: _unexpectedJsonResponseMessage(statusResponse),
            );
          }

          if (statusResponse.statusCode != 200) {
            return CloudFunctionsDomainResult(
              success: false,
              error:
                  statusData['error'] as String? ??
                  'Server error: ${statusResponse.statusCode}',
            );
          }

          final job = CloudFunctionsDomainJob.fromJson(statusData);
          onProgress?.call(job);

          if (job.status == 'success') {
            await _saveDomainServerUrl(prefs, job.publicBaseUrl);
            return CloudFunctionsDomainResult(
              success: true,
              domain: job.domain,
              publicBaseUrl: job.publicBaseUrl,
            );
          }

          if (job.status == 'failed') {
            return CloudFunctionsDomainResult(
              success: false,
              error: job.error ?? job.message,
            );
          }
        }

        return CloudFunctionsDomainResult(
          success: false,
          error: 'Превышено время ожидания выпуска сертификата',
        );
      }

      if (response.statusCode == 200) {
        final publicBaseUrl = data['publicBaseUrl'] as String? ?? '';
        await _saveDomainServerUrl(prefs, publicBaseUrl);
        return CloudFunctionsDomainResult(
          success: true,
          domain: data['domain'] as String? ?? '',
          publicBaseUrl: publicBaseUrl,
        );
      }

      final serverError = data['error'] as String?;
      return CloudFunctionsDomainResult(
        success: false,
        error: response.statusCode == 401
            ? 'Неверный API Token. Проверьте API_TOKEN в .env на сервере.'
            : serverError ?? 'Server error: ${response.statusCode}',
      );
    } catch (e) {
      return CloudFunctionsDomainResult(
        success: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<void> _saveDomainServerUrl(
    SharedPreferences prefs,
    String publicBaseUrl,
  ) async {
    if (publicBaseUrl.isEmpty) return;
    final normalizedPublicBaseUrl = _normalizeServerUrl(publicBaseUrl);
    await prefs.setString('cf3_registered_server', normalizedPublicBaseUrl);
    _registeredServerUrl = normalizedPublicBaseUrl;
  }
}

/// статус телеграма, как его отдаёт сервер
class CloudFunctionsTelegramStatus {
  final bool telegramEnabled;
  final String telegramBotToken;
  final String telegramUserId;
  final bool groupEnabled;
  final String groupChatId;
  final String groupTitle;
  final Map<String, int> topicMap; // топик телеграма по идентификатору предмета

  CloudFunctionsTelegramStatus({
    required this.telegramEnabled,
    required this.telegramBotToken,
    required this.telegramUserId,
    this.groupEnabled = false,
    this.groupChatId = '',
    this.groupTitle = '',
    this.topicMap = const {},
  });
}

/// результат операций с облаком
class CloudFunctionsResult {
  final bool success;
  final String? error;
  final String? registrationId;
  final String? verificationCode;
  final int? targetPrsId;
  final String? verificationToken;

  CloudFunctionsResult({
    required this.success,
    this.error,
    this.registrationId,
    this.verificationCode,
    this.targetPrsId,
    this.verificationToken,
  });
}

/// результат getGroupInfo, только из базы, в телеграм не ходим
class CloudFunctionsGroupInfo {
  final bool groupEnabled;
  final String groupChatId;
  final String groupTitle;
  final Map<String, int> topicMap; // топик телеграма по идентификатору предмета
  final Map<String, String> subjects; // название по идентификатору предмета
  final String? error;
  CloudFunctionsGroupInfo({
    required this.groupEnabled,
    required this.groupChatId,
    required this.groupTitle,
    required this.topicMap,
    required this.subjects,
    this.error,
  });
}

/// конфигурация сервера
class CloudFunctionsConfig {
  final int minCheckIntervalMinutes;
  final int defaultCheckIntervalMinutes;
  final String serverDomain;
  final String publicBaseUrl;

  CloudFunctionsConfig({
    required this.minCheckIntervalMinutes,
    required this.defaultCheckIntervalMinutes,
    this.serverDomain = '',
    this.publicBaseUrl = '',
  });
}

class CloudFunctionsDomainStatus {
  final String domain;
  final String publicBaseUrl;

  CloudFunctionsDomainStatus({
    required this.domain,
    required this.publicBaseUrl,
  });
}

class CloudFunctionsDomainResult {
  final bool success;
  final String? error;
  final String domain;
  final String publicBaseUrl;

  CloudFunctionsDomainResult({
    required this.success,
    this.error,
    this.domain = '',
    this.publicBaseUrl = '',
  });
}

class CloudFunctionsIpBlacklistResult {
  final bool success;
  final String? error;
  final List<String> entries;

  CloudFunctionsIpBlacklistResult({
    required this.success,
    this.error,
    this.entries = const [],
  });
}

class CloudFunctionsDomainJob {
  final String jobId;
  final String status;
  final String step;
  final String message;
  final String domain;
  final String publicBaseUrl;
  final String? error;

  CloudFunctionsDomainJob({
    required this.jobId,
    required this.status,
    required this.step,
    required this.message,
    required this.domain,
    required this.publicBaseUrl,
    this.error,
  });

  factory CloudFunctionsDomainJob.fromJson(Map<String, dynamic> json) {
    return CloudFunctionsDomainJob(
      jobId: json['jobId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      step: json['step'] as String? ?? '',
      message: json['message'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      publicBaseUrl: json['publicBaseUrl'] as String? ?? '',
      error: json['error'] as String?,
    );
  }
}

/// результат generateClassmateInvite
class ClassmateInviteResult {
  final bool success;
  final String? error;
  final String? inviteToken;
  final int expiresInMinutes;

  ClassmateInviteResult({
    required this.success,
    this.error,
    this.inviteToken,
    this.expiresInMinutes = 60,
  });
}

/// статус сессии аккаунта на сервере
class CloudFunctionsAccountStatus {
  final bool sessionInvalid;
  final String? reason;
  final String? invalidAt;

  CloudFunctionsAccountStatus({
    required this.sessionInvalid,
    this.reason,
    this.invalidAt,
  });
}

/// результат generateGroupCode
class CloudFunctionsGroupCodeResult {
  final bool success;
  final String? error;
  final String? code;
  final String? command;
  final int? expiresInMinutes;

  CloudFunctionsGroupCodeResult({
    required this.success,
    this.error,
    this.code,
    this.command,
    this.expiresInMinutes,
  });
}
