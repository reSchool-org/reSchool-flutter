import 'dart:async';

/// сохраняем ранние ссылки, пока навигация ещё не готова
class AppLinkInbox {
  StreamSubscription<Uri>? _subscription;
  final List<Uri> _waiting = [];
  void Function(Uri)? _handler;

  void start(Stream<Uri> links) {
    _subscription ??= links.listen((uri) {
      final handler = _handler;
      if (handler == null) {
        _waiting.add(uri);
      } else {
        handler(uri);
      }
    }, onError: (Object _) {});
  }

  void attach(void Function(Uri) handler) {
    _handler = handler;
    final waiting = List<Uri>.of(_waiting);
    _waiting.clear();
    for (final uri in waiting) {
      handler(uri);
    }
  }

  void detach() => _handler = null;

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _handler = null;
    _waiting.clear();
  }
}
