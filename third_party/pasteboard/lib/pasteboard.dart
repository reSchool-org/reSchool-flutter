import 'dart:async';
import 'dart:typed_data';

import 'src/pasteboard_platform_web.dart'
    if (dart.library.io) 'src/pasteboard_platform_io.dart';

class Pasteboard {
  /// изображения читаются на ios, android, вебе и десктопе
  static Future<Uint8List?> get image => pasteboard.image;

  /// чтение html доступно только на windows и в вебе, формат описан в документации microsoft
  static Future<String?> get html => pasteboard.html;

  /// запись изображения доступна на ios, android и в вебе
  static Future<void> writeImage(Uint8List? image) =>
      pasteboard.writeImage(image);

  /// на android пути из буфера имеют схему content и читаются через content resolver; на десктопе это пути файлов
  static Future<List<String>> files() => pasteboard.files();

  /// запись файлов в буфер доступна только на десктопе
  static Future<bool> writeFiles(List<String> files) =>
      pasteboard.writeFiles(files);

  /// чтение текста поддерживают все платформы
  static Future<String?> get text => pasteboard.text;

  /// запись текста поддерживают все платформы
  static void writeText(String value) => pasteboard.writeText(value);
}
