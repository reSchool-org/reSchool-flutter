import '../config/app_config.dart';

enum CloudRole {
  admin,
  user,
  classmate;

  bool get isAdmin => this == admin;
  bool get canMonitor => this != classmate;
  String get label => switch (this) {
    admin => 'Администратор',
    user => 'Пользователь с мониторингом',
    classmate => 'Пользователь без передачи пароля',
  };

  static CloudRole? parse(String? value) {
    for (final role in values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

class CloudConnectionLink {
  final String serverUrl;
  final String apiToken;
  final String inviteToken;
  final String? pin;
  final CloudRole? role;

  const CloudConnectionLink({
    required this.serverUrl,
    this.apiToken = '',
    this.inviteToken = '',
    this.pin,
    this.role,
  });

  factory CloudConnectionLink.parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'reschool' || uri.host != 'link-device') {
      throw const FormatException('Вставьте ссылку подключения reSchool');
    }
    final url = AppConfig.normalizeServerUrl(
      uri.queryParameters['server'] ?? '',
    );
    if (!AppConfig.isValidServerUrl(url)) {
      throw const FormatException('В ссылке указан неверный адрес сервера');
    }
    final apiToken = uri.queryParameters['token'] ?? '';
    final inviteToken =
        uri.queryParameters['inviteToken'] ??
        uri.queryParameters['invite'] ??
        '';
    if (apiToken.isEmpty == inviteToken.isEmpty) {
      throw const FormatException(
        'В ссылке должен быть ключ администратора или приглашение',
      );
    }
    final role = CloudRole.parse(uri.queryParameters['mode']);
    if (inviteToken.isNotEmpty && role == CloudRole.admin) {
      throw const FormatException('Приглашение не даёт прав администратора');
    }
    return CloudConnectionLink(
      serverUrl: url,
      apiToken: apiToken,
      inviteToken: inviteToken,
      pin: uri.queryParameters['pin'] ?? uri.queryParameters['fp'],
      role: role,
    );
  }
}
