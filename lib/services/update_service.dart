import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'android_apk_update.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? releaseNotes;
  final DateTime publishedAt;
  final bool isIOS;
  final bool isTestFlightPending; // true если app.txt не нашёлся, значит сборка на модерации

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.releaseNotes,
    required this.publishedAt,
    this.isIOS = false,
    this.isTestFlightPending = false,
  });
}

class UpdateService {
  static const String _repoOwner = 'reSchool-org';
  static const String _repoName = 'reSchool-flutter';
  static const String _lastCheckKey = 'last_update_check';
  static const String _skippedVersionKey = 'skipped_version';
  static String? _cachedVersion;
  static const String _logTag = '[UpdateService]';

  static Future<String> get currentVersion async {
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }
    debugPrint('$_logTag currentVersion: получаю версию из PackageInfo...');
    final packageInfo = await PackageInfo.fromPlatform();
    _cachedVersion = packageInfo.version;
    debugPrint('$_logTag currentVersion: версия приложения = $_cachedVersion');
    return _cachedVersion!;
  }

  static Future<UpdateInfo?> checkForUpdates({bool force = false}) async {
    debugPrint('$_logTag checkForUpdates: начало проверки (force=$force)');

    if (kIsWeb) {
      debugPrint('$_logTag checkForUpdates: Web платформа - обновления не поддерживаются');
      return null;
    }

    debugPrint('$_logTag checkForUpdates: платформа=${Platform.operatingSystem}');

    // если проверяли недавно, второй раз не лезем
    if (!force) {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey);
      if (lastCheck != null) {
        final lastCheckTime = DateTime.fromMillisecondsSinceEpoch(lastCheck);
        final diff = DateTime.now().difference(lastCheckTime);
        debugPrint('$_logTag checkForUpdates: последняя проверка была ${diff.inMinutes} мин назад (${lastCheckTime.toIso8601String()})');
        if (diff.inHours < 6) {
          debugPrint('$_logTag checkForUpdates: пропуск - проверка была менее 6 часов назад');
          return null;
        }
      } else {
        debugPrint('$_logTag checkForUpdates: первая проверка (нет сохранённой даты)');
      }
    } else {
      debugPrint('$_logTag checkForUpdates: принудительная проверка - игнорируем время последней проверки');
    }

    try {
      // идём на /releases/latest и смотрим редирект, у api есть лимит запросов
      final releasesUrl = Uri.parse(
        'https://github.com/$_repoOwner/$_repoName/releases/latest',
      );
      debugPrint('$_logTag checkForUpdates: запрос к GitHub releases: $releasesUrl');

      // get без автоматического перехода по редиректу
      final client = http.Client();
      final request = http.Request('GET', releasesUrl);
      request.followRedirects = false;

      final streamedResponse = await client.send(request);
      client.close();

      debugPrint('$_logTag checkForUpdates: ответ: statusCode=${streamedResponse.statusCode}');

      // github кинет нас на /releases/tag/vX.Y.Z
      if (streamedResponse.statusCode != 302 && streamedResponse.statusCode != 301) {
        debugPrint('$_logTag checkForUpdates: ожидался редирект 301/302, получен ${streamedResponse.statusCode}');
        return null;
      }

      final location = streamedResponse.headers['location'];
      debugPrint('$_logTag checkForUpdates: Location header: $location');

      if (location == null) {
        debugPrint('$_logTag checkForUpdates: отсутствует Location header');
        return null;
      }

      // версию вытаскиваем из url вида .../releases/tag/v1.2.3
      final tagMatch = RegExp(r'/releases/tag/v?(.+)$').firstMatch(location);
      if (tagMatch == null) {
        debugPrint('$_logTag checkForUpdates: не удалось извлечь версию из URL: $location');
        return null;
      }

      final tagName = tagMatch.group(1)!;
      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      debugPrint('$_logTag checkForUpdates: извлечённая версия = $latestVersion');

      final currentVer = await currentVersion;
      debugPrint('$_logTag checkForUpdates: сравнение версий - текущая=$currentVer, последняя=$latestVersion');

      // сравниваем версии
      final isNewer = _isNewerVersion(latestVersion, currentVer);
      debugPrint('$_logTag checkForUpdates: новая версия доступна = $isNewer');

      if (!isNewer) {
        debugPrint('$_logTag checkForUpdates: обновление не требуется (текущая версия актуальна или новее)');
        return null;
      }

      // эту версию пользователь мог и пропустить
      if (!force) {
        final prefs = await SharedPreferences.getInstance();
        final skipped = prefs.getString(_skippedVersionKey);
        debugPrint('$_logTag checkForUpdates: пропущенная пользователем версия = $skipped');
        if (skipped == latestVersion) {
          debugPrint('$_logTag checkForUpdates: пользователь пропустил эту версию - не показываем');
          return null;
        }
      }

      // ссылку на скачивание собираем по предсказуемому шаблону
      String downloadUrl;
      bool isIOS = false;
      bool isTestFlightPending = false;

      if (Platform.isAndroid) {
        var supportedAbis = <String>[];
        try {
          supportedAbis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
        } catch (e) {
          debugPrint('$_logTag не удалось определить ABI, используем общий APK: $e');
        }
        downloadUrl = AndroidApkUpdate.downloadUrl(latestVersion, supportedAbis);
        debugPrint('$_logTag checkForUpdates: URL для Android APK: $downloadUrl');
      } else if (Platform.isWindows) {
        downloadUrl = 'https://github.com/$_repoOwner/$_repoName/releases/download/v$latestVersion/reSchool-windows.zip';
        debugPrint('$_logTag checkForUpdates: URL для Windows ZIP: $downloadUrl');
      } else if (Platform.isIOS) {
        isIOS = true;
        // рядом должен лежать app.txt со ссылкой на TestFlight
        final appTxtUrl = 'https://github.com/$_repoOwner/$_repoName/releases/download/v$latestVersion/app.txt';
        debugPrint('$_logTag checkForUpdates: проверяю наличие app.txt: $appTxtUrl');

        try {
          final appTxtResponse = await http.get(Uri.parse(appTxtUrl));
          if (appTxtResponse.statusCode == 200) {
            downloadUrl = appTxtResponse.body.trim();
            debugPrint('$_logTag checkForUpdates: TestFlight URL из app.txt: $downloadUrl');
          } else {
            debugPrint('$_logTag checkForUpdates: app.txt не найден (статус ${appTxtResponse.statusCode}) - обновление на модерации');
            downloadUrl = '';
            isTestFlightPending = true;
          }
        } catch (e) {
          debugPrint('$_logTag checkForUpdates: ошибка получения app.txt: $e - обновление на модерации');
          downloadUrl = '';
          isTestFlightPending = true;
        }
      } else {
        debugPrint('$_logTag checkForUpdates: платформа ${Platform.operatingSystem} не поддерживается');
        return null;
      }

      // запоминаем время проверки
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('$_logTag checkForUpdates: сохранено время проверки');

      final updateInfo = UpdateInfo(
        version: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: null, // без api не достать
        publishedAt: DateTime.now(), // без api не достать
        isIOS: isIOS,
        isTestFlightPending: isTestFlightPending,
      );

      debugPrint('$_logTag checkForUpdates: обновление найдено!');
      debugPrint('$_logTag checkForUpdates: версия=${updateInfo.version}, isIOS=$isIOS, isTestFlightPending=$isTestFlightPending');

      return updateInfo;
    } catch (e, stackTrace) {
      debugPrint('$_logTag checkForUpdates: ОШИБКА: $e');
      debugPrint('$_logTag checkForUpdates: stackTrace: $stackTrace');
      return null;
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    debugPrint('$_logTag _isNewerVersion: сравнение "$latest" vs "$current"');
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

    // добиваем нулями, если частей не хватает
      while (latestParts.length < 3) {
        latestParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      debugPrint('$_logTag _isNewerVersion: latest=$latestParts, current=$currentParts');

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) {
          debugPrint('$_logTag _isNewerVersion: latest[$i]=${latestParts[i]} > current[$i]=${currentParts[i]} → true');
          return true;
        }
        if (latestParts[i] < currentParts[i]) {
          debugPrint('$_logTag _isNewerVersion: latest[$i]=${latestParts[i]} < current[$i]=${currentParts[i]} → false');
          return false;
        }
      }
      debugPrint('$_logTag _isNewerVersion: версии равны → false');
      return false;
    } catch (e) {
      debugPrint('$_logTag _isNewerVersion: ошибка парсинга: $e → false');
      return false;
    }
  }

  static Future<void> skipVersion(String version) async {
    debugPrint('$_logTag skipVersion: пользователь пропускает версию $version');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedVersionKey, version);
    debugPrint('$_logTag skipVersion: версия $version сохранена как пропущенная');
  }

  static Future<void> downloadAndInstall(
    UpdateInfo update,
    void Function(double progress) onProgress,
  ) async {
    debugPrint('$_logTag downloadAndInstall: начало установки версии ${update.version}');
    debugPrint('$_logTag downloadAndInstall: URL=${update.downloadUrl}');

    if (Platform.isAndroid) {
      debugPrint('$_logTag downloadAndInstall: используется Android-метод установки');
      await _downloadAndInstallAndroid(update, onProgress);
    } else if (Platform.isWindows) {
      debugPrint('$_logTag downloadAndInstall: используется Windows-метод установки');
      await _downloadAndInstallWindows(update, onProgress);
    } else {
      debugPrint('$_logTag downloadAndInstall: платформа ${Platform.operatingSystem} не поддерживается');
    }
  }

  static Future<void> _downloadAndInstallAndroid(
    UpdateInfo update,
    void Function(double progress) onProgress,
  ) async {
    debugPrint('$_logTag _downloadAndInstallAndroid: начало');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/reschool-${update.version}.apk');
    debugPrint('$_logTag _downloadAndInstallAndroid: путь для сохранения: ${file.path}');

    await AndroidApkUpdate.download(
      version: update.version,
      url: update.downloadUrl,
      file: file,
      onProgress: onProgress,
    );
    debugPrint('$_logTag _downloadAndInstallAndroid: скачивание завершено, файл сохранён');

    // отдаём apk установщику
    debugPrint('$_logTag _downloadAndInstallAndroid: открываю APK для установки...');
    final result = await OpenFilex.open(file.path);
    debugPrint('$_logTag _downloadAndInstallAndroid: результат открытия: type=${result.type}, message=${result.message}');
  }

  static Future<void> _downloadAndInstallWindows(
    UpdateInfo update,
    void Function(double progress) onProgress,
  ) async {
    debugPrint('$_logTag _downloadAndInstallWindows: начало');

    final dir = await getTemporaryDirectory();
    final zipFile = File('${dir.path}/reschool-${update.version}.zip');
    debugPrint('$_logTag _downloadAndInstallWindows: путь для сохранения ZIP: ${zipFile.path}');

    // качаем файл
    debugPrint('$_logTag _downloadAndInstallWindows: начинаю скачивание...');
    final request = http.Request('GET', Uri.parse(update.downloadUrl));
    final response = await http.Client().send(request);

    final contentLength = response.contentLength ?? 0;
    debugPrint('$_logTag _downloadAndInstallWindows: размер файла: ${(contentLength / 1024 / 1024).toStringAsFixed(2)} MB');
    debugPrint('$_logTag _downloadAndInstallWindows: HTTP статус: ${response.statusCode}');

    int received = 0;
    int lastLoggedPercent = 0;

    final sink = zipFile.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        final progress = received / contentLength;
        onProgress(progress);

        // логируем каждые 10%
        final percent = (progress * 100).toInt();
        if (percent >= lastLoggedPercent + 10) {
          lastLoggedPercent = percent;
          debugPrint('$_logTag _downloadAndInstallWindows: скачано $percent% (${(received / 1024 / 1024).toStringAsFixed(2)} MB)');
        }
      }
    }

    await sink.close();
    debugPrint('$_logTag _downloadAndInstallWindows: скачивание завершено, ZIP сохранён');

    // каталог, где лежит текущий exe
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final updateDir = '${dir.path}/reschool_update';

    debugPrint('$_logTag _downloadAndInstallWindows: путь к exe: $exePath');
    debugPrint('$_logTag _downloadAndInstallWindows: директория приложения: $appDir');
    debugPrint('$_logTag _downloadAndInstallWindows: директория для распаковки: $updateDir');

    // скрипт обновления отработает после закрытия приложения
    final scriptPath = '${dir.path}/update_reschool.bat';
    debugPrint('$_logTag _downloadAndInstallWindows: создаю скрипт обновления: $scriptPath');

    final script = '''
@echo off
echo Updating reSchool...
timeout /t 2 /nobreak >nul

:: Extract update
powershell -command "Expand-Archive -Path '${zipFile.path.replaceAll('/', '\\')}' -DestinationPath '$updateDir' -Force"

:: Copy files
xcopy /E /Y /I "$updateDir\\*" "$appDir\\"

:: Clean up
rmdir /S /Q "$updateDir"
del "${zipFile.path.replaceAll('/', '\\')}"

:: Start updated app
start "" "$exePath"

:: Delete this script
del "%~f0"
''';

    await File(scriptPath).writeAsString(script);
    debugPrint('$_logTag _downloadAndInstallWindows: скрипт обновления создан');
    debugPrint('$_logTag _downloadAndInstallWindows: содержимое скрипта:\n$script');

    // запускаем скрипт и выходим
    debugPrint('$_logTag _downloadAndInstallWindows: запускаю скрипт в detached режиме и завершаю приложение...');
    await Process.start('cmd', ['/c', scriptPath], mode: ProcessStartMode.detached);
    debugPrint('$_logTag _downloadAndInstallWindows: exit(0)');
    exit(0);
  }

  static Future<String> get currentVersionString async => await currentVersion;

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isWindows || Platform.isIOS;
  }
}
