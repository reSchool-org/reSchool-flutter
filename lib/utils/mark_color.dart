import 'package:flutter/material.dart';

final _markModifier = RegExp(r'\s*[+−-]$');

/// цвет берём по основной оценке, модификаторы оставляем в тексте
Color colorForMark(String mark) {
  final base = mark.trim().replaceFirst(_markModifier, '');
  return switch (base) {
    '5' => const Color(0xFF22C55E),
    '4' => const Color(0xFF3B82F6),
    '3' => const Color(0xFFF59E0B),
    '2' || '1' => const Color(0xFFEF4444),
    _ => Colors.grey,
  };
}
