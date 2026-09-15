/// владелец родительской сессии и ученик имеют разные идентификаторы
class StudentContext {
  final int? prsId;
  final int? userId;

  const StudentContext({this.prsId, this.userId});

  factory StudentContext.fromState(
    Map<String, dynamic> state, {
    DateTime? now,
  }) {
    final user = state['user'] as Map? ?? const {};
    final position = user['currentPosition'] as Map? ?? const {};
    if (position['posTypeCode'] != 'P') {
      return StudentContext(
        prsId: user['prsId'] as int?,
        userId: (state['userId'] ?? user['userId']) as int?,
      );
    }
    final children = (position['myChildren'] as List? ?? const [])
        .whereType<Map>()
        .where((child) => child['prsId'] is int && child['prsId'] > 0)
        .toList();
    if (children.isEmpty) return const StudentContext();
    final child = children.firstWhere(
      (child) =>
          child['isDefaultChild'] == true || child['isDefaultChild'] == 1,
      orElse: () => children.first,
    );
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final enrollments = (child['userData'] as List? ?? const [])
        .whereType<Map>()
        .where(
          (item) =>
              (item['orgIsReady'] == true || item['orgIsReady'] == 1) &&
              item['userId'] is int &&
              item['userId'] > 0,
        )
        .toList();
    final current = enrollments
        .where(
          (item) =>
              item['fullStartDate'] is num &&
              item['fullEndDate'] is num &&
              item['fullStartDate'] <= timestamp &&
              timestamp <= item['fullEndDate'],
        )
        .toList();
    final active = enrollments
        .where((item) => item['yearState'] == 'CURR')
        .toList();
    enrollments.sort(
      (a, b) => ((b['fullStartDate'] as num?) ?? 0).compareTo(
        (a['fullStartDate'] as num?) ?? 0,
      ),
    );
    final candidates = current.isNotEmpty
        ? current
        : active.isNotEmpty
        ? active
        : enrollments;
    return StudentContext(
      prsId: child['prsId'] as int,
      userId: candidates.isEmpty ? null : candidates.first['userId'] as int,
    );
  }
}
