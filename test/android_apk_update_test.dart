import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reschool/services/android_apk_update.dart';

void main() {
  const base =
      'https://github.com/reSchool-org/reSchool-flutter/releases/'
      'download/v2.0.1/reSchool-v2.0.1';

  test('prefers the first published ABI supported by Android', () {
    expect(
      AndroidApkUpdate.downloadUrl('2.0.1', ['arm64-v8a', 'armeabi-v7a']),
      '$base-arm64-v8a.apk',
    );
    expect(
      AndroidApkUpdate.downloadUrl('2.0.1', ['armeabi-v7a']),
      '$base-armeabi-v7a.apk',
    );
    expect(
      AndroidApkUpdate.downloadUrl('2.0.1', ['x86_64', 'x86', 'arm64-v8a']),
      '$base-x86_64.apk',
    );
  });

  test('unknown or unavailable ABI keeps the legacy APK filename', () {
    for (final abis in [
      <String>[],
      ['riscv64'],
      ['x86'],
    ]) {
      expect(AndroidApkUpdate.downloadUrl('2.0.1', abis), '$base.apk');
    }
  });

  group('download', () {
    late Directory dir;
    late File file;
    late List<Uri> requests;
    late List<double> progress;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('reschool-update-test-');
      file = File('${dir.path}/update.apk');
      requests = [];
      progress = [];
    });

    tearDown(() async => dir.delete(recursive: true));

    Future<void> download(http.Client client, {String? url}) async {
      try {
        await AndroidApkUpdate.download(
          version: '2.0.1',
          url: url ?? '$base-arm64-v8a.apk',
          file: file,
          onProgress: progress.add,
          client: client,
        );
      } finally {
        client.close();
      }
    }

    test(
      'downloads the architecture APK without fetching the common APK',
      () async {
        await download(
          MockClient((request) async {
            requests.add(request.url);
            expect(request.method, 'GET');
            return http.Response.bytes([80, 75, 3, 4], 200);
          }),
        );
        expect(requests.map((uri) => uri.toString()), ['$base-arm64-v8a.apk']);
        expect(await file.readAsBytes(), [80, 75, 3, 4]);
        expect(progress.last, 1);
      },
    );

    for (final status in [404, 410]) {
      test('falls back to the legacy APK on HTTP $status', () async {
        await download(
          MockClient((request) async {
            requests.add(request.url);
            if (request.url.toString() == '$base-arm64-v8a.apk') {
              return http.Response('Not found', status);
            }
            return http.Response.bytes([80, 75, 3, 4], 200);
          }),
        );
        expect(requests.map((uri) => uri.toString()), [
          '$base-arm64-v8a.apk',
          '$base.apk',
        ]);
        expect(await file.readAsBytes(), [80, 75, 3, 4]);
      });
    }

    test('does not save an HTTP error or keep an old download', () async {
      await file.writeAsString('stale APK');
      await expectLater(
        download(
          MockClient((request) async {
            requests.add(request.url);
            return http.Response('Service unavailable', 503);
          }),
        ),
        throwsA(isA<HttpException>()),
      );
      expect(requests, hasLength(1));
      expect(await file.exists(), isFalse);
      expect(progress, isEmpty);
    });

    test('missing common APK fails without retrying the same URL', () async {
      await expectLater(
        download(
          MockClient((request) async {
            requests.add(request.url);
            return http.Response('Not found', 404);
          }),
          url: '$base.apk',
        ),
        throwsA(isA<HttpException>()),
      );
      expect(requests, hasLength(1));
      expect(await file.exists(), isFalse);
    });

    test('empty APK is rejected', () async {
      await expectLater(
        download(MockClient((_) async => http.Response('', 200))),
        throwsA(isA<HttpException>()),
      );
      expect(await file.exists(), isFalse);
    });

    test('interrupted download removes the partial APK', () async {
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          (() async* {
            yield [80, 75];
            throw const HttpException('Connection closed');
          })(),
          200,
          contentLength: 4,
        );
      });
      await expectLater(download(client), throwsA(isA<HttpException>()));
      expect(await file.exists(), isFalse);
    });
  });
}
