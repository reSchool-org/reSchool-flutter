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

      final data = await _api.searchUsers(query);
      if (query == _searchQuery) {
        _searchResults = data.map((json) => UserSearchItem.fromJson(json)).toList();
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

  Future<int?> createGroupChat(String subject, List<UserSearchItem> members) async {
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
  final ApiService _api = ApiService();
  final int threadId;
  final String title;
  final bool isGroup;

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;

  ChatDetailViewModel({
    required this.threadId,
    required this.title,
    required this.isGroup,
  });

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;

  Future<void> loadMessages() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.getMessages(threadId);
      _messages = data.map((json) => ChatMessage.fromJson(json)).toList();
      _messages = _messages.reversed.toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendMessage(String text, {List<UploadFile>? files}) async {
    if (text.trim().isEmpty && (files == null || files.isEmpty)) return false;

    _isSending = true;
    notifyListeners();

    try {
      await _api.sendMessage(threadId, text, files: files);
      await loadMessages();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  String getAttachmentUrl(int msgId, int fileId) {
    return _api.getAttachmentUrl(msgId, fileId);
  }

  Future<File> downloadAttachment(int msgId, int fileId, String filename) async {
    return await _api.downloadAttachment(msgId, fileId, filename);
  }

  Map<String, String> get authHeaders => _api.authHeaders;

  Future<void> leaveChat() async {
    try {
      await _api.leaveChat(threadId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  bool isMessageMine(ChatMessage msg) {
    final myName = _api.userProfile?.fullName;
    if (myName != null && msg.senderFio != null) {
      return myName == msg.senderFio;
    }
    return msg.isOwner ?? false;
  }

  bool isFirstInSequence(int index) {
    if (index == 0) return true;
    return _messages[index].senderFio != _messages[index - 1].senderFio;
  }

  String getAvatarUrl(ChatMessage msg) {
    return _api.getAvatarUrl(
      imageId: msg.imageId,
      imgObjType: msg.imgObjType ?? 'USER_PICTURE',
      imgObjId: msg.senderId,
    );
  }
}
