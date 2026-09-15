import '../models/cloud_connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_font.dart';

class SettingsProvider extends ChangeNotifier {
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  bool _isClassmate = false;
  bool get isClassmate => _isClassmate;
  CloudRole? _cloudRole;
  CloudRole? get cloudRole => _cloudRole;
  bool _cloudAccountLinked = false;
  bool get cloudHomeworkEnabled =>
      _cloudEnabled && (_cloudRole != CloudRole.admin || _cloudAccountLinked);

  Future<void> reloadCloudSettings() => _loadSettings();

  bool _displayOnlyCurrentClass = true;
  int _hwDaysPast = 14;
  int _hwDaysFuture = 14;
  Locale _locale = const Locale('ru');
  bool _developerMode = false;
  bool _teacherChatEnabled = false;
  bool _obsidianEnabled = false;
  String? _obsidianPath;
  String? _obsidianVault;
  String? _obsidianOutputDir;
  bool _obsidianShowMarks = true;
  String _fontFamily = defaultAppFontKey;

  // настройки cors прокси, только для веба
  String? _webProxyServerUrl;
  String _webProxyToken = '';

  String? get webProxyServerUrl => _webProxyServerUrl;
  String get webProxyToken => _webProxyToken;

  // облако: логин, пароль и интервал опроса для пушей
  bool _cloudEnabled = false;
  String? _cloudServerUrl;
  String _cloudApiToken = '';
  int _cloudCheckIntervalMinutes = 10; // меньше 10 сервер всё равно не даст
  int? _cloudCheckIntervalMaxMinutes;
  bool _cloudTelegramEnabled = false;
  String? _cloudTelegramBotToken;
  String? _cloudTelegramUserId;

  // простые геттеры
  bool get displayOnlyCurrentClass => _displayOnlyCurrentClass;
  int get hwDaysPast => _hwDaysPast;
  int get hwDaysFuture => _hwDaysFuture;
  Locale get locale => _locale;
  bool get developerMode => _developerMode;
  bool get teacherChatEnabled => _teacherChatEnabled;
  bool get obsidianEnabled => _obsidianEnabled;
  String? get obsidianPath => _obsidianPath;
  String? get obsidianVault => _obsidianVault;
  String? get obsidianOutputDir => _obsidianOutputDir;
  bool get obsidianShowMarks => _obsidianShowMarks;
  String get fontFamily => _fontFamily;

  // геттеры облака
  bool get cloudEnabled => _cloudEnabled;
  String? get cloudServerUrl => _cloudServerUrl;
  String get cloudApiToken => _cloudApiToken;
  int get cloudCheckIntervalMinutes => _cloudCheckIntervalMinutes;
  int? get cloudCheckIntervalMaxMinutes => _cloudCheckIntervalMaxMinutes;
  String get cloudServerUrlOrEmpty => _cloudServerUrl ?? '';
  bool get cloudTelegramEnabled => _cloudTelegramEnabled;
  String? get cloudTelegramBotToken => _cloudTelegramBotToken;
  String? get cloudTelegramUserId => _cloudTelegramUserId;

  // старые имена, их ещё зовёт settings_screen
  bool get cf3Enabled => _cloudEnabled;
  String? get cf3CustomServerUrl => _cloudServerUrl;
  int get cf3CheckIntervalMinutes => _cloudCheckIntervalMinutes;
  String get cf3ServerUrl => _cloudServerUrl ?? '';
  bool get cf3TelegramEnabled => _cloudTelegramEnabled;
  String? get cf3TelegramBotToken => _cloudTelegramBotToken;
  String? get cf3TelegramUserId => _cloudTelegramUserId;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _displayOnlyCurrentClass =
        prefs.getBool('display_only_current_class') ?? true;
    _hwDaysPast = prefs.getInt('hw_days_past') ?? 14;
    _hwDaysFuture = prefs.getInt('hw_days_future') ?? 14;
    final storedDevMode = prefs.getBool('developer_mode') ?? false;
    _developerMode = kDebugMode && storedDevMode;
    if (!kDebugMode && storedDevMode) {
      // вне debug сборок режим разработчика включить нельзя
      await prefs.remove('developer_mode');
    }
    _teacherChatEnabled = prefs.getBool('teacher_chat_enabled') ?? false;
    _obsidianEnabled = prefs.getBool('obsidian_enabled') ?? false;
    _obsidianPath = prefs.getString('obsidian_path');
    _obsidianVault = prefs.getString('obsidian_vault');
    _obsidianOutputDir = prefs.getString('obsidian_output_dir');
    _obsidianShowMarks = prefs.getBool('obsidian_show_marks') ?? true;
    _fontFamily = prefs.getString('font_family') ?? defaultAppFontKey;

