import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/app_card.dart';
import 'login_screen.dart';
import '../utils/app_font.dart';

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
        title: Text(
          l10n.profileTitle,
          style: appFont(context, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(child: _buildBody(vm, colorScheme, l10n)),
    );
  }

  Widget _buildBody(
    ProfileViewModel vm,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    if (vm.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loadingProfile,
              style: appFont(context,
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
                style: appFont(context,
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
                  style: appFont(context, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 840 &&
              MediaQuery.textScalerOf(context).scale(16) <= 22;
          final padding = constraints.maxWidth < 600 ? 20.0 : 32.0;
          final hasFamily = vm.extendedProfile?.prsRel?.isNotEmpty ?? false;
          final hasEducation = vm.extendedProfile?.pupil?.isNotEmpty ?? false;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasFamily) _buildFamilySection(vm, colorScheme, l10n),
              if (hasFamily && hasEducation) const SizedBox(height: 28),
              if (hasEducation) _buildEducationSection(vm, colorScheme, l10n),
            ],
          );

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 960 : 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(vm, colorScheme, l10n, wide: wide),
                    const SizedBox(height: 32),
                    if (wide && (hasFamily || hasEducation))
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildInfoCard(vm, colorScheme, l10n),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: details),
                        ],
                      )
                    else ...[
                      _buildInfoCard(vm, colorScheme, l10n),
                      if (hasFamily || hasEducation) ...[
                        const SizedBox(height: 28),
                        details,
                      ],
                    ],
                    if (!wide) ...[
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.center,
                        child: _buildLogoutButton(vm, colorScheme, l10n),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    ProfileViewModel vm,
    ColorScheme colorScheme,
    AppLocalizations l10n, {
    required bool wide,
  }) {
    final login = vm.extendedProfile?.login?.trim();
    return AppCard(
      radius: 20,
      padding: EdgeInsets.all(wide ? 28 : 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(16) > 22;
          final avatarSize = wide ? 80.0 : 64.0;
          final avatar = Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: AuthenticatedAvatar(
              imgObjType: 'USER_PICTURE',
              imgObjId: vm.currentPrsId,
              imageId: vm.userImageId,
              fallbackText: vm.getInitials(),
              size: avatarSize,
            ),
          );
          final identity = Column(
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                vm.getFullName(),
                textAlign: stacked ? TextAlign.center : TextAlign.start,
                style: appFont(context,
                  fontSize: wide ? 26 : 22,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              if (login != null && login.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    login,
                    style: appFont(context,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          );

          if (stacked) {
            return Column(
              children: [avatar, const SizedBox(height: 16), identity],
            );
          }
          return Row(
            children: [
              avatar,
              const SizedBox(width: 20),
              Expanded(child: identity),
              if (wide) ...[
                const SizedBox(width: 24),
                _buildLogoutButton(vm, colorScheme, l10n),
              ],
            ],
          );
        },
      ),
    );
  }

  String _formatBirthDate(String value, AppLocalizations l10n) {
    final date =
        DateTime.tryParse(value) ??
        DateFormat('dd.MM.yyyy').tryParseStrict(value);
    return date == null
        ? value
        : DateFormat.yMMMd(l10n.locale.languageCode).format(date);
  }

  Widget _buildInfoCard(
    ProfileViewModel vm,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final items = <_InfoItem>[
      if (vm.extendedProfile?.birthDate?.isNotEmpty ?? false)
        _InfoItem(
          icon: Icons.cake_outlined,
          title: l10n.birthday,
          value: _formatBirthDate(vm.extendedProfile!.birthDate!, l10n),
        ),
      if (vm.userProfile?.phoneMob?.isNotEmpty ?? false)
        _InfoItem(
          icon: Icons.phone_outlined,
          title: l10n.phone,
          value: vm.userProfile!.phoneMob!,
        ),
      if (vm.extendedProfile?.data?.gender != null)
        _InfoItem(
          icon: Icons.person_outline_rounded,
          title: l10n.gender,
          value: vm.extendedProfile!.data!.gender == 1
              ? l10n.male
              : l10n.female,
        ),
      _InfoItem(
        icon: Icons.badge_outlined,
        title: 'ID',
        value: vm.userId?.toString() ?? '-',
      ),
      _InfoItem(
        icon: Icons.fingerprint_rounded,
        title: 'PRS ID',
        value: vm.currentPrsId?.toString() ?? '-',
      ),
    ];

    return _ProfileSection(
      title: l10n.info,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const _ProfileDivider(indent: 32),
              _InfoRow(item: items[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFamilySection(
    ProfileViewModel vm,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final relatives = vm.extendedProfile!.prsRel!;
    return _ProfileSection(
      title: l10n.profileFamily,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < relatives.length; i++) ...[
              if (i > 0) const _ProfileDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      relatives[i].relName ?? l10n.relative,
                      style: appFont(context,
                        fontSize: 13,
                        height: 1.4,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (relatives[i].data?.fullName.isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      Text(
                        relatives[i].data!.fullName,
                        style: appFont(context,
                          fontSize: 15,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                    if ((relatives[i].data?.mobilePhone ??
                                relatives[i].data?.homePhone)
                            ?.isNotEmpty ??
                        false) ...[
                      const SizedBox(height: 12),
                      _ContactRow(
                        icon: Icons.phone_outlined,
                        value:
                            relatives[i].data!.mobilePhone ??
                            relatives[i].data!.homePhone!,
                      ),
                    ],
                    if (relatives[i].data?.email?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      _ContactRow(
                        icon: Icons.mail_outline_rounded,
                        value: relatives[i].data!.email!,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEducationSection(
    ProfileViewModel vm,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    // учебные годы показываем от новых к старым, не меняя ответ API
    final pupils = [...vm.extendedProfile!.pupil!]
      ..sort((a, b) => (b.eduYear ?? '').compareTo(a.eduYear ?? ''));
    return _ProfileSection(
      title: l10n.profileEducation,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < pupils.length; i++) ...[
              if (i > 0) const _ProfileDivider(indent: 40),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.school_outlined,
                      size: 20,
                      color: colorScheme.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pupils[i].className ?? '-',
                            style: appFont(context,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (pupils[i].eduYear?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 3),
                            Text(
                              pupils[i].eduYear!,
                              style: appFont(context,
                                fontSize: 13,
                                height: 1.4,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (pupils[i].isReady == 1) ...[
                      const SizedBox(width: 12),
                      Tooltip(
                        message: l10n.profileEducationReady,
                        child: Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: appSuccessColor(context),
                          semanticLabel: l10n.profileEducationReady,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(
    ProfileViewModel vm,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.error,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: appFont(context, fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: Text(l10n.logout, style: appFont(context)),
      onPressed: () async {
        HapticFeedback.lightImpact();

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              l10n.logoutQuestion,
              style: appFont(context, fontWeight: FontWeight.w600),
            ),
            content: Text(
              l10n.logoutWarning,
              style: appFont(context,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  l10n.cancel,
                  style: appFont(context,
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
                  style: appFont(context, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );

        if (confirmed == true && mounted) {
          await vm.logout(context);
          if (mounted) {
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
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String title;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.title,
    required this.value,
  });
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _ProfileSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: appFont(context,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ProfileDivider extends StatelessWidget {
  final double indent;

  const _ProfileDivider({this.indent = 0});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: indent,
    color: appCardBorderColor(context),
  );
}

class _InfoRow extends StatelessWidget {
  final _InfoItem item;

  const _InfoRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final label = Text(
            item.title,
            style: appFont(context,
              fontSize: 14,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          );
          final value = Text(
            item.value,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
            style: appFont(context,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          );
          return Row(
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: stacked ? 1 : 0),
                child: Icon(item.icon, size: 20, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              if (stacked)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [label, const SizedBox(height: 4), value],
                  ),
                )
              else ...[
                Expanded(child: label),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: value),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;

  const _ContactRow({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: appFont(context,
              fontSize: 14,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
