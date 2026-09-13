import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/homework_analysis.dart';
import 'api_service.dart';
import 'reschool_http.dart';

/// разбор домашнего задания и учебники, всё через свой сервер с пиннингом
class AnalysisService {
  static final AnalysisService _instance = AnalysisService._internal();
  factory AnalysisService() => _instance;
  AnalysisService._internal();

  // картинки заданий не меняются, так что держим их в памяти на время сессии
  final Map<String, Uint8List> _imageCache = {};

  void clearCache() => _imageCache.clear();

  Future<String> _baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('cf3_registered_server');
    if (url == null || url.isEmpty) {
      throw Exception('Сервер reSchool не подключён');
    }
    return url;
  }

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final candidates = [
      prefs.getString('cf3_verification_token'),
      ApiService().cloudToken,
      prefs.getString('classmate_token'),
      prefs.getString('cf3_registration_id'),
    ];
    for (final candidate in candidates) {
      final value = (candidate ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    throw Exception('Сервер reSchool не подключён');
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final apiToken =
        prefs.getString('cloud_api_token') ??
        prefs.getString('cf3_api_token') ??
        '';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiToken.isNotEmpty) headers['X-API-Token'] = apiToken;
    return headers;
  }

  /// подключён ли вообще сервер, без этого разбора не будет
  Future<bool> isAvailable() async {
    try {
      await _baseUrl();
      await _token();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// разбор по id, либо по предмету, дате и тексту задания
  Future<HomeworkAnalysis> getAnalysis({
    int? analysisId,
    String? subject,
    DateTime? date,
    String? text,
  }) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    final response = await reschoolHttp.post(
      Uri.parse('$baseUrl/homework/analysis'),
      headers: await _headers(),
      body: jsonEncode({
        'token': token,
        if (analysisId != null) 'analysisId': analysisId,
        if (subject != null) 'subject': subject,
        if (date != null) 'date': _formatDate(date),
        if (text != null) 'text': text,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Не удалось получить разбор');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return HomeworkAnalysis.fromJson(decoded as Map<String, dynamic>);
  }

  /// картинка задания, вырезанная сервером из учебника
  Future<Uint8List> loadImage(String path) async {
    final cached = _imageCache[path];
    if (cached != null) return cached;

    final baseUrl = await _baseUrl();
    final token = await _token();
    final separator = path.contains('?') ? '&' : '?';
    final response = await reschoolHttp.get(
      Uri.parse(
        '$baseUrl$path$separator'
        'token=${Uri.encodeQueryComponent(token)}',
      ),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Не удалось загрузить изображение');
    }
    _imageCache[path] = response.bodyBytes;
    return response.bodyBytes;
  }

  /// сводка урока, если в слоте больше одной записи
  Future<HomeworkSummary?> getSummary({
    required String subject,
    required DateTime date,
  }) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    final response = await reschoolHttp.post(
      Uri.parse('$baseUrl/homework/summary'),
      headers: await _headers(),
      body: jsonEncode({
        'token': token,
        'subject': subject,
        'date': _formatDate(date),
      }),
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return HomeworkSummary.fromJson(decoded as Map<String, dynamic>);
  }

  Future<List<Textbook>> listTextbooks() async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    final response = await reschoolHttp.post(
      Uri.parse('$baseUrl/textbook/list'),
      headers: await _headers(),
      body: jsonEncode({'token': token}),
    );
    if (response.statusCode != 200) {
      throw Exception('Не удалось загрузить список учебников');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return ((decoded['textbooks'] as List<dynamic>?) ?? [])
        .map((e) => Textbook.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// заливка pdf, прогресс отдаём наружу, файлы тут большие
  Future<Textbook> uploadTextbook({
    required File file,
    void Function(int sent, int total)? onProgress,
  }) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    final headers = await _headers();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/textbook/upload'),
    );
    headers.forEach((key, value) {
      if (key != 'Content-Type') request.headers[key] = value;
    });
    request.fields['token'] = token;

    final length = await file.length();
    request.files.add(
      http.MultipartFile(
        'file',
        _ProgressStream(file.openRead(), length, onProgress).stream,
        length,
        filename: file.uri.pathSegments.last,
      ),
    );

    final streamed = await reschoolHttp.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      final error = _errorFrom(response.body);
      throw Exception(error);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return Textbook.fromJson(decoded['textbook'] as Map<String, dynamic>);
  }

  Future<void> deleteTextbook(int id) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    final response = await reschoolHttp.delete(
      Uri.parse(
        '$baseUrl/textbook/$id?token=${Uri.encodeQueryComponent(token)}',
      ),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorFrom(response.body));
    }
  }

  String _errorFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded['error']?.toString() ?? 'Неизвестная ошибка';
    } catch (_) {
      return 'Неизвестная ошибка';
    }
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// оборачивает поток файла, чтобы показывать прогресс заливки
class _ProgressStream {
  final Stream<List<int>> stream;

  _ProgressStream(
    Stream<List<int>> source,
    int total,
    void Function(int sent, int total)? onProgress,
  ) : stream = _wrap(source, total, onProgress);

  static Stream<List<int>> _wrap(
    Stream<List<int>> source,
    int total,
    void Function(int sent, int total)? onProgress,
  ) async* {
    var sent = 0;
    await for (final chunk in source) {
      sent += chunk.length;
      onProgress?.call(sent, total);
      yield chunk;
    }
  }
}
