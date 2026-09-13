import 'dart:io';

// отдельный файл без кеша не даёт процессам затирать чужой счётчик попыток
class PinAttemptStore {
  PinAttemptStore(this._file);
  final RandomAccessFile _file;

  Future<int> read() async {
    await _file.setPosition(0);
    final bytes = await _file.read(2);
    if (bytes.isEmpty) return 0; // при первом запуске и переходе со старого пин кода счётчика ещё нет
    if (bytes.length != 1 || bytes.single < 48 || bytes.single > 53) {
      throw StateError('Invalid PIN retry state');
    }
    return bytes.single - 48;
  }

  Future<void> write(int attempts) async {
    if (attempts < 0 || attempts > 5) throw StateError('Invalid attempt count');
    // не обнуляем файл при записи, иначе обрыв сбросит лимит; попытку сохраняем до проверки кода
    await _file.setPosition(0);
    await _file.writeByte(48 + attempts);
    await _file.truncate(1);
    await _file.flush();
  }
}

bool _storeBusy = false;

Future<T> withPinAttemptFile<T>(
  File retryFile,
  Future<T> Function(PinAttemptStore store) action,
) async {
  if (_storeBusy) throw StateError('PIN retry store is busy');
  _storeBusy = true;
  RandomAccessFile? file;
  try {
    await retryFile.parent.create(recursive: true);
    file = await retryFile.open(mode: FileMode.append);
    // блокировка охватывает всю попытку между процессами; при сбое хранилища или блокировки вход запрещён
    await file.lock(FileLock.exclusive);
    return await action(PinAttemptStore(file));
  } finally {
    // закрытие файла снимает блокировку и при исключении
    try {
      await file?.close();
    } finally {
      _storeBusy = false;
    }
  }
}
