import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';

class ChatSearchViewModel extends ChangeNotifier {
  final ApiService _api;
  final int? threadId;
  String query = '';
  List<ChatSearchHit> hits = [];
  bool isLoading = false;
  bool hasMore = false;
  bool hasError = false;
  int? _cursor;
  int _generation = 0;
  bool _disposed = false;
  ChatSearchViewModel({this.threadId, ApiService? api})
    : _api = api ?? ApiService();

  void invalidate(String text) {
    _generation++;
    query = text.trim();
    hits = [];
    _cursor = null;
    hasMore = query.length >= 3;
    isLoading = false;
    hasError = false;
    notifyListeners();
  }

  Future<void> load() async {
    if (isLoading || !hasMore || query.length < 3) return;
    final generation = _generation;
    isLoading = true;
    hasError = false;
    notifyListeners();
    try {
      do {
        final page = await _api.searchChatMessages(query, msgStart: _cursor);
        if (_disposed || generation != _generation) return;
        final next = page.lastOrNull?.cursor;
        hasMore = page.length >= 25 && next != null && next != _cursor;
        _cursor = next;
        final matching = page
            .where((hit) => threadId == null || hit.thread.threadId == threadId)
            .toList();
        final merged = {
          for (final hit in hits) hit.thread.threadId: hit,
          for (final hit in matching) hit.thread.threadId: hit,
        };
        hits = merged.values.toList();
        // сервер ищет по всем беседам, в открытой беседе пропускаем чужие результаты
        if (threadId == null || matching.isNotEmpty) break;
      } while (hasMore);
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
