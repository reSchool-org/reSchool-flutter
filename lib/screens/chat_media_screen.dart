import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../utils/app_font.dart';
import '../viewmodels/chat_media_viewmodel.dart';
import '../widgets/app_card.dart';
import '../widgets/content_image.dart';
import '../widgets/section_state.dart';

class ChatMediaScreen extends StatefulWidget {
  final int threadId;
  final String title;
  const ChatMediaScreen({
    super.key,
    required this.threadId,
    required this.title,
  });
  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> {
  late final _vm = ChatMediaViewModel(widget.threadId);
  int _filter = 0;
  String _query = '';
  String? _busyFile;
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
    super.dispose();
  }

  Future<void> _openFile(ChatMediaItem item, {bool share = false}) async {
    if (_busyFile != null) return;
    setState(() => _busyFile = item.key);
    final l10n = AppLocalizations.of(context)!;
    try {
      final file = await ApiService().downloadXFile(
        ApiService().getAttachmentUrl(item.message.msgId!, item.attachment.fileId!),
        item.attachment.fileName ?? 'file',
      );
      if (!mounted) return;
      if (share) {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
          files: [file],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ));
      } else {
        if (kIsWeb) {
          await file.saveTo(file.name);
          return;
        }
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.fileOpenError, style: appFont(context))));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.downloadFileError, style: appFont(context))));
      }
    } finally {
      if (mounted) setState(() => _busyFile = null);
    }
  }

  Widget _actions(ChatMediaItem item) {
    final l10n = AppLocalizations.of(context)!;
    if (_busyFile == item.key) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return PopupMenuButton<String>(
      enabled: _busyFile == null,
      tooltip: l10n.chatAttachments,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (value) => _openFile(item, share: value == 'share'),
      itemBuilder: (fontContext) => [
        PopupMenuItem(value: 'open', child: Text(l10n.fileActionOpen, style: appFont(fontContext))),
        PopupMenuItem(value: 'share', child: Text(l10n.fileActionShare, style: appFont(fontContext))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final items = _vm.items
        .where(
          (item) =>
              (_filter == 0 ||
                  (_filter == 1
                      ? item.attachment.isImage
                      : !item.attachment.isImage)) &&
              (item.attachment.fileName ?? '').toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          l10n.chatAttachments,
          style: appFont(context, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: l10n.refreshContent,
            onPressed: () => _vm.load(refresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  widget.title,
                  style: appFont(context, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: l10n.chatFileSearch,
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: appFieldFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (index, name) in [
                      l10n.all,
                      l10n.chatPhotos,
                      l10n.chatDocuments,
                    ].indexed)
                      ChoiceChip(
                        label: Text(name, style: appFont(context)),
                        selected: _filter == index,
                        onSelected: (_) => setState(() => _filter = index),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _vm.load(refresh: true),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (items.isEmpty && !_vm.isLoading && !_vm.hasError)
                        SliverToBoxAdapter(
                          child: SectionState(
                            icon: Icons.folder_open_rounded,
                            title: _vm.items.isEmpty
                                ? l10n.chatMediaEmpty
                                : l10n.chatMediaNoMatches,
                          ),
                        ),
                      if (_filter == 1)
                        SliverPadding(
                          padding: const EdgeInsets.all(20),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) => SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount:
                                        constraints.crossAxisExtent < 500
                                        ? 2
                                        : constraints.crossAxisExtent < 800
                                        ? 3
                                        : 4,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    mainAxisExtent: 190,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final item = items[index];
                                return AppInteractiveCard(
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: ContentImage(
                                          uri: Uri.parse(
                                            ApiService().getAttachmentUrl(
                                              item.message.msgId!,
                                              item.attachment.fileId!,
                                            ),
                                          ),
                                          label: item.attachment.fileName,
                                          height: 140,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.attachment.fileName ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: appFont(context, fontSize: 12),
                                              ),
                                            ),
                                            _actions(item),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }, childCount: items.length),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return AppInteractiveCard(
                                margin: const EdgeInsets.only(bottom: 10),

                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      item.attachment.isImage
                                          ? Icons.image_outlined
                                          : Icons.description_outlined,
                                      color: cs.primary,
                                    ),
                                  ),
                                  title: Text(
                                    item.attachment.fileName ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: appFont(context, fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    '${item.attachment.formattedSize} · ${DateFormat('dd.MM.yyyy').format(item.message.createDateTime)}',
                                    style: appFont(context,
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: _actions(item),
                                  onTap: _busyFile != null
                                      ? null
                                      : () => _openFile(item),
                                ),
                              );
                            },
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: _vm.isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : _vm.hasError
                              ? SectionState(
                                  icon: Icons.wifi_off_rounded,
                                  title: l10n.chatMediaError,
                                  onRetry: () => _vm.load(),
                                )
                              : _vm.hasMore
                              ? Center(
                                  child: TextButton(
                                    onPressed: () => _vm.load(),
                                    child: Text(l10n.loadMore, style: appFont(context)),
                                  ),
                                )
                              : const SizedBox(height: 16),
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
    );
  }
}
