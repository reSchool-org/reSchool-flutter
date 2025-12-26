import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_models.dart';
import '../viewmodels/chats_viewmodel.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/responsive_layout.dart';
import '../services/api_service.dart';
import 'chat_detail_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with SingleTickerProviderStateMixin {
  final ChatsViewModel _viewModel = ChatsViewModel();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchMode = false;

  ChatThread? _selectedThread;
  bool _selectedIsReSchoolBot = false;

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

    _viewModel.addListener(_onViewModelChanged);
    _viewModel.loadThreads();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _viewModel.removeListener(_onViewModelChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String query) {
    _viewModel.searchUsers(query);
  }

  void _toggleSearchMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (!_isSearchMode) {
        _searchController.clear();
        _viewModel.clearSearch();
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _openChat(ChatThread thread, bool isReSchoolBot) {
    HapticFeedback.selectionClick();

    if (isDesktop(context)) {
      setState(() {
        _selectedThread = thread;
        _selectedIsReSchoolBot = isReSchoolBot;
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            threadId: thread.threadId,
            title: isReSchoolBot ? 'reSchool' : thread.title,
            isGroup: thread.isGroup,
            imageId: thread.imageId,
            imgObjType: thread.imgObjType,
            imgObjId: thread.imgObjId,
          ),
        ),
      ).then((_) => _viewModel.loadThreads());
    }
  }

  void _openUserChat(UserSearchItem user) async {
    HapticFeedback.selectionClick();
    final threadId = await _viewModel.openUserChat(user);
    if (threadId != null && mounted) {
      _toggleSearchMode();

      if (isDesktop(context)) {
        await _viewModel.loadThreads();
        final newThread = _viewModel.threads.firstWhere(
          (t) => t.threadId == threadId,
          orElse: () => ChatThread(threadId: threadId, sendDate: 0),
        );
        setState(() {
          _selectedThread = newThread;
          _selectedIsReSchoolBot = false;
        });
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              threadId: threadId,
              title: user.fio ?? 'Чат',
              isGroup: false,
              imageId: user.imageId,
              imgObjType: 'USER_PICTURE',
              imgObjId: user.prsId,
            ),
          ),
        ).then((_) => _viewModel.loadThreads());
      }
    }
  }

  void _showCreateGroupSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth: isDesktop(context) ? 500 : double.infinity,
      ),
      builder: (context) => _CreateGroupSheet(
        onCreated: (threadId, subject) {
          Navigator.pop(context);

          if (isDesktop(this.context)) {
            _viewModel.loadThreads().then((_) {
              final newThread = _viewModel.threads.firstWhere(
                (t) => t.threadId == threadId,
                orElse: () => ChatThread(
                  threadId: threadId,
                  subject: subject,
                  sendDate: 0,
                ),
              );
              setState(() {
                _selectedThread = newThread;
                _selectedIsReSchoolBot = false;
              });
            });
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailScreen(
                  threadId: threadId,
                  title: subject,
                  isGroup: true,
                ),
              ),
            ).then((_) => _viewModel.loadThreads());
          }
        },
      ),
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Widget _buildKeyboardDoneButton() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset <= 0) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                onPressed: _dismissKeyboard,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: Stack(
          children: [
            SafeArea(
              child: ResponsiveLayout(
                mobile: _buildMobileLayout(colorScheme, l10n),
                desktop: _buildDesktopLayout(colorScheme, l10n),
              ),
            ),
            _buildKeyboardDoneButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(ColorScheme colorScheme, AppLocalizations l10n) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: _viewModel.loadThreads,
        color: colorScheme.primary,
        child: _buildChatsList(colorScheme, l10n, padding: 24),
      ),
    );
  }

  Widget _buildDesktopLayout(ColorScheme colorScheme, AppLocalizations l10n) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Row(
        children: [

          SizedBox(
            width: 400,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: RefreshIndicator(
                onRefresh: _viewModel.loadThreads,
                color: colorScheme.primary,
                child: _buildChatsList(
                  colorScheme,
                  l10n,
                  padding: 20,
                  compactHeader: true,
                ),
              ),
            ),
          ),

          Expanded(
            child: _selectedThread != null
                ? ChatDetailScreen(
                    key: ValueKey(_selectedThread!.threadId),
                    threadId: _selectedThread!.threadId,
                    title: _selectedIsReSchoolBot
                        ? 'reSchool'
                        : _selectedThread!.title,
                    isGroup: _selectedThread!.isGroup,
                    imageId: _selectedThread!.imageId,
                    imgObjType: _selectedThread!.imgObjType,
                    imgObjId: _selectedThread!.imgObjId,
                    embedded: true,
                    onBack: () => setState(() => _selectedThread = null),
                  )
                : _EmptyDetailPlaceholder(l10n: l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList(
    ColorScheme colorScheme,
    AppLocalizations l10n, {
    required double padding,
    bool compactHeader = false,
  }) {
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [

        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(padding, 16, padding, 8),
            child: Row(
              children: [
                Expanded(
                  child: _isSearchMode
                      ? _SearchField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onSearchChanged,
                          onClose: _toggleSearchMode,
                          l10n: l10n,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.messages,
                              style: GoogleFonts.outfit(
                                fontSize: compactHeader ? 28 : 34,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            if (!compactHeader) ...[
                              const SizedBox(height: 4),
                              Text(
                                l10n.chatsAndDialogs,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                if (!_isSearchMode) ...[
                  const SizedBox(width: 12),
                  _HeaderButton(
                    icon: Icons.search_rounded,
                    onTap: _toggleSearchMode,
                  ),
                  const SizedBox(width: 8),
                  _HeaderButton(
                    icon: Icons.group_add_rounded,
                    onTap: _showCreateGroupSheet,
                  ),
                ],
              ],
            ),
          ),
        ),

        if (_viewModel.isLoading && _viewModel.threads.isEmpty)
          SliverFillRemaining(child: _LoadingState(l10n: l10n))
        else if (_viewModel.error != null && _viewModel.threads.isEmpty)
          SliverFillRemaining(
            child: _ErrorState(
              error: _viewModel.error!,
              onRetry: _viewModel.loadThreads,
              l10n: l10n,
            ),
          )
        else ...[

          if (_isSearchMode && _viewModel.searchQuery.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 20, padding, 12),
                child: Text(
                  l10n.globalSearchCaps,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
            if (_viewModel.isSearching)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (_viewModel.searchResults.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      l10n.noOneFound,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final user = _viewModel.searchResults[index];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(padding, 0, padding, 8),
                      child: _UserSearchCard(
                        user: user,
                        onTap: () => _openUserChat(user),
                        l10n: l10n,
                      ),
                    );
                  },
                  childCount: _viewModel.searchResults.length,
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
                child: Container(
                  height: 1,
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
          ],

          if (_isSearchMode && _viewModel.searchQuery.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 12),
                child: Text(
                  l10n.foundChatsCaps,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),

          if (_viewModel.filteredThreads.isEmpty)
            SliverFillRemaining(child: _EmptyState(l10n: l10n))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final thread = _viewModel.filteredThreads[index];
                  final api = ApiService();
                  final isReSchoolBot = api.isCloudEnabled &&
                      api.serverThreadId != null &&
                      thread.threadId == api.serverThreadId;

                  final partnerId = thread.imgObjId ??
                      (thread.senderId != api.currentPrsId ? thread.senderId : null);

                  final isVerifiedUser = !isReSchoolBot &&
                      partnerId != null &&
                      _viewModel.verifiedIds.contains(partnerId);

                  final isSelected = _selectedThread?.threadId == thread.threadId;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, 10),
                    child: _ChatCard(
                      thread: thread,
                      isReSchoolBot: isReSchoolBot,
                      isVerifiedUser: isVerifiedUser,
                      isSelected: isSelected,
                      onTap: () => _openChat(thread, isReSchoolBot),
                      l10n: l10n,
                    ),
                  );
                },
                childCount: _viewModel.filteredThreads.length,
              ),
            ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

class _EmptyDetailPlaceholder extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyDetailPlaceholder({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.selectChat,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.selectChatPrompt,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? colorScheme.onSurface.withValues(alpha: 0.05)
          : colorScheme.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final AppLocalizations l10n;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.search_rounded,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              style: GoogleFonts.inter(
                fontSize: 16,
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchPlaceholder,
                hintStyle: GoogleFonts.inter(
                  fontSize: 16,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.close_rounded,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ChatCard extends StatelessWidget {
  final ChatThread thread;
  final bool isReSchoolBot;
  final bool isVerifiedUser;
  final bool isSelected;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  const _ChatCard({
    required this.thread,
    this.isReSchoolBot = false,
    this.isVerifiedUser = false,
    this.isSelected = false,
    required this.onTap,
    required this.l10n,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return DateFormat('HH:mm', l10n.locale.languageCode).format(date);
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      return l10n.yesterday;
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('EE', l10n.locale.languageCode).format(date);
    } else {
      return DateFormat('dd.MM', l10n.locale.languageCode).format(date);
    }
  }

  String _cleanPreview(String? preview) {
    if (preview == null) return '';
    return preview
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('\n', ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.1)
          : isDark
              ? colorScheme.onSurface.withValues(alpha: 0.03)
              : colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [

              if (isReSchoolBot)
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    image: const DecorationImage(
                      image: AssetImage('assets/icon.jpg'),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                )
              else
                AuthenticatedAvatar(
                  imageId: thread.imageId,
                  imgObjType: thread.imgObjType,
                  imgObjId: thread.imgObjId,
                  fallbackText: thread.senderFio ?? thread.title,
                  isGroup: thread.isGroup,
                  size: 52,
                  borderRadius: 14,
                ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      children: [
                        if (thread.isGroup)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.group_rounded,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  isReSchoolBot ? 'reSchool' : thread.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isReSchoolBot) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                              ],
                              if (isVerifiedUser) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    're',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(thread.sendDateTime),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    Text(
                      _cleanPreview(thread.msgPreview),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isDesktop(context)) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UserSearchCard extends StatelessWidget {
  final UserSearchItem user;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  const _UserSearchCard({required this.user, required this.onTap, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? colorScheme.onSurface.withValues(alpha: 0.03)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              AuthenticatedAvatar(
                imageId: user.imageId,
                imgObjType: 'USER_PICTURE',
                imgObjId: user.prsId,
                fallbackText: user.fio ?? '?',
                size: 44,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fio ?? l10n.noName,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (user.groupName != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              user.groupName!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (user.positionName != null)
                          Expanded(
                            child: Text(
                              user.positionName!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
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
    );
  }
}

class _LoadingState extends StatelessWidget {
  final AppLocalizations l10n;
  const _LoadingState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.loadingMessages,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final AppLocalizations l10n;

  const _ErrorState({required this.error, required this.onRetry, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.loadingError,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Material(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onRetry();
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: colorScheme.onPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.retry,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimary,
                        ),
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
}

class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noMessages,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.startChatting,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateGroupSheet extends StatefulWidget {
  final void Function(int threadId, String subject) onCreated;

  const _CreateGroupSheet({required this.onCreated});

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ChatsViewModel _viewModel = ChatsViewModel();
  final List<UserSearchItem> _selectedUsers = [];
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleUser(UserSearchItem user) {
    HapticFeedback.selectionClick();
    setState(() {
      final index = _selectedUsers.indexWhere((u) => u.prsId == user.prsId);
      if (index >= 0) {
        _selectedUsers.removeAt(index);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  void _createGroup() async {
    if (_subjectController.text.isEmpty || _selectedUsers.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() => _isCreating = true);

    final threadId = await _viewModel.createGroupChat(
      _subjectController.text,
      _selectedUsers,
    );

    if (threadId != null && mounted) {
      widget.onCreated(threadId, _subjectController.text);
    } else {
      setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: isDesktop(context) ? 500 : double.infinity,
          ),
          margin: isDesktop(context)
              ? const EdgeInsets.symmetric(horizontal: 24)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: isDesktop(context)
                ? BorderRadius.circular(24)
                : const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Material(
                      color: isDark
                          ? colorScheme.onSurface.withValues(alpha: 0.05)
                          : colorScheme.onSurface.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.close_rounded,
                            color: colorScheme.onSurface,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        l10n.newGroup,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Material(
                      color: (_subjectController.text.isNotEmpty &&
                              _selectedUsers.isNotEmpty &&
                              !_isCreating)
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: (_subjectController.text.isNotEmpty &&
                                _selectedUsers.isNotEmpty &&
                                !_isCreating)
                            ? _createGroup
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: _isCreating
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : Text(
                                  l10n.create,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: (_subjectController.text.isNotEmpty &&
                                            _selectedUsers.isNotEmpty)
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurface.withValues(alpha: 0.3),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (MediaQuery.of(context).viewInsets.bottom > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        onPressed: () => FocusScope.of(context).unfocus(),
                      ),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.onSurface.withValues(alpha: 0.05)
                        : colorScheme.onSurface.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _subjectController,
                    style: GoogleFonts.inter(fontSize: 16),
                    textInputAction: TextInputAction.done,
                    onEditingComplete: () => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: l10n.groupName,
                      hintStyle: GoogleFonts.inter(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),

              if (_selectedUsers.isNotEmpty)
                Container(
                  height: 48,
                  margin: const EdgeInsets.only(top: 16),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _selectedUsers.length,
                    itemBuilder: (context, index) {
                      final user = _selectedUsers[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                user.fio ?? '',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _toggleUser(user),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.onSurface.withValues(alpha: 0.05)
                        : colorScheme.onSurface.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.inter(fontSize: 16),
                    textInputAction: TextInputAction.search,
                    onEditingComplete: () => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: l10n.searchParticipants,
                      hintStyle: GoogleFonts.inter(
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: _viewModel.searchUsers,
                  ),
                ),
              ),

              Expanded(
                child: _viewModel.isSearching
                    ? Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _viewModel.searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _viewModel.searchResults[index];
                          final isSelected = _selectedUsers.any(
                            (u) => u.prsId == user.prsId,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: isDark
                                  ? colorScheme.onSurface.withValues(alpha: 0.03)
                                  : colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () => _toggleUser(user),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? colorScheme.primary.withValues(alpha: 0.5)
                                          : colorScheme.onSurface.withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      AuthenticatedAvatar(
                                        imageId: user.imageId,
                                        imgObjType: 'USER_PICTURE',
                                        imgObjId: user.prsId,
                                        fallbackText: user.fio ?? '?',
                                        size: 40,
                                        borderRadius: 10,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          user.fio ?? '',
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.primary
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isSelected
                                                ? colorScheme.primary
                                                : colorScheme.onSurface.withValues(alpha: 0.2),
                                            width: 2,
                                          ),
                                        ),
                                        child: isSelected
                                            ? Icon(
                                                Icons.check_rounded,
                                                size: 16,
                                                color: colorScheme.onPrimary,
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}