import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../models/chat_models.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_card.dart';
import 'chat_search_screen.dart';
import 'chat_media_screen.dart';
import '../services/api_service.dart';
import '../viewmodels/chats_viewmodel.dart';
import '../widgets/avatar_widget.dart';
import '../utils/app_font.dart';

class ChatDetailScreen extends StatefulWidget {
  final int threadId;
  final String title;
  final bool isGroup;
  final int? imageId;
  final String? imgObjType;
  final int? imgObjId;
  final bool embedded;
  final VoidCallback? onBack;
  final ChatSearchHit? searchHit;

  const ChatDetailScreen({
    super.key,
    required this.threadId,
    required this.title,
    required this.isGroup,
    this.imageId,
    this.imgObjType,
    this.imgObjId,
    this.embedded = false,
    this.onBack,
    this.searchHit,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with SingleTickerProviderStateMixin {
  late final ChatDetailViewModel _viewModel;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final List<UploadFile> _pendingFiles = [];
  ChatSearchHit? _searchHit;
  int _matchIndex = 0;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();

    _viewModel = ChatDetailViewModel(
      threadId: widget.threadId,
      title: widget.title,
      isGroup: widget.isGroup,
    );
    _viewModel.addListener(_onViewModelChanged);
    _searchHit = widget.searchHit;
    _loadInitialMessages();
    _viewModel.loadPermissions();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadInitialMessages() async {
    final numbers = _searchHit?.messageNumbers ?? [];
    await _viewModel.loadMessages(
      aroundMessage: numbers.isEmpty ? null : numbers[_matchIndex],
      matches: numbers.isEmpty ? null : numbers,
      searchText: _searchHit?.query,
    );
    if (mounted) _scrollToBottom();
  }

  Future<void> _loadOlder() async {
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    await _viewModel.loadOlder();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        (oldOffset + position.maxScrollExtent - oldExtent).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> _openSearch() async {
    final hit = await Navigator.push<ChatSearchHit>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatSearchScreen(threadId: widget.threadId),
      ),
    );
    if (hit == null || !mounted) return;
    setState(() {
      _searchHit = hit;
      _matchIndex = 0;
    });
    await _loadInitialMessages();
  }

  void _showMedia() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatMediaScreen(threadId: widget.threadId, title: widget.title),
      ),
    );
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (_viewModel.isSending || (text.isEmpty && _pendingFiles.isEmpty)) return;
    HapticFeedback.lightImpact();
    final filesToSend = List<UploadFile>.from(_pendingFiles);
    final originalInput = _messageController.text;
    final success = await _viewModel.sendMessage(
      text,
      files: filesToSend.isEmpty ? null : filesToSend,
    );
    if (!mounted) return;
    if (success) {
      if (_messageController.text == originalInput) _messageController.clear();
      setState(() {
        _pendingFiles.removeWhere(filesToSend.contains);
        _searchHit = null;
      });
      _scrollToBottom();
    } else {
      _showSnackBar(
        AppLocalizations.of(context)!.sendMessageError,
        isError: true,
      );
    }
  }

  Future<void> _messageActions(ChatMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.messageCopy, style: appFont(context)),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (_viewModel.canModify(message)) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.editMessage, style: appFont(context)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  l10n.deleteMessage,
                  style: appFont(context, color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ] else if (_viewModel.isMessageMine(message) &&
                (_viewModel.permissionsFailed ||
                    _viewModel.isLoadingPermissions))
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: Text(l10n.chatPermissionsError, style: appFont(context)),
                subtitle: Text(l10n.retry, style: appFont(context)),
                onTap: () => Navigator.pop(context, 'permissions'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') _copyMessage(message);
    if (action == 'permissions') {
      await _viewModel.loadPermissions();
      if (mounted) _messageActions(message);
      return;
    }
    if (action == 'edit') {
      await _editMessage(message);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deleteMessage, style: appFont(context)),
          content: Text(l10n.deleteMessageWarning, style: appFont(context)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel, style: appFont(context)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.deleteMessage, style: appFont(context)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final success = await _viewModel.deleteMessage(message);
      if (!success && mounted) {
        _showSnackBar(l10n.messageDeleteError, isError: true);
      }
    }
  }

  Future<void> _editMessage(ChatMessage message) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MessageEditDialog(
      initialText: message.cleanMsg,
      onSave: (text) => _viewModel.editMessage(message, text),
    ),
  );

  Future<void> _pickPhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';

        setState(() {
          _pendingFiles.add(
            UploadFile(data: bytes, name: image.name, mimeType: mimeType),
          );
        });
      }
    } catch (e) {
      _showSnackBar('Ошибка выбора фото', isError: true);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);

      if (result.isNotEmpty) {
        for (final file in result) {
          if (file.path != null) {
            final bytes = await File(file.path!).readAsBytes();
            if (!mounted) return;
            final mimeType =
                lookupMimeType(file.path!) ?? 'application/octet-stream';

            setState(() {
              _pendingFiles.add(
                UploadFile(data: bytes, name: file.name, mimeType: mimeType),
              );
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Ошибка выбора файла', isError: true);
    }
  }

  void _removePendingFile(int index) {
    HapticFeedback.selectionClick();
    setState(() => _pendingFiles.removeAt(index));
  }

  Future<void> _downloadAttachment(
    int msgId,
    int fileId,
    String fileName,
  ) async {
    try {
      _showSnackBar('Загрузка файла...');
      final file = await ApiService().downloadXFile(
        ApiService().getAttachmentUrl(msgId, fileId),
        fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (kIsWeb) {
          await file.saveTo(file.name);
          return;
        }
        _showSnackBar(
          'Файл сохранен',
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => OpenFilex.open(file.path),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSnackBar('Ошибка загрузки', isError: true);
      }
    }
  }

  Future<void> _shareAttachment(int msgId, int fileId, String fileName) async {
    try {
      _showSnackBar('Подготовка файла...');
      final file = await ApiService().downloadXFile(
        ApiService().getAttachmentUrl(msgId, fileId),
        fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await SharePlus.instance.share(
          ShareParams(files: [file], text: fileName),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSnackBar('Ошибка', isError: true);
      }
    }
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    SnackBarAction? action,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: appFont(context, fontWeight: FontWeight.w500)),
        backgroundColor: isError
            ? colorScheme.error
            : colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        action: action,
        duration: Duration(seconds: action != null ? 4 : 2),
      ),
    );
  }

  void _copyMessage(ChatMessage message) {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: message.cleanMsg));
    _showSnackBar('Сообщение скопировано');
  }

  void _showLeaveDialog() {
    HapticFeedback.selectionClick();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Покинуть чат?',
            style: appFont(context, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          content: Text(
            'Вы уверены, что хотите покинуть этот чат?',
            style: appFont(context, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Отмена',
                style: appFont(context, fontWeight: FontWeight.w500),
              ),
            ),
            Material(
              color: colorScheme.error,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  _viewModel.leaveChat().then((_) {
                    if (mounted) navigator.pop();
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    'Покинуть',
                    style: appFont(context,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onError,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserProfile(int prsId) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _UserProfileSheet(
        prsId: prsId,
        imageId: widget.imageId,
        imgObjType: widget.imgObjType,
        title: widget.title,
      ),
    );
  }

  void _showAttachmentOptions() {
    HapticFeedback.selectionClick();
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // полоска для перетаскивания
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // заголовок
              Text(
                'Прикрепить',
                style: appFont(ctx,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),

              // список действий
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _AttachOptionTile(
                      icon: Icons.image_rounded,
                      label: 'Фото',
                      color: const Color(0xFF3B82F6),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickPhoto();
                      },
                    ),
                    const SizedBox(height: 10),
                    _AttachOptionTile(
                      icon: Icons.insert_drive_file_rounded,
                      label: 'Файл',
                      color: const Color(0xFFF59E0B),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickFile();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Widget _buildKeyboardDoneButton() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
    );
  }

  Widget _historyButton({required bool older}) {
    final l10n = AppLocalizations.of(context)!;
    final loading = older
        ? _viewModel.isLoadingOlder
        : _viewModel.isLoadingNewer;
    final error = older ? _viewModel.olderError : _viewModel.newerError;
    final hasMore = older ? _viewModel.hasOlder : _viewModel.hasNewer;
    if (!loading && !hasMore && error == null) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: Center(
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: older ? _loadOlder : _viewModel.loadNewer,
                icon: Icon(
                  error != null
                      ? Icons.refresh_rounded
                      : older
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  error != null
                      ? '${l10n.chatMoreError}. ${l10n.retry}'
                      : older
                      ? l10n.olderMessages
                      : l10n.loadMore, style: appFont(context),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final partnerPrsId = _viewModel.resolvePartnerPrsId(
      threadPrsId: widget.imgObjId,
    );

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              // своя шапка вместо AppBar
              _ChatAppBar(
                title: widget.title,
                isGroup: widget.isGroup,
                imageId: widget.imageId,
                imgObjType: widget.imgObjType,
                imgObjId: widget.imgObjId,
                embedded: widget.embedded,
                onBack: widget.embedded
                    ? widget.onBack ?? () {}
                    : () => Navigator.pop(context),
                onLeave: widget.isGroup ? _showLeaveDialog : null,
                onSearch: _openSearch,
                onMedia: _showMedia,
                onRefresh: () {
                  _viewModel.loadNewer();
                  _viewModel.loadPermissions();
                },
                onTapProfile: partnerPrsId != null
                    ? () => _showUserProfile(partnerPrsId)
                    : null,
              ),

              if (_searchHit != null && _searchHit!.messageNumbers.isNotEmpty)
                Container(
                  color: appCardFill(context),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_matchIndex + 1} / ${_searchHit!.messageNumbers.length}',
                          style: appFont(context),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.previousMatch,
                        onPressed:
                            _viewModel.isLoading ||
                                _matchIndex + 1 >=
                                    _searchHit!.messageNumbers.length
                            ? null
                            : () {
                                setState(() => _matchIndex++);
                                _loadInitialMessages();
                              },
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      IconButton(
                        tooltip: l10n.nextMatch,
                        onPressed: _viewModel.isLoading || _matchIndex == 0
                            ? null
                            : () {
                                setState(() => _matchIndex--);
                                _loadInitialMessages();
                              },
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      IconButton(
                        tooltip: l10n.searchExit,
                        onPressed: () {
                          setState(() => _searchHit = null);
                          _loadInitialMessages();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              if (_viewModel.isModifying)
                const LinearProgressIndicator(minHeight: 2),

              // сообщения
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _viewModel.isLoading
                      ? const _LoadingState()
                      : _viewModel.error != null
                      ? _ErrorState(
                          error: l10n.chatLoadError,
                          onRetry: _loadInitialMessages,
                        )
                      : _viewModel.messages.isEmpty
                      ? const _EmptyMessagesState()
                      : ListView.builder(
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _viewModel.messages.length + 2,
                          itemBuilder: (context, row) {
                            if (row == 0) return _historyButton(older: true);
                            if (row == _viewModel.messages.length + 1) {
                              return _historyButton(older: false);
                            }
                            final index = row - 1;
                            final message = _viewModel.messages[index];
                            final isMe = _viewModel.isMessageMine(message);
                            final isFirstInSeq = _viewModel.isFirstInSequence(
                              index,
                            );

                            return _MessageBubble(
                              key: ValueKey(message.id),
                              highlighted:
                                  _searchHit?.messageNumbers.elementAtOrNull(
                                        _matchIndex,
                                      ) ==
                                      message.msgNum &&
                                  message.msgNum != null,
                              message: message,
                              isMe: isMe,
                              isFirstInSequence: isFirstInSeq,
                              isGroup: widget.isGroup,
                              partnerImageId: widget.imageId,
                              partnerImgObjType: widget.imgObjType,
                              partnerImgObjId: widget.imgObjId,
                              onLongPress: () => _messageActions(message),
                              onDownloadAttachment: (fileId, fileName) =>
                                  _downloadAttachment(
                                    message.msgId ?? 0,
                                    fileId,
                                    fileName,
                                  ),
                              onShareAttachment: (fileId, fileName) =>
                                  _shareAttachment(
                                    message.msgId ?? 0,
                                    fileId,
                                    fileName,
                                  ),
                            );
                          },
                        ),
                ),
              ),

              _buildKeyboardDoneButton(),

              // файлы, ждущие отправки
              if (_pendingFiles.isNotEmpty)
                _PendingFilesBar(
                  files: _pendingFiles,
                  onRemove: _removePendingFile,
                ),

              // строка ввода
              if (_viewModel.permissions?.canWrite == false)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    l10n.chatReadOnly,
                    textAlign: TextAlign.center,
                    style: appFont(context, color: colorScheme.onSurfaceVariant),
                  ),
                )
              else
                _MessageInputBar(
                  controller: _messageController,
                  focusNode: _messageFocusNode,
                  isSending: _viewModel.isSending,
                  onSend: _sendMessage,
                  onAttach: () {
                    if (!_viewModel.isSending) _showAttachmentOptions();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// шапка чата
class _ChatAppBar extends StatelessWidget {
  final String title;
  final bool isGroup;
  final int? imageId;
  final String? imgObjType;
  final int? imgObjId;
  final bool embedded;
  final VoidCallback onBack;
  final VoidCallback? onLeave;
  final VoidCallback? onTapProfile;
  final VoidCallback onSearch;
  final VoidCallback onMedia;
  final VoidCallback onRefresh;

  const _ChatAppBar({
    required this.title,
    required this.isGroup,
    this.imageId,
    this.imgObjType,
    this.imgObjId,
    this.embedded = false,
    required this.onBack,
    this.onLeave,
    this.onTapProfile,
    required this.onSearch,
    required this.onMedia,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          // кнопка назад, на десктопе внутри панели она не нужна
          if (!embedded)
            Material(
              color: isDark
                  ? colorScheme.onSurface.withValues(alpha: 0.05)
                  : colorScheme.onSurface.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onBack();
                },
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: colorScheme.onSurface,
                    size: 22,
                  ),
                ),
              ),
            ),
          if (!embedded) const SizedBox(width: 12),
          if (embedded) const SizedBox(width: 8),

          // аватар и название, у личных чатов по нажатию открывается профиль
          Expanded(
            child: GestureDetector(
              onTap: (!isGroup && onTapProfile != null) ? onTapProfile : null,
              child: Row(
                children: [
                  AuthenticatedAvatar(
                    imageId: imageId,
                    imgObjType: imgObjType,
                    imgObjId: imgObjId,
                    fallbackText: title,
                    isGroup: isGroup,
                    size: 44,
                    borderRadius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: appFont(context,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isGroup)
                          Text(
                            'Группа',
                            style: appFont(context,
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // меню
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (value) {
              if (value == 'leave') onLeave?.call();
              if (value == 'search') onSearch();
              if (value == 'media') onMedia();
              if (value == 'refresh') onRefresh();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'search',
                child: Text(AppLocalizations.of(context)!.searchMessages, style: appFont(context)),
              ),
              PopupMenuItem(
                value: 'media',
                child: Text(AppLocalizations.of(context)!.chatAttachments, style: appFont(context)),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Text(AppLocalizations.of(context)!.refreshContent, style: appFont(context)),
              ),
              if (isGroup && onLeave != null)
                PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app_rounded, color: colorScheme.error),
                      const SizedBox(width: 12),
                      Text(
                        'Покинуть чат',
                        style: appFont(context,
                          color: colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// пузырь сообщения
class _MessageBubble extends StatelessWidget {
  final bool highlighted;
  final ChatMessage message;
  final bool isMe;
  final bool isFirstInSequence;
  final bool isGroup;
  final int? partnerImageId;
  final String? partnerImgObjType;
  final int? partnerImgObjId;
  final VoidCallback onLongPress;
  final Function(int fileId, String fileName) onDownloadAttachment;
  final Function(int fileId, String fileName) onShareAttachment;

  const _MessageBubble({
    super.key,
    this.highlighted = false,
    required this.message,
    required this.isMe,
    required this.isFirstInSequence,
    required this.isGroup,
    this.partnerImageId,
    this.partnerImgObjType,
    this.partnerImgObjId,
    required this.onLongPress,
    required this.onDownloadAttachment,
    required this.onShareAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final myBubbleColor = colorScheme.primary;
    final myTextColor = colorScheme.onPrimary;
    final otherBubbleColor = isDark
        ? colorScheme.onSurface.withValues(alpha: 0.08)
        : colorScheme.onSurface.withValues(alpha: 0.05);

    final avatarImgObjType = isGroup
        ? 'USER_PICTURE'
        : (partnerImgObjType ?? 'USER_PICTURE');
    final avatarImgObjId = isGroup
        ? message.senderId
        : (partnerImgObjId ?? message.senderId);

    return Padding(
      padding: EdgeInsets.only(
        top: isFirstInSequence ? 12 : 2,
        bottom: 2,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // аватар собеседника
          if (!isMe)
            SizedBox(
              width: 32,
              child: isFirstInSequence
                  ? AuthenticatedAvatar(
                      imageId: isGroup ? null : partnerImageId,
                      imgObjType: avatarImgObjType,
                      imgObjId: avatarImgObjId,
                      fallbackText: message.senderFio ?? '?',
                      size: 28,
                      borderRadius: 8,
                    )
                  : null,
            ),
          if (!isMe) const SizedBox(width: 8),

          // сам пузырь
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // имя отправителя, нужно только в группах
                if (!isMe && isFirstInSequence && isGroup)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      message.senderFio ?? 'Неизвестный',
                      style: appFont(context,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),

                // пузырь
                GestureDetector(
                  onLongPress: onLongPress,
                  onSecondaryTap: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? myBubbleColor : otherBubbleColor,
                      border: highlighted
                          ? Border.all(color: colorScheme.tertiary, width: 2)
                          : null,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(
                          isMe ? 18 : (isFirstInSequence ? 4 : 18),
                        ),
                        bottomRight: Radius.circular(
                          isMe ? (isFirstInSequence ? 4 : 18) : 18,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // вложения
                          if (message.attachInfo != null &&
                              message.attachInfo!.isNotEmpty)
                            ...message.attachInfo!.map(
                              (attach) => _AttachmentChip(
                                attachment: attach,
                                isMe: isMe,
                                onDownload: () {
                                  if (attach.fileId != null) {
                                    onDownloadAttachment(
                                      attach.fileId!,
                                      attach.fileName ?? 'file',
                                    );
                                  }
                                },
                                onShare: () {
                                  if (attach.fileId != null) {
                                    onShareAttachment(
                                      attach.fileId!,
                                      attach.fileName ?? 'file',
                                    );
                                  }
                                },
                              ),
                            ),

                          // текст
                          if (message.cleanMsg.isNotEmpty)
                            Text(
                              message.cleanMsg,
                              style: appFont(context,
                                fontSize: 15,
                                height: 1.4,
                                color: isMe
                                    ? myTextColor
                                    : colorScheme.onSurface,
                              ),
                            ),
                          const SizedBox(height: 4),

                          // время
                          Text(
                            '${DateFormat('dd.MM · HH:mm').format(message.createDateTime)}${message.editDate != null ? ' · ${AppLocalizations.of(context)!.messageEdited}' : ''}',
                            style: appFont(context,
                              fontSize: 11,
                              color: isMe
                                  ? myTextColor.withValues(alpha: 0.7)
                                  : colorScheme.onSurface.withValues(
                                      alpha: 0.4,
                                    ),
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
        ],
      ),
    );
  }
}

// чип вложения
class _AttachmentChip extends StatelessWidget {
  final AttachInfo attachment;
  final bool isMe;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const _AttachmentChip({
    required this.attachment,
    required this.isMe,
    required this.onDownload,
    required this.onShare,
  });

  IconData _getIcon() {
    final type = attachment.fileType?.toLowerCase() ?? '';
    if (type.contains('image')) return Icons.image_rounded;
    if (type.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (type.contains('zip') || type.contains('rar')) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: 22,
            color: isMe ? Colors.white : colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName ?? 'Файл',
                  style: appFont(context,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isMe ? Colors.white : colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (attachment.fileSize != null)
                  Text(
                    attachment.formattedSize,
                    style: appFont(context,
                      fontSize: 11,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onShare();
            },
            child: Icon(
              Icons.share_outlined,
              size: 18,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.8)
                  : colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onDownload();
            },
            child: Icon(
              Icons.download_rounded,
              size: 20,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.8)
                  : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// строка ввода сообщения
class _MessageInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  const _MessageInputBar({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          // кнопка вложения
          Material(
            color: isDark
                ? colorScheme.onSurface.withValues(alpha: 0.05)
                : colorScheme.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onAttach,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.add_rounded,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // поле ввода
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.onSurface.withValues(alpha: 0.05)
                    : colorScheme.onSurface.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: appFont(context, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  hintStyle: appFont(context,
                    fontSize: 15,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // кнопка отправки
          Material(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: isSending ? null : onSend,
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 44,
                height: 44,
                child: isSending
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: colorScheme.onPrimary,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// панель с файлами на отправку
class _PendingFilesBar extends StatelessWidget {
  final List<UploadFile> files;
  final Function(int) onRemove;

  const _PendingFilesBar({required this.files, required this.onRemove});

  IconData _getIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_rounded;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mimeType.contains('zip') || mimeType.contains('rar')) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.05)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(files.length, (index) {
            final file = files[index];
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getIcon(file.mimeType),
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          file.name,
                          style: appFont(context,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatSize(file.size),
                        style: appFont(context,
                          fontSize: 10,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => onRemove(index),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// пункт меню вложений
class _AttachOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachOptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? colorScheme.onSurface.withValues(alpha: 0.05)
          : colorScheme.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: appFont(context,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// состояние загрузки
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

// состояние ошибки
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
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: appFont(context,
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Text(
                    'Повторить',
                    style: appFont(context,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimary,
                    ),
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

// пустой чат
class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState();

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
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Нет сообщений',
              style: appFont(context,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Начните диалог!',
              style: appFont(context,
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// карточка профиля пользователя
class _UserProfileSheet extends StatefulWidget {
  final int prsId;
  final int? imageId;
  final String? imgObjType;
  final String title;

  const _UserProfileSheet({
    required this.prsId,
    this.imageId,
    this.imgObjType,
    required this.title,
  });

  @override
  State<_UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<_UserProfileSheet> {
  ShortProfile? _profile;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService().getShortProfile(widget.prsId);
      if (mounted) {
        setState(() {
          _profile = ShortProfile.fromJson(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatBirthDate(DateTime? date) {
    if (date == null) return '';
    final months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // полоска для перетаскивания
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 24,
                ),
                child: Text(
                  'Не удалось загрузить профиль',
                  textAlign: TextAlign.center,
                  style: appFont(context,
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              )
            else ...[
              // аватар
              AuthenticatedAvatar(
                imageId: widget.imageId,
                imgObjType: widget.imgObjType,
                imgObjId: widget.prsId,
                fallbackText: _profile?.fullName ?? widget.title,
                size: 80,
                borderRadius: 22,
              ),
              const SizedBox(height: 16),

              // полное имя
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _profile?.fullName ?? widget.title,
                  textAlign: TextAlign.center,
                  style: appFont(context,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),

              // дата рождения
              if (_profile?.birthDate != null) ...[
                const SizedBox(height: 6),
                Text(
                  _formatBirthDate(_profile!.birthDate),
                  style: appFont(context,
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],

              // про учителя
              if (_profile?.teachers != null &&
                  _profile!.teachers!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: _profile!.teachers!.map((t) {
                      if (t.isClassTeacher && t.groupName != null) {
                        return _ProfileInfoRow(
                          icon: Icons.class_rounded,
                          label: 'Классный руководитель',
                          value: t.groupName!,
                          colorScheme: colorScheme,
                          isDark: isDark,
                        );
                      } else if (t.discips != null && t.discips!.isNotEmpty) {
                        return _ProfileInfoRow(
                          icon: Icons.school_rounded,
                          label: 'Предметы',
                          value: t.discips!.join(', '),
                          colorScheme: colorScheme,
                          isDark: isDark,
                        );
                      }
                      return const SizedBox.shrink();
                    }).toList(),
                  ),
                ),
              ],

              // идентификатор PRS
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _ProfileInfoRow(
                  icon: Icons.badge_rounded,
                  label: 'PRS ID',
                  value: widget.prsId.toString(),
                  colorScheme: colorScheme,
                  isDark: isDark,
                ),
              ),

              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final bool isDark;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.07),
        ),
      ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: appFont(context,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface.withValues(alpha: 0.45),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: appFont(context,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageEditDialog extends StatefulWidget {
  final String initialText;
  final Future<bool> Function(String) onSave;
  const _MessageEditDialog({required this.initialText, required this.onSave});

  @override
  State<_MessageEditDialog> createState() => _MessageEditDialogState();
}

class _MessageEditDialogState extends State<_MessageEditDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    final success = await widget.onSave(_controller.text.trim());
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = l10n.messageEditError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(l10n.editMessage, style: appFont(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 8,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: appFieldFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: appFont(context, 
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(l10n.cancel, style: appFont(context)),
          ),
          FilledButton(
            onPressed: _saving || _controller.text.trim().isEmpty
                ? null
                : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save, style: appFont(context)),
          ),
        ],
      ),
    );
  }
}
