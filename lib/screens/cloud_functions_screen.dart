import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cloud_connection.dart';
import '../providers/settings_provider.dart';
import '../providers/custom_homework_provider.dart';
import '../services/advanced_cloud_service.dart';
import '../services/api_service.dart';
import '../services/diary_navigation_service.dart';
import '../services/tls_pin_store.dart';
import '../utils/app_font.dart';
import '../widgets/app_card.dart';
import '../widgets/cloud_ui.dart';
import '../widgets/cloud_interval_dialog.dart';
import 'cloud_connection_screen.dart';
import 'cloud_server_settings.dart';
import 'server_updates_screen.dart';
import 'notification_history_screen.dart';
import 'telegram_group_screen.dart';
import 'textbooks_screen.dart';

enum _CloudDestination { monitoring, telegram, access, server, connection }

class CloudFunctionsScreen extends StatefulWidget {
  final AdvancedCloudService? service;
  final _CloudDestination? _destination;
  const CloudFunctionsScreen({super.key, this.service}) : _destination = null;
  const CloudFunctionsScreen._({
    required _CloudDestination this._destination,
    this.service,
  });
  @override
  State<CloudFunctionsScreen> createState() => _CloudFunctionsScreenState();
}

class _CloudFunctionsScreenState extends State<CloudFunctionsScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? AdvancedCloudService();
  final _telegramId = TextEditingController();
  final _botToken = TextEditingController();
  final _gradeClass = TextEditingController();
  Map<String, dynamic>? _status;
  String? _error;
  String? _inviteLink;
  bool _loading = true;
  bool _busy = false;
  bool _telegramEnabled = false;
  bool _adminTokenVisible = false;
  int _interval = 10;
  int? _intervalMax;
  int _minInterval = 10;
  int _maxInterval = 1440;
  bool _supportsRandomInterval = false;

  String get _intervalSummary => _intervalMax == null
      ? 'Каждые $_interval мин'
      : 'Случайно, $_interval-$_intervalMax мин';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        !_busy &&
        ModalRoute.of(context)?.isCurrent == true) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telegramId.dispose();
    _botToken.dispose();
    _gradeClass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    await settings.reloadCloudSettings();
    if (!mounted) return;
    if (!settings.cloudEnabled) {
      setState(() {
        _loading = false;
        _status = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.request('/cloud/status');
      await settings.reloadCloudSettings();
      if (!mounted) return;
      setState(() {
        _status = result;
        _telegramId.text = result['telegramUserId'] as String? ?? '';
        _telegramEnabled = result['telegramEnabled'] == true;
        _minInterval = result['minCheckIntervalMinutes'] as int? ?? 10;
        _maxInterval = result['maxCheckIntervalMinutes'] as int? ?? 1440;
        _intervalMax = result['checkIntervalMaxMinutes'] as int?;
        _supportsRandomInterval =
            result['randomCheckIntervalSupported'] == true;
        _interval =
            result['checkIntervalMinutes'] as int? ??
            settings.cloudCheckIntervalMinutes;
      });
      if (result['monitoring'] == true) {
        await settings.setCloudCheckIntervalMinutes(
          _interval,
          maxMinutes: _intervalMax,
        );
      }
      if (_gradeClass.text.isEmpty) {
        final grade =
            result['gradeClass'] as String? ??
            await ApiService().currentGradeClass();
        if (mounted) _gradeClass.text = grade ?? '';
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object e) => e is CloudException
      ? e.message
      : 'Не удалось связаться с сервером. Проверьте подключение к интернету';

  Future<void> _action(
    Future<void> Function() work, {
    String? success,
    bool reload = true,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      if (!mounted) return;
      if (reload) await _load();
      if (success != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success, style: appFont(context))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(CloudRole role) async {
    final connected = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CloudConnectionScreen(role: role)),
    );
    if (connected == true && mounted) {
      context.read<CustomHomeworkProvider>().clearCache();
      await _load();
    }
  }

  Future<void> _disconnect() async {
    final localOnly = await showDialog<bool>(
      context: context,
      builder: (ctx) => CloudTheme(
        child: AlertDialog(
          title:  Text('Отключиться от сервера?', style: appFont(ctx)),
          scrollable: true,
          content:  Text(
            'Можно удалить подключение только с устройства, даже если сервер выключен. В этом случае переданные данные останутся на сервере, а мониторинг и уведомления могут продолжиться. Для нового подключения понадобится ключ или приглашение.', style: appFont(ctx),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text('Отмена', style: appFont(ctx)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text('Только на устройстве', style: appFont(ctx)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text('Удалить и с сервера', style: appFont(ctx)),
            ),
          ],
        ),
      ),
    );
    if (localOnly == null || !mounted) return;
    final settings = context.read<SettingsProvider>();
    await _action(() async {
      try {
        await _service.disconnect(localOnly: localOnly);
      } catch (_) {
        if (localOnly || !mounted) rethrow;
        final forget = await showDialog<bool>(
          context: context,
          builder: (ctx) => CloudTheme(
            child: AlertDialog(
              title:  Text('Сервер не подтвердил удаление', style: appFont(ctx)),
              scrollable: true,
              content:  Text(
                'Можно отключиться только на этом устройстве. Переданные данные могут остаться на сервере, а мониторинг и уведомления могут продолжиться.', style: appFont(ctx),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child:  Text('Отмена', style: appFont(ctx)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child:  Text('Отключиться на устройстве', style: appFont(ctx)),
                ),
              ],
            ),
          ),
        );
        if (forget != true || !mounted) return;
        await _service.disconnect(localOnly: true);
      }
      await settings.reloadCloudSettings();
      if (mounted) context.read<CustomHomeworkProvider>().clearCache();
      if (mounted) {
        setState(() {
          _status = null;
          _inviteLink = null;
        });
      }
    });
    if (mounted && !settings.cloudEnabled && widget._destination != null) {
      Navigator.pop(context);
    }
  }

  Future<void> _updatePassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => CloudTheme(
        child: AlertDialog(
          title:  Text('Обновить пароль eSchool', style: appFont(ctx)),
          scrollable: true,
          content: TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: cloudInput('Новый пароль'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text('Отмена', style: appFont(ctx)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child:  Text('Обновить', style: appFont(ctx)),
            ),
          ],
        ),
      ),
    );
    // поле ещё участвует в анимации закрытия диалога
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (password == null || password.isEmpty || !mounted) return;
    await _action(() async {
      await _service.request('/update-password', body: {'password': password});
    }, success: 'Пароль обновлён');
  }

  Future<void> _createInvite() async {
    await _action(() async {
      final result = await _service.request(
        '/cloud/invites',
        body: {'gradeClass': _gradeClass.text.trim()},
      );
      if (!mounted) return;
      final settings = context.read<SettingsProvider>();
      final url = settings.cloudServerUrl!;
      final pin = TlsPinStore.instance.pinForUrl(url);
      setState(
        () => _inviteLink = Uri(
          scheme: 'reschool',
          host: 'link-device',
          queryParameters: {
            'server': url,
            'inviteToken': result['inviteToken'] as String,
            if (pin != null) 'pin': pin,
          },
        ).toString(),
      );
    }, reload: false);
  }

  void _openHomework() {
    DiaryNavigationService.instance.switchTab(0);
    Navigator.of(context)
        .popUntil((route) => route.isFirst || route.settings.name == '/home');
  }

  Future<void> _openSection(_CloudDestination destination) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CloudFunctionsScreen._(destination: destination, service: _service),
      ),
    );
    if (mounted) await _load();
  }

  String _pageTitle(CloudRole? role) => switch (widget._destination) {
    _CloudDestination.monitoring => 'Мониторинг аккаунта',
    _CloudDestination.telegram =>
      role?.isAdmin == true ? 'Telegram' : 'Уведомления',
    _CloudDestination.access => 'Доступ и приглашения',
    _CloudDestination.server => 'Сервер',
    _CloudDestination.connection => 'Подключение',
    null => 'Облачные функции',
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final role = settings.cloudRole;
    final connected = settings.cloudEnabled && role != null;
    final cs = Theme.of(context).colorScheme;
    return CloudTheme(
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          title: Text(
            connected ? _pageTitle(role) : 'Облачные функции',
            style: appFont(context, fontSize: 18, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          centerTitle: true,
          scrolledUnderElevation: 0,
          actions: [
            if (connected)
              IconButton(
                tooltip: 'Обновить состояние',
                onPressed: _busy || _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 22),
              ),
          ],
          bottom: _busy || (_loading && connected)
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: !settings.isLoaded
            ? const Center(child: CircularProgressIndicator())
            : !connected
            ? _onboarding()
            : _connectedPage(settings, role),
      ),
    );
  }

  Widget _onboarding() {
    final cs = Theme.of(context).colorScheme;
    return CloudPage(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.cloud_outlined, size: 28, color: cs.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ваше облако reSchool',
                      style: appFont(context, fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Общие задания и уведомления об обновлениях дневника.',
                      style: appFont(context,
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        CloudSettingsGroup(
          title: 'Подключение',
          footer: 'Выберите подходящий режим. Его можно изменить после отключения от сервера.',
          children: [
            CloudSettingsTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Войти как администратор',
              subtitle: 'Свой сервер · QR, SSH или API ключ',
              onTap: () => _connect(CloudRole.admin),
            ),
            CloudSettingsTile(
              icon: Icons.notifications_active_outlined,
              title: 'С передачей логина и пароля',
              subtitle: 'Проверка дневника и личные уведомления. Данные eSchool передаются серверу.',
              onTap: () => _connect(CloudRole.user),
            ),
            CloudSettingsTile(
              icon: Icons.lock_outline_rounded,
              title: 'Без передачи логина и пароля',
              subtitle: 'Общие задания класса. Данные eSchool остаются на устройстве.',
              onTap: () => _connect(CloudRole.classmate),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectionHeader(SettingsProvider settings, CloudRole role) {
    final cs = Theme.of(context).colorScheme;
    final failed = _error != null;
    final color = failed ? cs.error : cs.primary;
    final needsTextSpace =
        MediaQuery.sizeOf(context).width < 420 &&
        MediaQuery.textScalerOf(context).scale(15) > 20;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (!needsTextSpace) ...[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                failed ? Icons.cloud_off_outlined : Icons.cloud_outlined,
                color: color,
                size: 25,
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (role) {
                  CloudRole.admin => 'Администратор',
                  CloudRole.user => 'Пользователь',
                  CloudRole.classmate => 'Участник класса',
                }, style: appFont(context, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  Uri.tryParse(settings.cloudServerUrlOrEmpty)?.authority ??
                      settings.cloudServerUrlOrEmpty,
                  style: appFont(context, fontSize: 12, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  _loading
                      ? 'Проверяем подключение…'
                      : failed
                      ? 'Сервер недоступен'
                      : 'Подключено',
                  style: appFont(context,
                    fontSize: 12,
                    color: failed ? cs.error : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectedPage(SettingsProvider settings, CloudRole role) {
    if (_status == null &&
        (widget._destination == _CloudDestination.monitoring ||
            widget._destination == _CloudDestination.telegram)) {
      return CloudPage(
        children: [
          if (_error != null) CloudError(_error!),
          CloudSection(
            title: _loading ? 'Загружаем настройки…' : 'Настройки недоступны',
            icon: Icons.cloud_outlined,
            subtitle: _loading ? 'Получаем состояние с сервера.' : 'Обновите состояние, когда соединение с сервером восстановится.',
          ),
        ],
      );
    }
    return switch (widget._destination) {
      null => _settingsHome(settings, role),
      _CloudDestination.monitoring => _overview(role),
      _CloudDestination.telegram => _telegram(role),
      _CloudDestination.access => _access(settings),
      _CloudDestination.server => CloudPage(
        children: [
          if (_error != null) CloudError(_error!),
          const CloudServerSettings(),
          _disconnectCard(),
        ],
      ),
      _CloudDestination.connection => CloudPage(
        children: [
          if (_error != null) CloudError(_error!),
          CloudSection(
            title: 'Сервер',
            icon: Icons.link_rounded,
            subtitle: settings.cloudServerUrlOrEmpty,
            children: [
              Text(
                role.canMonitor
                    ? 'Сервер хранит зашифрованный пароль eSchool и проверяет обновления вашего аккаунта.'
                    : 'Сервер получил только приглашение и имя для общих заданий. Логин и пароль eSchool ему не передавались.', style: appFont(context),
              ),
            ],
          ),
          _disconnectCard(),
        ],
      ),
    };
  }

  Widget _settingsHome(SettingsProvider settings, CloudRole role) {
    final monitoring = _status?['monitoring'] == true;
    final invalid = _status?['sessionInvalid'] == true;
    return CloudPage(
      onRefresh: () async {
        if (!_busy && !_loading) await _load();
      },
      children: [
        _connectionHeader(settings, role),
        if (_error != null) CloudError(_error!),
        CloudSettingsGroup(
          title: 'Настройки облака',
          children: [
            if (role.canMonitor)
              CloudSettingsTile(
                icon: Icons.sync_rounded,
                title: 'Мониторинг аккаунта',
                subtitle: _loading || _error != null
                    ? 'Проверка обновлений дневника'
                    : invalid
                    ? 'Нужно обновить вход в eSchool'
                    : monitoring
                    ? 'Включён · ${_intervalSummary.toLowerCase()}'
                    : 'Не включён',
                onTap: () => _openSection(_CloudDestination.monitoring),
              ),
            if (role.canMonitor)
              CloudSettingsTile(
                icon: Icons.notifications_outlined,
                title: role.isAdmin ? 'Telegram' : 'Уведомления',
                subtitle: role.isAdmin
                    ? 'Бот, личные уведомления и группа'
                    : 'Уведомления в личный Telegram',
                onTap: () => _openSection(_CloudDestination.telegram),
              ),
            if (role.isAdmin)
              CloudSettingsTile(
                icon: Icons.people_outline_rounded,
                title: 'Доступ и приглашения',
                subtitle: 'Участники класса, ваши устройства и токен администратора',
                onTap: () => _openSection(_CloudDestination.access),
              ),
            if (role.isAdmin)
              CloudSettingsTile(
                icon: Icons.system_update_alt_rounded,
                title: 'Обновления сервера',
                subtitle: 'Версия reSchool Server и установка обновлений',
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServerUpdatesScreen(service: _service),
                  ),
                ),
              ),
            CloudSettingsTile(
              icon: role.isAdmin ? Icons.dns_outlined : Icons.link_rounded,
              title: role.isAdmin ? 'Сервер' : 'Подключение',
              subtitle: role.isAdmin
                  ? 'Адрес, домен и безопасность'
                  : 'Данные сервера и отключение',
              onTap: () => _openSection(
                role.isAdmin
                    ? _CloudDestination.server
                    : _CloudDestination.connection,
              ),
            ),
          ],
        ),
        CloudSettingsGroup(
          title: 'Возможности',
          children: [
            CloudSettingsTile(
              icon: Icons.edit_note_rounded,
              title: 'Общие домашние задания',
              subtitle: 'Задания и материалы класса в дневнике',
              onTap: _openHomework,
            ),
            if (role.canMonitor && monitoring)
              CloudSettingsTile(
                icon: Icons.history_rounded,
                title: 'История уведомлений',
                subtitle: 'Новые задания, оценки и сообщения',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationHistoryScreen(),
                  ),
                ),
              ),
            if (role.isAdmin)
              CloudSettingsTile(
                icon: Icons.auto_stories_outlined,
                title: 'Учебники и разбор заданий',
                subtitle: monitoring
                    ? 'Учебники вашего класса'
                    : 'Доступно после включения мониторинга',
                onTap: monitoring
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TextbooksScreen(),
                        ),
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _overview(CloudRole role) {
    final monitoring = _status?['monitoring'] == true;
    final invalid = _status?['sessionInvalid'] == true;
    return CloudPage(
      children: [
        if (_error != null) CloudError(_error!),
        if (role.canMonitor)
          CloudSection(
            title: monitoring
                ? (invalid ? 'Нужно обновить вход' : 'Аккаунт под наблюдением')
                : 'Мониторинг аккаунта',
            icon: invalid
                ? Icons.key_rounded
                : Icons.notifications_active_outlined,
            subtitle: monitoring
                ? 'Сервер проверяет новые домашние задания, оценки и сообщения текущего аккаунта eSchool.'
                : 'Включите проверку обновлений. Для этого серверу будут переданы логин и пароль текущего аккаунта eSchool.',
            children: [
              if (role.isAdmin && !monitoring)
                TextField(
                  controller: _gradeClass,
                  enabled: !_busy,
                  maxLength: 32,
                  decoration: cloudInput(
                    'Класс',
                    hint: 'Например, 10А',
                    helper: 'Если класс не определился автоматически, укажите его здесь',
                  ),
                ),
              if (monitoring) ...[
                if (_status?['fullName'] != null)
                  Text(
                    _status!['fullName'] as String,
                    style: appFont(context, fontWeight: FontWeight.w600),
                  ),
                Text(
                  _status?['lastCheckAt'] == null
                      ? 'Первая проверка ещё не выполнена'
                      : 'Последняя проверка: ${_lastCheck(_status!['lastCheckAt'] as String)}',
                  style: appFont(context, fontSize: 12),
                ),
                if (invalid)
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonal(
                        onPressed: _busy ? null : _updatePassword,
                        child:  Text('Обновить пароль', style: appFont(context)),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _action(() async {
                                await _service.request('/retry-session');
                              }),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label:  Text('Повторить вход', style: appFont(context)),
                      ),
                    ],
                  ),
                _intervalPicker(),
              ] else if (role.isAdmin)
                FilledButton.icon(
                  onPressed: _busy || _loading
                      ? null
                      : () => _action(() async {
                          await _service.enableAdminMonitoring(
                            gradeClass: _gradeClass.text,
                          );
                        }, success: 'Мониторинг включён'),
                  icon: const Icon(Icons.sync_rounded),
                  label:  Text('Передать данные и включить', style: appFont(context)),
                ),
            ],
          ),
      ],
    );
  }

  String _lastCheck(String value) {
    final parsed = DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z');
    if (parsed == null) return value;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _chooseInterval() async {
    final selected = await showDialog<CloudCheckInterval>(
      context: context,
      builder: (_) => CloudIntervalDialog(
        initial: (minutes: _interval, maximumMinutes: _intervalMax),
        minimum: _minInterval,
        maximum: _maxInterval,
        supportsRandom: _supportsRandomInterval,
      ),
    );
    if (!mounted ||
        selected == null ||
        (selected.minutes == _interval &&
            selected.maximumMinutes == _intervalMax)) {
      return;
    }
    final previous = (minutes: _interval, maximumMinutes: _intervalMax);
    setState(() {
      _interval = selected.minutes;
      _intervalMax = selected.maximumMinutes;
    });
    var saved = false;
    await _action(() async {
      await _service.request(
        '/update-interval',
        body: {
          'checkIntervalMinutes': selected.minutes,
          'checkIntervalMaxMinutes': selected.maximumMinutes,
        },
      );
      saved = true;
      if (mounted) {
        await context.read<SettingsProvider>().setCloudCheckIntervalMinutes(
          selected.minutes,
          maxMinutes: selected.maximumMinutes,
        );
      }
    }, success: 'Интервал сохранён');
    if (mounted && !saved) {
      setState(() {
        _interval = previous.minutes;
        _intervalMax = previous.maximumMinutes;
      });
    }
  }

  Widget _intervalPicker() => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      'Частота проверки',
      style: appFont(context, fontSize: 14, fontWeight: FontWeight.w500),
    ),
    subtitle: Text(
      _intervalSummary,
      style: appFont(context,
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    trailing: Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onTap: _busy ? null : _chooseInterval,
  );

  Widget _telegram(CloudRole role) {
    final configured = _status?['telegramBotConfigured'] == true;
    final username =
        (_status?['telegramBotUsername'] as String? ?? '').trim();
    final botName = username.isEmpty ? 'бот сервера' : '@$username';
    final monitoring = _status?['monitoring'] == true;
    return CloudPage(
      children: [
        if (_error != null) CloudError(_error!),
        if (role.isAdmin)
          CloudSection(
            title: 'Бот сервера',
            icon: Icons.smart_toy_outlined,
            subtitle: configured
                ? 'Подключён $botName. Этот бот доставляет личные уведомления всем пользователям сервера.'
                : 'Создайте бота в @BotFather и укажите токен один раз. Пользователи будут вводить только свой Telegram ID.',
            children: [
              TextField(
                controller: _botToken,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: cloudInput(
                  configured ? 'Новый токен для замены бота' : 'Токен бота',
                ),
              ),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                        await _service.request(
                          '/cloud/server-bot',
                          body: {'telegramBotToken': _botToken.text.trim()},
                        );
                        _botToken.clear();
                      }, success: 'Бот сервера подключён'),
                child: Text(configured ? 'Заменить бота' : 'Подключить бота', style: appFont(context)),
              ),
            ],
          ),
        CloudSection(
          title: 'Уведомления в личный Telegram',
          icon: Icons.telegram,
          subtitle: !configured
              ? (role.isAdmin
                    ? 'Сначала подключите бота сервера.'
                    : 'Администратор ещё не подключил бота. Вы сможете включить уведомления, когда он завершит настройку.')
              : !monitoring
              ? 'Сначала включите мониторинг аккаунта в настройках облака.'
              : 'Откройте $botName, нажмите «Старт» и введите ID, который покажет бот. Он будет присылать новые ДЗ, оценки и сообщения только вам.',
          children: [
            if (configured && username.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.https('t.me', '/$username'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label:  Text('Открыть бота', style: appFont(context)),
              ),
            if (monitoring) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title:  Text('Личные уведомления', style: appFont(context)),
                value: _telegramEnabled,
                onChanged: _busy || (!configured && !_telegramEnabled)
                    ? null
                    : (value) => setState(() => _telegramEnabled = value),
              ),
              if (_telegramEnabled)
                TextField(
                  controller: _telegramId,
                  keyboardType: TextInputType.number,
                  decoration: cloudInput('Ваш Telegram ID', hint: '123456789'),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _action(() async {
                            await _service.request(
                              '/cloud/telegram',
                              body: {
                                'telegramEnabled': _telegramEnabled,
                                'telegramUserId': _telegramId.text.trim(),
                              },
                            );
                          }, success: 'Настройки Telegram сохранены'),
                    child:  Text('Сохранить', style: appFont(context)),
                  ),
                  if (_telegramEnabled && configured)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _action(
                              () async {
                                await _service.request(
                                  '/cloud/telegram/test',
                                  body: {
                                    'telegramUserId': _telegramId.text.trim(),
                                  },
                                );
                              },
                              success: 'Тестовое сообщение отправлено',
                              reload: false,
                            ),
                      child:  Text('Проверить доставку', style: appFont(context)),
                    ),
                ],
              ),
            ],
          ],
        ),
        if (role.isAdmin)
          CloudSection(
            title: 'Группа класса',
            icon: Icons.forum_outlined,
            subtitle: 'Привяжите группу, распределите предметы по темам и настройте пересылку сообщений.',
            children: [
              OutlinedButton(
                onPressed: monitoring && configured && _telegramEnabled
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TelegramGroupScreen(),
                        ),
                      )
                    : null,
                child:  Text('Настроить группу', style: appFont(context)),
              ),
              if (!monitoring || !_telegramEnabled)
                 Text(
                  'Для управления группой включите мониторинг и сохраните свой Telegram ID.', style: appFont(context),
                ),
            ],
          ),
      ],
    );
  }

  Widget _access(SettingsProvider settings) => CloudPage(
    children: [
      if (_error != null) CloudError(_error!),
      if (settings.cloudRole == CloudRole.admin)
        CloudSection(
          title: 'Токен администратора',
          icon: Icons.key_rounded,
          subtitle: 'API ключ для подключения с полным доступом к серверу.',
          children: [
            if (settings.cloudApiToken.isEmpty)
              Text('Токен не сохранён на этом устройстве', style: appFont(context))
            else ...[
              InputDecorator(
                decoration: cloudInput('API ключ'),
                child: _adminTokenVisible
                    ? SelectableText(settings.cloudApiToken, style: appFont(context))
                    : Text('••••••••••••••••', style: appFont(context)),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _adminTokenVisible = !_adminTokenVisible,
                    ),
                    icon: Icon(
                      _adminTokenVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    label: Text(
                      _adminTokenVisible ? 'Скрыть токен' : 'Показать токен',
                      style: appFont(context),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _copyAdminToken,
                    icon: const Icon(Icons.copy_rounded),
                    label: Text('Скопировать токен', style: appFont(context)),
                  ),
                ],
              ),
            ],
          ],
        ),
      CloudSection(
        title: 'Пригласить пользователя',
        icon: Icons.person_add_alt_1_rounded,
        subtitle: 'Приглашение одноразовое и действует 1 час. Получатель сам выберет, передавать ли данные eSchool для мониторинга.',
        children: [
          TextField(
            controller: _gradeClass,
            decoration: cloudInput('Класс', hint: '9А'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _createInvite,
            icon: const Icon(Icons.add_link_rounded),
            label:  Text('Создать приглашение', style: appFont(context)),
          ),
        ],
      ),
      if (_inviteLink != null)
        CloudSection(
          title: 'Готово к подключению',
          icon: Icons.qr_code_rounded,
          subtitle: 'Покажите QR пользователю или скопируйте ссылку.',
          children: [
            CloudQrCard(
              child: QrImageView(
                data: _inviteLink!,
                backgroundColor: Colors.white,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _inviteLink!));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Приглашение скопировано',
                        style: appFont(context),
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label:  Text('Скопировать приглашение', style: appFont(context)),
            ),
          ],
        ),
      CloudSection(
        title: 'Другое устройство администратора',
        icon: Icons.devices_rounded,
        subtitle: 'Ссылка даёт полный доступ к серверу. Используйте её только для своих устройств.',
        children: [
          OutlinedButton.icon(
            onPressed: _showAdminQr,
            icon: const Icon(Icons.qr_code_rounded),
            label:  Text('Показать QR администратора', style: appFont(context)),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _showBrowserCode,
            icon: const Icon(Icons.language_rounded),
            label:  Text('Подключить браузер', style: appFont(context)),
          ),
        ],
      ),
    ],
  );

  Future<void> _copyAdminToken() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.cloudEnabled ||
        settings.cloudRole != CloudRole.admin ||
        settings.cloudApiToken.isEmpty) {
      return;
    }
    var message = 'Токен администратора скопирован';
    try {
      await Clipboard.setData(ClipboardData(text: settings.cloudApiToken));
    } on PlatformException {
      message = 'Не удалось скопировать токен. Покажите его и скопируйте вручную.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: appFont(context))),
    );
  }

  Future<void> _showBrowserCode() async {
    try {
      final result = await AdvancedCloudService().request(
        '/browser-connection',
        get: true,
      );
      final code = result['connectionCode'] as String;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => CloudTheme(
          child: AlertDialog(
            title:  Text('Подключение браузера', style: appFont(ctx)),
            content:  Text(
              'Скопируйте код и вставьте его в поле сервера в веб-версии. API ключ или приглашение вводится отдельно.', style: appFont(ctx),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text('Закрыть', style: appFont(ctx)),
              ),
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child:  Text('Скопировать код', style: appFont(ctx)),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error', style: appFont(context))));
      }
    }
  }

  Future<void> _showAdminQr() async {
    final settings = context.read<SettingsProvider>();
    final pin = TlsPinStore.instance.pinForUrl(settings.cloudServerUrlOrEmpty);
    final link = Uri(
      scheme: 'reschool',
      host: 'link-device',
      queryParameters: {
        'server': settings.cloudServerUrlOrEmpty,
        'token': settings.cloudApiToken,
        if (pin != null) 'pin': pin,
      },
    ).toString();
    await showDialog<void>(
      context: context,
      builder: (ctx) => CloudTheme(
        child: AlertDialog(
          title:  Text('Вход администратора', style: appFont(ctx)),
          scrollable: true,
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Text(
                  'Отсканируйте на своём устройстве. QR содержит API ключ сервера.', style: appFont(ctx),
                ),
                const SizedBox(height: 16),
                CloudQrCard(
                  child: QrImageView(data: link, backgroundColor: Colors.white),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: link)),
              child:  Text('Скопировать ссылку', style: appFont(ctx)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text('Готово', style: appFont(ctx)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disconnectCard() => CloudSettingsGroup(
    footer: 'Отключение на устройстве доступно, даже если сервер выключен. После этого можно выбрать другой режим входа.',
    children: [
      CloudSettingsTile(
        icon: Icons.link_off_rounded,
        title: 'Отключиться от сервера',
        destructive: true,
        onTap: _busy ? null : _disconnect,
      ),
    ],
  );
}
