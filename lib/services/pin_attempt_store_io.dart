import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'pin_attempt_file.dart';
export 'pin_attempt_file.dart' show PinAttemptStore;

Future<T> withPinAttemptStore<T>(
  Future<T> Function(PinAttemptStore store) action,
) async {
  final directory = await getApplicationSupportDirectory();
  return withPinAttemptFile(File('${directory.path}/pin_attempts_v1'), action);
}
