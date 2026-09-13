import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// переносим данные версии 9 в шифрование версии 10; ошибки хранилища не должны стирать данные входа
const appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  ),
);
