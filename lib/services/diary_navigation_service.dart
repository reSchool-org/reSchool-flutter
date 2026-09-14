import 'package:flutter/foundation.dart';

class DiaryNavigationRequest {
  final DateTime? date;
  final String? subject;
  final int? lessonId;
  DiaryNavigationRequest({this.date, this.subject, this.lessonId});
}

class ChatNavigationRequest {
  final int threadId;
  final int? messageNumber;
  final String title;
  final bool isGroup;

  ChatNavigationRequest({
    required this.threadId,
    this.messageNumber,
    this.title = 'Сообщения',
    this.isGroup = false,
  });
}

/// из любого места приложения умеет прыгнуть в дневник на нужную дату,
/// раскрыть предмет и переключить вкладку в HomeScreen
class DiaryNavigationService {
  static final DiaryNavigationService instance =
      DiaryNavigationService._internal();
  DiaryNavigationService._internal();

  final ValueNotifier<DiaryNavigationRequest?> pending = ValueNotifier(null);

  /// просит HomeScreen переключиться на эту вкладку
  final ValueNotifier<int?> pendingTab = ValueNotifier(null);
  final ValueNotifier<ChatNavigationRequest?> pendingChat = ValueNotifier(null);

  void request({DateTime? date, String? subject}) {
    pending.value = DiaryNavigationRequest(date: date, subject: subject);
  }

  /// переключить HomeScreen на [tabIndex] и при желании увести дневник на дату
  void switchTab(
    int tabIndex, {
    DateTime? date,
    String? subject,
    int? lessonId,
  }) {
    pendingTab.value = tabIndex;
    pendingChat.value = null;
    pending.value = null;
    if (date != null || subject != null || lessonId != null) {
      pending.value = DiaryNavigationRequest(
        date: date,
        subject: subject,
        lessonId: lessonId,
      );
    }
  }

  void openChat(ChatNavigationRequest request) {
    switchTab(3);
    pendingChat.value = request;
  }

  // подтверждаем только завершённый переход, чтобы окончание старой загрузки
  // не сбросило новый запрос
  void complete(DiaryNavigationRequest request) {
    if (identical(pending.value, request)) pending.value = null;
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
