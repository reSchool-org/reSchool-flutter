import 'package:flutter/material.dart';
import '../utils/app_font.dart';

/// точки перелома вёрстки
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1600;
}

/// тип устройства по ширине экрана
enum DeviceType { mobile, tablet, desktop }

/// тип устройства считаем по короткой стороне, так телефон не путается с планшетом
/// телефон в альбомной ориентации не уедет в десктопный режим
DeviceType getDeviceType(BuildContext context) {
  final size = MediaQuery.of(context).size;
  final shortestSide = size.shortestSide;

  // у телефонов короткая сторона меньше 600dp при любом повороте
  if (shortestSide < Breakpoints.mobile) return DeviceType.mobile;

  // дальше уже планшет или десктоп, различаем по ширине
  if (size.width < Breakpoints.tablet) return DeviceType.tablet;
  return DeviceType.desktop;
}

/// это телефон
bool isMobile(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide < Breakpoints.mobile;

/// это планшет или что то крупнее
bool isTablet(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide >= Breakpoints.mobile;

/// это десктоп
bool isDesktop(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide >= Breakpoints.mobile &&
    MediaQuery.of(context).size.width >= Breakpoints.tablet;

/// это широкий десктоп
bool isWideDesktop(BuildContext context) =>
    MediaQuery.of(context).size.shortestSide >= Breakpoints.mobile &&
    MediaQuery.of(context).size.width >= Breakpoints.desktop;

/// билдер, знающий про размер экрана
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, DeviceType deviceType) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return builder(context, getDeviceType(context));
      },
    );
  }
}

/// показывает разные виджеты в зависимости от размера экрана
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final deviceType = getDeviceType(context);

    switch (deviceType) {
      case DeviceType.desktop:
        return desktop ?? tablet ?? mobile;
      case DeviceType.tablet:
        return tablet ?? mobile;
      case DeviceType.mobile:
        return mobile;
    }
  }
}

/// ограничивает ширину контента на широких экранах
class ConstrainedContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool center;

  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = 600,
    this.padding,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    if (center) {
      content = Center(child: content);
    }

    return content;
  }
}

/// сетка, меняющая число колонок под ширину экрана
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double spacing;
  final double runSpacing;
  final EdgeInsetsGeometry? padding;

  const AdaptiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.spacing = 16,
    this.runSpacing = 16,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final deviceType = getDeviceType(context);
    final columns = switch (deviceType) {
      DeviceType.mobile => mobileColumns,
      DeviceType.tablet => tabletColumns,
      DeviceType.desktop => desktopColumns,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - (columns - 1) * spacing) / columns;

        return Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: children.map((child) {
              return SizedBox(
                width: itemWidth,
                child: child,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

/// две панели рядом, как чаты на десктопе
class SplitView extends StatelessWidget {
  final Widget master;
  final Widget? detail;
  final double masterWidth;
  final Widget? emptyDetail;

  const SplitView({
    super.key,
    required this.master,
    this.detail,
    this.masterWidth = 380,
    this.emptyDetail,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: masterWidth,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: master,
          ),
        ),
        Expanded(
          child: detail ?? emptyDetail ?? _EmptyDetailPlaceholder(),
        ),
      ],
    );
  }
}

class _EmptyDetailPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'Выберите чат',
            style: appFont(context, 
              fontSize: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// горизонтальные отступы под ширину экрана
double getResponsivePadding(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < Breakpoints.mobile) return 16;
  if (width < Breakpoints.tablet) return 24;
  if (width < Breakpoints.desktop) return 32;
  return 48;
}

/// максимальная ширина контента под тип экрана
double getContentMaxWidth(BuildContext context, {double defaultMax = 800}) {
  final width = MediaQuery.of(context).size.width;
  if (width < Breakpoints.mobile) return double.infinity;
  if (width < Breakpoints.tablet) return 600;
  return defaultMax;
}