    // облако: старые ключи cf3_ подхватываем ради совместимости
    _cloudEnabled =
        prefs.getBool('cloud_enabled') ?? prefs.getBool('cf3_enabled') ?? false;
    _cloudServerUrl =
        prefs.getString('cloud_server_url') ??
        prefs.getString('cf3_custom_server_url');
    _cloudApiToken = prefs.getString('cloud_api_token') ?? '';
    _cloudCheckIntervalMinutes =
        prefs.getInt('cloud_check_interval') ??
        prefs.getInt('cf3_check_interval') ??
        10;
    _cloudCheckIntervalMaxMinutes = prefs.getInt('cloud_check_interval_max');
    _cloudTelegramEnabled =
        prefs.getBool('cloud_telegram_enabled') ??
        prefs.getBool('cf3_telegram_enabled') ??
        false;
    _cloudTelegramBotToken =
        prefs.getString('cloud_telegram_bot_token') ??
        prefs.getString('cf3_telegram_bot_token');
    _cloudTelegramUserId =
        prefs.getString('cloud_telegram_user_id') ??
        prefs.getString('cf3_telegram_user_id');
    _isClassmate = prefs.getBool('is_classmate') ?? false;
    _cloudAccountLinked = prefs.getString('cf3_registration_id') != null;
    _cloudRole =
        CloudRole.parse(prefs.getString('cloud_role')) ??
        (_cloudEnabled
            ? (_isClassmate ? CloudRole.classmate : CloudRole.admin)
            : null);

    final String? languageCode = prefs.getString('language_code');
    if (languageCode != null) {
      _locale = Locale(languageCode);
    }

    // веб прокси
    _webProxyServerUrl = prefs.getString('web_proxy_server_url');
    _webProxyToken = prefs.getString('web_proxy_token') ?? '';
    if (kIsWeb) {
      _applyWebProxy();
    }

