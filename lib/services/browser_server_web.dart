import 'dart:js_interop';

@JS('reSchoolTransport.saveCode')
external JSPromise<JSString> _saveCode(JSString code);
@JS('reSchoolTransport.hasServer')
external JSBoolean _hasServer(JSString url);

Future<String> saveBrowserServerCode(String value) async {
  try {
    return (await _saveCode(value.toJS).toDart).toDart;
  } catch (error) {
    throw FormatException('$error');
  }
}

bool hasBrowserServer(String value) => _hasServer(value.toJS).toDart;
