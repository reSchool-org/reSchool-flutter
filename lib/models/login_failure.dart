import 'dart:convert';

enum LoginFailureKind { http, timeout, network, invalidResponse, unknown }

enum LoginFailureSource { login, state, proxy }

/// оставляем только диагностику, без заголовков запросов и данных входа
class LoginFailure implements Exception {
  final LoginFailureKind kind;
  final LoginFailureSource source;
  final int? statusCode;
  final String? serverCode;
  final String? serverMessage;

  const LoginFailure({
    required this.kind,
    this.source = LoginFailureSource.login,
    this.statusCode,
    this.serverCode,
    this.serverMessage,
  });

  factory LoginFailure.response(
    int statusCode,
    String body, {
    LoginFailureSource source = LoginFailureSource.login,
  }) {
    String? code;
    String? message;
    String? field(dynamic value) {
      if (value is! String && value is! num) return null;
      final text = value.toString().trim();
      if (text.isEmpty || text.contains('<') || text.contains('>')) return null;
      return text.length > 500 ? '${text.substring(0, 500)}…' : text;
    }

    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final error = data['error'];
        final details = error is Map ? error : data;
        code = field(
          details['code'] ??
              details['errorCode'] ??
              details['error_code'] ??
              data['code'] ??
              data['errorCode'] ??
              data['error_code'],
        );
        message =
            field(
              details['message'] ??
                  details['errorMessage'] ??
                  details['description'] ??
                  data['message'] ??
                  data['errorMessage'],
            ) ??
            field(error);
      }
    } on FormatException {
      // страницы ошибок html и сырые ответы нельзя показывать пользователю
    }
    return LoginFailure(
      kind: statusCode == 200
          ? LoginFailureKind.invalidResponse
          : LoginFailureKind.http,
      source: source,
      statusCode: statusCode,
      serverCode: code,
      serverMessage: message,
    );
  }
}
