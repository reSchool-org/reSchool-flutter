import 'package:flutter/material.dart';

// единый вид карточек: настройки, облачные функции и всё остальное
// должны выглядеть одинаково, поэтому цвета живут здесь, а не в экранах

/// фон карточки, чуть заметная подложка поверх surface
Color appCardFill(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return cs.onSurface.withValues(alpha: isDark ? 0.05 : 0.03);
}

/// фон полей ввода, чуть плотнее карточки, иначе поле теряется на ней
Color appFieldFill(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.05);
}

/// рамка карточки
Color appCardBorderColor(BuildContext context) =>
    Theme.of(context).colorScheme.outline.withValues(alpha: 0.08);

/// декорация карточки, [color] и [borderColor] переопределяют только цвет
BoxDecoration appCardDecoration(
  BuildContext context, {
  double radius = 16,
  Color? color,
  Color? borderColor,
  bool border = true,
}) {
  return BoxDecoration(
    color: color ?? appCardFill(context),
    borderRadius: BorderRadius.circular(radius),
    border: border
        ? Border.all(color: borderColor ?? appCardBorderColor(context))
        : null,
  );
}

/// готовая карточка, чтобы не расписывать Container с декорацией каждый раз
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 16,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: appCardDecoration(
        context,
        radius: radius,
        color: color,
        borderColor: borderColor,
      ),
      child: child,
    );
  }
}

/// фон рисуется на материале, чтобы не перекрывать отклик на нажатие
class AppInteractiveCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  const AppInteractiveCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: appCardFill(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: appCardBorderColor(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

/// зелёный «всё хорошо»: в тёмной теме нужен светлее, иначе не читается
Color appSuccessColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF7BD98A)
    : const Color(0xFF2E7D32);

/// оранжевый «обрати внимание», по той же причине завязан на яркость темы
Color appWarningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFB74D)
    : const Color(0xFFE65100);
