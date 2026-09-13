import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../utils/app_font.dart';
import '../viewmodels/school_directory_viewmodel.dart';
import '../widgets/app_card.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/section_state.dart';
import 'chat_detail_screen.dart';

class SchoolDirectoryScreen extends StatefulWidget {
  const SchoolDirectoryScreen({super.key});
  @override
  State<SchoolDirectoryScreen> createState() => _SchoolDirectoryScreenState();
}

class _SchoolDirectoryScreenState extends State<SchoolDirectoryScreen> {
  final _vm = SchoolDirectoryViewModel();
  final _search = TextEditingController();
  int? _openingUser;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_changed);
    _vm.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _openChat(UserSearchItem user) async {
    if (user.prsId == null || _openingUser != null) return;
    setState(() => _openingUser = user.prsId);
    try {
      final id = await ApiService().saveThread(interlocutorId: user.prsId);
      if (id <= 0) throw StateError('Chat was not created');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            threadId: id,
            title: user.fio ?? '',
            isGroup: false,
            imageId: user.imageId,
            imgObjType: 'USER_PICTURE',
            imgObjId: user.prsId,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.chatOpenError,
              style: appFont(context),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingUser = null);
    }
  }

  void _showEmployee(UserSearchItem user) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext)!;
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AuthenticatedAvatar(
                    imageId: user.imageId,
                    imgObjType: 'USER_PICTURE',
                    imgObjId: user.prsId,
                    fallbackText: user.fio ?? '',
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user.fio ?? '',
                    textAlign: TextAlign.center,
                    style: appFont(sheetContext, fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (user.pos ?? [])
                        .map((p) => p.posTypeName)
                        .whereType<String>()
                        .toSet()
                        .join('\n'),
                    textAlign: TextAlign.center,
                    style: appFont(sheetContext,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: user.prsId == null
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              _openChat(user);
                            },
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text(
                        l10n.startChat,
                        style: appFont(sheetContext, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final searching = _vm.query.trim().isNotEmpty;
    final users = searching ? _vm.searchResults : _vm.users;
    final groups = searching ? [] : _vm.groups;
    return PopScope(
      canPop: _vm.path.isEmpty || searching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _vm.backTo(_vm.path.length - 1);
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text(
            l10n.employeeDirectory,
            style: appFont(context, fontWeight: FontWeight.w600),
          ),
          leading: BackButton(
            onPressed: () {
              if (_vm.path.isNotEmpty && !searching) {
                _vm.backTo(_vm.path.length - 1);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            IconButton(
              tooltip: l10n.refreshContent,
              onPressed: _vm.isLoading ? null : _vm.load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: TextField(
                    controller: _search,
                    onChanged: _vm.search,
                    style: appFont(context),
                    decoration: InputDecoration(
                      hintText: l10n.directorySearch,
                      hintStyle: appFont(context, color: cs.onSurfaceVariant),
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: appFieldFill(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: searching
                          ? IconButton(
                              tooltip: l10n.close,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                _vm.search('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                if (!searching)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => _vm.backTo(0),
                          child: Text(
                            l10n.directoryRoot,
                            style: appFont(context, fontWeight: FontWeight.w500),
                          ),
                        ),
                        for (var i = 0; i < _vm.path.length; i++) ...[
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          TextButton(
                            onPressed: () => _vm.backTo(i + 1),
                            child: Text(
                              _vm.path[i].name,
                              style: appFont(context, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_openingUser != null)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _vm.load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_vm.isLoading)
                          const Padding(
                            padding: EdgeInsets.all(48),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_vm.hasError)
                          SectionState(
                            icon: Icons.wifi_off_rounded,
                            title: l10n.directoryLoadError,
                            onRetry: _vm.load,
                          )
                        else if (groups.isEmpty && users.isEmpty)
                          SectionState(
                            icon: Icons.people_outline_rounded,
                            title: searching
                                ? l10n.directoryNoResults
                                : l10n.directoryEmpty,
                          )
                        else
                          AppInteractiveCard(
                            child: Column(
                              children: [
                                for (final group in groups)
                                  ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 6,
                                    ),
                                    leading: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: cs.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        group.isOrganization
                                            ? Icons.business_rounded
                                            : Icons.folder_outlined,
                                        color: cs.primary,
                                      ),
                                    ),
                                    title: Text(
                                      group.name,
                                      style: appFont(context,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => _vm.enter(group),
                                  ),
                                for (final user in users)
                                  ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 6,
                                    ),
                                    leading: AuthenticatedAvatar(
                                      imageId: user.imageId,
                                      imgObjType: 'USER_PICTURE',
                                      imgObjId: user.prsId,
                                      fallbackText: user.fio ?? '',
                                      size: 42,
                                      borderRadius: 12,
                                    ),
                                    title: Text(
                                      user.fio ?? '',
                                      style: appFont(context,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      (user.pos ?? [])
                                          .map((p) => p.posTypeName)
                                          .whereType<String>()
                                          .toSet()
                                          .join(', '),
                                      style: appFont(context,
                                        fontSize: 13,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: Icon(
                                      Icons.chevron_right_rounded,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    onTap: _openingUser != null
                                        ? null
                                        : () => _showEmployee(user),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
