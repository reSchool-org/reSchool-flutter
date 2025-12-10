class LessonViewModel {
  final int id;
  final int num;
  final String subject;
  final String topic;
  final String teacher;
  final String teacherFull;
  final String homework;
  final double? homeworkDeadline;
  final List<HomeworkFile> homeworkFiles;
  final String? mark;
  final String? markDescription;
  final double? markWeight;
  final String startTime;
  final String endTime;

  LessonViewModel({
    required this.id,
    required this.num,
    required this.subject,
    required this.topic,
    required this.teacher,
    required this.teacherFull,
    required this.homework,
    this.homeworkDeadline,
    required this.homeworkFiles,
    this.mark,
    this.markDescription,
    this.markWeight,
    required this.startTime,
    required this.endTime,
  });

  LessonViewModel copyWith({
    int? id,
    int? num,
    String? subject,
    String? topic,
    String? teacher,
    String? teacherFull,
    String? homework,
    double? homeworkDeadline,
    List<HomeworkFile>? homeworkFiles,
    String? mark,
    String? markDescription,
    double? markWeight,
    String? startTime,
    String? endTime,
  }) {
    return LessonViewModel(
      id: id ?? this.id,
      num: num ?? this.num,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      teacher: teacher ?? this.teacher,
      teacherFull: teacherFull ?? this.teacherFull,
      homework: homework ?? this.homework,
      homeworkDeadline: homeworkDeadline ?? this.homeworkDeadline,
      homeworkFiles: homeworkFiles ?? this.homeworkFiles,
      mark: mark ?? this.mark,
      markDescription: markDescription ?? this.markDescription,
      markWeight: markWeight ?? this.markWeight,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

class HomeworkFile {
  final int id;
  final String name;
  final int variantId;

  HomeworkFile({required this.id, required this.name, required this.variantId});
}
