import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/app_font.dart';
import '../viewmodels/chat_search_viewmodel.dart';
import '../widgets/app_card.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/section_state.dart';

class ChatSearchScreen extends StatefulWidget {
  final int? threadId;
  const ChatSearchScreen({super.key, this.threadId});
  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  late final _vm = ChatSearchViewModel(threadId: widget.threadId);
  final _controller = TextEditingController();
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _vm.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _search(String value) {
    _debounce?.cancel();
    _vm.invalidate(value);
    _debounce = Timer(const Duration(milliseconds: 400), _vm.load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _vm.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          l10n.searchMessages,
          style: appFont(context, fontWeight: FontWeight.w600),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: TextField(
                  autofocus: true,
                  controller: _controller,
                  onChanged: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    _vm.load();
                  },
                  decoration: InputDecoration(
                    hintText: l10n.searchMessages,
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: appFieldFill(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.close,
                            onPressed: () {
                              _controller.clear();
                              _search('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    if (_vm.query.length < 3)
                      SectionState(
                        icon: Icons.manage_search_rounded,
                        title: l10n.searchMessagesHint,
                      )
                    else ...[
                      if (!_vm.isLoading && !_vm.hasError && _vm.hits.isEmpty)
                        SectionState(
                          icon: Icons.search_off_rounded,
                          title: l10n.searchNoResults,
                        ),
                      for (final hit in _vm.hits)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppInteractiveCard(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: AuthenticatedAvatar(
                                imageId: hit.thread.imageId,
                                imgObjType: hit.thread.imgObjType,
                                imgObjId: hit.thread.imgObjId,
                                fallbackText: hit.thread.title,
                                isGroup: hit.thread.isGroup,
                                size: 44,
                                borderRadius: 12,
                              ),
                              title: Text(
                                hit.thread.title,
                                style: appFont(context, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  hit.preview,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: appFont(context,
                                    height: 1.4,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onSurfaceVariant,
                              ),
                              onTap: () => Navigator.pop(context, hit),
                            ),
                          ),
                        ),
                      if (_vm.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_vm.hasError)
                        SectionState(
                          icon: Icons.wifi_off_rounded,
                          title: l10n.searchMessagesError,
                          onRetry: _vm.load,
                        )
                      else if (_vm.hasMore)
                        Center(
                          child: TextButton(
                            onPressed: _vm.load,
                            child: Text(l10n.loadMore, style: appFont(context)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
