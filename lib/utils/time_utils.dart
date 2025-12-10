import 'package:flutter/material.dart';

class TimeUtils {
  static int toMinutes(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return -1;
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String formatDuration(int minutes) {
    return '$minutes мин';
  }

  static String addMinutes(String time, int minutes) {
    final totalMinutes = toMinutes(time);
    if (totalMinutes == -1) return time;
    
    final newTotal = totalMinutes + minutes;
    
    final normalized = (newTotal % (24 * 60) + (24 * 60)) % (24 * 60);
    
    final h = normalized ~/ 60;
    final m = normalized % 60;
    
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static bool isTimeBetween(String start, String end, TimeOfDay now) {
    final startMin = toMinutes(start);
    final endMin = toMinutes(end);
    final nowMin = now.hour * 60 + now.minute;
    
    if (startMin == -1 || endMin == -1) return false;
    return nowMin >= startMin && nowMin < endMin;
  }
}
