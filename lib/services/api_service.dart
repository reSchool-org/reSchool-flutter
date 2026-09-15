import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import 'secure_storage.dart';
import 'reschool_http.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/profile_models.dart';
import '../models/chat_models.dart';
import '../models/account.dart';
import '../models/student_context.dart';
import '../models/login_failure.dart';
import '../models/lpart_models.dart';
import '../models/school_directory.dart';
import 'demo_data.dart';
import 'marks_cache_service.dart';
import 'school_cache_policy.dart';
import 'cloud_session_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _baseURL = "https://app.eschool.center/ec-server";
  final String _userAgent = "eSchoolMobile";
  final _storage = appSecureStorage;
  final DemoData _demoData = DemoData();

  // cors прокси для веба, выставляется через setWebProxy
  String? _webProxyServerUrl;
  String? _webProxyToken;

  /// настроить cors прокси для веб сборки, звать после загрузки SettingsProvider
  void setWebProxy(String? serverUrl, String? token) {
    _webProxyServerUrl = (serverUrl?.trim().isEmpty ?? true)
        ? null
        : serverUrl!.trim().replaceAll(RegExp(r'/+$'), '');
    _webProxyToken = (token?.trim().isEmpty ?? true) ? null : token!.trim();
  }

  bool get _proxyEnabled =>
      kIsWeb && _webProxyServerUrl != null && _webProxyToken != null;

  bool isAuthenticated = false;
  bool _isDemo = false;
  final Map<String, String> _cookies = {};
  int _identityEpoch = 0;
  int get identityEpoch => _identityEpoch;
  int _sessionVersion = 0;
  Future<bool>? _loginFuture;
  String? _loginUsername;
  String? _loginPassword;
  bool _loginIsRecovery = false;
  LoginFailure? _lastLoginFailure;
  LoginFailure? get lastLoginFailure => _lastLoginFailure;
  DateTime? _lastRecoveryAt;
  Future<void> _accountWrite = Future.value();

  int? userId;
  int? currentPrsId;
  StudentContext? _studentContext;
  int? get studentPrsId =>
      _studentContext == null ? currentPrsId : _studentContext!.prsId;
  int? get studentUserId =>
      _studentContext == null ? userId : _studentContext!.userId;
  int? currentYearId;
  Profile? userProfile;
  String? _deviceModel;
  String? _androidVersion;
  String? _eSchoolVersion;

  Account? _account;
  Account? get account => _account;
  bool get isDemo => _isDemo;

  String get deviceModel => _deviceModel ?? "Android Device";
  String get androidVersion => _androidVersion ?? "9";
  String get eSchoolVersion =>
      _eSchoolVersion ?? AppConfig.eSchoolVersionFallback;

  String? get cloudToken => _account?.cloudToken;
  int? get serverThreadId => _account?.serverThreadId;
  bool get isCloudEnabled => _account?.isCloudEnabled ?? false;

  // креды для сервера пушей
  String? get savedUsername => _account?.username;
  String? get savedPassword => _account?.password;

  Future<void> updateCloudSettings({
    required bool enabled,
    String? token,
    int? threadId,
  }) async {
    if (_account != null) {
      _account!.isCloudEnabled = enabled;
      _account!.cloudToken = token;
      _account!.serverThreadId = threadId;
      await _saveAccount();
    }
  }

  Future<void> init() async {
    // восстанавливаем прокси до первого запроса с сохранённой школьной сессией
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      setWebProxy(
        prefs.getString('web_proxy_server_url'),
        prefs.getString('web_proxy_token'),
      );
    }
    await _loadAccount();
    await _loadDeviceModel();
    await _loadAndroidVersion();
    await _loadESchoolVersion();
    if (_account != null) {
      await _restoreSession();
    }
  }

  Future<void> _loadAccount() async {
    try {
      String? jsonString;
      try {
        jsonString = await _storage.read(key: 'saved_account');
      } catch (_) {}

      if (jsonString == null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_account_insecure');
      }

      if (jsonString != null) {
        final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
        _account = Account.fromJson(jsonMap);
        _isDemo = _isDemoCredentials(_account!.username, _account!.password);
      } else {
        try {
          final oldJsonString = await _storage.read(key: 'saved_accounts');
          if (oldJsonString != null) {
            final List<dynamic> jsonList = jsonDecode(oldJsonString);
            if (jsonList.isNotEmpty) {
              _account = Account.fromJson(jsonList[0]);
              _isDemo = _isDemoCredentials(
                _account!.username,
                _account!.password,
              );
              await _saveAccount();
            }
            await _storage.delete(key: 'saved_accounts');
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _saveAccount() {
    final jsonString = _account == null ? null : jsonEncode(_account!.toJson());
    // сохранение новой сессии и удаление при выходе выполняются по порядку
    // иначе поздняя запись токена может вернуть аккаунт в хранилище после logout
    _accountWrite = _accountWrite.then((_) async {
      try {
        if (jsonString != null) {
          await _storage.write(key: 'saved_account', value: jsonString);
        } else {
          await _storage.delete(key: 'saved_account');
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('saved_account_insecure');
        }
      } catch (_) {}
    });
    return _accountWrite;
  }

  Future<void> _loadDeviceModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_device_model');
    if (saved != null) {
      _deviceModel = saved;
    } else {
      await randomizeDeviceModel();
    }
  }

  Future<void> _loadAndroidVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_android_version');
    if (saved != null) {
      _androidVersion = saved;
    } else {
      _androidVersion = (9 + Random().nextInt(8))
          .toString(); // длина от 9 до 16 символов
      await prefs.setString('saved_android_version', _androidVersion!);
    }
  }

  Future<void> _loadESchoolVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('eschool_cli_version');
    final cachedAt = prefs.getInt('eschool_cli_version_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const ttlMs = 24 * 60 * 60 * 1000; // сутки

    // в кэше мог остаться json от прошлого неудачного запроса
    final cachedValid =
        (cached != null && RegExp(r'^\d+\.\d+').hasMatch(cached))
        ? cached
        : null;
    if (cachedValid == null && cached != null) {
      // чистим битый кэш, чтобы версия перезапросилась
      await prefs.remove('eschool_cli_version');
      await prefs.remove('eschool_cli_version_at');
    }

    if (cachedValid != null && (now - cachedAt) < ttlMs) {
      _eSchoolVersion = cachedValid;
      return;
    }

    // до настройки прокси берём версию из кеша или сборки, cors мешает браузеру скачать релиз github
    if (kIsWeb && !_proxyEnabled) {
      _eSchoolVersion = cachedValid ?? AppConfig.eSchoolVersionFallback;
      return;
    }

    try {
      final versionUri = kIsWeb
          ? Uri.parse('$_webProxyServerUrl/proxy/version')
          : Uri.parse(AppConfig.eSchoolVersionUrl);
      final versionClient = kIsWeb ? reschoolHttp : http.Client();
      final http.Response response;
      try {
        response = await versionClient
            .get(
              versionUri,
              headers: kIsWeb ? {'X-Api-Token': _webProxyToken!} : null,
            )
            .timeout(Duration(seconds: kIsWeb ? 45 : 5));
      } finally {
        if (!kIsWeb) versionClient.close();
      }
      if (response.statusCode == 200) {
        String version = response.body.trim();
        // сервер иногда отдаёт json вместо голой строки, достаём поле version
        if (version.startsWith('{')) {
          try {
            final json = jsonDecode(version) as Map<String, dynamic>;
            version = (json['version'] as String?)?.trim() ?? '';
          } catch (_) {
            version = '';
          }
        }
        // проверяем, что это правда похоже на версию, вида 7.9.0
        if (version.isNotEmpty && RegExp(r'^\d+\.\d+').hasMatch(version)) {
          _eSchoolVersion = version;
          await prefs.setString('eschool_cli_version', version);
          await prefs.setInt('eschool_cli_version_at', now);
          return;
        }
      }
    } catch (_) {}

    // тут снова может лежать json от старой неудачной попытки
    final validCached =
        (cached != null && RegExp(r'^\d+\.\d+').hasMatch(cached))
        ? cached
        : null;
    _eSchoolVersion = validCached ?? AppConfig.eSchoolVersionFallback;
  }

  Future<void> randomizeDeviceModel() async {
    try {
      final jsonString = await rootBundle.loadString('assets/devices.json');
      final List<dynamic> devices = jsonDecode(jsonString);
      if (devices.isNotEmpty) {
        final rnd = Random();
        _deviceModel = devices[rnd.nextInt(devices.length)];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_device_model', _deviceModel!);
      }
    } catch (_) {
      _deviceModel = "Android Device";
    }
  }

  Future<void> _restoreSession() async {
    if (_account == null) return;

    _cookies.clear();
    isAuthenticated = false;
    _isDemo = _isDemoCredentials(_account!.username, _account!.password);
    userId = null;
    currentPrsId = null;
    _studentContext = null;
    currentYearId = null;
    userProfile = null;

    if (_isDemo) {
      _applyDemoSession();
      return;
    }

    if (_account!.sessionCookie != null) {
      _cookies['JSESSIONID'] = _account!.sessionCookie!;
    }

    final epoch = _identityEpoch;
    if (_cookies.isNotEmpty) {
      int? status;
      try {
        if (await _fetchState(
          recoverSession: false,
          onStatus: (value) => status = value,
        )) {
          if (epoch == _identityEpoch) isAuthenticated = true;
          return;
        }
      } catch (_) {
        return; // сбой сети не означает, что нужен новый вход
      }
      if (status != 401) return;
    }
    if (_account != null && epoch == _identityEpoch) {
      await _recoverSession(epoch, _sessionVersion);
    }
  }

  Future<void> logout() async {
    _identityEpoch++;
    _sessionVersion++;
    _loginFuture = null;
    _loginUsername = null;
    _loginPassword = null;
    _loginIsRecovery = false;
    _lastRecoveryAt = null;
    _lastLoginFailure = null;
    _cookies.clear();
    isAuthenticated = false;
    _isDemo = false;
    userId = null;
    currentPrsId = null;
    _studentContext = null;
    currentYearId = null;
    userProfile = null;
    _account = null;
    final marksCleanup = MarksCacheService().invalidate();
    await Future.wait([_saveAccount(), marksCleanup]);
  }

  String _sha256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  String _randomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
      ),
    );
  }

  Map<String, String> _getHeaders({bool isForm = false}) {
    final headers = {
      "Accept": "application/json, text/plain, */*",
      "User-Agent": _userAgent,
      "Accept-Language": "ru-RU,en,*",
      "Origin": "https://app.eschool.center",
      "Referer": "https://app.eschool.center/",
    };
    if (isForm) {
      headers["Content-Type"] = "application/x-www-form-urlencoded";
    }
    if (_cookies.isNotEmpty) {
      headers["Cookie"] = _cookies.entries
          .map((e) => "${e.key}=${e.value}")
          .join("; ");
    }
    return headers;
  }

  void _updateCookies(http.Response response, {bool updateAccount = true}) {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      final RegExp cookieRegex = RegExp(r'(JSESSIONID)=([^;]+)');
      final matches = cookieRegex.allMatches(rawCookie);
      for (final match in matches) {
        if (_cookies[match.group(1)!] != match.group(2)!) {
          _sessionVersion++;
        }
        _cookies[match.group(1)!] = match.group(2)!;

        if (updateAccount && _account != null) {
          _account!.sessionCookie = match.group(2)!;
          _saveAccount();
        }
      }
    }
  }

  void _logRequest(String method) {
    if (!kDebugMode) return;
    // ни url, ни заголовки, ни тело не логируем даже в debug
    final safeMethod = const {'GET', 'POST', 'PUT'}.contains(method)
        ? method
        : 'OTHER';
    debugPrint('[ApiService] Request method=$safeMethod');
  }

  void _logResponse(int statusCode, int byteCount) {
    if (!kDebugMode) return;
    debugPrint('[ApiService] Response status=$statusCode bytes=$byteCount');
  }

  /// низкоуровневая отправка, на вебе при настроенном прокси идёт через него
  Future<http.Response> _sendRequest(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    if (_proxyEnabled) {
      return _sendThroughProxy(method, uri, headers: headers, body: body);
    }
    if (kIsWeb) {
      throw const LoginFailure(
        kind: LoginFailureKind.network,
        source: LoginFailureSource.proxy,
        serverMessage: 'Укажите сервер и API-ключ в настройках веб-версии.',
      );
    }
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: body);
      case 'PUT':
        return http.put(uri, headers: headers, body: body);
      default:
        throw Exception('Unsupported method: $method');
    }
  }

  /// прокидываем запрос к eSchool через /proxy на сервере reSchool, обход cors на вебе
  Future<http.Response> _sendThroughProxy(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final proxyUri = Uri.parse('$_webProxyServerUrl/proxy');

    String? bodyStr;
    if (body is String) {
      bodyStr = body;
    } else if (body is Map) {
      bodyStr = (body as Map<String, dynamic>).entries
          .map(
            (e) =>
                '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}',
          )
          .join('&');
    }

    final payload = jsonEncode({
      'method': method,
      'url': uri.toString(),
      'headers': headers ?? {},
      'body': bodyStr,
      if (body is List<int>) 'bodyBase64': base64Encode(body),
      'responseEncoding': 'base64',
    });

    final proxyResponse = await reschoolHttp.post(
      proxyUri,
      headers: {
        'Content-Type': 'application/json',
        'X-Api-Token': _webProxyToken!,
      },
      body: payload,
    );

    if (proxyResponse.statusCode != 200) {
      throw LoginFailure.response(
        proxyResponse.statusCode,
        proxyResponse.body,
        source: LoginFailureSource.proxy,
      );
    }

    final data = jsonDecode(proxyResponse.body) as Map<String, dynamic>;
    final statusCode = (data['status'] as num).toInt();
    final rawHeaders = data['headers'] as Map<String, dynamic>? ?? {};
    final responseHeaders = rawHeaders.map(
      (k, v) => MapEntry(k.toLowerCase(), v.toString()),
    );
    final responseBody = data['body'] as String? ?? '';

    if (data['bodyEncoding'] == 'base64') {
      return http.Response.bytes(
        base64Decode(responseBody),
        statusCode,
        headers: responseHeaders,
      );
    }
    return http.Response(responseBody, statusCode, headers: responseHeaders);
  }

  Future<http.Response> _request(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
    bool isRetry = false,
  }) async {
    headers ??= _getHeaders();
    final epoch = _identityEpoch;
    final version = _sessionVersion;

    _logRequest(method);

    final uri = Uri.parse(url);
    http.Response response;

    try {
      response = await _sendRequest(method, uri, headers: headers, body: body);
    } catch (e) {
      rethrow;
    }

    _logResponse(response.statusCode, response.bodyBytes.length);
    // поздний ответ старой сессии не должен перезаписать уже восстановленную
    if (response.statusCode != 401 &&
        epoch == _identityEpoch &&
        version == _sessionVersion) {
      _updateCookies(response);
    }

    if (response.statusCode == 401 &&
        !isRetry &&
        _account != null &&
        epoch == _identityEpoch &&
        uri.origin == Uri.parse(_baseURL).origin) {
      final success = await _recoverSession(epoch, version);
      if (success && epoch == _identityEpoch) {
        // после входа заголовки пересобираем с новыми куками
        final newHeaders = Map<String, String>.from(headers);
        if (_cookies.isNotEmpty) {
          newHeaders["Cookie"] = _cookies.entries
              .map((e) => "${e.key}=${e.value}")
              .join("; ");
        }
        return _request(
          method,
          url,
          headers: newHeaders,
          body: body,
          isRetry: true,
        );
      }
    }

    return response;
  }

  Future<bool> _recoverSession(int epoch, int failedVersion) {
    final account = _account;
    if (epoch != _identityEpoch || account == null || _isDemo) {
      return Future.value(false);
    }
    final pending = _loginFuture;
    if (pending != null) {
      return _loginUsername == account.username &&
              _loginPassword == account.password
          ? pending
          : Future.value(false);
    }
    if (_sessionVersion != failedVersion && isAuthenticated) {
      return Future.value(true);
    }
    final now = DateTime.now();
    if (_lastRecoveryAt != null &&
        now.difference(_lastRecoveryAt!) < const Duration(seconds: 30)) {
      return Future.value(false);
    }
    _lastRecoveryAt = now;
    return _startLogin(
      account.username,
      account.password,
      recoverSession: true,
    );
  }

  Future<bool> login(
    String username,
    String password, {
    bool rememberMe = false,
  }) {
    return _startLogin(username, password, rememberMe: rememberMe);
  }

  Future<bool> _startLogin(
    String username,
    String password, {
    bool rememberMe = false,
    bool recoverSession = false,
  }) {
    final pending = _loginFuture;
    if (pending != null &&
        _loginIsRecovery == recoverSession &&
        _loginUsername == username &&
        _loginPassword == password) {
      return pending;
    }
    // явный вход отменяет восстановление; старые куки убираем, иначе они подменят проверку пароля
    if (!recoverSession ||
        (_account != null &&
            (_account!.username != username ||
                _account!.password != password)) ||
        (pending != null &&
            (_loginUsername != username || _loginPassword != password))) {
      _identityEpoch++;
      _sessionVersion++;
      _cookies.clear();
      isAuthenticated = false;
      userId = null;
      currentPrsId = null;
      _studentContext = null;
      currentYearId = null;
      userProfile = null;
      unawaited(
        MarksCacheService().invalidate().catchError((Object error) {
          debugPrint('Unable to clear marks cache on account change');
        }),
      );
    }
    final epoch = _identityEpoch;
    isAuthenticated = false;
    _lastLoginFailure = null;
    _loginUsername = username;
    _loginPassword = password;
    _loginIsRecovery = recoverSession;
    late final Future<bool> operation;
    final authentication = recoverSession
        ? _loginWithCloudSession(
            username,
            password,
            epoch,
            rememberMe: rememberMe,
          )
        : _performLogin(
            username,
            password,
            epoch: epoch,
            rememberMe: rememberMe,
          );
    operation = authentication.whenComplete(() {
      if (identical(_loginFuture, operation)) {
        _loginFuture = null;
        _loginUsername = null;
        _loginPassword = null;
        _loginIsRecovery = false;
      }
    });
    _loginFuture = operation;
    return operation;
  }

  Future<bool> _loginWithCloudSession(
    String username,
    String password,
    int epoch, {
    bool rememberMe = false,
  }) async {
    if (!_isDemoCredentials(username, password)) {
      final expectedPrsId = _account?.username == username
          ? _account?.prsId
          : null;
      final shared = await CloudSessionService().fetch(
        username,
        prsId: expectedPrsId,
      );
      if (epoch != _identityEpoch) return false;
      if (shared != null) {
        try {
          final headers = _getHeaders()
            ..['Cookie'] = 'JSESSIONID=${shared.cookie}';
          // проверка сессии идёт напрямую в eSchool и никогда не запускает login
          final response = await _sendRequest(
            'GET',
            Uri.parse('$_baseURL/state'),
            headers: headers,
          ).timeout(const Duration(seconds: 20));
          if (epoch != _identityEpoch) return false;
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final person = data is Map<String, dynamic> ? data['user'] : null;
            if (data is Map<String, dynamic> &&
                data['userId'] is int &&
                data['userId'] > 0 &&
                person is Map<String, dynamic> &&
                person['prsId'] == shared.prsId &&
                (expectedPrsId == null || person['prsId'] == expectedPrsId)) {
              final profile = data['profile'] is Map<String, dynamic>
                  ? Profile.fromJson(data['profile'])
                  : null;
              _cookies
                ..clear()
                ..['JSESSIONID'] = shared.cookie;
              _sessionVersion++;
              _updateCookies(response, updateAccount: false);
              userId = data['userId'];
              currentPrsId = shared.prsId;
              _studentContext = StudentContext.fromState(data);
              userProfile = profile;
              _isDemo = false;
              isAuthenticated = true;
              final previous = _account?.username == username ? _account : null;
              _account = Account(
                username: username,
                password: password,
                fullName: profile?.fullName ?? previous?.fullName ?? username,
                prsId: shared.prsId,
                imageId: profile?.imageId,
                sessionCookie: _cookies['JSESSIONID'],
                cloudToken: previous?.cloudToken,
                serverThreadId: previous?.serverThreadId,
                isCloudEnabled: previous?.isCloudEnabled ?? false,
              );
              await _saveAccount();
              return epoch == _identityEpoch;
            }
          } else if (response.statusCode != 401 && response.statusCode != 403) {
            return false; // не расходуем вход при временной недоступности eSchool
          }
        } catch (_) {
          return false;
        }
      }
    }
    if (epoch != _identityEpoch) return false;
    return _performLogin(
      username,
      password,
      epoch: epoch,
      rememberMe: rememberMe,
    );
  }

  Future<bool> _performLogin(
    String username,
    String password, {
    required int epoch,
    bool rememberMe = false,
  }) async {
    if (_isDemoCredentials(username, password)) {
      _applyDemoSession();
      _account = Account(
        username: username,
        password: password,
        fullName: _demoData.fullName,
        prsId: _demoData.prsId,
        imageId: null,
        sessionCookie: null,
        cloudToken: null,
        serverThreadId: null,
        isCloudEnabled: false,
      );
      await _saveAccount();
      return true;
    }

    if (_proxyEnabled) {
      await _loadESchoolVersion();
      if (epoch != _identityEpoch) return false;
    }
    _isDemo = false;
    final passwordHash = _sha256(password);
    final deviceId = _randomString(16).toLowerCase();
    final pushToken = _randomString(152);

    final devicePayload = {
      "cliType": "mobile",
      "cliVer": eSchoolVersion,
      "pushToken": pushToken,
      "deviceId": deviceId,
      "deviceName": "-",
      "deviceModel": deviceModel,
      "cliOs": "android",
      "cliOsVer": androidVersion,
    };

    final deviceString = jsonEncode(devicePayload);
    final body = {
      "username": username,
      "password": passwordHash,
      "device": deviceString,
    };

    final url = "$_baseURL/login";
    final headers = _getHeaders(isForm: true);

    _logRequest("POST");

    var failureSource = LoginFailureSource.login;
    try {
      final response = await _sendRequest(
        "POST",
        Uri.parse(url),
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 20));

      _logResponse(response.statusCode, response.bodyBytes.length);
      if (epoch != _identityEpoch) return false;

      // куку аккаунта трогаем, только если входим под текущим пользователем
      bool shouldUpdateAccount = false;
      if (_account != null && _account!.username == username) {
        shouldUpdateAccount = true;
      }

      _updateCookies(response, updateAccount: shouldUpdateAccount);

      if (response.statusCode == 200) {
        if (response.body.length > 5 || _cookies.containsKey('JSESSIONID')) {
          // тянем state, оттуда детали пользователя
          failureSource = LoginFailureSource.state;
          final validState = await _fetchState(
            recoverSession: false,
            onFailure: (failure) {
              if (epoch == _identityEpoch) _lastLoginFailure = failure;
            },
          ).timeout(const Duration(seconds: 20));
          if (epoch != _identityEpoch) return false;
          if (!validState) {
            return false;
          }
          isAuthenticated = true;

          // заводим аккаунт или обновляем существующий
          final fullName = userProfile?.fullName ?? username;
          final prsId = currentPrsId;
          final imageId = userProfile?.imageId;

          // при повторном входе настройки облака у аккаунта не теряем
          final previous = _account?.username == username ? _account : null;
          final oldCloudToken = previous?.cloudToken;
          final oldServerThreadId = previous?.serverThreadId;
          final oldIsCloudEnabled = previous?.isCloudEnabled ?? false;

          _account = Account(
            username: username,
            password: password,
            fullName: fullName,
            prsId: prsId,
            imageId: imageId,
            sessionCookie: _cookies['JSESSIONID'],
            cloudToken: oldCloudToken,
            serverThreadId: oldServerThreadId,
            isCloudEnabled: oldIsCloudEnabled,
          );

          _sessionVersion++;
          await _saveAccount();

          return epoch == _identityEpoch;
        }
      }
      _lastLoginFailure = LoginFailure.response(
        response.statusCode,
        response.body,
      );
      return false;
    } catch (error) {
      if (epoch == _identityEpoch) {
        _lastLoginFailure = error is LoginFailure
            ? error
            : LoginFailure(
                kind: switch (error) {
                  TimeoutException() => LoginFailureKind.timeout,
                  SocketException() ||
                  http.ClientException() ||
                  HandshakeException() => LoginFailureKind.network,
                  FormatException() => LoginFailureKind.invalidResponse,
                  _ => LoginFailureKind.unknown,
                },
                source: failureSource,
              );
      }
      return false;
    }
  }

  /// быстрая проверка по хранилищу, в сеть не ходим
  Future<bool> hasSavedCredentials() async {
    try {
      String? jsonString;
      try {
        jsonString = await _storage.read(key: 'saved_account');
      } catch (_) {}
      if (jsonString != null) return true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_account_insecure');
      return false;
    } catch (_) {
      return false;
    }
  }

  // attemptAutoLogin теперь просто отвечает, есть ли у нас аккаунты
  Future<bool> attemptAutoLogin() async {
    await init();
    return isAuthenticated;
  }

  Future<bool> _fetchState({
    bool recoverSession = true,
    void Function(int)? onStatus,
    void Function(LoginFailure)? onFailure,
  }) async {
    if (_isDemo) {
      _applyDemoSession();
      return true;
    }
    final url = "$_baseURL/state";
    final headers = _getHeaders();

    final epoch = _identityEpoch;
    final response = await _request(
      "GET",
      url,
      headers: headers,
      isRetry: !recoverSession,
    );
    onStatus?.call(response.statusCode);
    if (epoch != _identityEpoch) return false;

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        userId = data['userId'];
        _studentContext = StudentContext.fromState(data);
        currentYearId = null;
        if (data['user'] != null) {
          currentPrsId = data['user']['prsId'];
        }
        if (data['profile'] != null) {
          userProfile = Profile.fromJson(data['profile']);
        }

        if (userId != null) {
          return true;
        }
      } catch (_) {}
    }
    onFailure?.call(
      LoginFailure.response(
        response.statusCode,
        response.body,
        source: LoginFailureSource.state,
      ),
    );
    return false;
  }

  Future<Map<String, dynamic>> getPrsDiary(double d1, double d2) async {
    if (_isDemo) {
      final start = DateTime.fromMillisecondsSinceEpoch(d1.toInt());
      final end = DateTime.fromMillisecondsSinceEpoch(d2.toInt());
      return _demoData.prsDiaryJson(start, end);
    }
    if (studentPrsId == null) {
      await _fetchState();
    }

    if (studentPrsId == null) {
      throw Exception('User PrsID not found');
    }

    final url =
        "$_baseURL/student/getPrsDiary?prsId=$studentPrsId&d1=${d1.toInt()}&d2=${d2.toInt()}";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load diary: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getProfileNew(int prsId) async {
    if (_isDemo) {
      return _demoData.profileNewJson(prsId);
    }
    final url = "$_baseURL/profile/getProfile_new?prsId=$prsId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getShortProfile(int prsId) async {
    final url = "$_baseURL/profile/getShortProfile?prsId=$prsId";
    final headers = _getHeaders();
    final response = await _request("GET", url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load short profile: ${response.statusCode}');
    }
  }

  /// короткое безопасное имя файла, его же показываем в подтверждении скачивания
  static String sanitizeDownloadFilename(String filename) {
    var name = filename
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (name.isEmpty) name = 'download';
    if (RegExp(
      r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = 'download_$name';
    }
    // расширение сохраняем, даже если имя пришло абсурдно длинное
    final extension =
        RegExp(r'\.[a-zA-Z0-9]{1,10}$').firstMatch(name)?.group(0) ?? '';
    if (name.length > 120) {
      name =
          '${name.substring(0, 120 - extension.length).replaceAll(RegExp(r'[. ]+$'), '')}$extension';
    }
    return name;
  }

  Future<Uint8List> getDownloadBytes(String url) async {
    final uri = Uri.tryParse(url);
    final origin = Uri.parse(_baseURL);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        // класс Uri схлопывает явно пустую часть с user info
        RegExp(r'^https://[^/?#]*@', caseSensitive: false).hasMatch(url)) {
      throw ArgumentError(
        'Downloads require the eSchool HTTPS origin without user info',
      );
    }

    final List<int> bytes;
    if (_isDemo) {
      bytes =
          _demoData.fileBytes(uri) ??
          utf8.encode("Демонстрационный файл reSchool");
    } else if (kIsWeb) {
      final response = await _request(
        'GET',
        url,
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw Exception('Failed to download file: ${response.statusCode}');
      }
      if (response.bodyBytes.length > 50 * 1024 * 1024) {
        throw Exception('Download exceeds the 50 MiB limit');
      }
      bytes = response.bodyBytes;
    } else {
      const maxBytes = 50 * 1024 * 1024;
      const timeout = Duration(seconds: 60);
      final elapsed = Stopwatch()..start();
      final client = http.Client();
      StreamIterator<List<int>>? chunks;
      try {
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers.addAll(_getHeaders());
        _logRequest('GET');
        final response = await client.send(request).timeout(timeout);
        chunks = StreamIterator(response.stream);
        if (response.statusCode != 200) {
          throw Exception('Failed to download file: ${response.statusCode}');
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          throw Exception('Download exceeds the 50 MiB limit');
        }

        // считаем реально принятые байты, заявленной сервером длине верить нельзя
        final buffer = BytesBuilder(copy: false);
        final body = chunks;
        bytes = await (() async {
          while (await body.moveNext()) {
            final chunk = body.current;
            if (chunk.length > maxBytes - buffer.length) {
              throw Exception('Download exceeds the 50 MiB limit');
            }
            buffer.add(chunk);
          }
          return buffer.takeBytes();
        })().timeout(timeout - elapsed.elapsed);
        _logResponse(response.statusCode, bytes.length);
      } finally {
        client.close();
        await chunks?.cancel();
      }
    }

    return Uint8List.fromList(bytes);
  }

  Future<XFile> downloadXFile(String url, String filename) async {
    if (kIsWeb) {
      return XFile.fromData(
        await getDownloadBytes(url),
        name: sanitizeDownloadFilename(filename),
        mimeType: 'application/octet-stream',
      );
    }
    return XFile((await downloadFile(url, filename)).path);
  }

  Future<File> downloadFile(String url, String filename) async {
    final bytes = await getDownloadBytes(url);
    final safeName = sanitizeDownloadFilename(filename);
    final temp = await getTemporaryDirectory();
    final dir = await temp.createTemp('reschool_download_');
    try {
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getThreads() async {
    if (_isDemo) {
      return _demoData.getThreads();
    }
    final url = "$_baseURL/chat/threads?newOnly=false&row=0&rowsCount=50";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load threads: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(
    int threadId, {
    int rowStart = 1,
    int rowsCount = 50,
    int? msgStart,
    bool getNew = false,
    bool isSearch = false,
    String? searchText,
    List<int>? msgNums,
  }) async {
    if (_isDemo) {
      return _demoData.messagePage(
        threadId,
        rowStart: rowStart,
        rowsCount: rowsCount,
        msgStart: msgStart,
        getNew: getNew,
        isSearch: isSearch,
      );
    }
    final data = await _chatJson(
      'PUT',
      '/chat/messages',
      params: {
        'threadId': '$threadId',
        'rowStart': '$rowStart',
        'rowsCount': '$rowsCount',
        if (msgStart != null) 'msgStart': '$msgStart',
        'getNew': '$getNew',
        'isSearch': '$isSearch',
      },
      body: {'msgNums': msgNums, 'searchText': searchText},
    );
    return _chatList(data);
  }

  Future<dynamic> _chatJson(
    String method,
    String path, {
    Map<String, String>? params,
    Object? body,
  }) async {
    final uri = Uri.parse('$_baseURL$path').replace(queryParameters: params);
    final headers = _getHeaders();
    if (body != null) {
      headers['Content-Type'] = 'application/json;charset=UTF-8';
    }
    final response = await _request(
      method,
      uri.toString(),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('eSchool request failed: ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  List<Map<String, dynamic>> _chatList(dynamic data) {
    if (data is! List) throw const FormatException('Expected an eSchool list');
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<SchoolDirectoryGroup>> getEmployeeGroups() async {
    final data = _isDemo
        ? _demoData.employeeGroups()
        : _chatList(
            await _chatJson(
              'GET',
              '/groups/tree',
              params: {
                'bAllTypes': 'false',
                'bApplicants': 'false',
                'bEmployees': 'true',
                'bGroups': 'false',
              },
            ),
          );
    return data.map(SchoolDirectoryGroup.fromJson).toList();
  }

  Future<List<ChatSearchHit>> searchChatMessages(
    String text, {
    int? msgStart,
  }) async {
    final data = _isDemo
        ? _demoData.searchMessages(text, msgStart: msgStart)
        : _chatList(
            await _chatJson(
              'GET',
              '/chat/searchThreads',
              params: {
                'rowStart': '1',
                'rowsCount': '25',
                'text': text.trim(),
                if (msgStart != null) 'msgStart': '$msgStart',
              },
            ),
          );
    if (data.isNotEmpty && (data.first['msgId'] as num? ?? 1) <= 0) {
      throw const FormatException('Search was rejected by eSchool');
    }
    return data
        .map((json) => ChatSearchHit.fromJson({...json, 'filterText': text}))
        .toList();
  }

  Future<List<ChatMessage>> getChatMedia(
    int threadId, {
    int rowStart = 1,
    int rowsCount = 50,
    int? msgStart,
  }) async {
    final data = _isDemo
        ? _demoData.mediaPage(
            threadId,
            rowStart: rowStart,
            rowsCount: rowsCount,
            msgStart: msgStart,
          )
        : _chatList(
            await _chatJson(
              'GET',
              '/chat/media',
              params: {
                'threadId': '$threadId',
                'rowStart': '$rowStart',
                'rowsCount': '$rowsCount',
                'getNew': 'false',
                'isSearch': 'false',
                if (msgStart != null) 'msgStart': '$msgStart',
              },
            ),
          );
    return data.map(ChatMessage.fromJson).toList();
  }

  Future<ChatPermissions> getChatPermissions(int threadId) async {
    if (_isDemo) {
      return const ChatPermissions(canWrite: true, editMinutes: 1440);
    }
    final responses = await Future.wait([
      _chatJson('GET', '/chat/thread', params: {'threadId': '$threadId'}),
      _chatJson('GET', '/chat/msgEditTime'),
      _chatJson('GET', '/srv/sysTime'),
      _chatJson('GET', '/chat/noreply'),
    ]);
    final thread = responses[0] as Map;
    final minutes = int.tryParse(responses[1].toString());
    final serverTime = int.tryParse(responses[2].toString());
    if (minutes == null || serverTime == null) {
      throw const FormatException('Invalid chat permissions');
    }
    final isGroup = thread['dlgType'] == 2;
    final owner =
        thread['senderId'] == currentPrsId ||
        (thread['adminIds'] as List? ?? []).contains(currentPrsId);
    final noReply = int.tryParse(responses[3].toString());
    final canWrite =
        thread['closeDate'] == null &&
        thread['senderId'] != noReply &&
        (isGroup
            ? ((thread['addrCnt'] as num? ?? 0) > 0 &&
                  (thread['isAllowReplay'] != 0 || owner))
            : thread['senderInvalid'] != true && thread['senderInvalid'] != 1);
    return ChatPermissions(
      canWrite: canWrite,
      editMinutes: minutes,
      serverOffset: DateTime.fromMillisecondsSinceEpoch(serverTime)
          .difference(DateTime.now()),
    );
  }

  Future<void> editChatMessage(ChatMessage message, String text) async {
    if (message.msgId == null || text.trim().isEmpty) {
      throw ArgumentError('Empty message');
    }
    if (_isDemo) {
      _demoData.editMessage(message.msgId!, text);
      return;
    }
    final uri = Uri.parse('$_baseURL/chat/updateMessage');
    final multipart = http.MultipartRequest('POST', uri)
      ..fields['msgId'] = '${message.msgId}'
      ..fields['msgText'] = text
      // сервер ждёт список сохраняемых вложений даже при изменении только текста
      ..fields['fileIds'] = jsonEncode([
        for (final attachment in message.attachInfo ?? <AttachInfo>[])
          if (attachment.fileId != null)
            {
              'fls_id': attachment.fileId,
              'name': attachment.fileName,
              'type': 'MAIL_ATTACH',
            },
      ]);
    final bytes = await multipart.finalize().toBytes();
    final response = await _request(
      'POST',
      uri.toString(),
      headers: {
        ..._getHeaders(),
        'Content-Type': multipart.headers['content-type']!,
      },
      body: bytes,
    ).timeout(const Duration(seconds: 30));
    final result = int.tryParse(response.body.trim());
    if (response.statusCode != 200 || result == null || result <= 0) {
      throw Exception('Message edit rejected');
    }
  }

  Future<void> deleteChatMessage(int msgId) async {
    if (_isDemo) {
      _demoData.deleteMessage(msgId);
      return;
    }
    final result = await _chatJson(
      'GET',
      '/chat/deleteMessage',
      params: {'msgId': '$msgId'},
    );
    if (result != 1) throw Exception('Message deletion rejected');
  }

  Future<Uint8List> getContentImage(Uri uri) async {
    final trusted =
        uri.scheme == 'https' &&
        uri.host == 'app.eschool.center' &&
        uri.port == 443;
    if (!{'https', 'http'}.contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw ArgumentError('Unsupported image URL');
    }
    if (_isDemo && trusted) {
      final data = _demoData.fileBytes(uri);
      if (data != null) return Uint8List.fromList(data);
      return (await rootBundle.load('assets/icon.png')).buffer.asUint8List();
    }
    const maxBytes = 12 * 1024 * 1024;
    const timeout = Duration(seconds: 30);
    if (trusted && kIsWeb) {
      final response = await _request('GET', uri.toString()).timeout(timeout);
      if (response.statusCode != 200 || response.bodyBytes.length > maxBytes) {
        throw Exception('Image unavailable');
      }
      return response.bodyBytes;
    }
    final client = http.Client();
    try {
      return await (() async {
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll(trusted ? _getHeaders() : {'Accept': 'image/*'});
        final response = await client.send(request);
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > maxBytes) {
          throw Exception('Image unavailable');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (chunk.length > maxBytes - bytes.length) {
            throw Exception('Image too large');
          }
          bytes.add(chunk);
        }
        return bytes.takeBytes();
      })().timeout(timeout);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> sendMessage(
    int threadId,
    String msgText, {
    List<UploadFile>? files,
  }) async {
    if (_isDemo) {
      return _demoData.sendMessage(threadId, msgText, files: files);
    }
    final url = "$_baseURL/chat/sendNew";
    final msgUID = DateTime.now().millisecondsSinceEpoch.toString();

    final boundary = "----WebKitFormBoundary${_randomString(16)}";
    final headers = _getHeaders();
    headers["Content-Type"] = "multipart/form-data; boundary=$boundary";

    final bodyBytes = <int>[];

    void addField(String name, String value) {
      bodyBytes.addAll(utf8.encode("--$boundary\r\n"));
      bodyBytes.addAll(
        utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
      );
      bodyBytes.addAll(utf8.encode("$value\r\n"));
    }

    addField("threadId", threadId.toString());
    addField("msgText", msgText);
    addField("msgUID", msgUID);

    if (files != null) {
      for (final file in files) {
        bodyBytes.addAll(utf8.encode("--$boundary\r\n"));
        bodyBytes.addAll(
          utf8.encode(
            'Content-Disposition: form-data; name="file"; filename="${file.name}"\r\n',
          ),
        );
        bodyBytes.addAll(utf8.encode('Content-Type: ${file.mimeType}\r\n\r\n'));
        bodyBytes.addAll(file.data);
        bodyBytes.addAll(utf8.encode("\r\n"));
      }
    }

    bodyBytes.addAll(utf8.encode("--$boundary--\r\n"));

    // _request обычно ждёт в body строку или Map, но http.post переваривает и List<int>,
    // тип там Object?, так что список байт проходит нормально

    final response = await _request(
      "POST",
      url,
      headers: headers,
      body: bodyBytes,
    );

    if (response.statusCode == 200) {
      if (response.body.isNotEmpty) {
        final result = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(response.bodyBytes)) as Map,
        );
        if ((result['msgId'] as num? ?? 0) < 0 ||
            (result['threadId'] as num? ?? 0) < 0) {
          throw StateError('Message rejected by eSchool');
        }
        return result;
      }
      return {};
    } else {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (_isDemo) {
      return _demoData.searchUsers(query);
    }
    final url = "$_baseURL/usr/getUserListSearch";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> allUsers = jsonDecode(response.body);
      if (query.isEmpty) {
        return allUsers.cast<Map<String, dynamic>>();
      }
      final lowerQuery = query.toLowerCase();
      return allUsers.cast<Map<String, dynamic>>().where((user) {
        final fio = (user['fio'] ?? '').toString().toLowerCase();
        final prsId = (user['prsId'] ?? '').toString();
        return fio.contains(lowerQuery) || prsId == query;
      }).toList();
    } else {
      throw Exception('Failed to search users: ${response.statusCode}');
    }
  }

  Future<int> saveThread({
    int? interlocutorId,
    String? subject,
    bool isGroup = false,
  }) async {
    if (_isDemo) {
      return _demoData.saveThread(
        interlocutorId: interlocutorId,
        subject: subject,
        isGroup: isGroup,
      );
    }
    final url = "$_baseURL/chat/saveThread";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json;charset=UTF-8";

    final body = jsonEncode({
      "threadId": null,
      "senderId": null,
      "imageId": null,
      "subject": subject,
      "isAllowReplay": 2,
      "isGroup": isGroup,
      "interlocutor": interlocutorId,
    });

    final response = await _request("PUT", url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final threadId = int.tryParse(response.body);
      if (threadId != null) return threadId;
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return 0;
      }
    } else {
      throw Exception('Failed to save thread: ${response.statusCode}');
    }
  }

  Future<void> setGroupMembers(
    int threadId,
    List<Map<String, dynamic>> members,
  ) async {
    if (_isDemo) {
      return;
    }
    final url = "$_baseURL/chat/setMembers?threadId=$threadId";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json;charset=UTF-8";

    final body = jsonEncode(
      members
          .map(
            (user) => {
              "memberId": null,
              "memberCode": "PRS",
              "memberObjId": user['prsId'],
              "memberObjName": user['fio'],
            },
          )
          .toList(),
    );

    final response = await _request("PUT", url, headers: headers, body: body);

    if (response.statusCode != 200) {
      throw Exception('Failed to set group members: ${response.statusCode}');
    }
  }

  Future<void> leaveChat(int threadId) async {
    if (_isDemo) {
      return;
    }
    final url = "$_baseURL/chat/close_and_leave?threadId=$threadId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to leave chat: ${response.statusCode}');
    }
  }

  String getAvatarUrl({int? imageId, String? imgObjType, int? imgObjId}) {
    if (imageId != null) {
      return "$_baseURL/files/images/$imageId";
    }
    if (imgObjType != null && imgObjId != null) {
      return "$_baseURL/files/images/$imgObjType/$imgObjId";
    }
    return "";
  }

  String getAttachmentUrl(int msgId, int fileId) {
    if (msgId <= 0 || fileId <= 0) {
      throw ArgumentError('Attachment IDs must be positive');
    }
    return "$_baseURL/files/MAIL_ATTACH/$msgId/$fileId";
  }

  Future<File> downloadAttachment(
    int msgId,
    int fileId,
    String filename,
  ) async {
    final url = getAttachmentUrl(msgId, fileId);
    return await downloadFile(url, filename);
  }

  Map<String, String> get authHeaders => _getHeaders();

  /// класс, в котором пользователь учится прямо сейчас
  Future<String?> currentGradeClass({bool forceRefresh = false}) async {
    try {
      final classes = await getClassByUser(forceRefresh: forceRefresh);
      final now = DateTime.now();
      String? current;
      DateTime? currentFrom;
      String? fallback;
      for (final cls in classes) {
        if (cls is! Map) continue;
        final value = cls['name'] ?? cls['groupName'];
        if (value is! String ||
            value.trim().isEmpty ||
            value.trim().length > 32) {
          continue;
        }
        final name = value.trim();
        fallback = name;
        final from = _classDate(cls['dtFrom'] ?? cls['begDate']);
        final to = _classDate(cls['dtTo'] ?? cls['endDate']);
        if ((from != null || to != null) &&
            (from == null || !now.isBefore(from)) &&
            (to == null || !now.isAfter(to)) &&
            (current == null ||
                (from != null &&
                    (currentFrom == null || from.isAfter(currentFrom))))) {
          current = name;
          currentFrom = from;
        }
      }
      return current ?? fallback;
    } catch (e) {
      return null;
    }
  }

  DateTime? _classDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is! num || !value.isFinite) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        (value.abs() > 10000000000 ? value : value * 1000).round(),
      );
    } on ArgumentError {
      return null;
    }
  }

  Future<List<dynamic>> getClassByUser({bool forceRefresh = false}) async {
    if (_isDemo) {
      return _demoData.classByUserJson();
    }
    if (studentUserId == null) await _fetchState();
    final userId = studentUserId;

    if (userId == null) throw Exception('User ID not found');

    final cacheKey =
        'cache_${SchoolCachePolicy.namespace}_${userId}_class_by_user_$userId';
    final timeKey = '${cacheKey}_timestamp';
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timeKey);

      if (cached != null && timestamp != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final diff = DateTime.now().difference(savedDate);

        if (!diff.isNegative && diff < SchoolCachePolicy.lifetime) {
          try {
            return jsonDecode(cached);
          } catch (_) {}
        }
      }
    }

    final url = "$_baseURL/usr/getClassByUser?userId=$userId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get classes');
    }
  }

  Future<Map<String, dynamic>> getPeriods(
    int groupId, {
    bool forceRefresh = false,
  }) async {
    if (_isDemo) {
      return _demoData.periodsJson();
    }
    final cacheKey =
        'cache_${SchoolCachePolicy.namespace}_${userId}_periods_group_$groupId';
    final timeKey = '${cacheKey}_timestamp';
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timeKey);

      if (cached != null && timestamp != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final diff = DateTime.now().difference(savedDate);

        if (!diff.isNegative && diff < SchoolCachePolicy.lifetime) {
          try {
            return jsonDecode(cached);
          } catch (_) {}
        }
      }
    }

    final url = "$_baseURL/dict/periods/0?groupId=$groupId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get periods');
    }
  }

  Future<Map<String, dynamic>> getDiaryUnits(int periodId) async {
    if (_isDemo) {
      return _demoData.diaryUnitsJson();
    }
    if (studentUserId == null) await _fetchState();
    final userId = studentUserId;

    if (userId == null) throw Exception('User ID not found');

    final url =
        "$_baseURL/student/getDiaryUnits/?userId=$userId&eiId=$periodId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get diary units');
    }
  }

  Future<Map<String, dynamic>> getDiaryPeriod(int periodId) async {
    if (_isDemo) {
      return _demoData.diaryPeriodJson();
    }
    if (studentUserId == null) await _fetchState();
    final userId = studentUserId;

    if (userId == null) throw Exception('User ID not found');

    final url =
        "$_baseURL/student/getDiaryPeriod_/?userId=$userId&eiId=$periodId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get diary period: ${response.statusCode}');
    }
  }

  Future<int> getCurrentYearId() async {
    if (currentYearId != null) return currentYearId!;

    if (studentPrsId == null) await _fetchState();
    if (studentPrsId == null) throw Exception('User PrsID not found');

    final profileData = await getProfileNew(studentPrsId!);
    final pupils = profileData['pupil'] as List<dynamic>?;
    if (pupils == null || pupils.isEmpty) {
      throw Exception('No pupil data found in profile');
    }

    int maxYearId = 0;
    for (final p in pupils) {
      final yId = p['yearId'] as int? ?? 0;
      if (yId > maxYearId) maxYearId = yId;
    }

    if (maxYearId == 0) throw Exception('Could not determine yearId');
    currentYearId = maxYearId;
    return currentYearId!;
  }

  Future<Map<String, dynamic>> getPupilUnits(
    int prsId,
    int yearId, {
    bool forceRefresh = false,
  }) async {
    if (_isDemo) {
      // в демо режиме настоящего эндпоинта pupil units нет
      return {'result': []};
    }

    final cacheKey =
        'cache_${SchoolCachePolicy.namespace}_${userId}_pupil_units_${prsId}_$yearId';
    final timeKey = '${cacheKey}_timestamp';
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timeKey);
      if (cached != null && timestamp != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final diff = DateTime.now().difference(savedDate);
        if (!diff.isNegative && diff < SchoolCachePolicy.lifetime) {
          try {
            return jsonDecode(cached);
          } catch (_) {}
        }
      }
    }

    final url = "$_baseURL/student/getPupilUnits?prsId=$prsId&yearId=$yearId";
    final headers = _getHeaders();
    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get pupil units: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getPlanSuccess({
    required int groupId,
    required int unitId,
    required int userId,
    bool forceRefresh = false,
  }) async {
    if (_isDemo) {
      // в демо режиме аналитику оставляем пустой
      return {
        'root': {
          'topic': [],
          'user_avg': [],
          'user': {'user_id': userId},
        },
      };
    }

    final cacheKey =
        'cache_${SchoolCachePolicy.namespace}_${this.userId}_plan_success_${groupId}_${unitId}_$userId';
    final timeKey = '${cacheKey}_timestamp';
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timeKey);
      if (cached != null && timestamp != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final diff = DateTime.now().difference(savedDate);
        if (!diff.isNegative && diff < SchoolCachePolicy.lifetime) {
          try {
            return jsonDecode(cached);
          } catch (_) {}
        }
      }
    }

    final params = jsonEncode({
      "groupId": groupId,
      "unitId": unitId,
      "userId": userId,
    });
    final encodedParams = Uri.encodeComponent(params);
    final url = "$_baseURL/reports/data/get_plan_success?params=$encodedParams";
    final headers = _getHeaders();
    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get plan success: ${response.statusCode}');
    }
  }

  Future<List<LPartListItem>> getLPartListPupil(
    int begDate,
    int endDate,
    int yearId,
  ) async {
    if (studentPrsId == null) await _fetchState();
    if (studentPrsId == null) throw Exception('User PrsID not found');

    final url =
        "$_baseURL/student/getLPartListPupil?begDate=$begDate&endDate=$endDate&isOdod=0&prsId=$studentPrsId&yearId=$yearId";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json;charset=UTF-8";

    final response = await _request("PUT", url, headers: headers, body: "[]");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> result = data['result'] ?? [];
      return result.map((e) => LPartListItem.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load LPartListPupil: ${response.statusCode}');
    }
  }

  Future<LPartDetail> getLPartPupil(int partId) async {
    if (studentPrsId == null) await _fetchState();
    if (studentPrsId == null) throw Exception('User PrsID not found');

    final url =
        "$_baseURL/student/getLPartPupil?partId=$partId&prsId=$studentPrsId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> result = data['result'] ?? [];
      if (result.isEmpty) throw Exception('No detail found for partId=$partId');
      return LPartDetail.fromJson(result[0]);
    } else {
      throw Exception('Failed to load LPartPupil: ${response.statusCode}');
    }
  }

  bool _isDemoCredentials(String username, String password) {
    return username == "demo" && password == "J7eVN3wl2dXu";
  }

  void _applyDemoSession() {
    _isDemo = true;
    _cookies.clear();
    isAuthenticated = true;
    userId = _demoData.userId;
    currentPrsId = _demoData.prsId;
    userProfile = _demoData.profile;
  }
}
