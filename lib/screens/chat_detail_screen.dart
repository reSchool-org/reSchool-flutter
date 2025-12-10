import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  const ChatDetailScreen({
    super.key,
    required this.threadId,
    required this.title,
    required this.isGroup,
    this.imageId,
    this.imgObjType,
    this.imgObjId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  late final ChatDetailViewModel _viewModel;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  List<UploadFile> _pendingFiles = [];

  @override
  void initState() {
    super.initState();
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

    final filesToSend = List<UploadFile>.from(_pendingFiles);
    _messageController.clear();
    setState(() {
      _pendingFiles = [];
    });

    final success = await _viewModel.sendMessage(text, files: filesToSend.isNotEmpty ? filesToSend : null);
    if (success) {
      _scrollToBottom();
    }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора фото: $e')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора файла: $e')),
        );
      }
    }
  }

  void _removePendingFile(int index) {
    setState(() {
      _pendingFiles.removeAt(index);
    });
  }

  Future<void> _downloadAttachment(int msgId, int fileId, String fileName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Загрузка файла...'),
          duration: Duration(seconds: 1),
        ),
      );

      final file = await _viewModel.downloadAttachment(msgId, fileId, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Файл сохранен: $fileName'),
            action: SnackBarAction(
              label: 'Открыть',
              onPressed: () async {
                await OpenFilex.open(file.path);
              },
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  Future<void> _shareAttachment(int msgId, int fileId, String fileName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Подготовка файла...'),
          duration: Duration(seconds: 1),
        ),
      );

      final file = await _viewModel.downloadAttachment(msgId, fileId, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: fileName));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _copyMessage(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.cleanMsg));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Сообщение скопировано'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showLeaveDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Покинуть чат?'),
        content: const Text('Вы уверены, что хотите покинуть этот чат?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              _viewModel.leaveChat().then((_) {
                if (mounted) navigator.pop();
              });
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Покинуть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AuthenticatedAvatar(
              imageId: widget.imageId,
              imgObjType: widget.imgObjType,
              imgObjId: widget.imgObjId,
              fallbackText: widget.title,
              isGroup: widget.isGroup,
              size: 40,
              borderRadius: 12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.isGroup)
                    Text(
                      'Группа',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (widget.isGroup)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'leave') {
                  _showLeaveDialog();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, color: colorScheme.error),
                      const SizedBox(width: 12),
                      Text(
                        'Покинуть чат',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          
          Expanded(
            child: _viewModel.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _viewModel.error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(_viewModel.error!),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _viewModel.loadMessages,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : _viewModel.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Нет сообщений',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Начните диалог!',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _viewModel.messages.length,
                    itemBuilder: (context, index) {
                      final message = _viewModel.messages[index];
                      final isMe = _viewModel.isMessageMine(message);
                      final isFirstInSeq = _viewModel.isFirstInSequence(index);

                      return _MessageBubble(
                        message: message,
                        isMe: isMe,
                        isFirstInSequence: isFirstInSeq,
                        isGroup: widget.isGroup,
                        partnerImageId: widget.imageId,
                        partnerImgObjType: widget.imgObjType,
                        partnerImgObjId: widget.imgObjId,
                        onLongPress: () => _copyMessage(message),
                        onDownloadAttachment: (fileId, fileName) => _downloadAttachment(
                          message.msgId ?? 0,
                          fileId,
                          fileName,
                        ),
                        onShareAttachment: (fileId, fileName) => _shareAttachment(
                          message.msgId ?? 0,
                          fileId,
                          fileName,
                        ),
                      );
                    },
                  ),
          ),
          
          if (_pendingFiles.isNotEmpty)
            _PendingFilesPreview(
              files: _pendingFiles,
              onRemove: _removePendingFile,
            ),
          
          _ChatInputBar(
            controller: _messageController,
            focusNode: _messageFocusNode,
            isSending: _viewModel.isSending,
            onSend: _sendMessage,
            onPickPhoto: _pickPhoto,
            onPickFile: _pickFile,
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

    final myMessageColor = isDark
        ? colorScheme.primaryContainer
        : colorScheme.primary;
    final myTextColor = isDark ? colorScheme.onPrimaryContainer : Colors.white;
    final myTimeColor = isDark
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.7);

    final avatarImageId = isGroup ? null : partnerImageId;
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
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          
          if (!isMe)
            SizedBox(
              width: 36,
              child: isFirstInSequence
                  ? AuthenticatedAvatar(
                      imageId: avatarImageId,
                      imgObjType: avatarImgObjType,
                      imgObjId: avatarImgObjId,
                      fallbackText: message.senderFio ?? '?',
                      size: 32,
                      borderRadius: 16, 
                    )
                  : null,
            ),
          if (!isMe) const SizedBox(width: 8),
          
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                
                if (!isMe && isFirstInSequence && isGroup)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                      message.senderFio ?? 'Неизвестный',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
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
                      color: isMe
                          ? myMessageColor
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(
                          isMe ? 20 : (isFirstInSequence ? 4 : 20),
                        ),
                        bottomRight: Radius.circular(
                          isMe ? (isFirstInSequence ? 4 : 20) : 20,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          
                          if (message.attachInfo != null &&
                              message.attachInfo!.isNotEmpty)
                            ...message.attachInfo!.map(
                              (attach) => _AttachmentWidget(
                                attachment: attach,
                                isMe: isMe,
                                msgId: message.msgId ?? 0,
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
                              style: TextStyle(
                                color: isMe
                                    ? myTextColor
                                    : colorScheme.onSurface,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          const SizedBox(height: 4),
                          
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat(
                                  'HH:mm',
                                  'ru',
                                ).format(message.createDateTime),
                                style: TextStyle(
                                  color: isMe
                                      ? myTimeColor
                                      : colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
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

class _AttachmentWidget extends StatelessWidget {
  final AttachInfo attachment;
  final bool isMe;
  final int msgId;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const _AttachmentWidget({
    required this.attachment,
    required this.isMe,
    required this.msgId,
    required this.onDownload,
    required this.onShare,
  });

  IconData _getIcon() {
    final type = attachment.fileType?.toLowerCase() ?? '';
    if (type.contains('image')) return Icons.image_rounded;
    if (type.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (type.contains('zip') || type.contains('rar')) {
      return Icons.archive_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = isMe ? Colors.white.withValues(alpha: 0.8) : colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.2)
            : colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: 24,
            color: isMe ? Colors.white : colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName ?? 'Файл',
                  style: TextStyle(
                    color: isMe ? Colors.white : colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (attachment.fileSize != null)
                  Text(
                    attachment.formattedSize,
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onShare,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.share_outlined,
                size: 18,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDownload,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.download_rounded,
                size: 20,
                color: iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final VoidCallback onSend;
  final VoidCallback onPickPhoto;
  final VoidCallback onPickFile;

  const _ChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
    required this.onPickPhoto,
    required this.onPickFile,
  });

  void _showAttachmentOptions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
            const SizedBox(height: 20),
            
            Text(
              'Прикрепить',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _AttachOption(
                    icon: Icons.image_rounded,
                    label: 'Фото',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(ctx);
                      onPickPhoto();
                    },
                  ),
                  const SizedBox(height: 12),
                  _AttachOption(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'Файл',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pop(ctx);
                      onPickFile();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          
          IconButton(
            icon: Icon(
              Icons.add_circle_outline_rounded,
              color: colorScheme.primary,
            ),
            onPressed: () {
              _showAttachmentOptions(context);
            },
          ),
          
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: IconButton(
              icon: isSending
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: isSending ? null : onSend,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingFilesPreview extends StatelessWidget {
  final List<UploadFile> files;
  final Function(int) onRemove;

  const _PendingFilesPreview({
    required this.files,
    required this.onRemove,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_rounded;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mimeType.contains('zip') || mimeType.contains('rar')) {
      return Icons.archive_rounded;
    }
    return Icons.insert_drive_file_rounded;
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
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          file.name,
                          style: TextStyle(
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
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => onRemove(index),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
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

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
