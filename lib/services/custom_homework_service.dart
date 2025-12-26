import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/custom_homework.dart';

class CustomHomeworkService {
  static final CustomHomeworkService _instance = CustomHomeworkService._internal();
  factory CustomHomeworkService() => _instance;
  CustomHomeworkService._internal();

  String get _baseUrl => AppConfig.cloudFunctionsBaseUrl;

  Future<List<CustomHomework>> getHomework({
    required String token,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final url = Uri.parse('$_baseUrl/custom-homework/list');
    final body = {
      'token': token,
      if (dateFrom != null) 'date_from': _formatDate(dateFrom),
      if (dateTo != null) 'date_to': _formatDate(dateTo),
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      throw Exception('Unauthorized');
    }

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
    required String token,
    required String subject,
    required DateTime lessonDate,
    required String text,
    List<File>? files,
  }) async {
    final url = Uri.parse('$_baseUrl/custom-homework/create');

    final request = http.MultipartRequest('POST', url);
    request.fields['token'] = token;
    request.fields['subject'] = subject;
    request.fields['lesson_date'] = _formatDate(lessonDate);
    request.fields['text'] = text;

    if (files != null) {
      for (final file in files) {
        request.files.add(await http.MultipartFile.fromPath('files', file.path));
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 401) {
      throw Exception('Unauthorized');
    }

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
    }

    final data = jsonDecode(response.body);
    return CustomHomework.fromJson(data['homework'] as Map<String, dynamic>);
  }

  Future<CustomHomework> updateHomework({
    required String token,
    required int homeworkId,
    String? text,
    List<int>? deleteFileIds,
    List<File>? newFiles,
  }) async {
    final url = Uri.parse('$_baseUrl/custom-homework/update');

    final request = http.MultipartRequest('POST', url);
    request.fields['token'] = token;
    request.fields['homework_id'] = homeworkId.toString();

    if (text != null) {
      request.fields['text'] = text;
    }

    if (deleteFileIds != null && deleteFileIds.isNotEmpty) {
      request.fields['delete_file_ids'] = jsonEncode(deleteFileIds);
    }

    if (newFiles != null) {
      for (final file in newFiles) {
        request.files.add(await http.MultipartFile.fromPath('files', file.path));
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 401) {
      throw Exception('Unauthorized');
    }

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

  Future<void> deleteHomework({
    required String token,
    required int homeworkId,
  }) async {
    final url = Uri.parse('$_baseUrl/custom-homework/delete');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'homework_id': homeworkId,
      }),
    );

    if (response.statusCode == 401) {
      throw Exception('Unauthorized');
    }

    if (response.statusCode == 403) {
      throw Exception('Not authorized to delete this homework');
    }

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception(error);
    }
  }

  Future<File> downloadFile({
    required String token,
    required int fileId,
    required String fileName,
  }) async {
    final url = Uri.parse('$_baseUrl/custom-homework/file/$fileId?token=$token');

    final response = await http.get(url);

    if (response.statusCode == 401) {
      throw Exception('Unauthorized');
    }

    if (response.statusCode == 403) {
      throw Exception('Not authorized to download this file');
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to download file');
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);

    return file;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}