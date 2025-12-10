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

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _baseURL = "https://app.eschool.center/ec-server";
  final String _userAgent = "eSchoolMobile";
  final _storage = const FlutterSecureStorage();

  bool isAuthenticated = false;
  Map<String, String> _cookies = {};
  
  int? userId;
  int? currentPrsId;
  Profile? userProfile;
  String? _deviceModel;
  
  String get deviceModel => _deviceModel ?? "Android Device";

  Future<void> init() async {
    await _loadSession();
    await _loadDeviceModel();
  }

  Future<void> _loadSession() async {
    
    String? sessionCookie = await _storage.read(key: 'JSESSIONID');
    
    if (sessionCookie == null) {
      final prefs = await SharedPreferences.getInstance();
      sessionCookie = prefs.getString('JSESSIONID');
      if (sessionCookie != null) {
        
        await _storage.write(key: 'JSESSIONID', value: sessionCookie);
        await prefs.remove('JSESSIONID');
      }
    }

    if (sessionCookie != null) {
      _cookies['JSESSIONID'] = sessionCookie;
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

  Future<void> _saveSession() async {
    if (_cookies.containsKey('JSESSIONID')) {
      await _storage.write(key: 'JSESSIONID', value: _cookies['JSESSIONID']!);
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'JSESSIONID');
    await _storage.delete(key: 'saved_username');
    await _storage.delete(key: 'saved_password');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('JSESSIONID');
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');

    _cookies.clear();
    isAuthenticated = false;
    userId = null;
    currentPrsId = null;
    userProfile = null;
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

  void _updateCookies(http.Response response) {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      final RegExp cookieRegex = RegExp(r'(JSESSIONID)=([^;]+)');
      final match = cookieRegex.firstMatch(rawCookie);
      if (match != null) {
        _cookies[match.group(1)!] = match.group(2)!;
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
    print("URL: ${response.request?.url}");
    print("Status Code: ${response.statusCode}");
    print("Headers:");
    response.headers.forEach((key, value) {
      print("  $key: $value");
    });

    if (response.body.isNotEmpty) {
      if (response.body.length > 2000) {
        print("Response Body: ${response.body.substring(0, 2000)}... [Truncated]");
      } else {
        print("Response Body: ${response.body}");
      }
    } else {
      print("Response Body: [empty]");
    }
    print("==================================\n");
  }

  Future<bool> login(String username, String password, {bool rememberMe = false}) async {
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
      _updateCookies(response);

      if (response.statusCode == 200) {
         if (response.body.length > 5 || _cookies.containsKey('JSESSIONID')) {
           isAuthenticated = true;
           await _saveSession();
           
           if (rememberMe) {
             await _storage.write(key: 'saved_username', value: username);
             await _storage.write(key: 'saved_password', value: password);
           } else {
             await _storage.delete(key: 'saved_username');
             await _storage.delete(key: 'saved_password');
           }

           await _fetchState();
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
    
    if (_cookies.containsKey('JSESSIONID')) {
      try {
        final stateSuccess = await _fetchState();
        if (stateSuccess) {
          isAuthenticated = true;
          return true;
        }
      } catch (e) {
        print("Session invalid: $e");
      }
    }

    String? username = await _storage.read(key: 'saved_username');
    String? password = await _storage.read(key: 'saved_password');

    if (username == null || password == null) {
      final prefs = await SharedPreferences.getInstance();
      username = prefs.getString('saved_username');
      password = prefs.getString('saved_password');

      if (username != null && password != null) {
        
        final success = await login(username, password, rememberMe: true);
        if (success) {
          
          await prefs.remove('saved_username');
          await prefs.remove('saved_password');
          return true;
        }
        return false;
      }
    }

    if (username != null && password != null) {
      return await login(username, password, rememberMe: true);
    }

    return false;
  }

  Future<bool> _fetchState() async {
    final url = "$_baseURL/state";
    final headers = _getHeaders();
    
    _logRequest("GET", url, headers, null);

    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );
    
    _logResponse(response);
    _updateCookies(response);
    
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
    if (currentPrsId == null) {
       await _fetchState();
    }
    
    if (currentPrsId == null) {
      throw Exception('User PrsID not found');
    }

    final url = "$_baseURL/student/getPrsDiary?prsId=$currentPrsId&d1=${d1.toInt()}&d2=${d2.toInt()}";
    final headers = _getHeaders();

    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    
    _logResponse(response);
    _updateCookies(response);
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load diary: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getProfileNew(int prsId) async {
    final url = "$_baseURL/profile/getProfile_new?prsId=$prsId";
    final headers = _getHeaders();

    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    
    _logResponse(response);
    _updateCookies(response);
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }
  }

  Future<File> downloadFile(String url, String filename) async {
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
    final url = "$_baseURL/chat/threads?newOnly=false&row=0&rowsCount=50";
    final headers = _getHeaders();
    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load threads: ${response.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(int threadId) async {
    final url = "$_baseURL/chat/messages?getNew=false&isSearch=false&rowStart=0&rowsCount=50&threadId=$threadId";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json";

    final body = jsonEncode({"msgNums": null, "searchText": null});

    _logRequest("PUT", url, headers, body);

    final response = await http.put(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load messages: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> sendMessage(int threadId, String msgText, {List<UploadFile>? files}) async {
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

    _logRequest("POST", url, headers, files != null && files.isNotEmpty
        ? "[Multipart with ${files.length} file(s)]"
        : msgText);

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: bodyBytes,
    );
    _logResponse(response);
    _updateCookies(response);

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
    final url = "$_baseURL/usr/getUserListSearch";
    final headers = _getHeaders();
    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 200) {
      final List<dynamic> allUsers = jsonDecode(response.body);
      if (query.isEmpty) {
        return allUsers.cast<Map<String, dynamic>>();
      }
      final lowerQuery = query.toLowerCase();
      return allUsers
          .cast<Map<String, dynamic>>()
          .where((user) => (user['fio'] ?? '').toString().toLowerCase().contains(lowerQuery))
          .toList();
    } else {
      throw Exception('Failed to search users: ${response.statusCode}');
    }
  }

  Future<int> saveThread({int? interlocutorId, String? subject, bool isGroup = false}) async {
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

    _logRequest("PUT", url, headers, body);

    final response = await http.put(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    _logResponse(response);
    _updateCookies(response);

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
    final url = "$_baseURL/chat/setMembers?threadId=$threadId";
    final headers = _getHeaders();
    headers["Content-Type"] = "application/json;charset=UTF-8";

    final body = jsonEncode(members.map((user) => {
      "memberId": null,
      "memberCode": "PRS",
      "memberObjId": user['prsId'],
      "memberObjName": user['fio'],
    }).toList());

    _logRequest("PUT", url, headers, body);

    final response = await http.put(
      Uri.parse(url),
      headers: headers,
      body: body,
    );
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode != 200) {
      throw Exception('Failed to set group members: ${response.statusCode}');
    }
  }

  Future<void> leaveChat(int threadId) async {
    final url = "$_baseURL/chat/close_and_leave?threadId=$threadId";
    final headers = _getHeaders();
    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    _logResponse(response);
    _updateCookies(response);

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
    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 200) {
      
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get classes');
    }
  }

  Future<Map<String, dynamic>> getPeriods(int groupId, {bool forceRefresh = false}) async {
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
    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 200) {
      
      await prefs.setString(cacheKey, response.body);
      await prefs.setInt(timeKey, DateTime.now().millisecondsSinceEpoch);
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get periods');
    }
  }

  Future<Map<String, dynamic>> getDiaryUnits(int periodId) async {
    if (userId == null) await _fetchState();
    
    if (userId == null) throw Exception('User ID not found');

    final url = "$_baseURL/student/getDiaryUnits/?userId=$userId&eiId=$periodId";
    final headers = _getHeaders();
    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get diary units');
    }
  }

  Future<Map<String, dynamic>> getDiaryPeriod(int periodId) async {
    if (userId == null) await _fetchState();

    if (userId == null) throw Exception('User ID not found');

    final url = "$_baseURL/student/getDiaryPeriod_/?userId=$userId&eiId=$periodId";
    final headers = _getHeaders();
    _logRequest("GET", url, headers, null);

    final response = await http.get(Uri.parse(url), headers: headers);
    _logResponse(response);
    _updateCookies(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get diary period: ${response.statusCode}');
    }
  }
}
