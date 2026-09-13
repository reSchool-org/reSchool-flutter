import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/cloud_functions_service.dart';
import '../utils/app_font.dart';
import '../widgets/app_card.dart';
import '../widgets/cloud_ui.dart';

class TelegramGroupScreen extends StatefulWidget {
  const TelegramGroupScreen({super.key});

  @override
  State<TelegramGroupScreen> createState() => _TelegramGroupScreenState();
}

class _TelegramGroupScreenState extends State<TelegramGroupScreen> {
  final CloudFunctionsService _cf3 = CloudFunctionsService();
  final ApiService _api = ApiService();

  Color get _accentColor => Theme.of(context).colorScheme.primary;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  // что сервер знает про группу
  bool _groupEnabled = false;
  String _groupChatId = '';
  String _groupTitle = '';
  Map<String, int> _topicMap = {}; // топик по идентификатору предмета
  Map<String, String> _subjects = {}; // название по идентификатору предмета

  // пересылка чатов
  Map<int, int?> _chatForwardMap =
      {}; // threadId → topicId, пусто значит без топика
  List<ChatThread> _threads = []; // все треды eSchool, что у нас есть
  bool _threadsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final info = await _cf3.getGroupInfo();
    final chatForward = await _cf3.getChatForwardSettings();

    if (!mounted) return;

