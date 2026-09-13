import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/advanced_cloud_service.dart';
import '../utils/app_font.dart';
import '../widgets/cloud_ui.dart';

enum ServerConfigurationSection { general, account, ai }

/// отправляем только изменённые поля, маски секретов сохранять нельзя
class ServerConfigurationScreen extends StatefulWidget {
  final AdvancedCloudService? service;
  final ServerConfigurationSection section;
  const ServerConfigurationScreen({
    super.key,
    this.service,
    this.section = ServerConfigurationSection.general,
  });

  @override
  State<ServerConfigurationScreen> createState() =>
      _ServerConfigurationScreenState();
}

class _ServerConfigurationScreenState extends State<ServerConfigurationScreen> {
  late final _service = widget.service ?? AdvancedCloudService();
  final _search = TextEditingController();
  final _changes = <String, String>{};
  final _expanded = <String>{};
  List<Map<String, dynamic>> _fields = [];
  String _revision = '';
  String? _error;
  String? _notice;
  String? _operationId;
  bool _loading = true;
  bool _saving = false;
  bool _canLeave = false;
  int _pollGeneration = 0;

  static const _groups = {
    'eschool': ('Проверка обновлений', Icons.sync_rounded),
    'ai': ('Нейросеть и учебники', Icons.auto_awesome_outlined),
    'network': ('Адреса и соединение', Icons.language_rounded),
    'browser': ('Подключение браузера', Icons.web_rounded),
    'cache': ('Кеш и Redis', Icons.bolt_outlined),
    'database': ('База данных', Icons.storage_rounded),
    'security': ('Доступ и шифрование', Icons.shield_outlined),
    'other': ('Дополнительные параметры', Icons.tune_rounded),
  };

  String get _title => switch (widget.section) {
    ServerConfigurationSection.general => 'Настройки сервера',
    ServerConfigurationSection.account => 'Аккаунт сервера',
    ServerConfigurationSection.ai => 'Нейросеть',
  };

