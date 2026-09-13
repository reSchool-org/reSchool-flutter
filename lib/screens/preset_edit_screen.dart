import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/bell_schedule_provider.dart';
import '../utils/app_font.dart';

/// открыть экран создания или правки пресета
/// вернёт true, если пресет сохранили
Future<bool> showPresetEditScreen(
  BuildContext context,
  BellScheduleProvider provider, {
  BellSchedulePreset? preset,
}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => PresetEditScreen(provider: provider, preset: preset),
      fullscreenDialog: true,
    ),
  );
  return result == true;
}

class PresetEditScreen extends StatefulWidget {
  final BellScheduleProvider provider;
  final BellSchedulePreset? preset; // пусто значит создаём новый

  const PresetEditScreen({super.key, required this.provider, this.preset});

  @override
  State<PresetEditScreen> createState() => _PresetEditScreenState();
}

class _PresetEditScreenState extends State<PresetEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _subtitleController;

  // уроки храним как [номер, контроллер начала, контроллер конца]
  late List<_LessonEntry> _lessons;

  bool get _isEditing => widget.preset != null;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _nameController = TextEditingController(text: p?.name ?? '');
    _subtitleController = TextEditingController(text: p?.subtitle ?? '');

    if (p != null) {
      final sorted = p.lessons.keys.toList()..sort();
      _lessons = sorted
          .map((lessonNum) => _LessonEntry(
                lessonNum,
                TextEditingController(text: p.lessons[lessonNum]!.start),
                TextEditingController(text: p.lessons[lessonNum]!.end),
              ))
          .toList();
    } else {
      // заготовка на 7 уроков
      _lessons = List.generate(
        7,
        (i) {
          final h = 9 + i;
          return _LessonEntry(
            i + 1,
            TextEditingController(text: '${h.toString().padLeft(2, '0')}:00'),
            TextEditingController(text: '${h.toString().padLeft(2, '0')}:45'),
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subtitleController.dispose();
    for (final e in _lessons) {
      e.startCtrl.dispose();
      e.endCtrl.dispose();
    }
    super.dispose();
  }

  void _addLesson() {
    HapticFeedback.selectionClick();
    setState(() {
      // номер для следующего урока
      final nextNum = _lessons.isEmpty
          ? 1
          : (_lessons.map((e) => e.lessonNum).reduce((a, b) => a > b ? a : b) + 1);
      _lessons.add(_LessonEntry(
        nextNum,
        TextEditingController(text: ''),
        TextEditingController(text: ''),
      ));
    });
  }

  void _removeLesson(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _lessons[index].startCtrl.dispose();
      _lessons[index].endCtrl.dispose();
      _lessons.removeAt(index);
    });
  }

  void _editLessonNumber(int index) {
    final ctrl = TextEditingController(text: _lessons[index].lessonNum.toString());
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Номер урока', style: appFont(ctx, fontWeight: FontWeight.w600)),
        content: _StyledTextField(
          controller: ctrl,
          label: 'Номер',
          colorScheme: cs,
          keyboardType: TextInputType.number,
          icon: Icons.tag_rounded,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена',
                style: appFont(ctx, color: cs.onSurface.withValues(alpha: 0.6))),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text);
              if (n != null) setState(() => _lessons[index].lessonNum = n);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('OK', style: appFont(ctx, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите название пресета', style: appFont(context)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final lessons = <int, LessonTime>{};
    for (final entry in _lessons) {
      final start = entry.startCtrl.text.trim();
      final end = entry.endCtrl.text.trim();
      if (start.isNotEmpty && end.isNotEmpty) {
        lessons[entry.lessonNum] = LessonTime(start: start, end: end);
      }
    }

    if (lessons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Добавьте хотя бы один урок', style: appFont(context)),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    final subtitle = _subtitleController.text.trim().isEmpty
        ? null
        : _subtitleController.text.trim();

    if (_isEditing) {
      await widget.provider.updateUserPreset(
        id: widget.preset!.id,
        name: name,
        subtitle: subtitle,
        lessons: lessons,
      );
    } else {
      await widget.provider.createUserPreset(
        name: name,
        subtitle: subtitle,
        lessons: lessons,
      );
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // красивый SliverAppBar
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: cs.onSurface),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text('Сохранить', style: appFont(context, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            cs.primary.withValues(alpha: 0.18),
                            cs.surface,
                          ]
                        : [
                            cs.primary.withValues(alpha: 0.12),
                            cs.surface,
                          ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEditing ? 'Редактировать пресет' : 'Новый пресет',
                      style: appFont(context,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cs.primary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isEditing ? widget.preset!.name : 'Создание расписания звонков',
                      style: appFont(context,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // имя и адрес
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('Название', cs),
                  const SizedBox(height: 8),
                  _StyledTextField(
                    controller: _nameController,
                    label: 'Например: Корпус А',
                    colorScheme: cs,
                    icon: Icons.badge_outlined,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('Адрес / подпись', cs),
                  const SizedBox(height: 8),
                  _StyledTextField(
                    controller: _subtitleController,
                    label: 'Необязательно',
                    colorScheme: cs,
                    icon: Icons.location_on_outlined,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 28),
                  // заголовок блока с уроками
                  Row(
                    children: [
                      _SectionLabel('Уроки', cs),
                      const Spacer(),
                      Text(
                        '${_lessons.length} урок(а)',
                        style: appFont(context,
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // список уроков
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final entry = _lessons[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _LessonEditCard(
                    entry: entry,
                    index: i,
                    colorScheme: cs,
                    isDark: isDark,
                    onDelete: () => _removeLesson(i),
                    onEditNum: () => _editLessonNumber(i),
                    onChanged: () => setState(() {}),
                  ),
                );
              },
              childCount: _lessons.length,
            ),
          ),

          // кнопка добавления урока
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              child: GestureDetector(
                onTap: _addLesson,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.3),
                      width: 1.5,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                    color: cs.primary.withValues(alpha: 0.05),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline_rounded, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Добавить урок',
                        style: appFont(context,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// вспомогательные классы и виджеты

class _LessonEntry {
  int lessonNum;
  final TextEditingController startCtrl;
  final TextEditingController endCtrl;

  _LessonEntry(this.lessonNum, this.startCtrl, this.endCtrl);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _SectionLabel(this.text, this.cs);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: appFont(context,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: cs.onSurface.withValues(alpha: 0.4),
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ColorScheme colorScheme;
  final IconData icon;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  const _StyledTextField({
    required this.controller,
    required this.label,
    required this.colorScheme,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.06)
            : colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        style: appFont(context, fontSize: 15, color: colorScheme.onSurface),
        cursorColor: colorScheme.primary,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: appFont(context, color: colorScheme.onSurface.withValues(alpha: 0.45)),
          floatingLabelStyle: appFont(context, color: colorScheme.primary, fontSize: 13),
          border: InputBorder.none,
          prefixIcon: Icon(icon, size: 20, color: colorScheme.onSurface.withValues(alpha: 0.4)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

class _LessonEditCard extends StatelessWidget {
  final _LessonEntry entry;
  final int index;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onEditNum;
  final VoidCallback onChanged;

  const _LessonEditCard({
    required this.entry,
    required this.index,
    required this.colorScheme,
    required this.isDark,
    required this.onDelete,
    required this.onEditNum,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // номер урока, он же кнопка
          GestureDetector(
            onTap: onEditNum,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${entry.lessonNum}',
                  style: appFont(context,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // поля времени
          Expanded(
            child: Column(
              children: [
                _TimeInput(
                  controller: entry.startCtrl,
                  label: 'Начало',
                  colorScheme: colorScheme,
                  isDark: isDark,
                  icon: Icons.play_arrow_rounded,
                ),
                const SizedBox(height: 8),
                _TimeInput(
                  controller: entry.endCtrl,
                  label: 'Конец',
                  colorScheme: colorScheme,
                  isDark: isDark,
                  icon: Icons.stop_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // кнопка удаления
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ColorScheme colorScheme;
  final bool isDark;
  final IconData icon;

  const _TimeInput({
    required this.controller,
    required this.label,
    required this.colorScheme,
    required this.isDark,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.07)
            : colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.09)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.next,
        style: appFont(context, fontSize: 14, color: colorScheme.onSurface),
        cursorColor: colorScheme.primary,
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              appFont(context, fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.45)),
          floatingLabelStyle: appFont(context, fontSize: 10, color: colorScheme.primary),
          border: InputBorder.none,
          prefixIcon: Icon(icon, size: 15, color: colorScheme.onSurface.withValues(alpha: 0.35)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}
