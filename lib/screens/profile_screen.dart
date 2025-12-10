import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/profile_viewmodel.dart';
import '../widgets/avatar_widget.dart';
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

class _ProfileView extends StatelessWidget {
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (vm.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(vm.error!, style: TextStyle(color: colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => vm.loadProfile(),
              child: const Text("Повторить"),
            )
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Профиль"),
        actions: [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            
            Center(
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
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
                  const SizedBox(height: 12),
                  Text(
                    vm.getFullName(),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vm.extendedProfile?.login ?? "User",
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _GlassCard(
              children: [
                _InfoRow(icon: Icons.badge_outlined, title: "ID", value: "${vm.userId ?? 0}"),
                if (vm.extendedProfile?.birthDate != null)
                  _InfoRow(icon: Icons.calendar_today, title: "Дата рождения", value: vm.extendedProfile!.birthDate!),
                if (vm.userProfile?.phoneMob != null)
                  _InfoRow(icon: Icons.phone, title: "Телефон", value: vm.userProfile!.phoneMob!),
                if (vm.extendedProfile?.data?.gender != null)
                  _InfoRow(
                    icon: Icons.person_outline,
                    title: "Пол",
                    value: vm.extendedProfile!.data!.gender == 1 ? "Мужской" : "Женский",
                  ),
              ],
            ),
            const SizedBox(height: 24),

            if (vm.extendedProfile?.prsRel != null && vm.extendedProfile!.prsRel!.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text("Семья", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              ...vm.extendedProfile!.prsRel!.map((rel) {
                final data = rel.data;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GlassCard(
                    children: [
                      Text(
                        rel.relName ?? "Родственник",
                        style: theme.textTheme.titleSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (data != null) ...[
                        Text(data.fullName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                        if (data.mobilePhone != null || data.homePhone != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.phone, size: 14, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text(
                                  data.mobilePhone ?? data.homePhone!,
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        if (data.email != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.email, size: 14, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text(
                                  data.email!,
                                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                      ]
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            if (vm.extendedProfile?.pupil != null && vm.extendedProfile!.pupil!.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text("Обучение", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              ...vm.extendedProfile!.pupil!.map((pupil) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GlassCard(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pupil.eduYear ?? "", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                Text(pupil.className ?? "", style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          if (pupil.isReady == 1)
                            const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await vm.logout(context);
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
                child: const Text("Выйти", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final List<Widget> children;

  const _GlassCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoRow({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Spacer(),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
