import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pointycastle/export.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lesson_view_model.dart';

class ObsidianExportService {
  static const String _kmiUrl = 'https://kmi.aeza.net';

  /// случайный ключ из букв и цифр длиной [length]
  static String generateKey({int length = 32}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }

  /// шифрует [plaintext] через aes gcm, ключ выводим из [password] по pbkdf2
  /// на выходе base64(salt[16] + iv[12] + шифротекст)
  /// формат совпадает с decryptAesGcm() в плагине kmi paste для obsidian
  static String encryptAesGcm(String plaintext, String password) {
    final rng = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      seeds[i] = seedSource.nextInt(256);
    }
    rng.seed(KeyParameter(seeds));

    final salt = rng.nextBytes(16);
    final iv = rng.nextBytes(12);

    // pbkdf2 на sha256, 100000 итераций, ключ 32 байта
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
    final aesKey = pbkdf2.process(passwordBytes);

    // шифруем
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(KeyParameter(aesKey), 128, iv, Uint8List(0)),
    );

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);

    // склеиваем salt + iv + шифротекст, тег gcm pointycastle дописывает сам
    final combined = Uint8List(salt.length + iv.length + output.length);
    combined.setRange(0, salt.length, salt);
    combined.setRange(salt.length, salt.length + iv.length, iv);
    combined.setRange(salt.length + iv.length, combined.length, output);

    return base64.encode(combined);
  }

  /// заливает [content] на kmi.aeza.net и возвращает ссылку на пасту
  static Future<String> uploadToKmi(String content) async {
    final response = await http.post(
      Uri.parse(_kmiUrl),
      body: {'kmi': content},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('KMI upload failed: HTTP ${response.statusCode}');
    }
    final url = response.body.trim();
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      throw Exception('KMI returned unexpected response: $url');
    }
    return url;
  }

  /// собирает markdown заметку по [lessons] за [date]
  static String formatDayNote(DateTime date, List<LessonViewModel> lessons, {bool showMarks = true}) {
    final dateStr = DateFormat('d MMMM yyyy', 'ru').format(date);
    final weekday = DateFormat('EEEE', 'ru').format(date);
    final capitalized = weekday[0].toUpperCase() + weekday.substring(1);
    final isoDate = DateFormat('yyyy-MM-dd').format(date);

    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('дата: $isoDate');
    buf.writeln('---');
    buf.writeln();
    buf.writeln('# $capitalized, $dateStr');
    buf.writeln();

    final real = lessons.where((l) => !l.isPlaceholder).toList();
    if (real.isEmpty) {
      buf.writeln('*Уроков нет*');
      return buf.toString();
    }

    for (final lesson in real) {
      buf.writeln('## ${lesson.num}. ${lesson.subject}');
      if (lesson.teacher.isNotEmpty) {
        buf.writeln('**Учитель:** ${lesson.teacherFull.isNotEmpty ? lesson.teacherFull : lesson.teacher}');
      }
      if (lesson.startTime.isNotEmpty && lesson.endTime.isNotEmpty) {
        buf.writeln('**Время:** ${lesson.startTime} - ${lesson.endTime}');
      }
      if (lesson.topic.isNotEmpty) {
        buf.writeln('**Тема:** ${lesson.topic}');
      }
      if (showMarks && lesson.mark != null && lesson.mark!.isNotEmpty) {
        buf.writeln('**Оценка:** ${lesson.mark}');
        if (lesson.markDescription != null && lesson.markDescription!.isNotEmpty) {
          buf.writeln('**За что:** ${lesson.markDescription}');
        }
      }
      if (lesson.homework.isNotEmpty) {
        buf.writeln();
        buf.writeln('**Домашнее задание:**');
        buf.writeln(lesson.homework);
      }
      if (lesson.homeworkFiles.isNotEmpty) {
        buf.writeln();
        buf.writeln('**Прикреплённые файлы:**');
        for (final file in lesson.homeworkFiles) {
          final uri = Uri(
            scheme: 'reschool',
            host: 'file',
            queryParameters: {
              'variantId': file.variantId.toString(),
              'id': file.id.toString(),
              'name': file.name,
            },
          );
          buf.writeln('- [${file.name}]($uri)');
        }
      }
      buf.writeln();
    }

    return buf.toString().trimRight();
  }

  /// весь путь целиком: собрали, зашифровали, залили, открыли obsidian
  /// при успехе отдаёт ссылку kmi
  static Future<String> exportDayToObsidian({
    required DateTime date,
    required List<LessonViewModel> lessons,
    String? obsidianPath,
    String? obsidianVault,
    bool showMarks = true,
  }) async {
    final content = formatDayNote(date, lessons, showMarks: showMarks);
    final key = generateKey();
    final encrypted = encryptAesGcm(content, key);
    final kmiUrl = await uploadToKmi(encrypted);

    final fileName = DateFormat('yyyy-MM-dd').format(date);
    final params = {
      'file': fileName,
      'url': kmiUrl,
      'key': key,
      if (obsidianPath != null && obsidianPath.isNotEmpty) 'path': obsidianPath,
      if (obsidianVault != null && obsidianVault.isNotEmpty) 'vault': obsidianVault,
    };

    final uri = Uri(
      scheme: 'obsidian',
      host: 'kmi',
      queryParameters: params,
    );

    if (!await launchUrl(uri)) {
      throw Exception('Could not open Obsidian. Is it installed?');
    }

    return kmiUrl;
  }

  /// просто пишет [content] в [outputDir]/[fileName].md
  /// нужно на macos и windows, когда пользователь задал папку для выгрузки
  static Future<void> exportDayToDir({
    required DateTime date,
    required List<LessonViewModel> lessons,
    required String outputDir,
    bool showMarks = true,
  }) async {
    final content = formatDayNote(date, lessons, showMarks: showMarks);
    final fileName = '${DateFormat('yyyy-MM-dd').format(date)}.md';
    final dir = Directory(outputDir);
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content, flush: true);
  }
}
