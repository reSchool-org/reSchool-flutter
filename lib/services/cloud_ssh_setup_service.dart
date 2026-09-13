import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';

import 'advanced_cloud_service.dart';

class CloudSshResult {
  final String serverUrl;
  final String apiToken;
  final String pin;
  const CloudSshResult(this.serverUrl, this.apiToken, this.pin);
}

class CloudSshSetupService {
  SSHClient? _client;
  void cancel() => _client?.close();

  Future<CloudSshResult> install({
    required String host,
    required int port,
    required String username,
    required String password,
    required Future<bool> Function(String fingerprint) verifyHost,
    required void Function(String message) onProgress,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9.:_-]+$').hasMatch(host) ||
        port < 1 ||
        port > 65535) {
      throw const CloudException('Проверьте IP адрес и порт SSH');
    }
    final serverUrl = Uri(scheme: 'https', host: host, port: 4443).toString();
    onProgress('Подключаюсь по SSH');
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 20),
    );
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
      onVerifyHostKey: (_, fingerprint) => verifyHost(utf8.decode(fingerprint)),
      handshakeTimeout: const Duration(seconds: 30),
      authTimeout: const Duration(seconds: 30),
    );
    _client = client;
    String? remoteDir;
    try {
      await client.authenticated;
      final created = await client.runWithResult(
        'umask 077; mktemp -d /tmp/reschool.XXXXXXXX',
      );
      remoteDir = utf8.decode(created.stdout).trim();
      if (created.exitCode != 0 ||
          !RegExp(r'^/tmp/reschool\.[a-zA-Z0-9]+$').hasMatch(remoteDir)) {
        throw const CloudException('Не удалось подготовить папку установки');
      }
      onProgress('Передаю файлы сервера');
      final sftp = await client.sftp();
      for (final entry in {
        'server.tar.gz': 'assets/cloud/server.tar.gz',
      }.entries) {
        final data = await rootBundle.load(entry.value);
        final file = await sftp.open(
          '$remoteDir/${entry.key}',
          mode:
              SftpFileOpenMode.create |
              SftpFileOpenMode.write |
              SftpFileOpenMode.truncate,
        );
        await file.writeBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        await file.close();
      }
      final config = await sftp.open(
        '$remoteDir/connection.json',
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      await config.writeBytes(
        Uint8List.fromList(
          utf8.encode(jsonEncode({'host': host, 'serverUrl': serverUrl})),
        ),
      );
      await config.close();
      final uid = await client.runWithResult('id -u');
      final root = utf8.decode(uid.stdout).trim() == '0';
      final command =
          'tar -xzOf $remoteDir/server.tar.gz deploy/cloud-bootstrap.sh '
          '> $remoteDir/bootstrap.sh && '
          '${root ? '' : "sudo -S -p '' "}bash $remoteDir/bootstrap.sh $remoteDir';
      final session = await client.execute(command);
      if (!root) {
        session.stdin.add(Uint8List.fromList(utf8.encode('$password\n')));
      }
      await session.stdin.close();
      Map<String, dynamic>? result;
      String? error;
      final stdoutDone = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            if (line.startsWith('RESCHOOL_STAGE:')) {
              onProgress(line.substring(15));
            }
            if (line.startsWith('RESCHOOL_ERROR:')) error = line.substring(15);
            if (line.startsWith('RESCHOOL_RESULT:')) {
              result =
                  jsonDecode(utf8.decode(base64Decode(line.substring(16))))
                      as Map<String, dynamic>;
            }
          });
      // вывод пакетов не показываем, там могут оказаться значения конфигурации
      final stderrDone = session.stderr.drain<void>();
      await Future.wait([
        stdoutDone,
        stderrDone,
        session.done,
      ]).timeout(const Duration(minutes: 25));
      if (session.exitCode != 0 ||
          result == null ||
          result!['apiToken'] is! String ||
          result!['pin'] is! String) {
        throw CloudException(
          error ??
              'Установка не завершена. Проверьте права sudo и доступ сервера к интернету',
        );
      }
      return CloudSshResult(
        serverUrl,
        result!['apiToken'] as String,
        result!['pin'] as String,
      );
    } finally {
      if (remoteDir != null && !client.isClosed) {
        try {
          await client
              .run('rm -rf $remoteDir')
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      client.close();
      _client = null;
    }
  }
}
