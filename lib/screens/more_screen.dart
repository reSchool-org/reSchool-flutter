import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../providers/grading_provider.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/responsive_layout.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'login_screen.dart';
import 'bell_schedule_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProfileViewModel()..loadProfile(),
      child: const _MoreView(),
    );
  }
}

class _MoreView extends StatefulWidget {
  const _MoreView();

  @override
  State<_MoreView> createState() => _MoreViewState();
}

class _MoreViewState extends State<_MoreView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileViewModel>();
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop(context) ? 600.0 : double.infinity),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                _buildUserHeader(vm, colorScheme, l10n),

                const SizedBox(height: 32),

                _buildQuickActions(colorScheme, l10n),

                const SizedBox(height: 28),

                _buildSectionHeader(l10n.settings, colorScheme),
                const SizedBox(height: 12),
                _buildSettingsCard(colorScheme, l10n),

                const SizedBox(height: 24),

                _buildSectionHeader(l10n.info, colorScheme),
                const SizedBox(height: 12),
                _buildInfoCard(colorScheme, l10n),

                const SizedBox(height: 32),

                _buildLogoutButton(vm, colorScheme, l10n),

                const SizedBox(height: 32),
              ],
            ),
          ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader(ProfileViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    colorScheme.primary.withValues(alpha: 0.15),
                    colorScheme.primary.withValues(alpha: 0.05),
                  ]
                : [
                    colorScheme.primary.withValues(alpha: 0.12),
                    colorScheme.primary.withValues(alpha: 0.04),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [

            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
              child: vm.isLoading
                  ? Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    )
                  : AuthenticatedAvatar(
                      imgObjType: 'USER_PICTURE',
                      imgObjId: vm.currentPrsId,
                      imageId: vm.userImageId,
                      fallbackText: vm.getInitials(),
                      size: 60,
                      borderRadius: 30,
                    ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vm.isLoading ? l10n.loading : vm.getFullName(),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${vm.extendedProfile?.login ?? 'user'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(ColorScheme colorScheme, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.palette_outlined,
            label: l10n.theme,
            colorScheme: colorScheme,
            onTap: () => _showThemeDialog(colorScheme, l10n),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.access_time_rounded,
            label: l10n.calls,
            colorScheme: colorScheme,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BellScheduleScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.grade_outlined,
            label: l10n.grades,
            colorScheme: colorScheme,
            onTap: () => _showGradingSettings(colorScheme, l10n),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(ColorScheme colorScheme, AppLocalizations l10n) {
    return _MenuCard(
      colorScheme: colorScheme,
      children: [
        _MenuItem(
          icon: Icons.tune_rounded,
          title: l10n.settings,
          subtitle: l10n.general,
          colorScheme: colorScheme,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        _MenuDivider(colorScheme: colorScheme),
        _MenuItem(
          icon: Icons.notifications_outlined,
          title: 'Уведомления',
          subtitle: l10n.soon,
          colorScheme: colorScheme,
          isDisabled: true,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildInfoCard(ColorScheme colorScheme, AppLocalizations l10n) {
    return _MenuCard(
      colorScheme: colorScheme,
      children: [
        _MenuItem(
          icon: Icons.info_outline_rounded,
          title: l10n.aboutApp,
          subtitle: '${l10n.version} 1.0.1',
          colorScheme: colorScheme,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AboutScreen()),
          ),
        ),
        _MenuDivider(colorScheme: colorScheme),
        _MenuItem(
          icon: Icons.help_outline_rounded,
          title: l10n.help,
          subtitle: l10n.soon,
          colorScheme: colorScheme,
          isDisabled: true,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildLogoutButton(ProfileViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();

        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              l10n.logoutQuestion,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            content: Text(
              l10n.logoutWarning,
              style: GoogleFonts.inter(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  l10n.cancel,
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  l10n.logout,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );

        if (confirm == true && context.mounted) {
          await vm.logout(context);
          if (context.mounted) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const LoginScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ),
            );
          }
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.error.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.logout_rounded,
              size: 20,
              color: colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.logout,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeDialog(ColorScheme colorScheme, AppLocalizations l10n) {
    HapticFeedback.lightImpact();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer<ThemeProvider>(
          builder: (context, provider, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    l10n.selectTheme,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      _ThemeOptionCard(
                        icon: Icons.light_mode_rounded,
                        label: l10n.light,
                        isSelected: provider.themeMode == ThemeMode.light,
                        colorScheme: colorScheme,
                        onTap: () {
                          themeProvider.setTheme(ThemeMode.light);
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 12),
                      _ThemeOptionCard(
                        icon: Icons.dark_mode_rounded,
                        label: l10n.dark,
                        isSelected: provider.themeMode == ThemeMode.dark,
                        colorScheme: colorScheme,
                        onTap: () {
                          themeProvider.setTheme(ThemeMode.dark);
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 12),
                      _ThemeOptionCard(
                        icon: Icons.contrast_rounded,
                        label: l10n.auto,
                        isSelected: provider.themeMode == ThemeMode.system,
                        colorScheme: colorScheme,
                        onTap: () {
                          themeProvider.setTheme(ThemeMode.system);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showGradingSettings(ColorScheme colorScheme, AppLocalizations l10n) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _GradingSettingsSheet(colorScheme: colorScheme, l10n: l10n),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDark
              ? colorScheme.onSurface.withValues(alpha: 0.05)
              : colorScheme.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  final ColorScheme colorScheme;

  const _MenuCard({required this.children, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final bool isDisabled;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorScheme,
    required this.onTap,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = isDisabled ? 0.4 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Opacity(
            opacity: opacity,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  final ColorScheme colorScheme;

  const _MenuDivider({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 70,
      color: colorScheme.outline.withValues(alpha: 0.08),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outline.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 28,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradingSettingsSheet extends StatelessWidget {
  final ColorScheme colorScheme;
  final AppLocalizations l10n;

  const _GradingSettingsSheet({required this.colorScheme, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final grading = context.watch<GradingProvider>();

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [

            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text(
              l10n.gradingSystem,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.gradingPresetSelect,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),

            ...GradingProvider.availablePresets.map((preset) {
              final isSelected = grading.selectedPresetId == preset.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    grading.setPreset(preset.id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.1)
                          : colorScheme.onSurface.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.3)
                            : colorScheme.outline.withValues(alpha: 0.08),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                preset.name,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                preset.description,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),

            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                grading.setShowPredictedGrade(!grading.showPredictedGrade);
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.predictedGrade,
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            l10n.showQuarterGrade,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: grading.showPredictedGrade,
                      onChanged: (v) {
                        HapticFeedback.selectionClick();
                        grading.setShowPredictedGrade(v);
                      },
                      activeColor: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}