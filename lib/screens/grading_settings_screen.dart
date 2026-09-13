import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/grading_provider.dart';
import '../utils/app_font.dart';

// точка входа

void showGradingSettings(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider.value(
      value: Provider.of<GradingProvider>(context, listen: false),
      child: const GradingSettingsScreen(),
    ),
    fullscreenDialog: true,
  ));
}

// главный экран

class GradingSettingsScreen extends StatelessWidget {
  const GradingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grading = context.watch<GradingProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Система оценивания',
          style: appFont(context,
              fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _openEditor(context, null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: cs.primary),
                    const SizedBox(width: 4),
                    Text('Создать',
                        style: appFont(context,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _GradingList(grading: grading),
    );
  }

  void _openEditor(BuildContext context, GradingPreset? preset) {
    final g = Provider.of<GradingProvider>(context, listen: false);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: g,
        child: GradingPresetEditScreen(preset: preset),
      ),
    ));
  }
}

// список пресетов

class _GradingList extends StatelessWidget {
  final GradingProvider grading;
  const _GradingList({required this.grading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        _buildPredictionToggle(context, cs, isDark),
        const SizedBox(height: 24),

        _SectionLabel('Встроенные', cs),
        const SizedBox(height: 10),
        ...GradingProvider.availablePresets.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PresetCard(
                preset: p,
                isSelected: grading.selectedPresetId == p.id,
                onSelect: () {
                  HapticFeedback.selectionClick();
                  grading.setPreset(p.id);
                },
              ),
            )),
        const SizedBox(height: 20),

        Row(
          children: [
            _SectionLabel('Мои пресеты', cs),
            const Spacer(),
            if (grading.userPresets.isEmpty)
              Text('ещё нет',
                  style: appFont(context,
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  )),
          ],
        ),
        const SizedBox(height: 10),
        if (grading.userPresets.isEmpty)
          _EmptyHint(
              onTap: () => _openEditor(context, null), cs: cs, isDark: isDark),
        ...grading.userPresets.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PresetCard(
                preset: p,
                isSelected: grading.selectedPresetId == p.id,
                onSelect: () {
                  HapticFeedback.selectionClick();
                  grading.setPreset(p.id);
                },
                onEdit: () => _openEditor(context, p),
                onDelete: () => _confirmDelete(context, grading, p),
              ),
            )),
      ],
    );
  }

  Widget _buildPredictionToggle(
      BuildContext context, ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? cs.onSurface.withValues(alpha: 0.05)
            : cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Показывать прогноз оценки',
                    style: appFont(context,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface)),
                Text('Прогноз четвертной по среднему баллу',
                    style: appFont(context,
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
          Switch(
            value: grading.showPredictedGrade,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              grading.setShowPredictedGrade(v);
            },
            activeTrackColor: cs.primary.withValues(alpha: 0.4),
            activeThumbColor: cs.primary,
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, GradingPreset? preset) {
    final g = Provider.of<GradingProvider>(context, listen: false);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: g,
        child: GradingPresetEditScreen(preset: preset),
      ),
    ));
  }

  Future<void> _confirmDelete(
      BuildContext context, GradingProvider g, GradingPreset p) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Удалить пресет?',
            style: appFont(ctx, fontWeight: FontWeight.w600)),
        content: Text('Пресет «${p.name}» будет удалён.',
            style: appFont(ctx,
                color: cs.onSurface.withValues(alpha: 0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена',
                style: appFont(ctx,
                    color: cs.onSurface.withValues(alpha: 0.6))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Удалить',
                style: appFont(ctx, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.lightImpact();
      g.deleteUserPreset(p.id);
    }
  }
}

// карточка пресета

class _PresetCard extends StatelessWidget {
  final GradingPreset preset;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _PresetCard({
    required this.preset,
    required this.isSelected,
    required this.onSelect,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = preset.isUserCreated;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primary.withValues(alpha: 0.07)
            : isDark
                ? cs.onSurface.withValues(alpha: 0.04)
                : cs.onSurface.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.28)
              : cs.outline.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isUser
                            ? cs.secondary.withValues(alpha: 0.12)
                            : cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isUser
                            ? Icons.person_outline_rounded
                            : Icons.school_outlined,
                        size: 18,
                        color: isUser ? cs.secondary : cs.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            style: appFont(context,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color:
                                  isSelected ? cs.primary : cs.onSurface,
                            ),
                          ),
                          if (preset.description.isNotEmpty)
                            Text(preset.description,
                                style: appFont(context,
                                  fontSize: 12,
                                  color:
                                      cs.onSurface.withValues(alpha: 0.5),
                                )),
                        ],
                      ),
                    ),
                    if (isUser) ...[
                      _iconBtn(Icons.edit_outlined, cs.secondary, onEdit!),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.delete_outline_rounded, cs.error,
                          onDelete!),
                      const SizedBox(width: 6),
                    ],
                    if (isSelected)
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                            color: cs.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white),
                      )
                    else
                      const SizedBox(width: 24),
                  ],
                ),
                const SizedBox(height: 12),
                GradeRulesBar(rules: preset.rules),
                const SizedBox(height: 8),
                GradeRulesLegend(rules: preset.rules, colorScheme: cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }
}

