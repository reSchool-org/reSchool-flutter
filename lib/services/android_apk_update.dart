import 'dart:io';

import 'package:http/http.dart' as http;

/// имена apk должны совпадать с файлами релиза
class AndroidApkUpdate {
  static String downloadUrl(String version, List<String> supportedAbis) {
    const publishedAbis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};
    // андроид уже отсортировал архитектуры по предпочтению устройства
    final abi = supportedAbis.where(publishedAbis.contains).firstOrNull;
    final suffix = abi == null ? '' : '-$abi';
    return 'https://github.com/reSchool-org/reSchool-flutter/releases/download/'
        'v$version/reSchool-v$version$suffix.apk';
  }

  static Future<void> download({
    required String version,
    required String url,
    required File file,
    required void Function(double) onProgress,
    http.Client? client,
  }) async {
    final downloadClient = client ?? http.Client();
    try {
      var response = await downloadClient.send(
        http.Request('GET', Uri.parse(url)),
      );
      final fallbackUrl = downloadUrl(version, const []);
      if ((response.statusCode == 404 || response.statusCode == 410) &&
          url != fallbackUrl) {
        await response.stream.drain<void>();
        response = await downloadClient.send(
          http.Request('GET', Uri.parse(fallbackUrl)),
        );
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw HttpException(
          'Не удалось скачать APK: HTTP ${response.statusCode}',
        );
      }

      final contentLength = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength != null && contentLength > 0) {
            onProgress(received / contentLength);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0 ||
          (contentLength != null && received != contentLength)) {
        throw const HttpException('APK скачан не полностью');
      }
      onProgress(1);
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      if (client == null) downloadClient.close();
    }
  }
}
