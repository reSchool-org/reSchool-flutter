import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';

class ChatMediaViewModel extends ChangeNotifier {
  final int threadId;
  final ApiService _api;
  List<ChatMediaItem> items = [];
  bool isLoading = false;
  bool hasError = false;
  bool hasMore = true;
  int? _cursor;
  int _rows = 0;
  int _generation = 0;
  bool _disposed = false;
  ChatMediaViewModel(this.threadId, {ApiService? api})
    : _api = api ?? ApiService();

  Future<void> load({bool refresh = false}) async {
    if (isLoading && !refresh) return;
    if (!hasMore && !refresh) return;
    final generation = ++_generation;
    isLoading = true;
    hasError = false;
    notifyListeners();
    try {
      final messages = await _api.getChatMedia(
        threadId,
        rowStart: refresh || _cursor != null ? 1 : _rows + 1,
        msgStart: refresh ? null : _cursor,
      );
      if (_disposed || generation != _generation) return;
      final incoming = [
        for (final message in messages)
          if (message.msgId != null)
            for (final file in message.attachInfo ?? <AttachInfo>[])
              if (file.fileId != null) ChatMediaItem(message, file),
      ];
      final oldKeys = refresh ? <String>{} : items.map((i) => i.key).toSet();
      final merged = <String, ChatMediaItem>{
        if (!refresh)
          for (final item in items) item.key: item,
        for (final item in incoming) item.key: item,
      };
      items = merged.values.toList()
        ..sort((a, b) => b.message.createDate.compareTo(a.message.createDate));
      final cursors = messages.map((m) => m.msgNum).whereType<int>().toList();
      final previousCursor = refresh ? null : _cursor;
      if (cursors.isNotEmpty) {
        _cursor = cursors.reduce((a, b) => a < b ? a : b);
      } else if (refresh) {
        _cursor = null;
      }
      _rows = (refresh ? 0 : _rows) + messages.length;
      hasMore =
          messages.length >= 50 &&
          (previousCursor == null || _cursor != previousCursor) &&
          (incoming.isEmpty || incoming.any((i) => !oldKeys.contains(i.key)));
    } catch (_) {
      if (generation == _generation) hasError = true;
    } finally {
      if (generation == _generation) {
        isLoading = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
