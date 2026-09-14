import 'dart:async';

import 'package:provider/provider.dart';

import '../providers/bell_schedule_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/widget_config_provider.dart';
import '../services/widget_sync_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/diary_navigation_service.dart';
import '../services/update_service.dart';
import '../widgets/responsive_layout.dart';
import 'diary_screen.dart';
import 'marks_screen.dart';
import 'more_screen.dart';
import 'assignments_screen.dart';
import 'chats_screen.dart';
import '../utils/app_font.dart';
import '../widgets/avatar_widget.dart';
import 'profile_screen.dart';
import 'chat_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _updateCheckDone = false;
  bool _navigationScheduled = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Widget> _screens = [
    const DiaryScreen(),
    const MarksScreen(),
    const AssignmentsScreen(),
    const ChatsScreen(),
    const MoreScreen(),
  ];

  String _getInitials() {
    final name = ApiService().userProfile?.fullName ?? '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    String initials = parts.first[0];
    if (parts.length > 1) initials += parts.last[0];
    return initials.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = DiaryNavigationService.instance.pendingTab.value ?? 0;
    DiaryNavigationService.instance.pendingTab.addListener(_onPendingTabChange);
    DiaryNavigationService.instance.pendingChat.addListener(
      _onPendingTabChange,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _onPendingTabChange();
      _refreshWidgets();
      _checkForUpdates();
    });
  }

  @override
  void dispose() {
    DiaryNavigationService.instance.pendingTab.removeListener(
      _onPendingTabChange,
    );
    DiaryNavigationService.instance.pendingChat.removeListener(
      _onPendingTabChange,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshWidgets();
  }

  Future<void> _refreshWidgets() async {
    final config = context.read<WidgetConfigProvider>();
    final bells = context.read<BellScheduleProvider>();
    final settings = context.read<SettingsProvider>();
    await config.ready;
    if (!mounted) return;
    try {
      await WidgetSyncService.instance.refresh(
        bells: bells,
        settings: settings,
        config: config.config,
      );
    } catch (error) {
      debugPrint('Widget sync failed: $error');
    }
  }

  void _onPendingTabChange() {
    if (!mounted || _navigationScheduled) return;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      if (!mounted) return;
      final service = DiaryNavigationService.instance;
      final tab = service.consumeTab();
      final chat = service.pendingChat.value;
      if (tab == null && chat == null) return;
      final route = ModalRoute.of(context);
      Navigator.of(context)
          .popUntil((candidate) => candidate == route || candidate.isFirst);
      if (tab != null) setState(() => _currentIndex = tab);
      if (chat != null) {
        service.pendingChat.value = null;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              threadId: chat.threadId,
              title: chat.title,
              isGroup: chat.isGroup,
              initialMessageNumber: chat.messageNumber,
            ),
          ),
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _checkForUpdates() async {
    if (_updateCheckDone) return;
    _updateCheckDone = true;

    if (!UpdateService.isSupported) return;

    // демо аккаунту обновления не ищем
    if (ApiService().isDemo) return;

    final update = await UpdateService.checkForUpdates();
    if (update != null && mounted) {
      _showUpdateDialog(update);
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo update) async {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // если сборка на модерации в ios, диалог другой
    if (update.isIOS && update.isTestFlightPending) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.updateAvailable,
                  style: appFont(context, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            l10n.updatePendingReview(update.version),
            style: appFont(
              context,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'OK',
                style: appFont(context, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.system_update_rounded,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.updateAvailable,
                style: appFont(context, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              update.isIOS
                  ? l10n.updateAvailableTestFlight(update.version)
                  : l10n.updateAvailableMessage(update.version),
              style: appFont(
                context,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            if (update.releaseNotes != null &&
                update.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.whatsNew,
                style: appFont(
                  context,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    update.releaseNotes!,
                    style: appFont(
                      context,
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: Text(
              l10n.skipUpdate,
              style: appFont(
                context,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: Text(l10n.later, style: appFont(context)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'update'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              update.isIOS ? l10n.openTestFlight : l10n.updateNow,
              style: appFont(context, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );

    if (result == 'skip') {
      await UpdateService.skipVersion(update.version);
    } else if (result == 'update') {
      if (update.isIOS) {
        // открываем ссылку на TestFlight
        final url = Uri.parse(update.downloadUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      } else {
        await _downloadUpdate(update);
      }
    }
  }

  Future<void> _downloadUpdate(UpdateInfo update) async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final streamController = StreamController<int>.broadcast();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.downloadingUpdate,
          style: appFont(dialogContext, fontWeight: FontWeight.w600),
        ),
        content: StreamBuilder<int>(
          stream: streamController.stream,
          initialData: 0,
          builder: (context, snapshot) {
            final percent = snapshot.data ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '$percent%',
                  style: appFont(
                    context,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    try {
      await UpdateService.downloadAndInstall(update, (p) {
        streamController.add((p * 100).toInt());
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.updateError}: $e', style: appFont(context)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      await streamController.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (isMobile(context)) {
      return _buildMobileLayout(l10n);
    }
    return _buildNonMobileLayout(l10n);
  }

  // мобилка: нижняя панель навигации

  Widget _buildMobileLayout(AppLocalizations l10n) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.book_outlined),
            selectedIcon: const Icon(Icons.book),
            label: l10n.diary,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: l10n.marks,
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: l10n.assignments,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: l10n.chats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_rounded),
            selectedIcon: const Icon(Icons.menu),
            label: l10n.more,
          ),
        ],
      ),
    );
  }

  // всё остальное: NavigationRail плюс выезжающий drawer

  Widget _buildNonMobileLayout(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final api = ApiService();
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildTemporaryDrawer(l10n, colorScheme),
      body: Row(
        children: [
          SizedBox(
            width: 72,
            child: Column(
              children: [
                Expanded(
                  child: NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (index) =>
                        setState(() => _currentIndex = index),
                    labelType: NavigationRailLabelType.none,
                    minWidth: 72,
                    leading: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        tooltip: 'Открыть меню',
                        onPressed: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                      ),
                    ),
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.book_outlined),
                        selectedIcon: const Icon(Icons.book),
                        label: Text(l10n.diary, style: appFont(context)),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.bar_chart_outlined),
                        selectedIcon: const Icon(Icons.bar_chart),
                        label: Text(l10n.marks, style: appFont(context)),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.assignment_outlined),
                        selectedIcon: const Icon(Icons.assignment),
                        label: Text(l10n.assignments, style: appFont(context)),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        selectedIcon: const Icon(Icons.chat_bubble_rounded),
                        label: Text(l10n.chats, style: appFont(context)),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.menu_rounded),
                        selectedIcon: const Icon(Icons.menu),
                        label: Text(l10n.more, style: appFont(context)),
                      ),
                    ],
                  ),
                ),
                // аватар внизу, по тапу открывается профиль
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Tooltip(
                    message: 'Профиль',
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: AuthenticatedAvatar(
                        imgObjType: 'USER_PICTURE',
                        imgObjId: api.currentPrsId,
                        imageId: api.userProfile?.imageId,
                        fallbackText: _getInitials(),
                        size: 40,
                        borderRadius: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          Expanded(child: _screens[_currentIndex]),
        ],
      ),
    );
  }

  Widget _buildTemporaryDrawer(AppLocalizations l10n, ColorScheme colorScheme) {
    final api = ApiService();
    final fullName = api.userProfile?.fullName ?? '';

    final destinations = <(IconData, IconData, String)>[
      (Icons.book_outlined, Icons.book, l10n.diary),
      (Icons.bar_chart_outlined, Icons.bar_chart, l10n.marks),
      (Icons.assignment_outlined, Icons.assignment, l10n.assignments),
      (
        Icons.chat_bubble_outline_rounded,
        Icons.chat_bubble_rounded,
        l10n.chats,
      ),
      (Icons.menu_rounded, Icons.menu, l10n.more),
    ];

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // кнопка закрытия
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: IconButton(
                icon: const Icon(Icons.menu_open_rounded),
                tooltip: 'Свернуть',
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            ),

            // пункты навигации
            for (int i = 0; i < destinations.length; i++)
              _buildDrawerItem(
                index: i,
                outlinedIcon: destinations[i].$1,
                filledIcon: destinations[i].$2,
                label: destinations[i].$3,
                colorScheme: colorScheme,
              ),

            const Spacer(),

            // разделитель
            Divider(
              indent: 16,
              endIndent: 16,
              color: colorScheme.outline.withValues(alpha: 0.1),
            ),

            // профиль прибит к низу
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _scaffoldKey.currentState?.closeDrawer();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      AuthenticatedAvatar(
                        imgObjType: 'USER_PICTURE',
                        imgObjId: api.currentPrsId,
                        imageId: api.userProfile?.imageId,
                        fallbackText: _getInitials(),
                        size: 40,
                        borderRadius: 12,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          fullName,
                          style: appFont(
                            context,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required int index,
    required IconData outlinedIcon,
    required IconData filledIcon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
          _scaffoldKey.currentState?.closeDrawer();
        },
        borderRadius: BorderRadius.circular(100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? filledIcon : outlinedIcon,
                size: 24,
                color: isSelected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: appFont(
                  context,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
