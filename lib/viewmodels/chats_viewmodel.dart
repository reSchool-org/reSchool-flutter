import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../models/chat_models.dart';

class ChatsViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<ChatThread> _threads = [];
  List<UserSearchItem> _searchResults = [];
  Set<int> _verifiedIds = {};
  bool _isLoading = false;
  bool _isSearching = false;
  String? _error;
  String _searchQuery = '';

  List<ChatThread> get threads => _threads;
  List<UserSearchItem> get searchResults => _searchResults;
  Set<int> get verifiedIds => _verifiedIds;
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

      await _checkCloudVerification();

    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _logRequest(String method, String url, Map<String, String>? headers, Object? body) {
    print("\n========== LOCAL SERVER REQUEST ==========");
    print("URL: $url");
    print("Method: $method");
    if (headers != null) {
      print("Headers:");
      headers.forEach((key, value) => print("  $key: $value"));
    }
    if (body != null) {
      print("Body: $body");
    } else {
      print("Body: [empty]");
    }
    print("==========================================\n");
  }

  void _logResponse(http.Response response) {
    print("\n========== LOCAL SERVER RESPONSE ==========");
    print("URL: ${response.request?.url}");
    print("Status Code: ${response.statusCode}");
    if (response.body.isNotEmpty) {
      print("Response Body: ${response.body}");
    } else {
      print("Response Body: [empty]");
    }
    print("===========================================\n");
  }

  Future<void> _checkCloudVerification() async {
    try {
      final token = _api.cloudToken;
      final isEnabled = _api.isCloudEnabled;
      final currentPrsId = _api.currentPrsId;

      if (_api.isDemo) {
        _verifiedIds.clear();
        return;
      }

      if (token == null || !isEnabled) {
        _verifiedIds.clear();
        return;
      }

      final idsToCheck = _threads
          .where((t) => !t.isGroup)
          .map((t) {
            if (t.imgObjId != null) return t.imgObjId!;
            if (t.senderId != null && t.senderId != currentPrsId) return t.senderId!;
            return null;
          })
          .where((id) => id != null)
          .cast<int>()
          .toSet()
          .toList();

      if (idsToCheck.isEmpty) return;

      final url = Uri.parse('${AppConfig.cloudFunctionsBaseUrl}/check-verified-users');
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'token': token,
        'ids': idsToCheck,
      });

      _logRequest("POST", url.toString(), headers, body);

      final response = await http.post(
        url,
        headers: headers,
        body: body,
      );

      _logResponse(response);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> verified = data['verifiedIds'] ?? [];
        _verifiedIds = verified.map((e) => e as int).toSet();
      } else if (response.statusCode == 401) {
        print("Cloud token invalid, disabling cloud features");
        await _api.updateCloudSettings(enabled: false, token: null, threadId: null);
        _verifiedIds.clear();
      }
    } catch (e) {
      print("Cloud verification check failed: $e");
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

          _searchResults = [
            UserSearchItem(
              prsId: id,
              fio: name,

            )
          ];
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

          if (profileData['data'] != null && profileData['data']['prsId'] == prsId) {
            final user = UserSearchItem(
              prsId: prsId,
              fio: profileData['fio'],

            );
            results.add(user);
            seenPrsIds.add(prsId);
          }
        } catch (_) {
        }
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