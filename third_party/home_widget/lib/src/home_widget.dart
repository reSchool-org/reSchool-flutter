import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';

/// виджет и приложение обмениваются данными через общее хранилище
class HomeWidget {
  static const MethodChannel _channel = MethodChannel('home_widget');
  static const EventChannel _eventChannel = EventChannel('home_widget/updates');

  /// общая группа даёт приложению и виджету ios доступ к одним данным
  static String? groupId;

  /// сохраняем данные в общее хранилище виджета
  static Future<bool?> saveWidgetData<T>(
    String id,
    T? data, {
    bool deleteFile = true,
    String? appGroupId,
  }) async {
    if (deleteFile && data == null) {
      final raw = await getWidgetData<dynamic>(id, appGroupId: appGroupId);
      if (raw is String && _isHomeWidgetManagedFilePath(raw)) {
        final file = File(raw);
        if (await file.exists()) {
          try {
            await file.delete();
          } on FileSystemException {
            // ошибка удаления файла не должна мешать очистке данных виджета
          }
        }
      }
    }

    final arguments = <String, dynamic>{
      'id': id,
      'data': data,
      if (appGroupId != null) 'appGroupId': appGroupId,
    };
    return _channel.invokeMethod<bool>('saveWidgetData', arguments);
  }

  /// на android ищем полное имя, затем имя с пакетом и общее; на ios имя должно совпадать с kind виджета
  static Future<bool?> updateWidget({
    String? name,
    String? androidName,
    String? iOSName,
    String? qualifiedAndroidName,
  }) {
    return _channel.invokeMethod('updateWidget', {
      'name': name,
      'android': androidName,
      'ios': iOSName,
      'qualifiedAndroidName': qualifiedAndroidName,
    });
  }

  /// на android новые времена заменяют расписание, пустой список отменяет его; на ios задаём timeline сами
  /// для android регистрируем HomeWidgetScheduledUpdateReceiver и RECEIVE_BOOT_COMPLETED, точность требует права на точные будильники
  /// передаём абсолютное время, поэтому при смене часового пояса расписание по местным часам нужно пересчитать
  /// если провайдер не найден, получим PlatformException
  static Future<bool?> scheduleWidgetUpdates(
    List<DateTime> updateTimes, {
    String? name,
    String? androidName,
    String? qualifiedAndroidName,
  }) {
    final millis = updateTimes
        .map((time) => time.millisecondsSinceEpoch)
        .toList();
    return _channel.invokeMethod('scheduleWidgetUpdates', {
      'updateTimes': millis,
      'name': name,
      'android': androidName,
      'qualifiedAndroidName': qualifiedAndroidName,
    });
  }

  /// отменяем расписание только на android, ios возвращает false; неизвестный провайдер вызывает PlatformException
  static Future<bool?> cancelScheduledWidgetUpdates({
    String? name,
    String? androidName,
    String? qualifiedAndroidName,
  }) {
    return _channel.invokeMethod('cancelScheduledWidgetUpdates', {
      'name': name,
      'android': androidName,
      'qualifiedAndroidName': qualifiedAndroidName,
    });
  }

  /// на android 12 и новее проверяем право на точные будильники; без него обновления всё равно планируются, но могут задержаться
  /// приложение само выбирает и объявляет SCHEDULE_EXACT_ALARM или USE_EXACT_ALARM, на ios возвращаем false
  static Future<bool?> canScheduleExactWidgetUpdates() {
    return _channel.invokeMethod('canScheduleExactWidgetUpdates');
  }

  /// закрепление зависит от возможностей лаунчера
  static Future<bool?> isRequestPinWidgetSupported() {
    return _channel.invokeMethod('isRequestPinWidgetSupported');
  }

  /// закрепление доступно в некоторых лаунчерах начиная с android api 26, на ios аналога нет
  static Future<void> requestPinWidget({
    String? name,
    String? androidName,
    String? qualifiedAndroidName,
  }) {
    return _channel.invokeMethod('requestPinWidget', {
      'name': name,
      'android': androidName,
      'qualifiedAndroidName': qualifiedAndroidName,
    });
  }

  /// при отсутствии данных возвращаем переданное значение по умолчанию
  static Future<T?> getWidgetData<T>(
    String id, {
    T? defaultValue,
    String? appGroupId,
  }) {
    final arguments = <String, dynamic>{
      'id': id,
      'defaultValue': defaultValue,
      if (appGroupId != null) 'appGroupId': appGroupId,
    };
    return _channel.invokeMethod<T>('getWidgetData', arguments);
  }

