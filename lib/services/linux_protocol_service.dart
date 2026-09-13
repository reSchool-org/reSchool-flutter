import 'dart:io';

/// Регистрирует ссылки для текущего пользователя, в том числе у переносной сборки.
class LinuxProtocolService {
  static const desktopId = 'com.magisky.reschool.desktop';

  static Future<void> registerIfNeeded() async {
    if (!Platform.isLinux) return;
    try {
      await registerExecutable(
        Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable,
        environment: Platform.environment,
      );
    } catch (error) {
      // Ошибка интеграции с рабочим столом не должна мешать запуску дневника.
      stderr.writeln('LinuxProtocolService: $error');
    }
  }

  static Future<void> registerExecutable(
    String executable, {
    required Map<String, String> environment,
  }) async {
    if (!executable.startsWith('/') || executable.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('Expected an absolute executable path');
    }
    final configuredDataHome = environment['XDG_DATA_HOME'] ?? '';
    final home = environment['HOME'] ?? '';
    final dataHome = configuredDataHome.startsWith('/')
        ? configuredDataHome
        : home.isNotEmpty
        ? '$home/.local/share'
        : throw StateError('HOME is not set');
    final applications = Directory('$dataHome/applications');
    await applications.create(recursive: true);

    // Exec разбирается по правилам desktop entry, без командной оболочки.
    // Сначала экранируем аргумент, затем обратные слеши для формата key file.
    // env позволяет GLib найти команду даже при знаке % в пути приложения.
    final quotedExecutable = executable
        .replaceAll('%', '%%')
        .replaceAllMapped(RegExp(r'[\\"`$]'), (match) => '\\${match[0]}')
        .replaceAll('\\', '\\\\');
    final entry =
        '''[Desktop Entry]
Type=Application
Name=reSchool
Comment=Электронный дневник
Exec=/usr/bin/env "$quotedExecutable" %u
Terminal=false
Categories=Education;
MimeType=x-scheme-handler/reschool;
StartupWMClass=com.magisky.reschool
''';
    final file = File('${applications.path}/$desktopId');
    if (!await file.exists() || await file.readAsString() != entry) {
      await file.writeAsString(entry, flush: true);
      try {
        await Process.run('update-desktop-database', [
          applications.path,
        ], environment: environment);
      } on ProcessException {
        // Минимальные окружения могут обходиться без desktop-file-utils.
      }
    }
    final query = await Process.run('xdg-mime', [
      'query',
      'default',
      'x-scheme-handler/reschool',
    ], environment: environment);
    if (query.exitCode == 0 && query.stdout.toString().trim() == desktopId) {
      return;
    }
    final result = await Process.run('xdg-mime', [
      'default',
      desktopId,
      'x-scheme-handler/reschool',
    ], environment: environment);
    if (result.exitCode != 0) {
      throw ProcessException(
        'xdg-mime',
        [],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}
