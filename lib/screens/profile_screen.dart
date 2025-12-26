import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/responsive_layout.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProfileViewModel()..loadProfile(),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(vm, colorScheme, l10n),
    );
  }

  Widget _buildBody(ProfileViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    if (vm.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loadingProfile,
              style: GoogleFonts.inter(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    if (vm.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 32,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                vm.error!,
                style: GoogleFonts.inter(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => vm.loadProfile(),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.retry,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop(context) ? 600.0 : double.infinity),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
          children: [

            _buildHeader(vm, colorScheme),

            const SizedBox(height: 32),

            _buildInfoCard(vm, colorScheme, l10n),

            const SizedBox(height: 24),

            if (vm.extendedProfile?.prsRel != null &&
                vm.extendedProfile!.prsRel!.isNotEmpty)
              _buildFamilySection(vm, colorScheme, l10n),

            if (vm.extendedProfile?.pupil != null &&
                vm.extendedProfile!.pupil!.isNotEmpty)
              _buildEducationSection(vm, colorScheme, l10n),

            _buildLogoutButton(vm, colorScheme, l10n),

            const SizedBox(height: 32),
          ],
        ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ProfileViewModel vm, ColorScheme colorScheme) {
    return Column(
      children: [

        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.2),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AuthenticatedAvatar(
            imgObjType: 'USER_PICTURE',
            imgObjId: vm.currentPrsId,
            imageId: vm.userImageId,
            fallbackText: vm.getInitials(),
            size: 100,
            borderRadius: 50,
          ),
        ),

        const SizedBox(height: 20),

        Text(
          vm.getFullName(),
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 4),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${vm.extendedProfile?.login ?? "user"}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(ProfileViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    final items = <_InfoItem>[];

    items.add(_InfoItem(
      icon: Icons.badge_outlined,
      title: 'ID',
      value: '${vm.userId ?? 0}',
    ));

    items.add(_InfoItem(
      icon: Icons.fingerprint_rounded,
      title: 'PRS ID',
      value: '${vm.currentPrsId ?? 0}',
    ));

    if (vm.extendedProfile?.birthDate != null) {
      items.add(_InfoItem(
        icon: Icons.cake_outlined,
        title: l10n.birthday,
        value: vm.extendedProfile!.birthDate!,
      ));
    }

    if (vm.userProfile?.phoneMob != null) {
      items.add(_InfoItem(
        icon: Icons.phone_outlined,
        title: l10n.phone,
        value: vm.userProfile!.phoneMob!,
      ));
    }

    if (vm.extendedProfile?.data?.gender != null) {
      items.add(_InfoItem(
        icon: Icons.person_outline_rounded,
        title: l10n.gender,
        value: vm.extendedProfile!.data!.gender == 1 ? l10n.male : l10n.female,
      ));
    }

    return _ProfileCard(
      colorScheme: colorScheme,
      child: Column(
        children: items.asMap().entries.map((entry) {
          final isLast = entry.key == items.length - 1;
          return Column(
            children: [
              _InfoRow(
                icon: entry.value.icon,
                title: entry.value.title,
                value: entry.value.value,
                colorScheme: colorScheme,
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  color: colorScheme.outline.withValues(alpha: 0.08),
                  indent: 48,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFamilySection(ProfileViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            l10n.familyCaps,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        ...vm.extendedProfile!.prsRel!.map((rel) {
          final data = rel.data;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProfileCard(
              colorScheme: colorScheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.family_restroom_rounded,
                          size: 20,
                          color: colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rel.relName ?? l10n.relative,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                            if (data != null)
                              Text(
                                data.fullName,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (data != null) ...[
                    if (data.mobilePhone != null || data.homePhone != null) ...[
                      const SizedBox(height: 12),
                      _ContactRow(
                        icon: Icons.phone_outlined,
                        value: data.mobilePhone ?? data.homePhone!,
                        colorScheme: colorScheme,
                      ),
                    ],
                    if (data.email != null) ...[
                      const SizedBox(height: 8),
                      _ContactRow(
                        icon: Icons.mail_outline_rounded,
                        value: data.email!,
                        colorScheme: colorScheme,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildEducationSection(ProfileViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            l10n.educationCaps,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        ...vm.extendedProfile!.pupil!.map((pupil) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProfileCard(
              colorScheme: colorScheme,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        pupil.className?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pupil.className ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          pupil.eduYear ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pupil.isReady == 1)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildLogoutButton(ProfileViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
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
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  l10n.cancel,
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
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

        if (confirmed == true) {
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
}

class _InfoItem {
  final IconData icon;
  final String title;
  final String value;

  _InfoItem({required this.icon, required this.title, required this.value});
}

class _ProfileCard extends StatelessWidget {
  final Widget child;
  final ColorScheme colorScheme;

  const _ProfileCard({required this.child, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final ColorScheme colorScheme;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final ColorScheme colorScheme;

  const _ContactRow({
    required this.icon,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}