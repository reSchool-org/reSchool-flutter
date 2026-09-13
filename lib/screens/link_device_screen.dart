import 'package:flutter/material.dart';
import '../models/cloud_connection.dart';
import 'cloud_connection_screen.dart';

/// внешняя ссылка только заполняет форму, выбор передачи пароля остаётся за пользователем
class LinkDeviceScreen extends StatelessWidget {
  final String serverUrl;
  final String apiToken;
  final String? inviteToken;
  final int checkIntervalMinutes;
  final CloudRole? role;
  final String? pin;

  const LinkDeviceScreen({
    super.key,
    required this.serverUrl,
    required this.apiToken,
    this.inviteToken,
    required this.checkIntervalMinutes,
    this.role,
    this.pin,
  });

  bool get isClassmateMode => (inviteToken ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) => CloudConnectionScreen(
    role: isClassmateMode ? role ?? CloudRole.classmate : CloudRole.admin,
    initialLink: CloudConnectionLink(
      serverUrl: serverUrl,
      apiToken: apiToken,
      inviteToken: inviteToken ?? '',
      role: role,
      pin: pin,
    ),
  );
}
