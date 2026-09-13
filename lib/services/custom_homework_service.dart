import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/custom_homework.dart';
import 'api_service.dart';
import 'reschool_http.dart';

class CustomHomeworkService {
  static final CustomHomeworkService _instance =
      CustomHomeworkService._internal();
  factory CustomHomeworkService() => _instance;
  CustomHomeworkService._internal();

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('cf3_registered_server');
    if (url == null) throw Exception('Not registered with cloud server');
    return url;
  }

  Future<String> _getHomeworkToken() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenFromPrefs =
        (prefs.getString('cf3_verification_token') ?? '').trim();
    if (tokenFromPrefs.isNotEmpty) return tokenFromPrefs;

    final accountToken = (ApiService().cloudToken ?? '').trim();
    if (accountToken.isNotEmpty) return accountToken;

    // одноклассник: сервер смотрит на заголовок с api токеном, а поле токена в форме игнорит,
    // но пустым его слать нельзя, иначе сработает локальная проверка
    final classmateToken = (prefs.getString('classmate_token') ?? '').trim();
    if (classmateToken.isNotEmpty) return classmateToken;

    // старые версии приложения слали тут registrationId, поддерживаем
    final legacyRegistrationId =
        (prefs.getString('cf3_registration_id') ?? '').trim();
    if (legacyRegistrationId.isNotEmpty) return legacyRegistrationId;

    throw Exception('Not registered with cloud server');
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final apiToken = prefs.getString('cloud_api_token') ??
        prefs.getString('cf3_api_token') ??
        '';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiToken.isNotEmpty) headers['X-API-Token'] = apiToken;
    return headers;
  }

  Future<List<CustomHomework>> getHomework({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getHomeworkToken();
    final url = Uri.parse('$baseUrl/custom-homework/list');
    final body = {
      'token': token,
      if (dateFrom != null) 'date_from': _formatDate(dateFrom),
      if (dateTo != null) 'date_to': _formatDate(dateTo),
    };

    final response = await reschoolHttp.post(
      url,
      headers: await _headers(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) {
      throw Exception('Failed to load homework: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final List<dynamic> homeworkList = data['homework'] ?? [];
    return homeworkList
        .map((json) => CustomHomework.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<CustomHomework> createHomework({
    required String subject,
    required DateTime lessonDate,
    required String text,
    List<File>? files,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getHomeworkToken();
    final headers = await _headers();
    final url = Uri.parse('$baseUrl/custom-homework/create');

    final request = http.MultipartRequest('POST', url);
    headers.forEach((k, v) => request.headers[k] = v);
    request.fields['token'] = token;
    request.fields['subject'] = subject;
    request.fields['lesson_date'] = _formatDate(lessonDate);
    request.fields['text'] = text;

    if (files != null) {
      for (final file in files) {
        request.files
            .add(await http.MultipartFile.fromPath('files', file.path));
      }
    }

    final streamedResponse = await reschoolHttp.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
    }

    final data = jsonDecode(response.body);
    return CustomHomework.fromJson(data['homework'] as Map<String, dynamic>);
  }

  Future<CustomHomework> updateHomework({
    required int homeworkId,
    String? text,
    List<int>? deleteFileIds,
    List<File>? newFiles,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getHomeworkToken();
    final headers = await _headers();
    final url = Uri.parse('$baseUrl/custom-homework/update');

    final request = http.MultipartRequest('POST', url);
    headers.forEach((k, v) => request.headers[k] = v);
    request.fields['token'] = token;
    request.fields['homework_id'] = homeworkId.toString();

    if (text != null) request.fields['text'] = text;
    if (deleteFileIds != null && deleteFileIds.isNotEmpty) {
      request.fields['delete_file_ids'] = jsonEncode(deleteFileIds);
    }
    if (newFiles != null) {
      for (final file in newFiles) {
        request.files
            .add(await http.MultipartFile.fromPath('files', file.path));
      }
    }

    final streamedResponse = await reschoolHttp.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 403) {
      throw Exception('Not authorized to edit this homework');
    }
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
    }

    final data = jsonDecode(response.body);
    return CustomHomework.fromJson(data['homework'] as Map<String, dynamic>);
  }

  Future<void> deleteHomework({required int homeworkId}) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getHomeworkToken();
    final url = Uri.parse('$baseUrl/custom-homework/delete');

    final response = await reschoolHttp.post(
      url,
      headers: await _headers(),
      body: jsonEncode({'token': token, 'homework_id': homeworkId}),
    );

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 403) {
      throw Exception('Not authorized to delete this homework');
    }
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
    }
  }

  Future<File> downloadFile({
    required int fileId,
    required String fileName,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getHomeworkToken();
    final url = Uri.parse('$baseUrl/custom-homework/file/$fileId?token=$token');
    final headers = await _headers();

    final response = await reschoolHttp.get(url, headers: headers);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 403) {
      throw Exception('Not authorized to download this file');
    }
    if (response.statusCode != 200) throw Exception('Failed to download file');

    final tempDir = await getTemporaryDirectory();
    final safeName = _safeDownloadFileName(fileName, fileId);
    final file = File('${tempDir.path}${Platform.pathSeparator}$safeName');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  String _safeDownloadFileName(String fileName, int fileId) {
    final parts = fileName.replaceAll('\\', '/').split('/');
    final baseName = parts.isEmpty ? '' : parts.last.trim();
    final sanitized = baseName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceFirst(RegExp(r'^\.+'), '');
    if (sanitized.isEmpty) return 'file_$fileId';
    return sanitized;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
