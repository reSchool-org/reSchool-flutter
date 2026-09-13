import 'dart:io';
import 'package:flutter/foundation.dart';

/// прописывает схему `reschool://` в реестр windows,
/// чтобы ссылки открывались этим приложением
/// пишем в HKEY_CURRENT_USER, права администратора не нужны
/// звать один раз на старте под windows
class WindowsProtocolService {
  static const String _scheme = 'reschool';

  static Future<void> registerIfNeeded() async {
    if (!Platform.isWindows) return;

    final exe = Platform.resolvedExecutable;
    final regKey = r'SOFTWARE\Classes\reschool';

    try {
      // может, уже прописано и на тот же exe
      final checkResult = await Process.run('reg', [
        'query',
        'HKCU\\$regKey\\shell\\open\\command',
        '/ve',
      ]);

      final currentValue = checkResult.stdout.toString();
      if (currentValue.contains(exe)) {
        // всё на месте, ничего не трогаем
        return;
      }
    } catch (_) {
      // ключа ещё нет, значит просто регистрируем
    }

    try {
      // в значение по умолчанию кладём URL:reSchool Protocol
      await Process.run('reg', [
        'add', 'HKCU\\$regKey',
        '/ve', '/d', 'URL:$_scheme Protocol',
        '/f',
      ]);

      // рядом заводим пустой параметр URL Protocol
      await Process.run('reg', [
        'add', 'HKCU\\$regKey',
        '/v', 'URL Protocol',
        '/d', '',
        '/f',
      ]);

      // в команду открытия пишем путь к exe и %1
      await Process.run('reg', [
        'add', 'HKCU\\$regKey\\shell\\open\\command',
        '/ve', '/d', '"$exe" "%1"',
        '/f',
      ]);

      debugPrint('WindowsProtocolService: registered reschool:// scheme');
    } catch (e) {
      debugPrint('WindowsProtocolService: failed to register scheme: $e');
    }
  }
}
