import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'secure_storage.dart';
import 'pin_attempt_store.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class PinService {
  static final PinService _instance = PinService._internal();
  factory PinService() => _instance;
  PinService._internal();

  static const _storage = appSecureStorage;
  static const _pinKey = 'app_pin_hash';
  static const _pinInsecureKey = 'app_pin_hash_insecure';
  static const _biometricsKey = 'biometrics_enabled';
  static const _maxAttempts = 5;

  // повторный вызов не должен расходовать попытку параллельно, процессы согласует хранилище
  bool _verifying = false;

  Future<bool> isPinLocked() async {
    try {
      return await withPinAttemptStore((store) async => await store.read() >= _maxAttempts);
    } catch (_) {
      return true;
    }
  }

  final LocalAuthentication _localAuth = LocalAuthentication();

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode('reschool_pin_$pin')).toString();
  }

  Future<bool> isPinEnabled() async {
    try {
      final hash = await _storage.read(key: _pinKey);
      if (hash != null) return true;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinInsecureKey) != null;
  }

  Future<void> setPin(String pin) async {
    await withPinAttemptStore((store) async {
      final hash = _hashPin(pin);
      try {
        await _storage.write(key: _pinKey, value: hash);
      } catch (_) {
        // сохраняем прежний запасной вариант для платформ без защищённого хранилища
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_pinInsecureKey, hash)) {
          throw StateError('Cannot persist PIN');
        }
      }
      // настройка пин кода доступна только после входа в аккаунт
      await store.write(0);
    });
  }

  Future<bool> verifyPin(String pin) async {
    if (_verifying || !RegExp(r'^[0-9]{4}$').hasMatch(pin)) return false;
    _verifying = true;
    try {
      return await withPinAttemptStore((store) async {
        final attempts = await store.read();
        if (attempts >= _maxAttempts) return false;
        // сохраняем попытку до чтения и сравнения обеих копий пин кода
        await store.write(attempts + 1);
        String? stored;
        try {
          stored = await _storage.read(key: _pinKey);
        } catch (_) {}
        if (stored == null) {
          final prefs = await SharedPreferences.getInstance();
          stored = prefs.getString(_pinInsecureKey);
        }
        if (stored == null || stored != _hashPin(pin)) return false;
        await store.write(0);
        return true;
      });
    } catch (_) {
      return false;
    } finally {
      _verifying = false;
    }
  }

  Future<void> removePin() async {
    try {
      await _storage.delete(key: _pinKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinInsecureKey);
    await setBiometricsEnabled(false);
  }

  Future<void> setBiometricsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricsKey, value);
  }

  Future<bool> isBiometricsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricsKey) ?? false;
  }

  Future<bool> isBiometricsAvailable() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isWindows || Platform.isLinux) return false;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!isSupported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      return canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      // biometricOnly: true на андроиде сужает аутентификацию
      // до сильной и слабой биометрии и ломается на части устройств с api ниже 30,
      // с false системный диалог нормально работает везде
      final biometricOnly = !Platform.isAndroid;
      return await _localAuth.authenticate(
        localizedReason: 'Войдите в приложение с помощью биометрии',
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
