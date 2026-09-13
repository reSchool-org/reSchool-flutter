import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/cloud_connection.dart';
import '../providers/settings_provider.dart';
import '../providers/custom_homework_provider.dart';
import '../services/advanced_cloud_service.dart';
import '../services/browser_server.dart';
import '../services/cloud_ssh_setup_service.dart';
import '../services/tls_pin_store.dart';
import '../utils/app_font.dart';
import '../widgets/cloud_ui.dart';
import '../widgets/server_trust_dialog.dart';
import 'qr_scanner_screen.dart';

class CloudConnectionScreen extends StatefulWidget {
  final CloudRole role;
  final CloudConnectionLink? initialLink;
  const CloudConnectionScreen({
    super.key,
    required this.role,
    this.initialLink,
  });
  @override
  State<CloudConnectionScreen> createState() => _CloudConnectionScreenState();
}

class _CloudConnectionScreenState extends State<CloudConnectionScreen> {
  final _service = AdvancedCloudService();
  final _ssh = CloudSshSetupService();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _link = TextEditingController();
  final _telegramId = TextEditingController();
  final _host = TextEditingController();
  final _sshPort = TextEditingController(text: '22');
  final _sshLogin = TextEditingController(text: 'root');
  final _sshPassword = TextEditingController();
  late CloudRole _role;
  String _method = 'qr';
  String? _pin;
  String? _error;
  String _progress = '';
  bool _busy = false;
  bool _hidden = true;
  bool _linkReady = false;
  bool _configureTelegram = false;
  CloudSshResult? _installed;
  bool get _canScan =>
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _role = widget.role;
    final link = widget.initialLink;
    if (link != null) {
      _url.text = link.serverUrl;
      _token.text = _role.isAdmin ? link.apiToken : link.inviteToken;
      _pin = link.pin;
      _method = _role.isAdmin ? 'manual' : 'link';
      _linkReady = true;
      _link.text = Uri(
        scheme: 'reschool',
        host: 'link-device',
        queryParameters: {
          'server': link.serverUrl,
          if (link.apiToken.isNotEmpty) 'token': link.apiToken,
          if (link.inviteToken.isNotEmpty) 'inviteToken': link.inviteToken,
          if (link.pin != null) 'pin': link.pin!,
          if (link.role != null) 'mode': link.role!.name,
        },
      ).toString();
    }
  }

  @override
  void dispose() {
    _ssh.cancel();
    for (final controller in [
      _url,
      _token,
      _link,
      _telegramId,
      _host,
      _sshPort,
      _sshLogin,
      _sshPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _readLink(String value) async {
    try {
      final link = CloudConnectionLink.parse(value);
      if (_role.isAdmin != link.apiToken.isNotEmpty) {
        throw CloudException(
          _role.isAdmin ? 'Для входа администратором нужен QR с API ключом' : 'Попросите администратора создать приглашение пользователя в разделе «Доступ и приглашения»',
        );
      }
      setState(() {
        _url.text = link.serverUrl;
        _token.text = _role.isAdmin ? link.apiToken : link.inviteToken;
        _pin = link.pin;
        _error = null;
        _link.text = value.trim();
        _linkReady = true;
        if (_role.isAdmin) _method = 'manual';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _linkReady = false;
          _error = e is FormatException ? e.message : '$e';
        });
      }
    }
  }

  Future<void> _scan() async {
    final value = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (value != null && mounted) await _readLink(value);
  }

  Future<bool> _verifySshHost(String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'cloud_ssh_host:${_host.text.trim()}:${_sshPort.text.trim()}';
    final known = prefs.getString(key);
    if (known == fingerprint) return true;
    if (!mounted) return false;
    final trusted = await showDialog<bool>(
      context: context,
      builder: (ctx) => CloudTheme(
        child: AlertDialog(
          title: Text(
            known == null
                ? 'Первое подключение по SSH'
                : 'Ключ SSH сервера изменился', style: appFont(ctx),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Сверьте отпечаток ключа ${_host.text.trim()} перед передачей пароля.', style: appFont(ctx),
              ),
              const SizedBox(height: 16),
              SelectableText(fingerprint, style: appFont(ctx)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text('Отмена', style: appFont(ctx)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text('Доверять серверу', style: appFont(ctx)),
            ),
          ],
        ),
      ),
    );
    if (trusted == true) await prefs.setString(key, fingerprint);
    return trusted == true;
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (!_role.isAdmin && _method != 'manual' && !_linkReady) return;
    final settings = context.read<SettingsProvider>();
    if (settings.cloudEnabled) {
      setState(
        () => _error =
            'Сначала отключите текущее подключение во вкладке облачных функций',
      );
      return;
    }
    if (_method != 'ssh') {
      try {
        _url.text = await saveBrowserServerCode(_url.text);
      } on FormatException catch (error) {
        if (mounted) setState(() => _error = error.message);
        return;
      }
      if (!mounted) return;
      final url = AppConfig.normalizeServerUrl(_url.text);
      if (!AppConfig.isValidServerUrl(url) || _token.text.trim().isEmpty) {
        setState(
          () => _error =
              'Введите адрес сервера и ${_role.isAdmin ? 'API ключ' : 'код приглашения'}',
        );
        return;
      }
      if (_role == CloudRole.user &&
          _configureTelegram &&
          _telegramId.text.trim().isNotEmpty &&
          !RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(_telegramId.text.trim())) {
        setState(() => _error = 'Telegram ID должен быть положительным числом');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Проверяю подключение';
    });
    try {
      if (_method == 'ssh') {
        if (_installed == null) {
          if (_host.text.trim().isEmpty ||
              _sshLogin.text.trim().isEmpty ||
              _sshPassword.text.isEmpty) {
            throw const CloudException(
              'Заполните IP адрес, логин и пароль SSH',
            );
          }
          _installed = await _ssh.install(
            host: _host.text.trim(),
            port: int.tryParse(_sshPort.text) ?? 0,
            username: _sshLogin.text.trim(),
            password: _sshPassword.text,
            verifyHost: _verifySshHost,
            onProgress: (message) {
              if (mounted) setState(() => _progress = message);
            },
          );
          _sshPassword.clear();
        }
        _url.text = _installed!.serverUrl;
        _token.text = _installed!.apiToken;
        _pin = _installed!.pin;
      }
      final serverUrl = AppConfig.normalizeServerUrl(_url.text);
      if ((_pin ?? '').isNotEmpty) {
        await TlsPinStore.instance.load();
        await TlsPinStore.instance.savePin(serverUrl, _pin!);
      }
      if (!mounted) return;
      if (!await ensureServerTrusted(context, serverUrl)) {
        throw const CloudException(
          'Подключение отменено, сертификат не подтверждён',
        );
      }
      if (mounted) {
        setState(
          () => _progress = _role.isAdmin
              ? 'Проверяю ключ администратора'
              : _role == CloudRole.user
              ? 'Подключаю аккаунт и включаю мониторинг'
              : 'Подключаю общие задания',
        );
      }
      if (_role.isAdmin) {
        await _service.connectAdmin(serverUrl, _token.text.trim());
      } else {
        await _service.join(
          serverUrl: serverUrl,
          inviteToken: _token.text,
          role: _role,
          telegramUserId: _configureTelegram ? _telegramId.text.trim() : null,
        );
      }
      await settings.reloadCloudSettings();
      if (mounted) {
        context.read<CustomHomeworkProvider>().clearCache();
        setState(() => _busy = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is CloudException ? e.message : 'Не удалось подключиться. Проверьте адрес, доступность сервера и данные входа',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: CloudTheme(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _role.isAdmin
                  ? 'Вход администратора'
                  : 'Подключение пользователя',
              style: appFont(context, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
          ),
          body: CloudPage(
            children: [
              if (_role.isAdmin) ...[
                Text(
                  'Как подключить сервер?',
                  style: appFont(context, fontSize: 24, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Выберите удобный способ. После входа вы сможете настроить облачные функции.',
                  style: appFont(context,
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                SegmentedButton<String>(
                  segments:  [
                    ButtonSegment(
                      value: 'qr',
                      icon: Icon(Icons.qr_code_rounded),
                      label: Text('QR', style: appFont(context)),
                    ),
                    ButtonSegment(
                      value: 'ssh',
                      icon: Icon(Icons.terminal_rounded),
                      label: Text('SSH', style: appFont(context)),
                    ),
                    ButtonSegment(
                      value: 'manual',
                      icon: Icon(Icons.edit_rounded),
                      label: Text('Вручную', style: appFont(context)),
                    ),
                  ],
                  selected: {_method},
                  onSelectionChanged: _busy
                      ? null
                      : (values) => setState(() {
                          _method = values.first;
                          _error = null;
                        }),
                ),
              ] else ...[
                CloudSection(
                  title: _role.label,
                  icon: _role.canMonitor
                      ? Icons.notifications_active_outlined
                      : Icons.lock_outline_rounded,
                  subtitle: _role.canMonitor
                      ? 'Сервер получит логин и пароль текущего аккаунта eSchool, будет проверять новые ДЗ, оценки и сообщения и присылать их вам в Telegram.'
                      : 'Логин и пароль eSchool остаются на устройстве. Вы сможете читать и добавлять общие домашние задания своего класса.',
                ),
                if (widget.initialLink != null &&
                    widget.initialLink!.role == null)
                  SwitchListTile.adaptive(
                    title:  Text('Передать данные для мониторинга', style: appFont(context)),
                    value: _role == CloudRole.user,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _role = value
                                ? CloudRole.user
                                : CloudRole.classmate;
                          }),
                  ),
                SegmentedButton<String>(
                  segments:  [
                    ButtonSegment(value: 'qr', label: Text('QR', style: appFont(context))),
                    ButtonSegment(value: 'link', label: Text('Ссылка', style: appFont(context))),
                    ButtonSegment(value: 'manual', label: Text('Вручную', style: appFont(context))),
                  ],
                  showSelectedIcon: false,
                  selected: {_method},
                  onSelectionChanged: _busy
                      ? null
                      : (values) => setState(() {
                          _method = values.first;
                          _error = null;
                        }),
                ),
              ],
              if (_method == 'ssh' && _role.isAdmin)
                _sshForm()
              else ...[
                if (_method == 'qr')
                  CloudSection(
                    title: _role.isAdmin ? 'QR код или ссылка' : 'Вход по QR',
                    icon: Icons.qr_code_scanner_rounded,
                    subtitle: _role.isAdmin
                        ? 'Отсканируйте QR сервера или вставьте ссылку подключения.'
                        : _canScan
                        ? 'Отсканируйте QR приглашения, созданного администратором в разделе «Доступ и приглашения».'
                        : 'Сканирование QR доступно на телефоне и в веб версии. Здесь можно воспользоваться ссылкой или ручным вводом.',
                    children: [
                      if (_canScan)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label:  Text('Сканировать QR', style: appFont(context)),
                        ),
                      if (_role.isAdmin) ..._linkFields(),
                      if (!_role.isAdmin && !_canScan)
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _method = 'link'),
                          icon: const Icon(Icons.link_rounded),
                          label:  Text('Ввести ссылку', style: appFont(context)),
                        ),
                    ],
                  ),
                if (_method == 'link')
                  CloudSection(
                    title: 'Вход по ссылке',
                    icon: Icons.link_rounded,
                    subtitle: 'Вставьте ссылку приглашения от администратора сервера.',
                    children: _linkFields(),
                  ),
                if (!_role.isAdmin && _method != 'manual' && _linkReady)
                  CloudSection(
                    title: 'Приглашение готово',
                    icon: Icons.check_circle_outline_rounded,
                    subtitle:
                        'Проверьте адрес сервера и подтвердите подключение.',
                    children: [SelectableText(_url.text, style: appFont(context))],
                  ),
                if (_method == 'manual')
                  CloudSection(
                    title: 'Данные подключения',
                    icon: Icons.dns_outlined,
                    children: [
                      TextField(
                        controller: _url,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        onChanged: (_) => setState(() {
                          _pin = null;
                          _linkReady = false;
                        }),
                        decoration: cloudInput(
                          kIsWeb ? 'Адрес или код подключения' : 'URL сервера',
                          hint: 'https://192.0.2.10:4443',
                        ),
                      ),
                      TextField(
                        controller: _token,
                        enabled: !_busy,
                        onChanged: (_) => setState(() => _linkReady = false),
                        obscureText: _hidden,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: cloudInput(
                          _role.isAdmin ? 'API ключ' : 'Код приглашения',
                          suffix: IconButton(
                            tooltip: _hidden ? 'Показать ключ' : 'Скрыть ключ',
                            onPressed: () => setState(() => _hidden = !_hidden),
                            icon: Icon(
                              _hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_role == CloudRole.user &&
                    (_method == 'manual' || _linkReady))
                  CloudSection(
                    title: 'Личные уведомления',
                    icon: Icons.telegram,
                    subtitle: 'Telegram ID необязателен. Его можно добавить позже: «Облачные функции» → «Уведомления». Бота настраивает администратор.',
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Настроить Telegram сейчас',
                          style: appFont(context),
                        ),
                        value: _configureTelegram,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _configureTelegram = value),
                      ),
                      if (_configureTelegram)
                        TextField(
                          controller: _telegramId,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: cloudInput(
                            'Telegram ID (необязательно)',
                            hint: '123456789',
                          ),
                        ),
                    ],
                  ),
              ],
              if (_error != null) CloudError(_error!),
              if (_busy)
                Column(
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(_progress, textAlign: TextAlign.center, style: appFont(context)),
                    ),
                  ],
                ),
              if (_method == 'manual' ||
                  _method == 'ssh' ||
                  (!_role.isAdmin && _linkReady))
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || (kIsWeb && _method == 'ssh')
                        ? null
                        : _connect,
                    icon: Icon(
                      _method == 'ssh'
                          ? Icons.rocket_launch_outlined
                          : Icons.login_rounded,
                    ),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        _method == 'ssh'
                            ? (_installed != null
                                  ? 'Подключиться к установленному серверу'
                                  : 'Установить и подключиться')
                            : _role == CloudRole.user
                            ? 'Передать данные и подключиться'
                            : 'Подключиться',
                        style: appFont(
                          context,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _linkFields() => [
    TextField(
      controller: _link,
      enabled: !_busy,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.url,
      onChanged: (_) => setState(() {
        _linkReady = false;
        _error = null;
      }),
      decoration: cloudInput(
        'Ссылка подключения',
        hint: 'reschool://link-device?…',
        suffix: IconButton(
          tooltip: 'Вставить',
          icon: const Icon(Icons.content_paste_rounded),
          onPressed: _busy
              ? null
              : () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (mounted && data?.text != null) {
                    _link.text = data!.text!;
                    await _readLink(_link.text);
                  }
                },
        ),
      ),
      onSubmitted: _readLink,
    ),
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : () => _readLink(_link.text),
        icon: const Icon(Icons.link_rounded),
        label: Text(
          'Использовать ссылку',
          textAlign: TextAlign.center,
          style: appFont(context, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  ];

  Widget _sshForm() => CloudSection(
    title: 'Установка по SSH',
    icon: Icons.terminal_rounded,
    subtitle: kIsWeb ? 'Для SSH откройте reSchool на телефоне или компьютере.' : 'Ubuntu или Debian, вход под root или пользователем с sudo. Приложение установит Docker, базу данных и Server Advanced в /opt/reschool. Для подключения нужен открытый порт 4443.',
    children: [
      TextField(
        controller: _host,
        enabled: !_busy && _installed == null,
        autocorrect: false,
        decoration: cloudInput('IP адрес сервера', hint: '192.0.2.10'),
      ),
      TextField(
        controller: _sshPort,
        enabled: !_busy && _installed == null,
        keyboardType: TextInputType.number,
        decoration: cloudInput('Порт SSH'),
      ),
      TextField(
        controller: _sshLogin,
        enabled: !_busy && _installed == null,
        autocorrect: false,
        decoration: cloudInput('Логин SSH'),
      ),
      TextField(
        controller: _sshPassword,
        enabled: !_busy && _installed == null,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: cloudInput(
          'Пароль SSH',
          helper: 'Используется только для установки и не сохраняется',
        ),
      ),
    ],
  );
}