  /// общая группа обязательна для обмена данными приложения и расширения виджета ios
  static Future<bool?> setAppGroupId(String groupId) {
    HomeWidget.groupId = groupId;
    return _channel.invokeMethod('setAppGroupId', {'groupId': groupId});
  }

  /// проверяем запуск приложения по виджету
  static Future<Uri?> initiallyLaunchedFromHomeWidget() {
    return _channel
        .invokeMethod<String>('initiallyLaunchedFromHomeWidget')
        .then(_handleReceivedData);
  }

  /// после настройки виджета android нужно вызвать HomeWidget.finishHomeWidgetConfigure
  static Future<String?> initiallyLaunchedFromHomeWidgetConfigure() {
    return _channel.invokeMethod<String>(
      'initiallyLaunchedFromHomeWidgetConfigure',
    );
  }

  /// завершаем настройку, начатую через HomeWidget.initiallyLaunchedFromHomeWidgetConfigure
  static Future<void> finishHomeWidgetConfigure() {
    return _channel.invokeMethod<void>('finishHomeWidgetConfigure');
  }

  /// слушаем открытия приложения через виджет
  static Stream<Uri?> get widgetClicked {
    return _eventChannel.receiveBroadcastStream().map<Uri?>(
      _handleReceivedData,
    );
  }

  static Uri? _handleReceivedData(dynamic value) {
    if (value != null) {
      if (value is String) {
        try {
          return Uri.parse(value);
        } on FormatException {
          debugPrint('Received Data($value) is not parsable into an Uri');
        }
      }
      return Uri();
    } else {
      return null;
    }
  }

  /// обработчик нажатия в виджете позволяет вызвать код dart в фоне
  @Deprecated('Use `registerInteractivityCallback` instead')
  static Future<bool?> registerBackgroundCallback(
    FutureOr<void> Function(Uri?) callback,
  ) => registerInteractivityCallback(callback);

  /// обработчик нажатия в виджете позволяет вызвать код dart в фоне
  static Future<bool?> registerInteractivityCallback(
    FutureOr<void> Function(Uri?) callback,
  ) {
    final args = <dynamic>[
      ui.PluginUtilities.getCallbackHandle(callbackDispatcher)?.toRawHandle(),
      ui.PluginUtilities.getCallbackHandle(callback)?.toRawHandle(),
    ];
    return _channel.invokeMethod('registerBackgroundCallback', args);
  }

  /// при очистке ключа удаляем только файлы внутри каталога home_widget
  static bool _isHomeWidgetManagedFilePath(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.contains('/home_widget/');
  }

