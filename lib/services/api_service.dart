import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../models/profile_models.dart';
import '../models/chat_models.dart';
import '../models/account.dart';
import 'demo_data.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _baseURL = "https://app.eschool.center/ec-server";
  final String _userAgent = "eSchoolMobile";
  final _storage = const FlutterSecureStorage();
  final DemoData _demoData = DemoData();

  bool isAuthenticated = false;
  bool _isDemo = false;
  Map<String, String> _cookies = {};

  int? userId;
  int? currentPrsId;
  Profile? userProfile;
  String? _deviceModel;

  Account? _account;
  Account? get account => _account;
  bool get isDemo => _isDemo;

  String get deviceModel => _deviceModel ?? "Android Device";

  String? get cloudToken => _account?.cloudToken;
  int? get serverThreadId => _account?.serverThreadId;
  bool get isCloudEnabled => _account?.isCloudEnabled ?? false;

  Future<void> updateCloudSettings({
    required bool enabled,
    String? token,
    int? threadId,
  }) async {
    if (_account != null) {
      _account!.isCloudEnabled = enabled;
      _account!.cloudToken = token;
      _account!.serverThreadId = threadId;
      await _saveAccount();
    }
  }

  Future<void> init() async {
    await _loadAccount();
    await _loadDeviceModel();
    if (_account != null) {
      await _restoreSession();
    }
  }

  Future<void> _loadAccount() async {
    try {
      String? jsonString;
      try {
        jsonString = await _storage.read(key: 'saved_account');
      } catch (e) {
        print("Secure storage read failed (expected on unsigned macOS): $e");
      }

      if (jsonString == null) {
        final prefs = await SharedPreferences.getInstance();
        jsonString = prefs.getString('saved_account_insecure');
      }

      if (jsonString != null) {
        final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
        _account = Account.fromJson(jsonMap);
        _isDemo = _isDemoCredentials(_account!.username, _account!.password);
      } else {
        try {
          final oldJsonString = await _storage.read(key: 'saved_accounts');
          if (oldJsonString != null) {
             final List<dynamic> jsonList = jsonDecode(oldJsonString);
             if (jsonList.isNotEmpty) {
               _account = Account.fromJson(jsonList[0]);
               _isDemo = _isDemoCredentials(_account!.username, _account!.password);
               await _saveAccount();
             }
             await _storage.delete(key: 'saved_accounts');
          }
        } catch (_) {}
      }
    } catch (e) {
      print("Error loading accounts: $e");
    }
  }

  Future<void> _saveAccount() async {
    try {
      if (_account != null) {
        final jsonString = jsonEncode(_account!.toJson());
        try {
          await _storage.write(key: 'saved_account', value: jsonString);
        } catch (e) {
          print("Secure storage write failed, falling back to SharedPreferences: $e");
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_account_insecure', jsonString);
        }
      } else {
        try {
          await _storage.delete(key: 'saved_account');
        } catch (_) {}
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_account_insecure');
      }
    } catch (e) {
      print("Error saving accounts: $e");
    }
  }

  Future<void> _loadDeviceModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_device_model');
    if (saved != null) {
      _deviceModel = saved;
    } else {
      await randomizeDeviceModel();
    }
  }

  Future<void> randomizeDeviceModel() async {
    try {
      final jsonString = await rootBundle.loadString('assets/devices.json');
      final List<dynamic> devices = jsonDecode(jsonString);
      if (devices.isNotEmpty) {
        final rnd = Random();
        _deviceModel = devices[rnd.nextInt(devices.length)];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_device_model', _deviceModel!);
      }
    } catch (e) {
      print("Error loading devices.json: $e");
      _deviceModel = "Android Device";
    }
  }

  Future<void> _restoreSession() async {
     if (_account == null) return;

     _cookies.clear();
     isAuthenticated = false;
     _isDemo = _isDemoCredentials(_account!.username, _account!.password);
     userId = null;
     currentPrsId = null;
     userProfile = null;

     if (_isDemo) {
       _applyDemoSession();
       return;
     }

     if (_account!.sessionCookie != null) {
       _cookies['JSESSIONID'] = _account!.sessionCookie!;
     }

     bool success = false;
     if (_cookies.isNotEmpty) {
         success = await _fetchState();
     }

     if (!success) {
        print("Session invalid for ${_account!.username}, re-logging in...");
        success = await login(_account!.username, _account!.password);
     } else {
        isAuthenticated = true;
     }
  }

  Future<void> logout() async {
    _cookies.clear();
    isAuthenticated = false;
    _isDemo = false;
    userId = null;
    currentPrsId = null;
    userProfile = null;
    _account = null;
    await _saveAccount();
  }

  String _sha256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
      length,
      (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
    ));
  }

  Map<String, String> _getHeaders({bool isForm = false}) {
    final headers = {
      "Accept": "application/json, text/plain, */*",
      "User-Agent": _userAgent,
      "Accept-Language": "ru-RU,en,*",
      "Origin": "https://app.eschool.center",
      "Referer": "https://app.eschool.center/",
    };
    if (isForm) {
      headers["Content-Type"] = "application/x-www-form-urlencoded";
    }
    if (_cookies.isNotEmpty) {
      headers["Cookie"] = _cookies.entries.map((e) => "${e.key}=${e.value}").join("; ");
    }
    return headers;
  }

  void _updateCookies(http.Response response, {bool updateAccount = true}) {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      final RegExp cookieRegex = RegExp(r'(JSESSIONID)=([^;]+)');
      final matches = cookieRegex.allMatches(rawCookie);
      for (final match in matches) {
        _cookies[match.group(1)!] = match.group(2)!;

        if (updateAccount && _account != null) {
           _account!.sessionCookie = match.group(2)!;
           _saveAccount();
        }
      }
    }
  }

  void _logRequest(String method, String url, Map<String, String> headers, Object? body) {
    print("\n========== API REQUEST ==========");
    print("URL: $url");
    print("Method: $method");
    print("Headers:");
    headers.forEach((key, value) {
      if (key.toLowerCase() == "cookie") {
        print("  $key: [COOKIES HIDDEN]");
      } else {
        print("  $key: $value");
      }
    });

    if (body != null) {
      if (body is String) {
        print("Body: $body");
      } else if (body is Map) {
         print("Body: ${jsonEncode(body)}");
      } else {
        print("Body: [Binary or Object]");
      }
    } else {
      print("Body: [empty]");
    }
    print("==================================\n");
  }

  void _logResponse(http.Response response) {
    print("\n========== API RESPONSE ==========");
    print("Status Code: ${response.statusCode}");
    print("Headers:");
    response.headers.forEach((key, value) {
      if (key.toLowerCase() == "set-cookie") {
        print("  $key: [COOKIES HIDDEN]");
      } else {
        print("  $key: $value");
      }
    });
    if (response.body.length > 1000) {
      print("Body: ${response.body.substring(0, 1000)}... [truncated]");
    } else {
      print("Body: ${response.body}");
    }
    print("==================================\n");
  }

  Future<http.Response> _request(String method, String url, {Map<String, String>? headers, Object? body, bool isRetry = false}) async {
    headers ??= _getHeaders();

    _logRequest(method, url, headers, body);

    final uri = Uri.parse(url);
    http.Response response;

    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: body);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: body);
          break;
        default:
          throw Exception('Unsupported method: $method');
      }
    } catch (e) {
      rethrow;
    }

    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 401 && !isRetry && _account != null) {
      print("Received 401, attempting re-login for ${_account!.username}...");

      final success = await login(_account!.username, _account!.password);
      if (success) {
        print("Re-login successful, retrying request...");

        final newHeaders = Map<String, String>.from(headers);
        if (_cookies.isNotEmpty) {
          newHeaders["Cookie"] = _cookies.entries.map((e) => "${e.key}=${e.value}").join("; ");
        }
        return _request(method, url, headers: newHeaders, body: body, isRetry: true);
      } else {
        print("Re-login failed.");
      }
    }

    return response;
  }

  Future<bool> login(String username, String password, {bool rememberMe = false}) async {
    if (_isDemoCredentials(username, password)) {
      _applyDemoSession();
      _account = Account(
        username: username,
        password: password,
        fullName: _demoData.fullName,
        prsId: _demoData.prsId,
        imageId: null,
        sessionCookie: null,
        cloudToken: null,
        serverThreadId: null,
        isCloudEnabled: false,
      );
      await _saveAccount();
      return true;
    }

    _isDemo = false;
    final passwordHash = _sha256(password);
    final deviceId = _randomString(16).toLowerCase();
    final pushToken = _randomString(152);

    final devicePayload = {
      "cliType": "mobile",
      "cliVer": "7.4.0",
      "pushToken": pushToken,
      "deviceId": deviceId,
      "deviceName": "-",
      "deviceModel": deviceModel,
      "cliOs": "android",
      "cliOsVer": "9"
    };

    final deviceString = jsonEncode(devicePayload);
    final body = {
      "username": username,
      "password": passwordHash,
      "device": deviceString,
    };

    final url = "$_baseURL/login";
    final headers = _getHeaders(isForm: true);

    _logRequest("POST", url, headers, body);

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      _logResponse(response);

      bool shouldUpdateAccount = false;
      if (_account != null && _account!.username == username) {
        shouldUpdateAccount = true;
      }

      _updateCookies(response, updateAccount: shouldUpdateAccount);

      if (response.statusCode == 200) {
         if (response.body.length > 5 || _cookies.containsKey('JSESSIONID')) {
           isAuthenticated = true;

           await _fetchState();

           final fullName = userProfile?.fullName ?? username;
           final prsId = currentPrsId;
           final imageId = userProfile?.imageId;

           final oldCloudToken = _account?.cloudToken;
           final oldServerThreadId = _account?.serverThreadId;
           final oldIsCloudEnabled = _account?.isCloudEnabled ?? false;

           _account = Account(
             username: username,
             password: password,
             fullName: fullName,
             prsId: prsId,
             imageId: imageId,
             sessionCookie: _cookies['JSESSIONID'],
             cloudToken: oldCloudToken,
             serverThreadId: oldServerThreadId,
             isCloudEnabled: oldIsCloudEnabled,
           );

           await _saveAccount();

           return true;
         }
      }
      return false;

    } catch (e) {
      print("Login Error: $e");
      return false;
    }
  }

  Future<bool> attemptAutoLogin() async {
    await init();
    return isAuthenticated;
  }

  Future<bool> _fetchState() async {
    if (_isDemo) {
      _applyDemoSession();
      return true;
    }
    final url = "$_baseURL/state";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        userId = data['userId'];
        if (data['user'] != null) {
          currentPrsId = data['user']['prsId'];
        }
        if (data['profile'] != null) {
           userProfile = Profile.fromJson(data['profile']);
        }

        if (userId != null) {
          return true;
        }
      } catch (e) {
        print("Error parsing state: $e");
      }
    }
    return false;
  }

  Future<Map<String, dynamic>> getPrsDiary(double d1, double d2) async {
    if (_isDemo) {
      final start = DateTime.fromMillisecondsSinceEpoch(d1.toInt());
      final end = DateTime.fromMillisecondsSinceEpoch(d2.toInt());
      return _demoData.prsDiaryJson(start, end);
    }
    if (currentPrsId == null) {
       await _fetchState();
    }

    if (currentPrsId == null) {
      throw Exception('User PrsID not found');
    }

    final url = "$_baseURL/student/getPrsDiary?prsId=$currentPrsId&d1=${d1.toInt()}&d2=${d2.toInt()}";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load diary: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getProfileNew(int prsId) async {
    if (_isDemo) {
      return _demoData.profileNewJson(prsId);
    }
    final url = "$_baseURL/profile/getProfile_new?prsId=$prsId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }
  }

  Future<File> downloadFile(String url, String filename) async {
    if (_isDemo) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString("Файл доступен для просмотра офлайн.");
      return file;
    }
    final headers = _getHeaders();
    _logRequest("GET (Download)", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);

    print("\n========== API RESPONSE (Download) ==========");
    print("Status Code: ${response.statusCode}");
    print("File Size: ${response.bodyBytes.length} bytes");
    print("===========================================\n");

    if (response.statusCode == 200) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('Failed to download file: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getThreads() async {
    if (_isDemo) {
      return _demoData.getThreads();
    }
    final url = "$_baseURL/chat/threads?newOnly=false&row=0&rowsCount=50";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load threads: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(int threadId) async {
    if (_isDemo) {
      return _demoData.getMessages(threadId);
    }
    final url = "$_baseURL/chat/messages?getNew=false&isSearch=false&rowStart=0&rowsCount=50&threadId=$threadId";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json";

    final body = jsonEncode({"msgNums": null, "searchText": null});

    final response = await _request("PUT", url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load messages: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> sendMessage(int threadId, String msgText, {List<UploadFile>? files}) async {
    if (_isDemo) {
      return _demoData.sendMessage(threadId, msgText);
    }
    final url = "$_baseURL/chat/sendNew";
    final msgUID = DateTime.now().millisecondsSinceEpoch.toString();

    final boundary = "----WebKitFormBoundary${_randomString(16)}";
    final headers = _getHeaders();
    headers["Content-Type"] = "multipart/form-data; boundary=$boundary";

    final bodyBytes = <int>[];

    void addField(String name, String value) {
      bodyBytes.addAll(utf8.encode("--$boundary\r\n"));
      bodyBytes.addAll(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
      bodyBytes.addAll(utf8.encode("$value\r\n"));
    }

    addField("threadId", threadId.toString());
    addField("msgText", msgText);
    addField("msgUID", msgUID);

    if (files != null) {
      for (final file in files) {
        bodyBytes.addAll(utf8.encode("--$boundary\r\n"));
        bodyBytes.addAll(utf8.encode('Content-Disposition: form-data; name="file"; filename="${file.name}"\r\n'));
        bodyBytes.addAll(utf8.encode('Content-Type: ${file.mimeType}\r\n\r\n'));
        bodyBytes.addAll(file.data);
        bodyBytes.addAll(utf8.encode("\r\n"));
      }
    }

    bodyBytes.addAll(utf8.encode("--$boundary--\r\n"));

    final response = await _request("POST", url, headers: headers, body: bodyBytes);

    if (response.statusCode == 200) {
      if (response.body.isNotEmpty) {
        return jsonDecode(response.body);
      }
      return {};
    } else {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (_isDemo) {
      return _demoData.searchUsers(query);
    }
    final url = "$_baseURL/usr/getUserListSearch";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> allUsers = jsonDecode(response.body);
      if (query.isEmpty) {
        return allUsers.cast<Map<String, dynamic>>();
      }
      final lowerQuery = query.toLowerCase();
      return allUsers
          .cast<Map<String, dynamic>>()
          .where((user) {
            final fio = (user['fio'] ?? '').toString().toLowerCase();
            final prsId = (user['prsId'] ?? '').toString();
            return fio.contains(lowerQuery) || prsId == query;
          })
          .toList();
    } else {
      throw Exception('Failed to search users: ${response.statusCode}');
    }
  }

  Future<int> saveThread({int? interlocutorId, String? subject, bool isGroup = false}) async {
    if (_isDemo) {
      return _demoData.saveThread(
        interlocutorId: interlocutorId,
        subject: subject,
        isGroup: isGroup,
      );
    }
    final url = "$_baseURL/chat/saveThread";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json;charset=UTF-8";

    final body = jsonEncode({
      "threadId": null,
      "senderId": null,
      "imageId": null,
      "subject": subject,
      "isAllowReplay": 2,
      "isGroup": isGroup,
      "interlocutor": interlocutorId,
    });

    final response = await _request("PUT", url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final threadId = int.tryParse(response.body);
      if (threadId != null) return threadId;
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return 0;
      }
    } else {
      throw Exception('Failed to save thread: ${response.statusCode}');
    }
  }

  Future<void> setGroupMembers(int threadId, List<Map<String, dynamic>> members) async {
    if (_isDemo) {
      return;
    }
    final url = "$_baseURL/chat/setMembers?threadId=$threadId";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json;charset=UTF-8";

    final body = jsonEncode(members.map((user) => {
      "memberId": null,
      "memberCode": "PRS",
      "memberObjId": user['prsId'],
      "memberObjName": user['fio'],
    }).toList());

    final response = await _request("PUT", url, headers: headers, body: body);

    if (response.statusCode != 200) {
      throw Exception('Failed to set group members: ${response.statusCode}');
    }
  }

  Future<void> leaveChat(int threadId) async {
    if (_isDemo) {
      return;
    }
    final url = "$_baseURL/chat/close_and_leave?threadId=$threadId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to leave chat: ${response.statusCode}');
    }
  }

  String getAvatarUrl({int? imageId, String? imgObjType, int? imgObjId}) {
    if (imageId != null) {
      return "$_baseURL/files/images/$imageId";
    }
    if (imgObjType != null && imgObjId != null) {
      return "$_baseURL/files/images/$imgObjType/$imgObjId";
    }
    return "";
  }

  String getAttachmentUrl(int msgId, int fileId) {
    return "$_baseURL/files/MAIL_ATTACH/$msgId/$fileId";
  }

  Future<File> downloadAttachment(int msgId, int fileId, String filename) async {
    final url = getAttachmentUrl(msgId, fileId);
    return await downloadFile(url, filename);
  }

  Map<String, String> get authHeaders => _getHeaders();

  Future<List<dynamic>> getClassByUser({bool forceRefresh = false}) async {
    if (_isDemo) {
      return _demoData.classByUserJson();
    }
    if (userId == null) await _fetchState();

    if (userId == null) throw Exception('User ID not found');

    final cacheKey = 'cache_class_by_user_$userId';
    final timeKey = '${cacheKey}_timestamp';
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timeKey);

      if (cached != null && timestamp != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final diff = DateTime.now().difference(savedDate);

        if (diff.inDays < 7) {
          try {
            return jsonDecode(cached);
          } catch (e) {
            print("Error parsing cached class: $e");
          }
        }
      }
    }

    final url = "$_baseURL/usr/getClassByUser?userId=$userId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get classes');
    }
  }

  Future<Map<String, dynamic>> getPeriods(int groupId, {bool forceRefresh = false}) async {
    if (_isDemo) {
      return _demoData.periodsJson();
    }
    final cacheKey = 'cache_periods_group_$groupId';
    final timeKey = '${cacheKey}_timestamp';
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(cacheKey);
      final timestamp = prefs.getInt(timeKey);

      if (cached != null && timestamp != null) {
        final savedDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final diff = DateTime.now().difference(savedDate);

        if (diff.inDays < 7) {
          try {
            return jsonDecode(cached);
          } catch (e) {
            print("Error parsing cached periods: $e");
          }
        }
      }
    }

    final url = "$_baseURL/dict/periods/0?groupId=$groupId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get periods');
    }
  }

  Future<Map<String, dynamic>> getDiaryUnits(int periodId) async {
    if (_isDemo) {
      return _demoData.diaryUnitsJson();
    }
    if (userId == null) await _fetchState();

    if (userId == null) throw Exception('User ID not found');

    final url = "$_baseURL/student/getDiaryUnits/?userId=$userId&eiId=$periodId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get diary units');
    }
  }

  Future<Map<String, dynamic>> getDiaryPeriod(int periodId) async {
    if (_isDemo) {
      return _demoData.diaryPeriodJson();
    }
    if (userId == null) await _fetchState();

    if (userId == null) throw Exception('User ID not found');

    final url = "$_baseURL/student/getDiaryPeriod_/?userId=$userId&eiId=$periodId";
    final headers = _getHeaders();

    final response = await _request("GET", url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get diary period: ${response.statusCode}');
    }
  }

  bool _isDemoCredentials(String username, String password) {
    return username == "demo" && password == "J7eVN3wl2dXu";
  }

  void _applyDemoSession() {
    _isDemo = true;
    _cookies.clear();
    isAuthenticated = true;
    userId = _demoData.userId;
    currentPrsId = _demoData.prsId;
    userProfile = _demoData.profile;
  }

}