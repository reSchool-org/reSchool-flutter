import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../screens/link_device_screen.dart';
import 'api_service.dart';
import '../models/cloud_connection.dart';
import 'diary_navigation_service.dart';
import '../utils/app_font.dart';

class DeepLinkHandler {
  /// разбирает ссылки со схемой `reschool://`
  /// что понимаем:
  /// file, параметры variantId, id, name
  /// привязка устройства, параметры server, token, interval, pin
  /// diary, параметры date и subject
  static void handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    if (uri.scheme != 'reschool') return;

    if (uri.host == 'file') {
      _handleFileLink(uri, navigatorKey);
    } else if (uri.host == 'link-device') {
      _handleLinkDevice(uri, navigatorKey);
    } else if (uri.host == 'widget') {
      final tab = switch (uri.pathSegments.firstOrNull) {
        'schedule' => 0,
        'grades' => 1,
        'homework' => 2,
        _ => null,
      };
      if (tab == null) return;
      DiaryNavigationService.instance.switchTab(tab);
    } else if (uri.host == 'message' || uri.host == 'chat') {
      final threadId = _positiveId(
        uri.queryParameters['threadId'] ?? uri.queryParameters['id'],
      );
      if (threadId == null) return;
      DiaryNavigationService.instance.openChat(
        ChatNavigationRequest(
          threadId: threadId,
          messageNumber: _positiveId(uri.queryParameters['msgNum']),
          title: uri.queryParameters['title'] ?? 'Сообщения',
          isGroup: uri.queryParameters['isGroup'] == 'true',
        ),
      );
    } else if (uri.host == 'grade' &&
        DateTime.tryParse(uri.queryParameters['date'] ?? '') == null) {
      DiaryNavigationService.instance.switchTab(1);
    } else if (uri.host == 'diary' ||
        uri.host == 'homework' ||
        uri.host == 'grade') {
      _handleDiaryLink(uri, navigatorKey);
    }
  }

  static int? _positiveId(String? value) {
    final id = int.tryParse(value ?? '');
    return id != null && id > 0 ? id : null;
  }

  static void _handleDiaryLink(
    Uri uri,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    final dateStr = uri.queryParameters['date'];
    final subject = uri.queryParameters['subject'];
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;

    // уводим на вкладку дневника и открываем нужную дату с предметом,
    // за pendingTab следит HomeScreen и переключается сам, а DiaryScreen забирает отложенный запрос
    DiaryNavigationService.instance.switchTab(
      0,
      date: date,
      subject: subject,
      lessonId: _positiveId(uri.queryParameters['lessonId']),
    );
    // главный экран выполнит переход после входа, здесь нельзя закрывать экран авторизации
  }

  static Future<void> _handleLinkDevice(
    Uri uri,
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    final CloudConnectionLink link;
    try {
      link = CloudConnectionLink.parse(uri.toString());
    } on FormatException {
      return;
    }
    final interval = int.tryParse(uri.queryParameters['interval'] ?? '') ?? 10;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => LinkDeviceScreen(
          serverUrl: link.serverUrl,
          apiToken: link.apiToken,
          inviteToken: link.inviteToken,
          checkIntervalMinutes: interval,
          pin: link.pin,
          role: link.role,
        ),
      ),
    );
  }

  static void _handleFileLink(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    final variantId = int.tryParse(
      uri.queryParameters['variantId'] ?? '',
      radix: 10,
    );
    final id = int.tryParse(uri.queryParameters['id'] ?? '', radix: 10);
    final name = ApiService.sanitizeDownloadFilename(
      uri.queryParameters['name'] ?? 'file',
    );

    if (variantId == null || variantId <= 0 || id == null || id <= 0) return;

    final fileUrl =
        'https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/$variantId/$id';

    final context = navigatorKey.currentContext;
    if (context == null) return;

    _downloadAndOpen(context, fileUrl, name);
  }

  static Future<void> _downloadAndOpen(
    BuildContext context,
    String url,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Открыть файл?', style: appFont(dialogContext)),
        content: Text(
          'Скачать и открыть файл "$name" во внешнем приложении? '
          'Файл может содержать вредоносный код. Продолжайте только если доверяете отправителю.',
          style: appFont(dialogContext),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Отмена', style: appFont(dialogContext)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Скачать и открыть', style: appFont(dialogContext)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    messenger?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Загрузка $name…', style: appFont(context))),
          ],
        ),
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final file = await ApiService().downloadXFile(url, name);
      if (!context.mounted) return;
      messenger?.hideCurrentSnackBar();
      if (kIsWeb) {
        await file.saveTo(file.name);
      } else {
        await OpenFilex.open(file.path);
      }
    } catch (_) {
      if (!context.mounted) return;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось загрузить или открыть файл.',
            style: appFont(context),
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