  static String _normalizeExtension(String extension) {
    var ext = extension.trim();
    if (ext.startsWith('.')) {
      ext = ext.substring(1);
    }
    if (ext.isEmpty) {
      throw ArgumentError.value(extension, 'extension', 'must not be empty');
    }
    if (ext.contains('/') || ext.contains(r'\') || ext.contains('..')) {
      throw ArgumentError.value(
        extension,
        'extension',
        'must not contain path separators',
      );
    }
    return ext;
  }

  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    if (key.contains('/') ||
        key.contains(r'\') ||
        key.contains('..') ||
        key.contains(' ')) {
      throw ArgumentError.value(
        key,
        'key',
        'must not contain /, \\, .., or spaces',
      );
    }
  }

  /// сохраняем байты в общее хранилище виджета, абсолютный путь записываем под ключом
  /// на ios используем контейнер группы, на android каталог поддержки приложения
  static Future<String> saveFile(
    String key,
    Uint8List bytes, {
    String extension = 'bin',
    String? appGroupId,
  }) async {
    final ext = _normalizeExtension(extension);
    _validateKey(key);

    try {
      late final String? directory;
      // coverage:ignore-start
      if (Platform.isIOS) {
        final PathProviderFoundation provider = PathProviderFoundation();
        final resolvedGroupId = appGroupId ?? HomeWidget.groupId;
        assert(
          resolvedGroupId != null,
          'No groupId defined. Did you forget to call `HomeWidget.setAppGroupId`',
        );
        directory = await provider.getContainerPath(
          appGroupIdentifier: resolvedGroupId!,
        );

        if (directory == null) {
          throw StateError(
            'Widget storage directory is null for group "$resolvedGroupId". '
            'Verify App Group configuration and HomeWidget.setAppGroupId.',
          );
        }
      } else {
        // coverage:ignore-end
        directory = (await getApplicationSupportDirectory()).path;
      }

      final String path = '$directory/home_widget/$key.$ext';
      final File file = File(path);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsBytes(bytes);

      await saveWidgetData<String>(key, path, appGroupId: appGroupId);

      return path;
    } catch (e) {
      throw Exception('Failed to save file to widget container: $e');
    }
  }

  /// для анимации сохраняем только первый кадр как png через saveFile
  static Future<String> saveImage(
    String key,
    ImageProvider imageProvider, {
    ImageConfiguration configuration = ImageConfiguration.empty,
    String? appGroupId,
  }) async {
    _validateKey(key);
    final completer = Completer<Uint8List>();
    final stream = imageProvider.resolve(configuration);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) async {
        stream.removeListener(listener);
        try {
          final ByteData? byteData = await info.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          // coverage:ignore-start
          if (byteData == null) {
            if (!completer.isCompleted) {
              completer.completeError(
                Exception('Failed to encode image to PNG'),
              );
            }
          } else
          // coverage:ignore-end
          if (!completer.isCompleted) {
            completer.complete(byteData.buffer.asUint8List());
          }
        }
        // coverage:ignore-start
        catch (e, st) {
          if (!completer.isCompleted) {
            completer.completeError(e, st);
          }
        }
        // coverage:ignore-end
      },
      onError: (Object exception, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(exception, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    final bytes = await completer.future;
    return saveFile(key, bytes, extension: 'png', appGroupId: appGroupId);
  }

  /// снимок виджета сохраняем в общий контейнер, путь записываем под ключом; ошибки рендера и записи передаём вызывающему коду
  static Future<String> renderFlutterWidget(
    Widget widget, {
    required String key,
    Size logicalSize = const Size(200, 200),
    double? pixelRatio,
    String? appGroupId,
  }) async {
    pixelRatio ??=
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;

    final RenderRepaintBoundary repaintBoundary = RenderRepaintBoundary();

    final PipelineOwner pipelineOwner = PipelineOwner();

    final BuildOwner buildOwner = BuildOwner(focusManager: FocusManager());

    try {
      final RenderView renderView = RenderView(
        view: ui.PlatformDispatcher.instance.implicitView!,
        child: RenderPositionedBox(
          alignment: Alignment.center,
          child: repaintBoundary,
        ),
        configuration: ViewConfiguration(
          logicalConstraints: BoxConstraints.tight(logicalSize),
          devicePixelRatio: pixelRatio,
        ),
      );

      pipelineOwner.rootNode = renderView;

      renderView.prepareInitialFrame();

      final RenderObjectToWidgetElement<RenderBox> rootElement =
          RenderObjectToWidgetAdapter<RenderBox>(
            container: repaintBoundary,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [widget],
              ),
            ),
          ).attachToRenderTree(buildOwner);

      buildOwner.buildScope(rootElement);

      buildOwner.buildScope(rootElement);

      buildOwner.finalizeTree();

      pipelineOwner.flushLayout();

      pipelineOwner.flushCompositingBits();

      pipelineOwner.flushPaint();

      final ui.Image image = await repaintBoundary.toImage(
        pixelRatio: pixelRatio,
      );

      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      // coverage:ignore-start
      if (byteData == null) {
        throw Exception('Failed to encode widget to PNG');
      }
      // coverage:ignore-end

      try {
        return await saveFile(
          key,
          byteData.buffer.asUint8List(),
          extension: 'png',
          appGroupId: appGroupId,
        );
      } catch (e) {
        throw Exception('Failed to save screenshot to app group container: $e');
      }
    } catch (e) {
      throw Exception('Failed to render the widget: $e');
    }
  }

  /// на ios возвращаем запись на тип виджета, на android на каждый закреплённый экземпляр
  static Future<List<HomeWidgetInfo>> getInstalledWidgets() async {
    final result =
        await _channel.invokeMethod('getInstalledWidgets') as List<dynamic>?;
    return result
            ?.map((widget) => (widget as Map).cast<String, dynamic>())
            .map(HomeWidgetInfo.fromMap)
            .toList() ??
        [];
  }
}
