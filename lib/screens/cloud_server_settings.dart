import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/cloud_functions_service.dart';
import '../services/tls_pin_store.dart';
import '../widgets/cloud_ui.dart';
import 'server_configuration_screen.dart';
import '../utils/app_font.dart';

class CloudServerSettings extends StatefulWidget {
  const CloudServerSettings({super.key});
  @override
  State<CloudServerSettings> createState() => _CloudServerSettingsState();
}

class _CloudServerSettingsState extends State<CloudServerSettings> {
  final _service = CloudFunctionsService();
  final _domain = TextEditingController();
  final _ip = TextEditingController();
  List<String> _blocked = [];
  bool _busy = false;
  String? _error;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _domain.dispose();
    _ip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.getServerDomainStatus(),
      _service.getIpBlacklist(),
    ]);
    if (!mounted) return;
    final domain = results[0] as CloudFunctionsDomainStatus?;
    final blacklist = results[1] as CloudFunctionsIpBlacklistResult;
    setState(() {
      _domain.text = domain?.domain ?? '';
      _blocked = blacklist.entries;
      if (!blacklist.success) _error = blacklist.error;
    });
  }

  Future<void> _saveDomain() async {
    if (_domain.text.trim().isEmpty) {
      setState(() => _error = 'Введите домен');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _service.updateServerDomain(
      _domain.text.trim(),
      onProgress: (job) {
        if (mounted) setState(() => _progress = job.message);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.success ? null : result.error;
      _progress = result.success ? 'Домен подключён, HTTPS настроен' : null;
    });
    if (result.success) {
      await context.read<SettingsProvider>().reloadCloudSettings();
    }
  }

  Future<void> _saveBlocked(List<String> values) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _service.updateIpBlacklist(entries: values);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) {
        _blocked = result.entries;
        _ip.clear();
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = context.watch<SettingsProvider>().cloudServerUrlOrEmpty;
    final pin = TlsPinStore.instance.pinForUrl(url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CloudSettingsGroup(
          children: [
            CloudSettingsTile(
              icon: Icons.person_outline_rounded,
              title: 'Аккаунт сервера',
              subtitle: 'Логин и пароль eSchool',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ServerConfigurationScreen(
                    section: ServerConfigurationSection.account,
                  ),
                ),
              ),
            ),
            CloudSettingsTile(
              icon: Icons.auto_awesome_outlined,
              title: 'Нейросеть',
              subtitle: 'Включение ИИ, модель и разбор заданий',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ServerConfigurationScreen(
                    section: ServerConfigurationSection.ai,
                  ),
                ),
              ),
            ),
            CloudSettingsTile(
              icon: Icons.tune_rounded,
              title: 'Настройки сервера',
              subtitle: 'Подключение, проверка обновлений, кеш и безопасность',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ServerConfigurationScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        CloudSection(
          title: 'Адрес и защищённое соединение',
          icon: Icons.https_outlined,
          subtitle: url,
          children: [
            Text(
              pin == null
                  ? 'Сертификат проверяется системой'
                  : 'Сертификат закреплён на этом устройстве', style: appFont(context),
            ),
            if (pin != null)
              SelectableText(pin, style: appFont(context, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        CloudSection(
          title: 'Свой домен',
          icon: Icons.language_rounded,
          subtitle: 'Можно продолжать пользоваться сервером по IP. Если у вас есть домен, направьте его A запись на сервер и откройте порты 80 и 443.',
          children: [
            TextField(
              controller: _domain,
              enabled: !_busy,
              autocorrect: false,
              decoration: cloudInput('Домен', hint: 'school.example.com'),
            ),
            FilledButton.tonal(
              onPressed: _busy ? null : _saveDomain,
              child:  Text('Подключить домен', style: appFont(context)),
            ),
            if (_progress != null) Text(_progress!, style: appFont(context)),
          ],
        ),
        const SizedBox(height: 16),
        CloudSection(
          title: 'Чёрный список IP',
          icon: Icons.block_rounded,
          subtitle: 'Сервер отклоняет запросы с указанных адресов. Поддерживаются IPv4, IPv6 и подсети CIDR.',
          children: [
            TextField(
              controller: _ip,
              enabled: !_busy,
              decoration: cloudInput(
                'IP адрес или подсеть',
                hint: '192.0.2.0/24',
              ),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      final value = _ip.text.trim();
                      if (value.isNotEmpty && !_blocked.contains(value)) {
                        _saveBlocked([..._blocked, value]);
                      }
                    },
              child:  Text('Добавить адрес', style: appFont(context)),
            ),
            if (_blocked.isEmpty)  Text('Список пуст', style: appFont(context)),
            if (_blocked.isNotEmpty)
              Column(
                children: [
                  for (final entry in _blocked)
                    Row(
                      children: [
                        Expanded(child: Text(entry, style: appFont(context))),
                        IconButton(
                          tooltip: 'Удалить адрес',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: _busy
                              ? null
                              : () => _saveBlocked(
                                  _blocked
                                      .where((value) => value != entry)
                                      .toList(),
                                ),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: CloudError(_error!),
          ),
      ],
    );
  }
}
