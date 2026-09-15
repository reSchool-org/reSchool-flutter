class TimeUtils {
  /// Не объявляем день законченным, если время хотя бы одного урока неизвестно.
  static int? lastLessonEnd(Iterable<String> times) {
    final pattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$');
    int? latest;
    for (final time in times) {
      if (!pattern.hasMatch(time)) return null;
      final seconds = toSeconds(time);
      if (latest == null || seconds > latest) latest = seconds;
    }
    return latest;
  }

  static int toMinutes(String time) {
    final parts = time.split(':');
    if (parts.length < 2 || parts.length > 3) return -1;
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

  static String addSeconds(String time, int seconds) {
    final baseSeconds = toSeconds(time);
    if (baseSeconds == -1) return time;

    final totalSeconds = baseSeconds + seconds;
    final normalized =
        (totalSeconds % (24 * 60 * 60) + (24 * 60 * 60)) % (24 * 60 * 60);

    final h = normalized ~/ 3600;
    final m = (normalized % 3600) ~/ 60;
    final s = normalized % 60;

    // отдаём HH:MM:SS, чтобы не потерять секунды
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// переводит время в секунды, понимает и HH:MM, и HH:MM:SS
  static int toSeconds(String time) {
    final parts = time.split(':');
    if (parts.length == 2) {
      return int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60;
    } else if (parts.length == 3) {
      return int.parse(parts[0]) * 3600 +
          int.parse(parts[1]) * 60 +
          int.parse(parts[2]);
    }
    return -1;
  }

  /// время для показа пользователю, секунды прячем
  static String formatForDisplay(String time) {
    final parts = time.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return time;
  }

  static bool isTimeBetween(String start, String end, DateTime now) {
    final startSec = toSeconds(start);
    final endSec = toSeconds(end);
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;

    if (startSec == -1 || endSec == -1) return false;
    return nowSec >= startSec && nowSec < endSec;
  }
}
