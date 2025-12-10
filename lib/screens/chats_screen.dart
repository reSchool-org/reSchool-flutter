import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_models.dart';
import '../viewmodels/chats_viewmodel.dart';
import '../widgets/avatar_widget.dart';
import 'chat_detail_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final ChatsViewModel _viewModel = ChatsViewModel();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchMode = false;

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.loadThreads();
  }

  @override
  void dispose() {
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

  void _openChat(ChatThread thread) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          threadId: thread.threadId,
          title: thread.title,
          isGroup: thread.isGroup,
          imageId: thread.imageId,
          imgObjType: thread.imgObjType,
          imgObjId: thread.imgObjId,
        ),
      ),
    ).then((_) => _viewModel.loadThreads());
  }

  void _openUserChat(UserSearchItem user) async {
    final threadId = await _viewModel.openUserChat(user);
    if (threadId != null && mounted) {
      _toggleSearchMode();
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

  void _showCreateGroupSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreateGroupSheet(
        onCreated: (threadId, subject) {
          Navigator.pop(context);
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
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _viewModel.loadThreads,
        child: CustomScrollView(
          slivers: [
            
            SliverAppBar(
              title: _isSearchMode
                  ? TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      style: Theme.of(context).textTheme.titleLarge,
                      decoration: const InputDecoration(
                        hintText: 'Поиск чатов и людей...',
                        border: InputBorder.none,
                      ),
                    )
                  : const Text('Сообщения'),
              floating: true,
              snap: true,
              pinned: true,
              actions: [
                IconButton(
                  icon: Icon(_isSearchMode ? Icons.close : Icons.search),
                  onPressed: _toggleSearchMode,
                ),
                if (!_isSearchMode)
                  IconButton(
                    icon: const Icon(Icons.group_add_rounded),
                    onPressed: _showCreateGroupSheet,
                  ),
              ],
            ),

            if (_viewModel.isLoading && _viewModel.threads.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_viewModel.error != null && _viewModel.threads.isEmpty)
              SliverFillRemaining(
                child: _ErrorState(
                  error: _viewModel.error!,
                  onRetry: _viewModel.loadThreads,
                ),
              )
            else ...[
              
              if (_isSearchMode && _viewModel.searchQuery.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Глобальный поиск',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (_viewModel.isSearching)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_viewModel.searchResults.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'Никого не найдено',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final user = _viewModel.searchResults[index];
                        return _UserSearchTile(
                          user: user,
                          onTap: () => _openUserChat(user),
                        );
                      },
                      childCount: _viewModel.searchResults.length,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Divider(
                    height: 32,
                    indent: 16,
                    endIndent: 16,
                    color: colorScheme.outlineVariant,
                  ),
                ),
              ],

              if (_isSearchMode && _viewModel.searchQuery.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Найденные чаты',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              if (_viewModel.filteredThreads.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Нет чатов',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final thread = _viewModel.filteredThreads[index];
                      return _ChatTile(
                        thread: thread,
                        onTap: () => _openChat(thread),
                      );
                    },
                    childCount: _viewModel.filteredThreads.length,
                  ),
                ),
            ],

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatThread thread;
  final VoidCallback onTap;

  const _ChatTile({required this.thread, required this.onTap});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return DateFormat('HH:mm', 'ru').format(date);
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      return 'Вчера';
    } else if (now.difference(date).inDays < 7) {
      return DateFormat('EE', 'ru').format(date);
    } else {
      return DateFormat('dd.MM', 'ru').format(date);
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                
                AuthenticatedAvatar(
                  imageId: thread.imageId,
                  imgObjType: thread.imgObjType,
                  imgObjId: thread.imgObjId,
                  fallbackText: thread.senderFio ?? thread.title,
                  isGroup: thread.isGroup,
                  size: 56,
                  borderRadius: 16,
                ),
                const SizedBox(width: 12),
                
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
                            child: Text(
                              thread.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(thread.sendDateTime),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _cleanPreview(thread.msgPreview),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  final UserSearchItem user;
  final VoidCallback onTap;

  const _UserSearchTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AuthenticatedAvatar(
        imageId: user.imageId,
        imgObjType: 'USER_PICTURE',
        imgObjId: user.prsId,
        fallbackText: user.fio ?? '?',
        size: 48,
        borderRadius: 14,
      ),
      title: Text(
        user.fio ?? 'Без имени',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Row(
        children: [
          if (user.groupName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                user.groupName!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (user.positionName != null)
            Expanded(
              child: Text(
                user.positionName!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 16,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ошибка загрузки',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
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

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Text(
                  'Новая группа',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: (_subjectController.text.isNotEmpty &&
                          _selectedUsers.isNotEmpty &&
                          !_isCreating)
                      ? _createGroup
                      : null,
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Создать'),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: 'Название группы',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          
          if (_selectedUsers.isNotEmpty)
            Container(
              height: 50,
              margin: const EdgeInsets.only(top: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selectedUsers.length,
                itemBuilder: (context, index) {
                  final user = _selectedUsers[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(user.fio ?? ''),
                      onDeleted: () => _toggleUser(user),
                      deleteIcon: const Icon(Icons.close, size: 18),
                    ),
                  );
                },
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск участников...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _viewModel.searchUsers,
            ),
          ),
          
          Expanded(
            child: _viewModel.isSearching
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _viewModel.searchResults.length,
                    itemBuilder: (context, index) {
                      final user = _viewModel.searchResults[index];
                      final isSelected = _selectedUsers.any((u) => u.prsId == user.prsId);
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(user.fio?.substring(0, 1) ?? '?'),
                        ),
                        title: Text(user.fio ?? ''),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: colorScheme.primary)
                            : null,
                        onTap: () => _toggleUser(user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
