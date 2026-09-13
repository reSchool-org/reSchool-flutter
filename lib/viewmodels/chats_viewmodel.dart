import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../models/chat_models.dart';

class ChatsViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<ChatThread> _threads = [];
  List<UserSearchItem> _searchResults = [];
  bool _isLoading = false;
  bool _isSearching = false;
  String? _error;
  String _searchQuery = '';

  List<ChatThread> get threads => _threads;
  List<UserSearchItem> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  List<ChatThread> get filteredThreads {
    if (_searchQuery.isEmpty) return _threads;
    final query = _searchQuery.toLowerCase();
    return _threads.where((thread) {
      return thread.title.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> loadThreads() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.getThreads();
      _threads = data.map((json) => ChatThread.fromJson(json)).toList();
      _threads.sort((a, b) => b.sendDate.compareTo(a.sendDate));
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> searchUsers(String query) async {
    _searchQuery = query;

    if (query.isEmpty) {
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (query != _searchQuery) return;

      if (query.endsWith('/prsId')) {
        final idStr = query.split('/').first;
        final id = int.tryParse(idStr);
        if (id != null) {
          String name = 'Пользователь $id';
          try {
            final profile = await _api.getProfileNew(id);
            if (profile['fio'] != null) {
              name = profile['fio'];
            }
          } catch (_) {}

          _searchResults = [UserSearchItem(prsId: id, fio: name)];
          _isSearching = false;
          notifyListeners();
          return;
        }
      }

      final List<UserSearchItem> results = [];
      final Set<int> seenPrsIds = {};

      if (int.tryParse(query) != null) {
        try {
          final prsId = int.parse(query);
          final profileData = await _api.getProfileNew(prsId);

          if (profileData['data'] != null &&
              profileData['data']['prsId'] == prsId) {
            final user = UserSearchItem(prsId: prsId, fio: profileData['fio']);
            results.add(user);
            seenPrsIds.add(prsId);
          }
        } catch (_) {}
      }

      final data = await _api.searchUsers(query);
      if (query == _searchQuery) {
        for (final json in data) {
          final user = UserSearchItem.fromJson(json);
          if (user.prsId != null && !seenPrsIds.contains(user.prsId)) {
            results.add(user);
            seenPrsIds.add(user.prsId!);
          }
        }
        _searchResults = results;
      }
    } catch (e) {
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<int?> openUserChat(UserSearchItem user) async {
    if (user.prsId == null) return null;

    try {
      final threadId = await _api.saveThread(interlocutorId: user.prsId);
      await loadThreads();
      return threadId;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<int?> createGroupChat(
    String subject,
    List<UserSearchItem> members,
  ) async {
    if (subject.isEmpty || members.isEmpty) return null;

    try {
      final threadId = await _api.saveThread(subject: subject, isGroup: true);
      if (threadId != 0) {
        await _api.setGroupMembers(
          threadId,
          members.map((u) => {'prsId': u.prsId, 'fio': u.fio}).toList(),
        );
        await loadThreads();
        return threadId;
      }
      return null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  void clearSearch() {
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
  }
}

class ChatDetailViewModel extends ChangeNotifier {
  final ApiService _api;
  final int threadId;
  final String title;
  final bool isGroup;
  static const pageSize = 50;
  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool isLoading = false;
  bool isLoadingOlder = false;
  bool isLoadingNewer = false;
  bool isSending = false;
  bool isModifying = false;
  bool isLoadingPermissions = false;
  bool hasOlder = false;
  bool hasNewer = false;
  String? error;
  String? olderError;
  String? newerError;
  ChatPermissions? permissions;
  bool permissionsFailed = false;
  bool _disposed = false;
  int _generation = 0;
  int _rowsLoaded = 0;

  ChatDetailViewModel({
    required this.threadId,
    required this.title,
    required this.isGroup,
    ApiService? api,
  }) : _api = api ?? ApiService();

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> loadPermissions() async {
    if (isLoadingPermissions) return;
    isLoadingPermissions = true;
    permissionsFailed = false;
    _emit();
    try {
      permissions = await _api.getChatPermissions(threadId);
    } catch (_) {
      permissionsFailed = true;
    } finally {
      isLoadingPermissions = false;
      _emit();
    }
  }

  Future<void> loadMessages({
    int? aroundMessage,
    String? searchText,
    List<int>? matches,
  }) async {
    final generation = ++_generation;
    isLoading = true;
    isLoadingOlder = false;
    isLoadingNewer = false;
    error = olderError = newerError = null;
    _emit();
    try {
      final data = await _api.getMessages(
        threadId,
        rowsCount: pageSize,
        msgStart: aroundMessage,
        isSearch: aroundMessage != null,
        searchText: searchText,
        msgNums: matches,
      );
      if (_disposed || generation != _generation) return;
      _messages = _sorted(data.map(ChatMessage.fromJson));
      _rowsLoaded = data.length;
      hasOlder = data.length >= pageSize;
      hasNewer = aroundMessage != null;
    } catch (_) {
      if (generation == _generation) error = 'chatLoadError';
    } finally {
      if (generation == _generation) {
        isLoading = false;
        _emit();
      }
    }
  }

  Future<void> loadOlder() async {
    if (isLoading || isLoadingOlder || !hasOlder) return;
    final generation = _generation;
    isLoadingOlder = true;
    olderError = null;
    _emit();
    try {
      final cursor = _messages.firstOrNull?.msgNum;
      final data = await _api.getMessages(
        threadId,
        rowsCount: pageSize,
        rowStart: cursor == null ? _rowsLoaded + 1 : 1,
        msgStart: cursor,
      );
      if (_disposed || generation != _generation) return;
      final oldIds = _messages.map((message) => message.id).toSet();
      final incoming = data.map(ChatMessage.fromJson).toList();
      _messages = _sorted([...incoming, ..._messages]);
      _rowsLoaded += data.length;
      hasOlder =
          data.length >= pageSize &&
          incoming.any((m) => !oldIds.contains(m.id));
    } catch (_) {
      if (generation == _generation) olderError = 'chatMoreError';
    } finally {
      if (generation == _generation) {
        isLoadingOlder = false;
        _emit();
      }
    }
  }

  Future<void> loadNewer() async {
    if (isLoading || isLoadingNewer) return;
    final cursor = _messages.lastOrNull?.msgNum;
    if (cursor == null) {
      await loadMessages();
      return;
    }
    final generation = _generation;
    isLoadingNewer = true;
    newerError = null;
    _emit();
    try {
      final data = await _api.getMessages(
        threadId,
        rowsCount: pageSize,
        msgStart: cursor,
        getNew: true,
      );
      if (_disposed || generation != _generation) return;
      final incoming = data.map(ChatMessage.fromJson).toList();
      final oldIds = _messages.map((m) => m.id).toSet();
      _messages = _sorted([..._messages, ...incoming]);
      hasNewer =
          data.length >= pageSize &&
          incoming.any((m) => !oldIds.contains(m.id));
    } catch (_) {
      if (generation == _generation) newerError = 'chatMoreError';
    } finally {
      if (generation == _generation) {
        isLoadingNewer = false;
        _emit();
      }
    }
  }

  List<ChatMessage> _sorted(Iterable<ChatMessage> messages) {
    final unique = <int, ChatMessage>{
      for (final message in messages) message.id: message,
    };
    return unique.values.toList()..sort(
      (a, b) => a.msgNum != null && b.msgNum != null
          ? a.msgNum!.compareTo(b.msgNum!)
          : a.createDate.compareTo(b.createDate),
    );
  }

  Future<bool> sendMessage(String text, {List<UploadFile>? files}) async {
    if (isSending ||
        (text.trim().isEmpty && (files == null || files.isEmpty))) {
      return false;
    }
    isSending = true;
    _emit();
    try {
      await _api.sendMessage(threadId, text, files: files);
      // отправка уже состоялась, ошибка обновления не должна предлагать отправить дубль
      await loadMessages();
      return true;
    } catch (_) {
      return false;
    } finally {
      isSending = false;
      _emit();
    }
  }

  bool canModify(ChatMessage message) =>
      !isModifying &&
      (permissions?.canModify(message, isMine: isMessageMine(message)) ??
          false);

  Future<bool> editMessage(ChatMessage message, String text) async {
    if (!canModify(message) || text.trim().isEmpty) return false;
    isModifying = true;
    _emit();
    try {
      await _api.editChatMessage(message, text);
      _invalidatePages();
      _messages = _messages
          .map((m) => m.id == message.id ? m.withText(text) : m)
          .toList();
      return true;
    } catch (_) {
      return false;
    } finally {
      isModifying = false;
      _emit();
    }
  }

  Future<bool> deleteMessage(ChatMessage message) async {
    if (!canModify(message)) return false;
    isModifying = true;
    _emit();
    try {
      await _api.deleteChatMessage(message.msgId!);
      _invalidatePages();
      _messages.removeWhere((m) => m.id == message.id);
      return true;
    } catch (_) {
      return false;
    } finally {
      isModifying = false;
      _emit();
    }
  }

  void _invalidatePages() {
    _generation++;
    isLoading = isLoadingOlder = isLoadingNewer = false;
  }

  String getAttachmentUrl(int msgId, int fileId) =>
      _api.getAttachmentUrl(msgId, fileId);
  Future<File> downloadAttachment(int msgId, int fileId, String filename) =>
      _api.downloadAttachment(msgId, fileId, filename);
  Map<String, String> get authHeaders => _api.authHeaders;
  Future<void> leaveChat() => _api.leaveChat(threadId);

  bool isMessageMine(ChatMessage message) {
    if (message.isOwner != null) return message.isOwner!;
    final prsId = _api.currentPrsId;
    return prsId != null && (message.senderPrsId ?? message.senderId) == prsId;
  }

  int? resolvePartnerPrsId({int? threadPrsId}) {
    if (isGroup) return null;
    final currentPrsId = _api.currentPrsId;
    bool isPartnerId(int? id) => id != null && id > 0 && id != currentPrsId;

    if (isPartnerId(threadPrsId)) return threadPrsId;
    for (final message in _messages) {
      // отсутствие признака владельца не делает сообщение входящим; своё сообщение не подставляем вместо ответа
      if (isMessageMine(message) ||
          (message.isOwner == null && currentPrsId == null)) {
        continue;
      }
      final prsId = message.avatarPrsId;
      if (isPartnerId(prsId)) return prsId;
    }
    return null;
  }

  bool isFirstInSequence(int index) =>
      index == 0 ||
      _messages[index].senderId != _messages[index - 1].senderId ||
      _messages[index].createDateTime
              .difference(_messages[index - 1].createDateTime)
              .inMinutes >
          10;

  String getAvatarUrl(ChatMessage msg) => _api.getAvatarUrl(
    imageId: msg.imageId,
    imgObjType: msg.imgObjType ?? 'USER_PICTURE',
    imgObjId: msg.avatarPrsId,
  );
}
