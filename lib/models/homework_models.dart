import 'lesson_view_model.dart';

class HomeworkItem {
  final DateTime date;
  final String subject;
  final String text;
  final String? html;
  final List<HomeworkFile> files;
  // у lpart списка файлов нет, пока не загрузим детали,
  // но по attachCount ui уже понимает, что вложения есть
  final int? attachCount;
  final double? deadline;
  final int? partId;
  final String? catName;
  final String? teacherName;

  HomeworkItem({
    required this.date,
    required this.subject,
    required this.text,
    this.html,
    required this.files,
    this.attachCount,
    this.deadline,
    this.partId,
    this.catName,
    this.teacherName,
  });
}