    if (info == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить настройки';
      });
      return;
    }

    setState(() {
      _isLoading = false;
      _groupEnabled = info.groupEnabled;
      _groupChatId = info.groupChatId;
      _groupTitle = info.groupTitle;
      _topicMap = Map<String, int>.from(info.topicMap);
      _subjects = Map<String, String>.from(info.subjects);
      _chatForwardMap = chatForward ?? {};
    });

    // треды подтягиваем фоном, они нужны только ради названий
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    if (_threadsLoaded) return;
    try {
      final raw = await _api.getThreads();
      if (!mounted) return;
      setState(() {
        _threads = raw.map((j) => ChatThread.fromJson(j)).toList();
        _threadsLoaded = true;
      });
    } catch (_) {}
  }

  String _threadTitle(int threadId) {
    final t = _threads.where((t) => t.threadId == threadId).firstOrNull;
    return t?.title ?? 'Чат $threadId';
  }

  Future<void> _saveTopicMap() async {
    setState(() => _isSaving = true);
    final result = await _cf3.updateTelegramGroup(
      groupEnabled: _groupEnabled,
      groupChatId: _groupChatId.isNotEmpty ? _groupChatId : null,
      groupTitle: _groupTitle.isNotEmpty ? _groupTitle : null,
      topicMap: _topicMap,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!result.success) _showSnackBar('Ошибка: ${result.error}');
  }

  Future<void> _saveChatForward() async {
    setState(() => _isSaving = true);
    final result = await _cf3.updateChatForwardSettings(_chatForwardMap);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!result.success) _showSnackBar('Ошибка: ${result.error}');
  }

  Future<void> _sendTopicLabels() async {
    setState(() => _isSaving = true);
    final result = await _cf3.sendTopicLabels();
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (result.success) {
      _showSnackBar('Предметы отправлены в топики');
    } else {
      _showSnackBar('Ошибка: ${result.error}');
    }
  }

  Future<void> _toggleGroupEnabled(bool v) async {
    setState(() {
      _groupEnabled = v;
      _isSaving = true;
    });
    final result = await _cf3.updateTelegramGroup(
      groupEnabled: v,
      groupChatId: _groupChatId.isNotEmpty ? _groupChatId : null,
      groupTitle: _groupTitle.isNotEmpty ? _groupTitle : null,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!result.success) {
      setState(() => _groupEnabled = !v);
      _showSnackBar('Ошибка: ${result.error}');
    }
  }

  Future<void> _disconnectGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Отключить группу?',
          style: appFont(ctx, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Бот перестанет отправлять сообщения в группу.',
          style: appFont(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: appFont(ctx)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('Отключить', style: appFont(ctx)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    final result = await _cf3.updateTelegramGroup(
      groupEnabled: false,
      groupChatId: null,
      groupTitle: null,
      topicMap: {},
    );
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _isSaving = false;
        _groupEnabled = false;
        _groupChatId = '';
        _groupTitle = '';
        _topicMap = {};
      });
      _showSnackBar('Группа отключена');
    } else {
      setState(() => _isSaving = false);
      _showSnackBar('Ошибка: ${result.error}');
    }
  }

  Future<void> _addTopicMapping() async {
    String topicIdStr = '';
    String? selectedSubjectId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Тема для предмета',
            style: appFont(ctx, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: ValueKey('topic_field_$topicIdStr'),
                initialValue: topicIdStr,
                keyboardType: TextInputType.number,
                style: appFont(ctx, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'ID темы',
                  hintText: 'Например: 42',
                  labelStyle: appFont(ctx,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _accentColor, width: 2),
                  ),
                ),
                onChanged: (v) => topicIdStr = v.trim(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final detected = await showDialog<int?>(
                      context: ctx,
                      barrierDismissible: false,
                      builder: (_) => const _TopicDetectDialog(),
                    );
                    if (detected != null) {
                      setDialogState(() => topicIdStr = detected.toString());
                    }
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: Text(
                    'Определить автоматически',
                    style: appFont(ctx, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentColor,
                    side: BorderSide(color: _accentColor),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_subjects.isEmpty)
                Text(
                  'Предметы не загружены. Дождитесь первой проверки уведомлений.',
                  style: appFont(ctx,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                )
              else ...[
                Text(
                  'Предмет:',
                  style: appFont(ctx,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: appCardDecoration(context, radius: 10),
                  child: DropdownButtonHideUnderline(
                    child: ButtonTheme(
                      alignedDropdown: true,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedSubjectId,
                        hint: Text(
                          'Выберите предмет',
                          style: appFont(ctx,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                        items: _subjects.entries
                            .where((e) => !_topicMap.containsKey(e.key))
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: appFont(ctx, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedSubjectId = v),
                        borderRadius: BorderRadius.circular(10),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: appFont(ctx)),
            ),
            FilledButton(
              onPressed: () {
                final tid = int.tryParse(topicIdStr);
                if (tid == null || selectedSubjectId == null) return;
                Navigator.pop(ctx);
                setState(() => _topicMap[selectedSubjectId!] = tid);
                _saveTopicMap();
              },
              style: FilledButton.styleFrom(backgroundColor: _accentColor),
              child: Text('Добавить', style: appFont(ctx)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeSubjectForEntry(String subjectId, int topicId) async {
    if (_subjects.isEmpty) {
      _showSnackBar('Предметы не загружены');
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (fontContext, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Топик ID: $topicId',
                    style: appFont(fontContext, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  Text(
                    'Выберите предмет для этого топика',
                    style: appFont(fontContext,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _subjects.length,
                itemBuilder: (fontContext, i) {
                  final entry = _subjects.entries.elementAt(i);
                  final isSelected = subjectId == entry.key;
                  return ListTile(
                    title: Text(
                      entry.value,
                      style: appFont(fontContext,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      'ID: ${entry.key}',
                      style: appFont(fontContext,
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: _accentColor)
                        : null,
                    selected: isSelected,
                    selectedColor: _accentColor,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _topicMap.remove(subjectId);
                        _topicMap[entry.key] = topicId;
                      });
                      _saveTopicMap();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// диалог добавления пересылки чата
  Future<void> _addChatForward() async {
    // без загруженных тредов показывать нечего
    if (!_threadsLoaded) {
      setState(() => _isLoading = true);
      await _loadThreads();
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    if (_threads.isEmpty) {
      _showSnackBar('Не удалось загрузить список чатов');
      return;
    }

    // уже добавленные треды из списка убираем
    final available = _threads
        .where((t) => !_chatForwardMap.containsKey(t.threadId))
        .toList();
    if (available.isEmpty) {
      _showSnackBar('Все чаты уже добавлены');
      return;
    }

    ChatThread? selected;
    String topicIdStr = '';
    String searchQuery = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (fontContext, scrollController) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выберите чат',
                      style: appFont(fontContext, fontWeight: FontWeight.w600, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Сообщения из выбранного чата будут пересылаться в Telegram',
                      style: appFont(fontContext,
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  style: appFont(fontContext, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Поиск по чатам...',
                    hintStyle: appFont(fontContext,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: appFieldFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (v) =>
                      setSheet(() => searchQuery = v.toLowerCase()),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (fontContext) {
                    final filtered = available
                        .where(
                          (t) => t.title.toLowerCase().contains(searchQuery),
                        )
                        .toList();
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          'Нет результатов',
                          style: appFont(fontContext,
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (fontContext, i) {
                        final thread = filtered[i];
                        final isSelected =
                            selected?.threadId == thread.threadId;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _accentColor
                                  : Theme.of(ctx).colorScheme.onSurface
                                        .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              thread.isGroup
                                  ? Icons.groups_outlined
                                  : Icons.chat_bubble_outline,
                              size: 20,
                              color: isSelected
                                  ? Colors.white
                                  : Theme.of(ctx).colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                            ),
                          ),
                          title: Text(
                            thread.title,
                            style: appFont(fontContext,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            thread.isGroup ? 'Группа' : 'Личный чат',
                            style: appFont(fontContext,
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: _accentColor,
                                  size: 22,
                                )
                              : null,
                          selected: isSelected,
                          onTap: () => setSheet(() => selected = thread),
                        );
                      },
                    );
                  },
                ),
              ),
              if (selected != null) ...[
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(ctx).viewInsets.bottom + 16,
                  ),
                  child: StatefulBuilder(
                    builder: (ctx2, setTopicState) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.topic_outlined,
                              color: _accentColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Тема в группе (необязательно)',
                              style: appFont(ctx2, 
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          keyboardType: TextInputType.number,
                          style: appFont(ctx2, fontSize: 14),
                          controller: TextEditingController(text: topicIdStr),
                          decoration: InputDecoration(
                            hintText:
                                'ID топика (оставьте пустым - без топика)',
                            hintStyle: appFont(ctx2, 
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                            ),
                            filled: true,
                            fillColor: appFieldFill(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _accentColor,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (v) =>
                              setTopicState(() => topicIdStr = v.trim()),
                        ),
                        const SizedBox(height: 8),
                        // кнопка автоопределения
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final detected = await showDialog<int?>(
                                context: ctx,
                                barrierDismissible: false,
                                builder: (_) => const _TopicDetectDialog(),
                              );
                              if (detected != null) {
                                setTopicState(
                                  () => topicIdStr = detected.toString(),
                                );
                              }
                            },
                            icon: const Icon(Icons.auto_fix_high, size: 16),
                            label: Text(
                              'Определить автоматически',
                              style: appFont(ctx2, 
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accentColor,
                              side: BorderSide(color: _accentColor, width: 1),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              final topicId = topicIdStr.isEmpty
                                  ? null
                                  : int.tryParse(topicIdStr);
                              Navigator.pop(ctx);
                              setState(
                                () => _chatForwardMap[selected!.threadId] =
                                    topicId,
                              );
                              _saveChatForward();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: _accentColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Добавить',
                              style: appFont(ctx2, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// поменять топик у уже настроенной пересылки
  Future<void> _editChatForwardTopic(int threadId, int? currentTopicId) async {
    String topicIdStr = currentTopicId?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Тема для пересылки',
            style: appFont(ctx, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _threadTitle(threadId),
                style: appFont(ctx, fontWeight: FontWeight.w500, fontSize: 15),
              ),
              const SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                style: appFont(ctx, fontSize: 15),
                controller: TextEditingController(text: topicIdStr),
                decoration: InputDecoration(
                  labelText: 'ID темы',
                  hintText: 'Оставьте пустым - без топика',
                  labelStyle: appFont(ctx,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _accentColor, width: 2),
                  ),
                ),
                onChanged: (v) => setDlg(() => topicIdStr = v.trim()),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final detected = await showDialog<int?>(
                      context: ctx,
                      barrierDismissible: false,
                      builder: (_) => const _TopicDetectDialog(),
                    );
                    if (detected != null) {
                      setDlg(() => topicIdStr = detected.toString());
                    }
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: Text(
                    'Определить автоматически',
                    style: appFont(ctx, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accentColor,
                    side: BorderSide(color: _accentColor),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: appFont(ctx)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _accentColor),
              child: Text('Сохранить', style: appFont(ctx)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final topicId = topicIdStr.isEmpty ? null : int.tryParse(topicIdStr);
    setState(() => _chatForwardMap[threadId] = topicId);
    _saveChatForward();
  }

  Future<void> _showActivationCode() async {
    // лоадер показываем прямо в диалоге
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (fontContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          height: 100,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: _accentColor,
                  strokeWidth: 2.5,
                ),
                const SizedBox(height: 14),
                Text(
                  'Генерация кода...',
                  style: appFont(fontContext,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final result = await _cf3.generateGroupCode();
    if (!mounted) return;
    Navigator.of(context).pop(); // закрываем лоадер

    if (!result.success) {
      _showSnackBar('Ошибка: ${result.error}');
      return;
    }

    final command = result.command!;
    final expires = result.expiresInMinutes!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // иконка
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.key_outlined, color: _accentColor, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'Код активации',
              style: appFont(ctx, fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              'Отправьте команду в вашу Telegram-группу',
              style: appFont(ctx,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // блок с командой
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _accentColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      command,
                      style: appFont(ctx,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: command));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Команда скопирована',
                            style: appFont(ctx),
                          ),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_outlined,
                        size: 18,
                        color: _accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // предупреждение про срок годности
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  'Действует $expires минут',
                  style: appFont(ctx,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: _accentColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Готово',
                style: appFont(ctx, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: appFont(context)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Группа Telegram',
          style: appFont(context,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAll,
              tooltip: 'Обновить',
            ),
        ],
      ),
      body: CloudTheme(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? _buildErrorState(colorScheme)
            : CloudPage(
                children: [
                  _buildConnectionCard(colorScheme),
                  if (_groupChatId.isNotEmpty) _buildTopicsCard(colorScheme),
                  _buildChatForwardCard(colorScheme),
                ],
              ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 48, color: colorScheme.error),
        const SizedBox(height: 12),
        Text(_loadError!, style: appFont(context, color: colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loadAll,
          icon: const Icon(Icons.refresh),
          label: Text('Повторить', style: appFont(context)),
        ),
      ],
    ),
  );

  Future<void> _showConnectionHelp() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Переподключить группу',
          style: appFont(ctx, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Добавьте бота в нужную Telegram-группу, получите команду '
          'и отправьте её в эту группу.',
          style: appFont(ctx, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: appFont(ctx)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Получить команду', style: appFont(ctx)),
          ),
        ],
      ),
    );
    if (proceed == true && mounted) await _showActivationCode();
  }

  Widget _buildConnectionCard(ColorScheme cs) {
    final connected = _groupChatId.isNotEmpty;
    final statusColor = _groupEnabled
        ? appSuccessColor(context)
        : cs.onSurfaceVariant;
    return AppInteractiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.telegram_rounded,
                    color: cs.primary,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected
                            ? (_groupTitle.isNotEmpty
                                  ? _groupTitle
                                  : 'Ваша группа')
                            : 'Подключите группу',
                        style: appFont(context,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (connected) ...[
                        Text(
                          _groupEnabled
                              ? '● Подключена'
                              : '● Отправка на паузе',
                          style: appFont(context, fontSize: 12, color: statusColor),
                        ),
                        const SizedBox(height: 5),
                        SelectableText(
                          'ID: $_groupChatId',
                          style: appFont(context,
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ] else
                        Text(
                          'Уведомления ReSchool в Telegram',
                          style: appFont(context,
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
                if (connected)
                  PopupMenuButton<String>(
                    tooltip: 'Управление группой',
                    enabled: !_isSaving,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                    onSelected: (value) {
                      if (value == 'reconnect') _showConnectionHelp();
                      if (value == 'disconnect') _disconnectGroup();
                    },
                    itemBuilder: (fontContext) => [
                      PopupMenuItem(
                        value: 'reconnect',
                        child: Text('Переподключить группу', style: appFont(fontContext)),
                      ),
                      PopupMenuItem(
                        value: 'disconnect',
                        child: Text(
                          'Отключить группу',
                          style: appFont(fontContext, color: cs.error),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (connected) ...[
            Divider(height: 1, color: appCardBorderColor(context)),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              title: Text(
                'Отправлять в группу',
                style: appFont(context, fontWeight: FontWeight.w500, fontSize: 14),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Домашние задания и оценки',
                  style: appFont(context,
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              value: _groupEnabled,
              onChanged: _isSaving ? null : _toggleGroupEnabled,
            ),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Добавьте бота в Telegram-группу, затем получите '
                    'команду и отправьте её в группу.',
                    style: appFont(context,
                      fontSize: 13,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _showActivationCode,
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label:  Text('Подключить группу', style: appFont(context)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: appFont(context, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: appFont(context,
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(String label, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    child: FilledButton.tonalIcon(
      onPressed: _isSaving ? null : onPressed,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(label, style: appFont(context)),
    ),
  );

  Widget _buildTopicsCard(ColorScheme cs) => CloudSection(
    title: 'Темы по предметам',
    icon: Icons.topic_outlined,
    subtitle: 'Распределяйте домашние задания и оценки по темам группы.',
    children: [
      if (_topicMap.isEmpty)
        _buildEmptyState(
          Icons.forum_outlined,
          'Всё приходит в общий чат',
          'Добавьте тему для нужного предмета.',
        )
      else
        Column(
          children: [
            for (final e in _topicMap.entries)
              _buildTopicRow(cs, e.key, e.value),
          ],
        ),
      _buildAddButton('Добавить тему', _addTopicMapping),
      if (_topicMap.isNotEmpty)
        TextButton.icon(
          onPressed: _isSaving ? null : _sendTopicLabels,
          icon: const Icon(Icons.label_outline_rounded, size: 18),
          label: Text(
            'Отправить названия предметов',
            style: appFont(context, fontSize: 13),
          ),
        ),
    ],
  );

  Widget _buildMappingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String editLabel,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 22, color: cs.onSurfaceVariant),
      title: Text(
        title,
        style: appFont(context, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: appFont(context, fontSize: 12, color: cs.onSurfaceVariant),
      ),
      onTap: _isSaving ? null : onEdit,
      trailing: PopupMenuButton<String>(
        tooltip: 'Действия: $title',
        enabled: !_isSaving,
        icon: Icon(Icons.more_horiz_rounded, color: cs.onSurfaceVariant),
        onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (fontContext) => [
          PopupMenuItem(
            value: 'edit',
            child: Text(editLabel, style: appFont(fontContext)),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('Удалить', style: appFont(fontContext, color: cs.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicRow(ColorScheme cs, String subjectId, int topicId) =>
      _buildMappingRow(
        icon: Icons.menu_book_outlined,
        title: _subjects[subjectId] ?? 'Предмет ID $subjectId',
        subtitle: 'Тема $topicId',
        editLabel: 'Изменить предмет',
        onEdit: () => _changeSubjectForEntry(subjectId, topicId),
        onDelete: () {
          setState(() => _topicMap.remove(subjectId));
          _saveTopicMap();
        },
      );

  Widget _buildChatForwardCard(ColorScheme cs) => CloudSection(
    title: 'Пересылка чатов',
    icon: Icons.forward_to_inbox_outlined,
    subtitle: 'Сообщения из выбранных чатов eSchool в Telegram.',
    children: [
      if (_chatForwardMap.isEmpty)
        _buildEmptyState(
          Icons.chat_bubble_outline_rounded,
          'Чаты ещё не добавлены',
          'Пересылайте сообщения в тему или общий чат.',
        )
      else
        Column(
          children: [
            for (final e in _chatForwardMap.entries)
              _buildChatForwardRow(cs, e.key, e.value),
          ],
        ),
      _buildAddButton('Добавить чат', _addChatForward),
    ],
  );

  Widget _buildChatForwardRow(ColorScheme cs, int threadId, int? topicId) {
    final thread = _threads.where((t) => t.threadId == threadId).firstOrNull;
    return _buildMappingRow(
      icon: thread?.isGroup == true
          ? Icons.groups_outlined
          : Icons.chat_bubble_outline_rounded,
      title: thread?.title ?? 'Чат $threadId',
      subtitle: topicId != null ? 'Тема $topicId' : 'Общий чат группы',
      editLabel: 'Изменить тему',
      onEdit: () => _editChatForwardTopic(threadId, topicId),
      onDelete: () {
        setState(() => _chatForwardMap.remove(threadId));
        _saveChatForward();
      },
    );
  }
}

/// почти полноэкранный диалог, ведёт пользователя через автоопределение топика
/// отдаёт найденный topic id, при отмене или таймауте пусто
class _TopicDetectDialog extends StatefulWidget {
  const _TopicDetectDialog();

  @override
  State<_TopicDetectDialog> createState() => _TopicDetectDialogState();
}

class _TopicDetectDialogState extends State<_TopicDetectDialog>
    with SingleTickerProviderStateMixin {
  final CloudFunctionsService _cf3 = CloudFunctionsService();

  Color get _accentColor => Theme.of(context).colorScheme.primary;
  static const _totalSeconds = 60;

  bool _isStarting = true;
  bool _detected = false;
  bool _error = false;
  String? _errorMsg;
  int? _detectedTopicId;
  int _secondsLeft = _totalSeconds;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _start();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final result = await _cf3.requestTopicDetect();
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _isStarting = false;
        _error = true;
        _errorMsg = result.error;
      });
      return;
    }
    setState(() => _isStarting = false);
    _poll();
  }

  Future<void> _poll() async {
    for (int i = _totalSeconds; i > 0; i--) {
      if (!mounted) return;
      setState(() => _secondsLeft = i);

      final topicId = await _cf3.pollDetectedTopic();
      if (!mounted) return;

      if (topicId != null) {
        setState(() {
          _detected = true;
          _detectedTopicId = topicId;
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) Navigator.of(context).pop(topicId);
        return;
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    if (mounted) {
      setState(() {
        _error = true;
        _errorMsg = 'Время ожидания истекло. Попробуйте ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: _buildContent(colorScheme),
      actions: [
        if (!_detected)
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(
                'Отмена',
                style: appFont(context,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    if (_isStarting) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: _accentColor, strokeWidth: 2.5),
              const SizedBox(height: 16),
              Text(
                'Подключение...',
                style: appFont(context,
                  fontSize: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error) {
      return SizedBox(
        height: 160,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                color: colorScheme.error,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMsg ?? 'Что-то пошло не так',
              style: appFont(context, fontSize: 13, color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_detected) {
      return SizedBox(
        height: 160,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: appSuccessColor(context).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                color: appSuccessColor(context),
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Топик определён!',
              style: appFont(context, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'ID: $_detectedTopicId',
              style: appFont(context, fontSize: 14, color: _accentColor),
            ),
          ],
        ),
      );
    }

    // ждём
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // анимированная иконка
        ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.topic_outlined, color: _accentColor, size: 32),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Определение топика',
          style: appFont(context, fontWeight: FontWeight.w700, fontSize: 17),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                'Откройте Telegram и отправьте сообщение',
                style: appFont(context,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.72),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'п',
                  style: appFont(context,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'в нужный топик вашей Telegram-группы',
                style: appFont(context,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.72),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // индикатор прогресса
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _secondsLeft > 15 ? _accentColor : colorScheme.error,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Ожидание: $_secondsLeft с',
              style: appFont(context,
                fontSize: 12,
                color: _secondsLeft > 15
                    ? colorScheme.onSurface.withValues(alpha: 0.5)
                    : colorScheme.error.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