    _isLoaded = true;
    notifyListeners();
  }

  void _applyWebProxy() {
    // импорт ленивый, чтобы ApiService не тянулся в сборки, где веба нет
    final url = _webProxyServerUrl;
    final token = _webProxyToken;
    if (url != null && url.isNotEmpty && token.isNotEmpty) {
      // ставит его сам ApiService, см. api_service.dart
      _pendingWebProxy = (url: url, token: token);
    }
  }

  // прокси лежит тут, пока ApiService не заберёт его после инициализации
  ({String url, String token})? _pendingWebProxy;
  ({String url, String token})? get pendingWebProxy => _pendingWebProxy;

  Future<void> setDisplayOnlyCurrentClass(bool value) async {
    _displayOnlyCurrentClass = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('display_only_current_class', value);
  }

  Future<void> setHwDaysPast(int value) async {
    _hwDaysPast = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hw_days_past', value);
  }

  Future<void> setHwDaysFuture(int value) async {
    _hwDaysFuture = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hw_days_future', value);
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
  }

  Future<void> setDeveloperMode(bool value) async {
    // в release и profile сборках режим разработчика включаться не должен вообще
    if (value && !kDebugMode) return;

    _developerMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (!kDebugMode) {
      await prefs.remove('developer_mode');
      return;
    }
    await prefs.setBool('developer_mode', value);
  }

  Future<void> setTeacherChatEnabled(bool value) async {
    _teacherChatEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('teacher_chat_enabled', value);
  }

  Future<void> setObsidianEnabled(bool value) async {
    _obsidianEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('obsidian_enabled', value);
  }

  Future<void> setObsidianPath(String? value) async {
    _obsidianPath = value?.trim().isEmpty == true ? null : value?.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_obsidianPath == null) {
      await prefs.remove('obsidian_path');
    } else {
      await prefs.setString('obsidian_path', _obsidianPath!);
    }
  }

  Future<void> setObsidianVault(String? value) async {
    _obsidianVault = value?.trim().isEmpty == true ? null : value?.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_obsidianVault == null) {
      await prefs.remove('obsidian_vault');
    } else {
      await prefs.setString('obsidian_vault', _obsidianVault!);
    }
  }

  Future<void> setObsidianOutputDir(String? value) async {
    _obsidianOutputDir = value?.trim().isEmpty == true ? null : value?.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_obsidianOutputDir == null) {
      await prefs.remove('obsidian_output_dir');
    } else {
      await prefs.setString('obsidian_output_dir', _obsidianOutputDir!);
    }
  }

  Future<void> setFontFamily(String value) async {
    _fontFamily = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('font_family', value);
  }

  Future<void> setObsidianShowMarks(bool value) async {
    _obsidianShowMarks = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('obsidian_show_marks', value);
  }

  // сеттеры облака
  Future<void> setCloudEnabled(bool value) async {
    _cloudEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cloud_enabled', value);
  }

  Future<void> setCloudServerUrl(String? value) async {
    _cloudServerUrl = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('cloud_server_url');
    } else {
      await prefs.setString('cloud_server_url', value);
    }
  }

  Future<void> setCloudApiToken(String value) async {
    _cloudApiToken = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_api_token', value);
  }

  Future<void> setCloudCheckIntervalMinutes(
    int value, {
    int? maxMinutes,
  }) async {
    if (value < 1 || (maxMinutes != null && maxMinutes <= value)) {
      throw ArgumentError('Invalid cloud check interval');
    }
    if (_cloudCheckIntervalMinutes == value &&
        _cloudCheckIntervalMaxMinutes == maxMinutes) {
      return;
    }
    _cloudCheckIntervalMinutes = value;
    _cloudCheckIntervalMaxMinutes = maxMinutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cloud_check_interval', value);
    if (maxMinutes == null) {
      await prefs.remove('cloud_check_interval_max');
    } else {
      await prefs.setInt('cloud_check_interval_max', maxMinutes);
    }
    notifyListeners();
  }

  Future<void> setCloudTelegramEnabled(bool value) async {
    _cloudTelegramEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cloud_telegram_enabled', value);
  }

  Future<void> setCloudTelegramBotToken(String? value) async {
    _cloudTelegramBotToken = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('cloud_telegram_bot_token');
    } else {
      await prefs.setString('cloud_telegram_bot_token', value);
    }
  }

  Future<void> setCloudTelegramUserId(String? value) async {
    _cloudTelegramUserId = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('cloud_telegram_user_id');
    } else {
      await prefs.setString('cloud_telegram_user_id', value);
    }
  }

  // сеттеры веб прокси
  Future<void> setWebProxyServerUrl(String? value) async {
    _webProxyServerUrl = value?.trim().isEmpty == true ? null : value?.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_webProxyServerUrl == null) {
      await prefs.remove('web_proxy_server_url');
    } else {
      await prefs.setString('web_proxy_server_url', _webProxyServerUrl!);
    }
  }

  Future<void> setWebProxyToken(String value) async {
    _webProxyToken = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('web_proxy_token', value);
  }

  // старые имена ключей cf3_
  Future<void> setCf3Enabled(bool value) => setCloudEnabled(value);
  Future<void> setCf3CustomServerUrl(String? value) => setCloudServerUrl(value);
  Future<void> setCf3CheckIntervalMinutes(int value) =>
      setCloudCheckIntervalMinutes(value);
  Future<void> setCf3TelegramEnabled(bool value) =>
      setCloudTelegramEnabled(value);
  Future<void> setCf3TelegramBotToken(String? value) =>
      setCloudTelegramBotToken(value);
  Future<void> setCf3TelegramUserId(String? value) =>
      setCloudTelegramUserId(value);

  // сброс всех настроек облака
  Future<void> resetAllCloudSettings() async {
    _cloudEnabled = false;
    _cloudRole = null;
    _isClassmate = false;
    _cloudServerUrl = null;
    _cloudApiToken = '';
    _cloudCheckIntervalMinutes = 10;
    _cloudCheckIntervalMaxMinutes = null;
    _cloudTelegramEnabled = false;
    _cloudTelegramBotToken = null;
    _cloudTelegramUserId = null;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    // сначала новые ключи
    await prefs.remove('cloud_enabled');
    await prefs.remove('cloud_role');
    await prefs.remove('is_classmate');
    await prefs.remove('classmate_id');
    await prefs.remove('classmate_token');
    await prefs.remove('cloud_server_url');
    await prefs.remove('cloud_api_token');
    await prefs.remove('cloud_check_interval');
    await prefs.remove('cloud_check_interval_max');
    await prefs.remove('cloud_telegram_enabled');
    await prefs.remove('cloud_telegram_bot_token');
    await prefs.remove('cloud_telegram_user_id');
    // потом старые cf3_
    await prefs.remove('cf3_enabled');
    await prefs.remove('cf3_custom_server_url');
    await prefs.remove('cf3_check_interval');
    await prefs.remove('cf3_verification_token');
    await prefs.remove('cf3_telegram_enabled');
    await prefs.remove('cf3_telegram_bot_token');
    await prefs.remove('cf3_telegram_user_id');
  }
}
