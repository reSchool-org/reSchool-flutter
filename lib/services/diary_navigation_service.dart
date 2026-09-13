import 'package:flutter/foundation.dart';

class DiaryNavigationRequest {
  final DateTime? date;
  final String? subject;
  DiaryNavigationRequest({this.date, this.subject});
}

/// из любого места приложения умеет прыгнуть в дневник на нужную дату,
/// раскрыть предмет и переключить вкладку в HomeScreen
class DiaryNavigationService {
  static final DiaryNavigationService instance = DiaryNavigationService._internal();
  DiaryNavigationService._internal();

  final ValueNotifier<DiaryNavigationRequest?> pending = ValueNotifier(null);

  /// просит HomeScreen переключиться на эту вкладку
  final ValueNotifier<int?> pendingTab = ValueNotifier(null);

  void request({DateTime? date, String? subject}) {
    pending.value = DiaryNavigationRequest(date: date, subject: subject);
  }

  /// переключить HomeScreen на [tabIndex] и при желании увести дневник на дату
  void switchTab(int tabIndex, {DateTime? date, String? subject}) {
    if (date != null || subject != null) {
      pending.value = DiaryNavigationRequest(date: date, subject: subject);
    }
    pendingTab.value = tabIndex;
  }

  DiaryNavigationRequest? consume() {
    final req = pending.value;
    pending.value = null;
    return req;
  }

  int? consumeTab() {
    final t = pendingTab.value;
    pendingTab.value = null;
    return t;
  }
}
