import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double wide = 1600;
}

enum DeviceType { mobile, tablet, desktop }

DeviceType getDeviceType(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < Breakpoints.mobile) return DeviceType.mobile;
  if (width < Breakpoints.tablet) return DeviceType.tablet;
  return DeviceType.desktop;
}

bool isMobile(BuildContext context) =>
    MediaQuery.of(context).size.width < Breakpoints.mobile;

bool isTablet(BuildContext context) =>
    MediaQuery.of(context).size.width >= Breakpoints.mobile;

bool isDesktop(BuildContext context) =>
    MediaQuery.of(context).size.width >= Breakpoints.tablet;

bool isWideDesktop(BuildContext context) =>
    MediaQuery.of(context).size.width >= Breakpoints.desktop;

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
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

double getResponsivePadding(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < Breakpoints.mobile) return 16;
  if (width < Breakpoints.tablet) return 24;
  if (width < Breakpoints.desktop) return 32;
  return 48;
}

double getContentMaxWidth(BuildContext context, {double defaultMax = 800}) {
  final width = MediaQuery.of(context).size.width;
  if (width < Breakpoints.mobile) return double.infinity;
  if (width < Breakpoints.tablet) return 600;
  return defaultMax;
}