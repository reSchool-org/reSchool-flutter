import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

class WorkmanagerAndroid extends WorkmanagerPlatform {
  final WorkmanagerHostApi _api = WorkmanagerHostApi();

  WorkmanagerAndroid() : super();

  static void registerWith() {
    WorkmanagerPlatform.instance = WorkmanagerAndroid();
  }

  @override
  Future<void> initialize(
    Function callbackDispatcher, {
    @Deprecated(
        'Use WorkmanagerDebug handlers instead. This parameter has no effect.')
    bool isInDebugMode = false,
  }) async {
    final callback = PluginUtilities.getCallbackHandle(callbackDispatcher);
    await _api.initialize(InitializeRequest(
      callbackHandle: callback!.toRawHandle(),
    ));
  }

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    await _api.registerOneOffTask(OneOffTaskRequest(
      uniqueName: uniqueName,
      taskName: taskName,
      inputData: inputData?.cast<String?, Object?>(),
      initialDelaySeconds: initialDelay?.inSeconds,
      constraints: constraints,
      existingWorkPolicy: existingWorkPolicy,
      backoffPolicy: backoffPolicyDelay != null && backoffPolicy != null
          ? BackoffPolicyConfig(
              backoffPolicy: backoffPolicy,
              backoffDelayMillis: backoffPolicyDelay.inMilliseconds,
            )
          : null,
      tag: tag,
      outOfQuotaPolicy: outOfQuotaPolicy,
      foregroundServiceConfig:
          resolveForegroundServiceConfig(foregroundServiceConfig),
      expedited: expedited,
    ));
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    await _api.registerPeriodicTask(PeriodicTaskRequest(
      uniqueName: uniqueName,
      taskName: taskName,
      frequencySeconds: frequency?.inSeconds ?? 900, 
      flexIntervalSeconds: flexInterval?.inSeconds,
      inputData: inputData?.cast<String?, Object?>(),
      initialDelaySeconds: initialDelay?.inSeconds,
      constraints: constraints,
      existingWorkPolicy: existingWorkPolicy,
      backoffPolicy: backoffPolicyDelay != null && backoffPolicy != null
          ? BackoffPolicyConfig(
              backoffPolicy: backoffPolicy,
              backoffDelayMillis: backoffPolicyDelay.inMilliseconds,
            )
          : null,
      tag: tag,
      foregroundServiceConfig:
          resolveForegroundServiceConfig(foregroundServiceConfig),
    ));
  }

  @override
  Future<void> registerProcessingTask(
    String uniqueName,
    String taskName, {
    Duration? initialDelay,
    Map<String, dynamic>? inputData,
    Constraints? constraints,
  }) async {
    // такие задачи есть только на ios, на android ничего не делаем
    throw UnsupportedError('Processing tasks are not supported on Android');
  }

  @override
  Future<void> registerHealthResearchTask(
    String uniqueName,
    String taskName, {
    Duration? initialDelay,
    Map<String, dynamic>? inputData,
    Constraints? constraints,
  }) async {
    // исследовательские задачи есть только с ios 17, на android ничего не делаем
    throw UnsupportedError(
        'Health research tasks are not supported on Android');
  }

  @override
  Future<void> registerContinuedProcessingTask(
    String uniqueName,
    String taskName, {
    String? title,
    String? subtitle,
    Map<String, dynamic>? inputData,
  }) async {
    // продолженные задачи есть только с ios 26, на android ничего не делаем
    throw UnsupportedError(
        'Continued processing tasks are not supported on Android');
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    await _api.cancelByUniqueName(uniqueName);
  }

  @override
  Future<void> cancelByTag(String tag) async {
    await _api.cancelByTag(tag);
  }

  @override
  Future<void> cancelAll() async {
    await _api.cancelAll();
  }

  @override
  Future<bool> isScheduledByUniqueName(String uniqueName) async {
    return await _api.isScheduledByUniqueName(uniqueName);
  }

  @override
  Future<String> printScheduledTasks() async {
    throw UnsupportedError('printScheduledTasks is not supported on Android');
  }

  @override
  Future<WorkInfo?> getWorkInfo(String uniqueName) async {
    final data = await _api.getWorkInfoByUniqueName(uniqueName);
    return data == null ? null : WorkInfo.fromData(data);
  }

  @override
  Future<void> reportProgress(Map<String, dynamic> progress) async {
    await _api.reportProgress(progress.cast<String?, Object?>());
  }

  @override
  Future<void> setProgressListener(ProgressListener? listener) async {
    await _api.setProgressListener(listener != null);
  }
}

/// значения по умолчанию задаём на android, чтобы общий контракт оставался необязательным для старых реализаций
const String _defaultForegroundNotificationTitle = 'Task in progress';
const String _defaultForegroundNotificationText = 'Your task is still running';
const String _defaultForegroundNotificationChannelId =
    'workmanager_foreground_tasks';
const String _defaultForegroundNotificationChannelName = 'Long-running tasks';
const int _defaultForegroundNotificationId = 0;
const ForegroundServiceType _defaultForegroundServiceType =
    ForegroundServiceType.dataSync;

/// без запрошенной настройки возвращаем null, иначе дополняем отсутствующие поля
@visibleForTesting
ForegroundServiceConfig? resolveForegroundServiceConfig(
  ForegroundServiceConfig? config,
) {
  if (config == null) {
    return null;
  }
  return ForegroundServiceConfig(
    notificationTitle:
        config.notificationTitle ?? _defaultForegroundNotificationTitle,
    notificationText:
        config.notificationText ?? _defaultForegroundNotificationText,
    notificationChannelId:
        config.notificationChannelId ?? _defaultForegroundNotificationChannelId,
    notificationChannelName: config.notificationChannelName ??
        _defaultForegroundNotificationChannelName,
    notificationId: config.notificationId ?? _defaultForegroundNotificationId,
    foregroundServiceType:
        config.foregroundServiceType ?? _defaultForegroundServiceType,
  );
}