  bool _belongsToSection(Map<String, dynamic> field) {
    final account = [
      'ESCHOOL_USERNAME',
      'ESCHOOL_PASSWORD',
    ].contains(field['key']);
    return switch (widget.section) {
      ServerConfigurationSection.general => !account && field['group'] != 'ai',
      ServerConfigurationSection.account => account,
      ServerConfigurationSection.ai => field['group'] == 'ai',
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollGeneration++;
    _search.dispose();
    super.dispose();
  }

  bool _active(Map<String, dynamic>? operation) =>
      ['queued', 'applying', 'rolling_back'].contains(operation?['status']);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.request('/server-settings', get: true);
      if (!mounted) return;
      final operation = result['operation'] as Map<String, dynamic>?;
      setState(() {
        _fields = (result['fields'] as List)
            .cast<Map<String, dynamic>>()
            .where(_belongsToSection)
            .toList();
        _revision = result['revision'] as String;
        _loading = false;
        if (_active(operation)) {
          _operationId = operation!['id'] as String;
          _saving = true;
          _notice = operation['message'] as String?;
        } else if (operation != null) {
          if (operation['status'] == 'applied') {
            _notice = operation['message'] as String?;
          } else {
            _error = operation['message'] as String?;
          }
        }
      });
      if (_active(operation)) unawaited(_poll());
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  String _display(Map<String, dynamic> field, {bool changed = false}) {
    final key = field['key'] as String;
    final value = changed ? _changes[key]! : field['value'] as String;
    if (field['secret'] == true) {
      if (changed) return value.isEmpty ? 'Будет удалён' : 'Будет заменён';
      return field['configured'] == true ? 'Сохранён на сервере' : 'Не задан';
    }
    if (field['kind'] == 'boolean') {
      return ['true', '1', 'yes', 'on'].contains(value.toLowerCase())
          ? 'Включено'
          : 'Выключено';
    }
    for (final option in (field['options'] as List? ?? const [])) {
      if (option['value'] == value) return option['label'] as String;
    }
    return value.isEmpty ? 'Не задано' : value;
  }

  bool _aiConnectionField(Map<String, dynamic> field) {
    final key = field['key'] as String;
    return key == 'AI_PROVIDER' ||
        key.startsWith('GEMINI_') ||
        key.startsWith('OPENROUTER_');
  }

  bool _visibleAiConnectionField(Map<String, dynamic> field) {
    final providerFields = _fields.where((f) => f['key'] == 'AI_PROVIDER');
    final provider =
        _changes['AI_PROVIDER'] ??
        (providerFields.isEmpty ? 'google' : providerFields.first['value']);
    final key = field['key'] as String;
    return key == 'AI_PROVIDER' ||
        key.startsWith(provider == 'openrouter' ? 'OPENROUTER_' : 'GEMINI_');
  }

  Future<void> _edit(Map<String, dynamic> field) async {
    final key = field['key'] as String;
    final locked = field['locked'] as String;
    if (locked.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.lock_outline_rounded),
          title: Text(field['label'] as String, style: appFont(context)),
          content: Text(locked, style: appFont(context)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text('Понятно', style: appFont(context)),
            ),
          ],
        ),
      );
      return;
    }
    final secret = field['secret'] == true;
    final controller = TextEditingController(
      text: _changes[key] ?? field['value'] as String,
    );
    final form = GlobalKey<FormState>();
    var visible = false;
    var boolean = [
      'true',
      '1',
      'yes',
      'on',
    ].contains(controller.text.toLowerCase());
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => CloudTheme(
          child: AlertDialog(
            title: Text(field['label'] as String, style: appFont(context)),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if ((field['hint'] as String).isNotEmpty) ...[
                        Text(
                          field['hint'] as String,
                          style: appFont(context, textStyle: Theme.of(context).textTheme.bodyMedium),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (field['kind'] == 'boolean')
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(boolean ? 'Включено' : 'Выключено', style: appFont(context)),
                          value: boolean,
                          onChanged: (value) => update(() => boolean = value),
                        )
                      else if (field['kind'] == 'select')
                        DropdownButtonFormField<String>(
                          initialValue:
                              (field['options'] as List).any(
                                (option) => option['value'] == controller.text,
                              )
                              ? controller.text
                              : null,
                          isExpanded: true,
                          decoration: cloudInput('Провайдер'),
                          items: [
                            for (final option in field['options'] as List)
                              DropdownMenuItem(
                                value: option['value'] as String,
                                child: Text(option['label'] as String, style: appFont(context)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) controller.text = value;
                          },
                          validator: (value) => value == null
                              ? 'Выберите значение из списка'
                              : null,
                        )
                      else
                        TextFormField(
                          controller: controller,
                          autofocus: true,
                          obscureText: secret && !visible,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: field['kind'] == 'integer'
                              ? TextInputType.number
                              : TextInputType.text,
                          decoration: cloudInput(
                            secret ? 'Новое значение' : 'Значение',
                            helper: secret
                                ? 'Пустое поле сохраняет прежний секрет'
                                : null,
                            suffix: secret
                                ? IconButton(
                                    tooltip: visible ? 'Скрыть' : 'Показать',
                                    icon: Icon(
                                      visible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () =>
                                        update(() => visible = !visible),
                                  )
                                : null,
                          ),
                          validator: (value) {
                            if (field['kind'] == 'integer') {
                              final number = int.tryParse(value ?? '');
                              if (number == null ||
                                  number < (field['minimum'] as num) ||
                                  number > (field['maximum'] as num)) {
                                return 'От ${field['minimum']} до ${field['maximum']}';
                              }
                            }
                            return null;
                          },
                        ),
                      const SizedBox(height: 14),
                      Text(
                        key,
                        style: appFont(context,
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (secret && field['configured'] == true)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label:  Text('Удалить сохранённое значение', style: appFont(context)),
                            onPressed: () => Navigator.pop(context, ''),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child:  Text('Отмена', style: appFont(context)),
              ),
              FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  if (secret && controller.text.isEmpty) {
                    Navigator.pop(context);
                    return;
                  }
                  Navigator.pop(
                    context,
                    field['kind'] == 'boolean' ? '$boolean' : controller.text,
                  );
                },
                child:  Text('Готово', style: appFont(context)),
              ),
            ],
          ),
        ),
      ),
    );
    // после закрытия диалога анимация ещё один кадр может использовать контроллер
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || result == null) return;
    setState(() {
      if (!secret && result == field['value']) {
        _changes.remove(key);
      } else {
        _changes[key] = result;
      }
      _error = null;
      _notice = null;
      _operationId = null;
    });
  }

  Future<void> _save() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:  Text('Применить настройки?', style: appFont(context)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                 Text(
                  'Сервер ненадолго перезапустится. Перед этим будет создана резервная копия. Если проверка запуска не пройдёт, прежние значения восстановятся.', style: appFont(context),
                ),
                const SizedBox(height: 20),
                for (final field in _fields.where(
                  (f) => _changes.containsKey(f['key']),
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          field['label'] as String,
                          style: appFont(context, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_display(field)} → ${_display(field, changed: true)}',
                          style: appFont(context, fontSize: 12),
                          softWrap: true,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:  Text('Отмена', style: appFont(context)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child:  Text('Применить', style: appFont(context)),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final random = Random.secure();
    _operationId ??= List.generate(
      36,
      (i) => [8, 13, 18, 23].contains(i)
          ? '-'
          : random.nextInt(16).toRadixString(16),
    ).join();
    setState(() {
      _saving = true;
      _error = null;
      _notice = 'Сохраняем настройки…';
    });
    try {
      final result = await _service.request(
        '/server-settings',
        body: {
          'revision': _revision,
          'operationId': _operationId,
          'changes': Map.of(_changes),
        },
      );
      if (!mounted) return;
      setState(
        () => _notice = (result['operation'] as Map?)?['message'] as String?,
      );
    } on CloudException catch (e) {
      if (!mounted) return;
      if (e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500) {
        setState(() {
          _saving = false;
          _error = e.message;
          _notice = null;
          _operationId = null;
        });
        _showResult(e.message);
        return;
      }
      // обрыв ответа не означает, что сервер отклонил операцию
    } catch (_) {
      if (!mounted) return;
    }
    await _poll();
  }

  Future<void> _poll() async {
    final generation = ++_pollGeneration;
    final deadline = DateTime.now().add(const Duration(minutes: 7));
    for (
      var attempt = 0;
      attempt < 100 &&
          mounted &&
          generation == _pollGeneration &&
          DateTime.now().isBefore(deadline);
      attempt++
    ) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!mounted || generation != _pollGeneration) return;
      try {
        final result = await _service.request(
          '/server-settings/operation',
          get: true,
        );
        if (!mounted || generation != _pollGeneration) return;
        final operation = result['operation'] as Map<String, dynamic>?;
        if (operation?['id'] != _operationId) continue;
        setState(() => _notice = operation?['message'] as String?);
        if (!_active(operation)) {
          final success = operation?['status'] == 'applied';
          setState(() {
            _saving = false;
            if (success) _changes.clear();
            _error = success ? null : _notice;
            if (!success) _notice = null;
            _operationId = null;
          });
          _showResult(operation?['message'] as String? ?? 'Операция завершена');
          if (success) await _load();
          return;
        }
      } catch (_) {
        // при пересоздании контейнера сервер ненадолго пропадает
      }
    }
    if (mounted && generation == _pollGeneration) {
      setState(() {
        _saving = false;
        _notice = null;
        _error = 'Пока не удалось подтвердить результат. Обновите состояние сервера; ваши изменения сохранены на этом экране.';
      });
    }
  }

  void _showResult(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message, style: appFont(context))));
  }

  Future<void> _leave() async {
    if (_saving) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title:  Text('Настройки ещё применяются', style: appFont(context)),
          content:  Text(
            'Сервер продолжит применение. Результат можно проверить, вернувшись на этот экран.', style: appFont(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:  Text('Остаться', style: appFont(context)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:  Text('Выйти', style: appFont(context)),
            ),
          ],
        ),
      );
      if (leave != true) return;
    } else if (_changes.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title:  Text('Выйти без сохранения?', style: appFont(context)),
          content:  Text(
            'Изменения на этом экране будут отменены. Настройки сервера останутся прежними.', style: appFont(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:  Text('Остаться', style: appFont(context)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:  Text('Выйти', style: appFont(context)),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (!mounted) return;
    setState(() => _canLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final filtered = _fields
        .where(
          (f) => '${f['label']} ${f['key']} ${f['hint']}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return PopScope(
      canPop: _canLeave || (_changes.isEmpty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: CloudTheme(
        child: Scaffold(
          appBar: AppBar(
            title: Text(_title, style: appFont(context)),
            actions: [
              IconButton(
                tooltip: 'Обновить состояние',
                onPressed: _loading || _saving
                    ? null
                    : () async {
                        if (_changes.isNotEmpty) {
                          final discard = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title:  Text('Обновить настройки?', style: appFont(context)),
                              content:  Text(
                                'Несохранённые изменения будут отменены.', style: appFont(context),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child:  Text('Отмена', style: appFont(context)),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child:  Text('Обновить', style: appFont(context)),
                                ),
                              ],
                            ),
                          );
                          if (discard != true || !mounted) return;
                          setState(_changes.clear);
                        }
                        await _load();
                      },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: _loading && _fields.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : CloudPage(
                  children: [
                    if (widget.section == ServerConfigurationSection.account)
                      const CloudSection(
                        title: 'Аккаунт eSchool',
                        icon: Icons.person_outline_rounded,
                        subtitle: 'С этим аккаунтом сервер подключается к eSchool и проверяет пользователей.',
                      ),
                    if (widget.section == ServerConfigurationSection.ai &&
                        _fields.any((f) => f['key'] == 'ANALYSIS_ENABLED'))
                      _analysisSwitch(context),
                    if (_error != null) CloudError(_error!),
                    if (_notice != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_notice!, style: appFont(context, fontSize: 13)),
                            if (_saving) ...[
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                            ],
                          ],
                        ),
                      ),
                    if (_fields.isNotEmpty &&
                        widget.section == ServerConfigurationSection.general)
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: cloudInput(
                          'Поиск настроек',
                          hint: 'Название или параметр .env',
                          suffix: const Icon(Icons.search_rounded),
                        ),
                      ),
                    if (filtered.isEmpty && _fields.isNotEmpty)
                       Center(child: Text('Ничего не найдено', style: appFont(context))),
                    if (widget.section == ServerConfigurationSection.account &&
                        _fields.isNotEmpty)
                      CloudSettingsGroup(
                        children: [
                          for (final field in _fields)
                            _tile(
                              context,
                              field,
                              field['secret'] == true
                                  ? Icons.key_rounded
                                  : Icons.person_outline_rounded,
                            ),
                        ],
                      ),
                    if (widget.section == ServerConfigurationSection.ai &&
                        _fields.isNotEmpty) ...[
                      CloudSettingsGroup(
                        title: 'Подключение к ИИ',
                        children: [
                          for (final field
                              in _fields
                                  .where(_aiConnectionField)
                                  .where(_visibleAiConnectionField))
                            _tile(context, field, Icons.auto_awesome_outlined),
                        ],
                      ),
                      CloudSettingsGroup(
                        title: 'Разбор заданий и учебники',
                        children: [
                          for (final field in _fields.where(
                            (f) =>
                                !_aiConnectionField(f) &&
                                f['key'] != 'ANALYSIS_ENABLED',
                          ))
                            _tile(context, field, Icons.auto_stories_outlined),
                        ],
                      ),
                    ],
                    if (widget.section == ServerConfigurationSection.general)
                      for (final group in _groups.entries)
                        if (filtered.any((f) => f['group'] == group.key))
                          CloudSettingsGroup(
                            children: [
                              CloudSettingsTile(
                                icon: group.value.$2,
                                title: group.value.$1,
                                subtitle:
                                    '${filtered.where((f) => f['group'] == group.key).length} параметров${_fields.any((f) => f['group'] == group.key && _changes.containsKey(f['key'])) ? ' · есть изменения' : ''}',
                                onTap: () => setState(() {
                                  if (!_expanded.remove(group.key)) {
                                    _expanded.add(group.key);
                                  }
                                }),
                              ),
                              if (query.isNotEmpty ||
                                  _expanded.contains(group.key))
                                for (final field in filtered.where(
                                  (f) => f['group'] == group.key,
                                ))
                                  _tile(context, field, group.value.$2),
                            ],
                          ),
                  ],
                ),
          bottomNavigationBar: _changes.isEmpty && !_saving
              ? null
              : SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(
                        top: BorderSide(
                          color: cs.outline.withValues(alpha: .12),
                        ),
                      ),
                    ),
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(
                              _saving
                                  ? 'Применяем…'
                                  : 'Изменено: ${_changes.length}',
                              style: appFont(context, fontSize: 13),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() {
                                      _changes.clear();
                                      _operationId = null;
                                    }),
                              child:  Text('Отменить', style: appFont(context)),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saving ? null : _save,
                              child:  Text('Сохранить', style: appFont(context)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _analysisSwitch(BuildContext context) {
    final field = _fields.firstWhere((f) => f['key'] == 'ANALYSIS_ENABLED');
    final original = [
      'true',
      '1',
      'yes',
      'on',
    ].contains((field['value'] as String).toLowerCase());
    final enabled = _changes.containsKey('ANALYSIS_ENABLED')
        ? _changes['ANALYSIS_ENABLED'] == 'true'
        : original;
    return CloudSection(
      title: 'Разбор домашних заданий',
      icon: Icons.auto_awesome_outlined,
      subtitle: 'Оценка сложности и времени выполнения, работа с учебниками.',
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title:  Text('Использовать ИИ', style: appFont(context)),
          subtitle: Text(enabled ? 'Включено' : 'Выключено', style: appFont(context)),
          value: enabled,
          onChanged: _saving || (field['locked'] as String).isNotEmpty
              ? null
              : (value) => setState(() {
                  if (value == original) {
                    _changes.remove('ANALYSIS_ENABLED');
                  } else {
                    _changes['ANALYSIS_ENABLED'] = '$value';
                  }
                  _operationId = null;
                  _error = null;
                  _notice = null;
                }),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    Map<String, dynamic> field,
    IconData icon,
  ) {
    final changed = _changes.containsKey(field['key']);
    final locked = (field['locked'] as String).isNotEmpty;
    final source = switch (field['source']) {
      'env' => '.env',
      'deployment' => 'Установка',
      _ => 'По умолчанию',
    };
    return Row(
      children: [
        Expanded(
          child: CloudSettingsTile(
            icon: changed
                ? Icons.edit_outlined
                : locked
                ? Icons.lock_outline_rounded
                : icon,
            title: field['label'] as String,
            subtitle:
                '${_display(field, changed: changed)}\n${changed ? 'Есть изменения' : source}',
            onTap: _saving ? null : () => _edit(field),
          ),
        ),
        if (changed)
          IconButton(
            tooltip: 'Отменить изменение',
            icon: const Icon(Icons.undo_rounded, size: 20),
            onPressed: _saving
                ? null
                : () => setState(() {
                    _changes.remove(field['key']);
                    _operationId = null;
                  }),
          ),
      ],
    );
  }
}
