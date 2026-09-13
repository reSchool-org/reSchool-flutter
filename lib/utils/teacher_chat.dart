import 'app_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../screens/chat_detail_screen.dart';

/// ищет учителя по полному ФИО и открывает с ним чат
/// пока идёт запрос, висит модальный лоадер
Future<void> openChatWithTeacher(
  BuildContext context,
  String teacherFull,
) async {
  var name = teacherFull.trim();
  if (name.isEmpty) return;
  final names = name
      .split(',')
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList();
  if (names.length > 1) {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title:  Text('Выберите преподавателя', style: appFont(dialogContext)),
        children: names
            .map(
              (teacher) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, teacher),
                child: Text(teacher, style: appFont(dialogContext)),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null || !context.mounted) return;
    name = selected;
  }
  HapticFeedback.lightImpact();

  if (!context.mounted) return;

  // показываем лоадер
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black26,
    builder: (_) => const _LoadingDialog(),
  );
  bool dialogOpen = true;

  void closeDialog() {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
    }
  }

  try {
    final api = ApiService();
    final rawUsers = await api.searchUsers(name);
    final users = rawUsers.map((m) => UserSearchItem.fromJson(m)).toList();

    // ищем точное совпадение ФИО, если его нет, берём первый результат
    UserSearchItem? match;
    final nameLower = name.toLowerCase();
    for (final u in users) {
      if ((u.fio ?? '').toLowerCase().trim() == nameLower) {
        match = u;
        break;
      }
    }
    match ??= users.firstOrNull;

    closeDialog();
    if (!context.mounted) return;

    if (match == null || match.prsId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Учитель «$name» не найден в системе', style: appFont(context)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final threadId = await api.saveThread(interlocutorId: match.prsId!);
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          threadId: threadId,
          title: match!.fio ?? name,
          isGroup: false,
          imageId: match.imageId,
          imgObjType: 'USER_PICTURE',
          imgObjId: match.prsId,
        ),
      ),
    );
  } catch (_) {
    closeDialog();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
          content: Text('Не удалось открыть чат с учителем', style: appFont(context)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Открываем чат…',
              style: appFont(context, 
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
