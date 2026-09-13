import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/reschool_http.dart';
import '../services/tls_pin_store.dart';
import '../utils/app_font.dart';

/// проверяет сертификат сервера и, если он самоподписанный и незнакомый,
/// показывает отпечаток и просит сверить его с тем, что напечатал сервер
/// возвращает true, когда серверу можно доверять: либо сертификат обычный,
/// либо ключ уже закреплён, либо пользователь только что его подтвердил
Future<bool> ensureServerTrusted(BuildContext context, String serverUrl) async {
  final result = await inspectServerTrust(serverUrl);
  if (!context.mounted) return result.isReady;

  // до сервера не достучались, пусть в этом разбирается обычный запрос со своей ошибкой
  if (result.trust == ServerTrust.unreachable) return true;
  if (result.isReady) return true;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TrustDialog(serverUrl: serverUrl, result: result),
  );

  if (confirmed != true) return false;

  await TlsPinStore.instance.savePin(serverUrl, result.pin);
  return true;
}

class _TrustDialog extends StatelessWidget {
  const _TrustDialog({required this.serverUrl, required this.result});

  final String serverUrl;
  final ServerTrustResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final changed = result.trust == ServerTrust.changed;
    final host = Uri.tryParse(serverUrl)?.host ?? serverUrl;

    return AlertDialog(
      icon: Icon(
        changed ? Icons.gpp_maybe_outlined : Icons.verified_user_outlined,
        color: changed ? colorScheme.error : colorScheme.primary,
      ),
      title: Text(
        changed ? 'Сертификат сервера изменился' : 'Подтвердите сервер',
        style: appFont(context, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              changed
                  ? 'Раньше $host показывал другой ключ. Так бывает после переустановки '
                      'сервера, но так же выглядит и перехват соединения. Подтверждайте, '
                      'только если сервер действительно переустанавливали.'
                  : 'У $host свой сертификат, без домена и Let\'s Encrypt. Соединение '
                      'шифруется, но проверить сертификат может только владелец сервера. '
                      'Сверьте отпечаток с тем, что сервер напечатал при запуске.',
              style: appFont(context, fontSize: 14, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _FingerprintBox(
              label: 'Отпечаток ключа',
              value: result.pin,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _FingerprintBox(
              label: 'Сертификат SHA-256',
              value: result.fingerprint,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 12),
            Text(
              'Команда на сервере: docker compose logs certgen',
              style: appFont(context, fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Отмена', style: appFont(context, fontSize: 14)),
        ),
        FilledButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop(true);
          },
          style: changed
              ? FilledButton.styleFrom(backgroundColor: colorScheme.error)
              : null,
          child: Text('Доверять', style: appFont(context, fontSize: 14)),
        ),
      ],
    );
  }
}

class _FingerprintBox extends StatelessWidget {
  const _FingerprintBox({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: appFont(context, fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            HapticFeedback.selectionClick();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              value,
              style: appFont(context,
                fontSize: 12,
                height: 1.4,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
