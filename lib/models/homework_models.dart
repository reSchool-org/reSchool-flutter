import 'lesson_view_model.dart';

class HomeworkItem {
  final DateTime date;
  final String subject;
  final String text;
  final List<HomeworkFile> files;
  final double? deadline;

  HomeworkItem({
    required this.date,
    required this.subject,
    required this.text,
    required this.files,
    this.deadline,
  });
}