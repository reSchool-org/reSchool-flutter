import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_font.dart';
import 'cloud_ui.dart';

typedef CloudCheckInterval = ({int minutes, int? maximumMinutes});

class CloudIntervalDialog extends StatefulWidget {
  final CloudCheckInterval initial;
  final int minimum;
  final int maximum;
  final bool supportsRandom;

  const CloudIntervalDialog({
    super.key,
    required this.initial,
    required this.minimum,
    required this.maximum,
    required this.supportsRandom,
  });

  @override
  State<CloudIntervalDialog> createState() => _CloudIntervalDialogState();
}

class _CloudIntervalDialogState extends State<CloudIntervalDialog> {
  final _form = GlobalKey<FormState>();
  late final _lower = TextEditingController(text: '${widget.initial.minutes}');
  late final _upper = TextEditingController(
    text:
        '${widget.initial.maximumMinutes ?? (widget.initial.minutes + 10).clamp(widget.minimum, widget.maximum)}',
  );
  late bool _random = widget.initial.maximumMinutes != null;

  @override
  void dispose() {
    _lower.dispose();
    _upper.dispose();
    super.dispose();
  }

  String? _validate(String? text, {bool upper = false}) {
    final value = int.tryParse(text?.trim() ?? '');
    if (value == null) return 'Введите число минут';
    if (value < widget.minimum || value > widget.maximum) {
      return 'Допустимо от ${widget.minimum} до ${widget.maximum} минут';
    }
    if (upper && value <= (int.tryParse(_lower.text) ?? 0)) {
      return 'Должно быть больше нижней границы';
    }
    return null;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop<CloudCheckInterval>(context, (
      minutes: int.parse(_lower.text),
      maximumMinutes: _random ? int.parse(_upper.text) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CloudTheme(
      child: AlertDialog(
        title:  Text('Частота проверки', style: appFont(context)),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title:  Text('Случайный интервал', style: appFont(context)),
                  value: _random,
                  onChanged: widget.supportsRandom
                      ? (value) => setState(() => _random = value)
                      : null,
                ),
                Text(
                  _random
                      ? 'После каждой проверки сервер выбирает новую задержку в заданном диапазоне.'
                      : 'Введите свой интервал или выберите готовый вариант.',
                  style: appFont(context,
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('interval-minutes'),
                  controller: _lower,
                  keyboardType: TextInputType.number,
                  textInputAction: _random
                      ? TextInputAction.next
                      : TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: cloudInput(
                    _random ? 'От, минут' : 'Интервал, минут',
                  ).copyWith(errorMaxLines: 3),
                  validator: (value) => _validate(value),
                  onFieldSubmitted: _random ? null : (_) => _save(),
                ),
                if (_random) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('interval-maximum'),
                    controller: _upper,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: cloudInput(
                      'До, минут',
                    ).copyWith(errorMaxLines: 3),
                    validator: (value) => _validate(value, upper: true),
                    onFieldSubmitted: (_) => _save(),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in {widget.minimum, 15, 30, 60}.where(
                        (value) =>
                            value >= widget.minimum && value <= widget.maximum,
                      ))
                        OutlinedButton(
                          onPressed: () {
                            _lower.text = '$minutes';
                            _form.currentState!.validate();
                          },
                          child: Text('$minutes мин', style: appFont(context)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'От ${widget.minimum} до ${widget.maximum} минут.',
                  style: appFont(context, fontSize: 12, color: cs.onSurfaceVariant),
                ),
                if (!widget.supportsRandom) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Для случайного интервала обновите Server Advanced.',
                    style: appFont(context,
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text('Отмена', style: appFont(context)),
          ),
          FilledButton(
            onPressed: _save,
            child:  Text('Сохранить интервал', style: appFont(context)),
          ),
        ],
      ),
    );
  }
}
