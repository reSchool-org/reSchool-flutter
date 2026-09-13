import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/advanced_cloud_service.dart';
import '../widgets/cloud_ui.dart';
import '../utils/app_font.dart';

class ServerUpdatesScreen extends StatefulWidget {
  final AdvancedCloudService? service;
  const ServerUpdatesScreen({super.key, this.service});

  @override
  State<ServerUpdatesScreen> createState() => _ServerUpdatesScreenState();
}

class _ServerUpdatesScreenState extends State<ServerUpdatesScreen> {
  late final _service = widget.service ?? AdvancedCloudService();
  Map<String, dynamic>? _snapshot;
  Map<String, dynamic>? _operation;
  Timer? _timer;
  String? _error;
  String? _requestId;
  bool _loading = false;
  bool _starting = false;
  bool _uncertain = false;
  DateTime? _pollStarted;

  bool get _running => const [
    'queued',
    'applying',
    'rolling_back',
  ].contains(_operation?['status']);
  bool get _busy => _loading || _starting || _running || _uncertain;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _message(Object error) {
    if (error is CloudException) {
      if (error.statusCode == 404) {
        return 'На этом сервере ещё нет обновлений из приложения. '
            'Сначала обновите сервер и подключите сервис reschool-settings по SSH.';
      }
      return error.message;
    }
    return 'Не удалось связаться с сервером. Проверьте подключение и повторите.';
  }

  Future<void> _load({bool check = false, bool polling = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (!polling) _error = null;
    });
    try {
      final result = await _service.request(
        check ? '/server-updates/check' : '/server-updates',
        get: true,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        _operation = result['operation'] as Map<String, dynamic>?;
        _error = null;
        _uncertain = false;
        if (!_running) _requestId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = polling
            ? 'Ожидаем подключения к серверу после перезапуска…'
            : _message(error),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _schedulePoll();
      }
    }
  }

  void _schedulePoll() {
    _timer?.cancel();
    if (!_running && !_uncertain) {
      _pollStarted = null;
      return;
    }
    _pollStarted ??= DateTime.now();
    if (DateTime.now().difference(_pollStarted!) >
        const Duration(minutes: 30)) {
      setState(() {
        _error =
            'Не удалось дождаться завершения обновления. '
            'Проверьте состояние сервера повторно.';
      });
      return;
    }
    _timer = Timer(const Duration(seconds: 3), () => _load(polling: true));
  }

  Future<void> _install() async {
    if (_busy || _snapshot?['updateAvailable'] != true) return;
    final random = Random.secure();
    _requestId ??= List.generate(
      36,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final result = await _service.request(
        '/server-updates',
        body: {
          'version': _snapshot!['latestVersion'],
          'operationId': _requestId,
        },
      );
      if (!mounted) return;
      setState(() {
        _operation = result['operation'] as Map<String, dynamic>?;
        if (!_running) _requestId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        // запрос мог дойти до хоста до обрыва соединения
        _uncertain =
            error is! CloudException ||
            error.statusCode == null ||
            error.statusCode! >= 500;
      });
      if (_uncertain) await _load();
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        _schedulePoll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = _snapshot?['latestVersion'] as String?;
    final current = _snapshot?['currentVersion'] as String?;
    final available = _snapshot?['updateAvailable'] == true;
    return CloudTheme(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Обновления сервера', style: appFont(context)),
        ),
        body: CloudPage(
          children: [
            CloudSection(
              title: 'reSchool Server',
              icon: Icons.system_update_alt_rounded,
              subtitle: 'Проверка и установка новых версий сервера.',
              children: [
                Text(
                  'Текущая версия: ${current ?? 'не определена'}',
                  style: appFont(context),
                ),
                if (latest != null)
                  Text('Доступная версия: $latest', style: appFont(context)),
                if (_snapshot?['checkedAt'] != null &&
                    _snapshot?['supported'] == true &&
                    !_running)
                  Text(
                    available
                        ? 'Доступно обновление сервера'
                        : latest == null
                        ? 'Опубликованных обновлений пока нет'
                        : 'Установлена актуальная версия',
                    style: appFont(context),
                  ),
                if (_snapshot?['supported'] == false)
                  Text(
                    'Для этой установки сначала подключите обновления по SSH.',
                    style: appFont(context),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _load(check: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        'Проверить обновления',
                        style: appFont(context),
                      ),
                    ),
                    if (available && _snapshot?['supported'] == true)
                      FilledButton.icon(
                        onPressed: _busy || _error != null ? null : _install,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(
                          'Обновить до $latest',
                          style: appFont(context),
                        ),
                      ),
                  ],
                ),
                Text(
                  'Во время установки сервер ненадолго перезапустится. '
                  'Перед обновлением сохраняются резервные копии. '
                  'Настройки и загруженные файлы сохраняются.',
                  style: appFont(context),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_operation != null)
              CloudSection(
                title: _running
                    ? 'Установка обновления'
                    : 'Результат обновления',
                icon: _operation?['status'] == 'applied'
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                subtitle:
                    _operation?['message'] as String? ?? 'Проверяем состояние…',
              ),
            if (_error != null) ...[
              CloudError(_error!),
              OutlinedButton(
                onPressed: _loading || _starting
                    ? null
                    : () {
                        _pollStarted = null;
                        _load();
                      },
                child: Text('Обновить состояние', style: appFont(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