// визуальная полоса зон

// цвета оценок
const _kC2 = Color(0xFFEF5350);
const _kC3 = Color(0xFFFF9800);
const _kC4 = Color(0xFF42A5F5);
const _kC5 = Color(0xFF66BB6A);

/// шкала от 1.0 до 5.0: чистые зоны заливаем сплошным цветом,
/// пограничные плавным градиентом между цветами двух соседних оценок
class GradeRulesBar extends StatelessWidget {
  final GradingRules rules;
  final double height;
  final bool showLabels;

  const GradeRulesBar({
    super.key,
    required this.rules,
    this.height = 30,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    const scaleMin = 1.0;
    const scaleMax = 5.0;
    final r = rules;

    double pos(double v) =>
        ((v - scaleMin) / (scaleMax - scaleMin)).clamp(0.0, 1.0);

    // восемь точек: каждая пограничная зона это пара,
    // если ширина нулевая, получаем резкий переход, как в пресете Standard
    final stops = _monotonic([
      0.0,
      pos(r.grade3Min), // начало зоны двойки с тройкой
      pos(r.grade2Max), // конец  зоны двойки с тройкой
      pos(r.grade4Min), // начало зоны тройки с четвёркой
      pos(r.grade3Max), // конец  зоны тройки с четвёркой
      pos(r.grade5Min), // начало зоны четвёрки с пятёркой
      pos(r.grade4Max), // конец  зоны четвёрки с пятёркой
      1.0,
    ]);

    final gradient = LinearGradient(
      colors: const [_kC2, _kC2, _kC3, _kC3, _kC4, _kC4, _kC5, _kC5],
      stops: stops,
    );

    // центры чистых зон, туда встают подписи «2» «3» «4» «5»
    final mid2 = (0.0 + stops[1]) / 2;
    final mid3 = (stops[2] + stops[3]) / 2;
    final mid4 = (stops[4] + stops[5]) / 2;
    final mid5 = (stops[6] + 1.0) / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: gradient),
                ),
              ),
              if (showLabels) ...[
                _lbl(context, '2', mid2, w, height),
                _lbl(context, '3', mid3, w, height),
                _lbl(context, '4', mid4, w, height),
                _lbl(context, '5', mid5, w, height),
              ],
            ],
          );
        }),
      ),
    );
  }

  Widget _lbl(BuildContext context, String text, double frac, double totalW, double h) {
    final cx = frac * totalW;
    return Positioned(
      left: (cx - 14).clamp(0.0, totalW - 28),
      width: 28,
      top: 0,
      height: h,
      child: Center(
        child: Text(
          text,
          style: appFont(context,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            shadows: const [
              Shadow(
                color: Color(0x44000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              )
            ],
          ),
        ),
      ),
    );
  }

  static List<double> _monotonic(List<double> src) {
    final result = List<double>.of(src);
    for (int i = 1; i < result.length; i++) {
      if (result[i] < result[i - 1]) result[i] = result[i - 1];
    }
    return result;
  }
}

