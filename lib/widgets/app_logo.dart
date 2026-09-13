import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics_compat.dart'
    show RenderingStrategy;

/// логотип подстраивается под выбранный акцент и яркость темы
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hue = HSLColor.fromColor(colors.primary).hue;
    final isDark = colors.brightness == Brightness.dark;

    // близкие насыщенные цвета сохраняют цельность логотипа
    final palette = _LogoColors(
      HSLColor.fromAHSL(1, hue, 0.72, isDark ? 0.65 : 0.40).toColor(),
      HSLColor.fromAHSL(1, hue, 0.78, isDark ? 0.80 : 0.68).toColor(),
      HSLColor.fromAHSL(1, hue, 0.84, isDark ? 0.72 : 0.54).toColor(),
    );

    // рисуем svg с четырёхкратным запасом, чтобы при уменьшении сгладить тонкие линии
    return SizedBox(
      width: size,
      height: size,
      child: OverflowBox(
        minWidth: size * 4,
        maxWidth: size * 4,
        minHeight: size * 4,
        maxHeight: size * 4,
        child: Transform.scale(
          scale: 1 / 4,
          filterQuality: FilterQuality.medium,
          child: SvgPicture.asset(
            'assets/logo.svg',
            width: size * 4,
            height: size * 4,
            renderingStrategy: RenderingStrategy.raster,
            semanticsLabel: 'reSchool',
            colorMapper: palette,
          ),
        ),
      ),
    );
  }
}

@immutable
class _LogoColors extends ColorMapper {
  const _LogoColors(this.primary, this.secondary, this.tertiary);

  final Color primary;
  final Color secondary;
  final Color tertiary;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => switch (color.toARGB32()) {
    0xFF243B7B => primary,
    0xFF69BCE2 => secondary,
    0xFFD7B34A => tertiary,
    _ => color,
  };

  @override
  bool operator ==(Object other) =>
      other is _LogoColors &&
      primary == other.primary &&
      secondary == other.secondary &&
      tertiary == other.tertiary;

  @override
  int get hashCode => Object.hash(primary, secondary, tertiary);
}
