import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import '../models/school_directory.dart';
import '../services/api_service.dart';

class SchoolDirectoryViewModel extends ChangeNotifier {
  final ApiService _api;
  List<SchoolDirectoryGroup> roots = [];
  final List<SchoolDirectoryGroup> path = [];
  bool isLoading = false;
  bool hasError = false;
  bool _disposed = false;
  String query = '';
  SchoolDirectoryViewModel({ApiService? api}) : _api = api ?? ApiService();

  List<SchoolDirectoryGroup> get groups => path.lastOrNull?.groups ?? roots;
  List<UserSearchItem> get users => path.lastOrNull?.users ?? [];
  List<UserSearchItem> get searchResults {
    final words = query
        .trim()
        .toLowerCase()
        .replaceAll('ё', 'е')
        .split(RegExp(r'\s+'));
    final unique = <int, UserSearchItem>{};
    for (final user in roots.expand((group) => group.descendants)) {
      if (user.prsId == null) continue;
      final text =
          '${user.fio ?? ''} ${(user.pos ?? []).map((p) => p.posTypeName).join(' ')}'
              .toLowerCase()
              .replaceAll('ё', 'е');
      if (words.every(text.contains)) unique[user.prsId!] = user;
    }
    return unique.values.toList()
      ..sort((a, b) => (a.fio ?? '').compareTo(b.fio ?? ''));
  }

  void search(String text) {
    query = text;
    notifyListeners();
  }

  void enter(SchoolDirectoryGroup group) {
    path.add(group);
    notifyListeners();
  }

  void backTo(int depth) {
    path.removeRange(depth, path.length);
    notifyListeners();
  }

  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    hasError = false;
    notifyListeners();
    try {
      final loaded = await _api.getEmployeeGroups();
      if (_disposed) return;
      roots = loaded;
      path.clear();
    } catch (_) {
      hasError = true;
    } finally {
      isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