class GradeRulesLegend extends StatelessWidget {
  final GradingRules rules;
  final ColorScheme colorScheme;
  const GradeRulesLegend(
      {super.key, required this.rules, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final r = rules;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _chip(context, '2 если < ${_f(r.grade2Max)}', _kC2, cs),
        _chip(context, '3: ${_f(r.grade3Min)}-${_f(r.grade3Max)}', _kC3, cs),
        _chip(context, '4: ${_f(r.grade4Min)}-${_f(r.grade4Max)}', _kC4, cs),
        _chip(context, '5 если ≥ ${_f(r.grade5Min)}', _kC5, cs),
      ],
    );
  }

  String _f(double v) => v.toStringAsFixed(2);

  Widget _chip(BuildContext context, String label, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: appFont(context,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

// пустое состояние

class _EmptyHint extends StatelessWidget {
  final VoidCallback onTap;
  final ColorScheme cs;
  final bool isDark;
  const _EmptyHint(
      {required this.onTap, required this.cs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark
              ? cs.primary.withValues(alpha: 0.04)
              : cs.primary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add_rounded, size: 22, color: cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Создать своё правило',
                      style: appFont(context,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.primary)),
                  Text('Задайте пороги и пограничные зоны',
                      style: appFont(context,
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.4))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: cs.primary.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// экран редактора пресета

class GradingPresetEditScreen extends StatefulWidget {
  final GradingPreset? preset;
  const GradingPresetEditScreen({super.key, this.preset});

  @override
  State<GradingPresetEditScreen> createState() =>
      _GradingPresetEditScreenState();
}

class _GradingPresetEditScreenState extends State<GradingPresetEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  // граница двойки и тройки: [grade3Min .. grade2Max]
  late double _b23lo; // grade3Min, тут начинается тройка
  late double _b23hi; // grade2Max, дальше двойки уже нет

  // граница тройки и четвёрки: [grade4Min .. grade3Max]
  late double _b34lo; // нижняя граница четвёрки
  late double _b34hi; // верхняя граница тройки

  // граница четвёрки и пятёрки: [grade5Min .. grade4Max]
  late double _b45lo; // нижняя граница пятёрки
  late double _b45hi; // верхняя граница четвёрки

  bool _saving = false;

  bool get _isEditing => widget.preset != null;

  GradingRules get _currentRules => GradingRules(
        grade3Min: _b23lo,
        grade2Max: _b23hi,
        grade4Min: _b34lo,
        grade3Max: _b34hi,
        grade5Min: _b45lo,
        grade4Max: _b45hi,
      );

  @override
  void initState() {
    super.initState();
    final r = widget.preset?.rules;
    _nameCtrl = TextEditingController(text: widget.preset?.name ?? '');
    _descCtrl =
        TextEditingController(text: widget.preset?.description ?? '');
    _b23lo = r?.grade3Min ?? 2.50;
    _b23hi = r?.grade2Max ?? 2.70;
    _b34lo = r?.grade4Min ?? 3.50;
    _b34hi = r?.grade3Max ?? 3.66;
    _b45lo = r?.grade5Min ?? 4.40;
    _b45hi = r?.grade4Max ?? 4.66;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Введите название');
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    final g = Provider.of<GradingProvider>(context, listen: false);
    final desc = _descCtrl.text.trim();
    final rules = _currentRules;

    if (_isEditing) {
      await g.updateUserPreset(
          id: widget.preset!.id,
          name: name,
          description: desc,
          rules: rules);
    } else {
      final created =
          await g.createUserPreset(name: name, description: desc, rules: rules);
      g.setPreset(created.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String msg) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: appFont(context)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.errorContainer,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Редактировать правило' : 'Новое правило',
          style: appFont(context,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: cs.onSurface),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _saving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                    ),
                    child: Text('Сохранить',
                        style:
                            appFont(context, fontWeight: FontWeight.w600)),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // название
          _FieldLabel('Название', cs),
          const SizedBox(height: 8),
          _StyledField(
              controller: _nameCtrl,
              hint: 'Например: Моя школа',
              icon: Icons.badge_outlined,
              cs: cs,
              isDark: isDark),
          const SizedBox(height: 14),
          _FieldLabel('Описание (необязательно)', cs),
          const SizedBox(height: 8),
          _StyledField(
              controller: _descCtrl,
              hint: 'Город, номер школы...',
              icon: Icons.info_outline_rounded,
              cs: cs,
              isDark: isDark),
          const SizedBox(height: 28),

          // визуальная шкала
          _FieldLabel('Зоны оценок', cs),
          const SizedBox(height: 4),
          Text(
            'Диагональные полосы - пограничные зоны, где учитель вправе поставить любую из двух оценок',
            style: appFont(context,
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 14),
          GradeRulesBar(rules: _currentRules, height: 32),
          const SizedBox(height: 20),

          // слайдеры диапазонов
          _BorderZoneCard(
            lowerGrade: 2,
            upperGrade: 3,
            lo: _b23lo,
            hi: _b23hi,
            rangeMin: 1.0,
            rangeMax: math.min(_b34lo - 0.05, 3.49),
            colorLo: Colors.red,
            colorHi: Colors.orange,
            cs: cs,
            isDark: isDark,
            onChanged: (lo, hi) => setState(() {
              _b23lo = lo;
              _b23hi = hi;
            }),
          ),
          const SizedBox(height: 10),
          _BorderZoneCard(
            lowerGrade: 3,
            upperGrade: 4,
            lo: _b34lo,
            hi: _b34hi,
            rangeMin: math.max(_b23hi + 0.05, 2.5),
            rangeMax: math.min(_b45lo - 0.05, 4.39),
            colorLo: Colors.orange,
            colorHi: Colors.blue,
            cs: cs,
            isDark: isDark,
            onChanged: (lo, hi) => setState(() {
              _b34lo = lo;
              _b34hi = hi;
            }),
          ),
          const SizedBox(height: 10),
          _BorderZoneCard(
            lowerGrade: 4,
            upperGrade: 5,
            lo: _b45lo,
            hi: _b45hi,
            rangeMin: math.max(_b34hi + 0.05, 3.5),
            rangeMax: 5.0,
            colorLo: Colors.blue,
            colorHi: Colors.green,
            cs: cs,
            isDark: isDark,
            onChanged: (lo, hi) => setState(() {
              _b45lo = lo;
              _b45hi = hi;
            }),
          ),
          const SizedBox(height: 26),

          // предпросмотр
          _FieldLabel('Предпросмотр', cs),
          const SizedBox(height: 12),
          _PreviewTable(rules: _currentRules, cs: cs, isDark: isDark),
        ],
      ),
    );
  }
}

// карточка пограничной зоны

class _BorderZoneCard extends StatelessWidget {
  final int lowerGrade;
  final int upperGrade;
  final double lo;
  final double hi;
  final double rangeMin;
  final double rangeMax;
  final Color colorLo;
  final Color colorHi;
  final ColorScheme cs;
  final bool isDark;
  final void Function(double lo, double hi) onChanged;

  const _BorderZoneCard({
    required this.lowerGrade,
    required this.upperGrade,
    required this.lo,
    required this.hi,
    required this.rangeMin,
    required this.rangeMax,
    required this.colorLo,
    required this.colorHi,
    required this.cs,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // пограничной зоны может и не быть, тогда lo >= hi
    final hasBorder = hi > lo;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: isDark
            ? cs.onSurface.withValues(alpha: 0.04)
            : cs.onSurface.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // заголовок
          Row(
            children: [
              // иконка пограничной зоны
              _gradeChip(context, lowerGrade, colorLo),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.swap_horiz_rounded,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.4)),
              ),
              _gradeChip(context, upperGrade, colorHi),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasBorder
                      ? 'Пограничная зона: ${_f(lo)} - ${_f(hi)}'
                      : 'Пограничная зона отсутствует',
                  style: appFont(context,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // пояснение
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              hasBorder
                  ? 'При среднем ${_f(lo)}-${_f(hi)} учитель может поставить $lowerGrade или $upperGrade'
                  : 'Сдвиньте ползунки вправо, чтобы создать пограничную зону',
              style: appFont(context,
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // слайдер диапазона
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colorHi.withValues(alpha: 0.5),
              inactiveTrackColor: cs.onSurface.withValues(alpha: 0.1),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
              rangeThumbShape:
                  const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
              overlayColor: colorHi.withValues(alpha: 0.15),
              valueIndicatorColor: colorHi,
              showValueIndicator: ShowValueIndicator.onDrag,
            ),
            child: RangeSlider(
              values: RangeValues(
                lo.clamp(rangeMin, rangeMax),
                hi.clamp(rangeMin, rangeMax),
              ),
              min: rangeMin,
              max: rangeMax,
              divisions:
                  ((rangeMax - rangeMin) / 0.05).round().clamp(1, 999),
              labels: RangeLabels(_f(lo), _f(hi)),
              onChanged: (rv) {
                HapticFeedback.selectionClick();
                final newLo = (rv.start * 20).round() / 20.0;
                final newHi = (rv.end * 20).round() / 20.0;
                onChanged(newLo, newHi);
              },
            ),
          ),
          // подписи min и max
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_f(rangeMin),
                    style: appFont(context,
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.35))),
                Text(_f(rangeMax),
                    style: appFont(context,
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.35))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeChip(BuildContext context, int grade, Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Text(
        '$grade',
        style: appFont(context,
            fontSize: 15, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  String _f(double v) => v.toStringAsFixed(2);
}

// таблица предпросмотра

class _PreviewTable extends StatelessWidget {
  final GradingRules rules;
  final ColorScheme cs;
  final bool isDark;

  const _PreviewTable(
      {required this.rules, required this.cs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final r = rules;
// берём точки чуть выше и чуть ниже каждой границы плюс центры зон
    final samples = <double>{
      r.grade3Min - 0.30,
      r.grade3Min - 0.01,
      (r.grade3Min + r.grade2Max) / 2,
      r.grade2Max,
      r.grade2Max + 0.01,
      (r.grade2Max + r.grade4Min) / 2,
      r.grade4Min - 0.01,
      (r.grade4Min + r.grade3Max) / 2,
      r.grade3Max,
      r.grade3Max + 0.01,
      (r.grade3Max + r.grade5Min) / 2,
      r.grade5Min - 0.01,
      (r.grade5Min + r.grade4Max) / 2,
      r.grade4Max,
      r.grade4Max + 0.01,
      r.grade4Max + 0.20,
    }
        .where((v) => v >= 1.0 && v <= 5.0)
        .toList()
      ..sort();

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? cs.onSurface.withValues(alpha: 0.04)
            : cs.onSurface.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: samples.asMap().entries.map((entry) {
          final i = entry.key;
          final avg = entry.value;
          final predicted = rules.getPredictedGrade(avg);
          final isBorder = predicted.contains('-');
          final gradeInt = rules.getPrimaryGrade(avg);
          final color = _color(gradeInt);
          final isLast = i == samples.length - 1;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    Text(
                      avg.toStringAsFixed(2),
                      style: appFont(context,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    if (isBorder)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('пограничная',
                              style: appFont(context,
                                fontSize: 9,
                                color:
                                    cs.onSurface.withValues(alpha: 0.45),
                              )),
                        ),
                      ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_rounded,
                        size: 13,
                        color: cs.onSurface.withValues(alpha: 0.25)),
                    const SizedBox(width: 10),
                    Container(
                      constraints:
                          const BoxConstraints(minWidth: 40),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        predicted,
                        style: appFont(context,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                    height: 1,
                    indent: 14,
                    color: cs.outline.withValues(alpha: 0.06)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Color _color(int g) {
    switch (g) {
      case 5:  return Colors.green;
      case 4:  return Colors.blue;
      case 3:  return Colors.orange;
      default: return Colors.red;
    }
  }
}

// вспомогательные виджеты

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

class _FieldLabel extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _FieldLabel(this.text, this.cs);

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

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ColorScheme cs;
  final bool isDark;
  const _StyledField(
      {required this.controller,
      required this.hint,
      required this.icon,
      required this.cs,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? cs.onSurface.withValues(alpha: 0.06)
            : cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        style: appFont(context, fontSize: 15, color: cs.onSurface),
        cursorColor: cs.primary,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: appFont(context,
              color: cs.onSurface.withValues(alpha: 0.35)),
          border: InputBorder.none,
          prefixIcon:
              Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.4)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        ),
      ),
    );
  }
}
