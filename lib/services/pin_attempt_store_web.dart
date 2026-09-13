import 'dart:js_interop';

@JS('navigator.locks.request')
external JSPromise<JSAny?> _requestLock(JSString name, JSFunction callback);

@JS('localStorage.getItem')
external JSString? _getItem(JSString key);

@JS('localStorage.setItem')
external void _setItem(JSString key, JSString value);

class PinAttemptStore {
  static const _key = 'reschool_pin_attempts_v1';

  Future<int> read() async {
    final value = _getItem(_key.toJS)?.toDart;
    if (value == null) return 0;
    if (!RegExp(r'^[0-5]$').hasMatch(value)) {
      throw StateError('Invalid PIN retry state');
    }
    return int.parse(value);
  }

  Future<void> write(int attempts) async {
    if (attempts < 0 || attempts > 5) throw StateError('Invalid attempt count');
    _setItem(_key.toJS, attempts.toString().toJS);
  }
}

Future<T> withPinAttemptStore<T>(
  Future<T> Function(PinAttemptStore store) action,
) async {
  late T result;
  // web locks упорядочивает вкладки одного сайта; при сбое остаётся восстановление паролем
  await _requestLock(
    'reschool_pin_attempts_v1'.toJS,
    ((JSAny? _) {
      return (() async {
        result = await action(PinAttemptStore());
        return null;
      })().toJS;
    }).toJS,
  ).toDart;
  return result;
}
