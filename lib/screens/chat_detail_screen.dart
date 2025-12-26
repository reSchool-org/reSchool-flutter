import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/chat_models.dart';
import '../viewmodels/chats_viewmodel.dart';
import '../widgets/avatar_widget.dart';

class ChatDetailScreen extends StatefulWidget {
  final int threadId;
  final String title;
  final bool isGroup;
  final int? imageId;
  final String? imgObjType;
  final int? imgObjId;
  final bool embedded;
  final VoidCallback? onBack;

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
  List<UploadFile> _pendingFiles = [];

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
    _viewModel.loadMessages();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _viewModel.removeListener(_onViewModelChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
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

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingFiles.isEmpty) return;

    HapticFeedback.lightImpact();
    final filesToSend = List<UploadFile>.from(_pendingFiles);
    _messageController.clear();
    setState(() => _pendingFiles = []);

    final success = await _viewModel.sendMessage(
      text,
      files: filesToSend.isNotEmpty ? filesToSend : null,
    );
    if (success) _scrollToBottom();
  }

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
          _pendingFiles.add(UploadFile(
            data: bytes,
            name: image.name,
            mimeType: mimeType,
          ));
        });
      }
    } catch (e) {
      _showSnackBar('Ошибка выбора фото', isError: true);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          if (file.path != null) {
            final bytes = await File(file.path!).readAsBytes();
            final mimeType = lookupMimeType(file.path!) ?? 'application/octet-stream';

            setState(() {
              _pendingFiles.add(UploadFile(
                data: bytes,
                name: file.name,
                mimeType: mimeType,
              ));
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

  Future<void> _downloadAttachment(int msgId, int fileId, String fileName) async {
    try {
      _showSnackBar('Загрузка файла...');
      final file = await _viewModel.downloadAttachment(msgId, fileId, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
      final file = await _viewModel.downloadAttachment(msgId, fileId, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await Share.shareXFiles([XFile(file.path)], text: fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSnackBar('Ошибка', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false, SnackBarAction? action}) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? colorScheme.error : colorScheme.inverseSurface,
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
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Вы уверены, что хотите покинуть этот чат?',
            style: GoogleFonts.inter(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Отмена',
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
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
                    style: GoogleFonts.inter(
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

              Text(
                'Прикрепить',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [

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
                  ),

                  Expanded(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: _viewModel.isLoading
                          ? const _LoadingState()
                          : _viewModel.error != null
                              ? _ErrorState(
                                  error: _viewModel.error!,
                                  onRetry: _viewModel.loadMessages,
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
                                      itemCount: _viewModel.messages.length,
                                      itemBuilder: (context, index) {
                                        final message = _viewModel.messages[index];
                                        final isMe = _viewModel.isMessageMine(message);
                                        final isFirstInSeq =
                                            _viewModel.isFirstInSequence(index);

                                        return _MessageBubble(
                                          message: message,
                                          isMe: isMe,
                                          isFirstInSequence: isFirstInSeq,
                                          isGroup: widget.isGroup,
                                          partnerImageId: widget.imageId,
                                          partnerImgObjType: widget.imgObjType,
                                          partnerImgObjId: widget.imgObjId,
                                          onLongPress: () => _copyMessage(message),
                                          onDownloadAttachment:
                                              (fileId, fileName) =>
                                                  _downloadAttachment(
                                            message.msgId ?? 0,
                                            fileId,
                                            fileName,
                                          ),
                                          onShareAttachment:
                                              (fileId, fileName) =>
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

                  if (_pendingFiles.isNotEmpty)
                    _PendingFilesBar(
                      files: _pendingFiles,
                      onRemove: _removePendingFile,
                    ),

                  _MessageInputBar(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    isSending: _viewModel.isSending,
                    onSend: _sendMessage,
                    onAttach: _showAttachmentOptions,
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget {
  final String title;
  final bool isGroup;
  final int? imageId;
  final String? imgObjType;
  final int? imgObjId;
  final bool embedded;
  final VoidCallback onBack;
  final VoidCallback? onLeave;

  const _ChatAppBar({
    required this.title,
    required this.isGroup,
    this.imageId,
    this.imgObjType,
    this.imgObjId,
    this.embedded = false,
    required this.onBack,
    this.onLeave,
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
                  style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),

          if (isGroup && onLeave != null)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (value) {
                if (value == 'leave') onLeave!();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app_rounded, color: colorScheme.error),
                      const SizedBox(width: 12),
                      Text(
                        'Покинуть чат',
                        style: GoogleFonts.inter(
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

class _MessageBubble extends StatelessWidget {
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

    final avatarImgObjType = isGroup ? 'USER_PICTURE' : (partnerImgObjType ?? 'USER_PICTURE');
    final avatarImgObjId = isGroup ? message.senderId : (partnerImgObjId ?? message.senderId);

    return Padding(
      padding: EdgeInsets.only(
        top: isFirstInSequence ? 12 : 2,
        bottom: 2,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [

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

          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [

                if (!isMe && isFirstInSequence && isGroup)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      message.senderFio ?? 'Неизвестный',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),

                GestureDetector(
                  onLongPress: onLongPress,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? myBubbleColor : otherBubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : (isFirstInSequence ? 4 : 18)),
                        bottomRight: Radius.circular(isMe ? (isFirstInSequence ? 4 : 18) : 18),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          if (message.attachInfo != null && message.attachInfo!.isNotEmpty)
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

                          if (message.cleanMsg.isNotEmpty)
                            Text(
                              message.cleanMsg,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                height: 1.4,
                                color: isMe ? myTextColor : colorScheme.onSurface,
                              ),
                            ),
                          const SizedBox(height: 4),

                          Text(
                            DateFormat('HH:mm', 'ru').format(message.createDateTime),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isMe
                                  ? myTextColor.withValues(alpha: 0.7)
                                  : colorScheme.onSurface.withValues(alpha: 0.4),
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
    if (type.contains('zip') || type.contains('rar')) return Icons.folder_zip_rounded;
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
                  style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
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
              color: isMe ? Colors.white.withValues(alpha: 0.8) : colorScheme.primary,
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
              color: isMe ? Colors.white.withValues(alpha: 0.8) : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

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
          top: BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        children: [

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
                style: GoogleFonts.inter(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  hintStyle: GoogleFonts.inter(
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

class _PendingFilesBar extends StatelessWidget {
  final List<UploadFile> files;
  final Function(int) onRemove;

  const _PendingFilesBar({
    required this.files,
    required this.onRemove,
  });

  IconData _getIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_rounded;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mimeType.contains('zip') || mimeType.contains('rar')) return Icons.folder_zip_rounded;
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
          top: BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.05),
          ),
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
                          style: GoogleFonts.inter(
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
                        style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    'Повторить',
                    style: GoogleFonts.inter(
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
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Начните диалог!',
              style: GoogleFonts.inter(
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