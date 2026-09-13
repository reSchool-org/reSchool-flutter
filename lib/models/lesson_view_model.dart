class LessonViewModel {
  final int id;
  final int num;
  final String subject;
  final String topic;
  final String teacher;
  final String teacherFull;
  final String homework;
  final String? homeworkHtml;
  final double? homeworkDeadline;
  final List<HomeworkFile> homeworkFiles;
  // для домашнего задания lpart в списке приходит только превью и attachCnt, остальное тянем по partId
  final int? homeworkPartId;
  final int? homeworkAttachCount;
  final String? mark;
  final String? markDescription;
  final double? markWeight;
  final String startTime;
  final String endTime;
  final bool isPlaceholder;

  LessonViewModel({
    required this.id,
    required this.num,
    required this.subject,
    required this.topic,
    required this.teacher,
    required this.teacherFull,
    required this.homework,
    this.homeworkHtml,
    this.homeworkDeadline,
    required this.homeworkFiles,
    this.homeworkPartId,
    this.homeworkAttachCount,
    this.mark,
    this.markDescription,
    this.markWeight,
    required this.startTime,
    required this.endTime,
    this.isPlaceholder = false,
  });

  LessonViewModel copyWith({
    int? id,
    int? num,
    String? subject,
    String? topic,
    String? teacher,
    String? teacherFull,
    String? homework,
    String? homeworkHtml,
    double? homeworkDeadline,
    List<HomeworkFile>? homeworkFiles,
    int? homeworkPartId,
    int? homeworkAttachCount,
    String? mark,
    String? markDescription,
    double? markWeight,
    String? startTime,
    String? endTime,
    bool? isPlaceholder,
  }) {
    return LessonViewModel(
      id: id ?? this.id,
      num: num ?? this.num,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      teacher: teacher ?? this.teacher,
      teacherFull: teacherFull ?? this.teacherFull,
      homework: homework ?? this.homework,
      homeworkHtml: homeworkHtml ?? this.homeworkHtml,
      homeworkDeadline: homeworkDeadline ?? this.homeworkDeadline,
      homeworkFiles: homeworkFiles ?? this.homeworkFiles,
      homeworkPartId: homeworkPartId ?? this.homeworkPartId,
      homeworkAttachCount: homeworkAttachCount ?? this.homeworkAttachCount,
      mark: mark ?? this.mark,
      markDescription: markDescription ?? this.markDescription,
      markWeight: markWeight ?? this.markWeight,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isPlaceholder: isPlaceholder ?? this.isPlaceholder,
    );
  }

  factory LessonViewModel.placeholder({
    required int num,
    required String startTime,
    required String endTime,
  }) {
    return LessonViewModel(
      id: -num,
      num: num,
      subject: "Урок не указан",
      topic: "",
      teacher: "",
      teacherFull: "",
      homework: "",
      homeworkFiles: [],
      homeworkPartId: null,
      homeworkAttachCount: 0,
      startTime: startTime,
      endTime: endTime,
      isPlaceholder: true,
    );
  }
}

class HomeworkFile {
  final int id;
  final String name;
  final int variantId;
  final String? url;

  HomeworkFile({
    required this.id,
    required this.name,
    required this.variantId,
    this.url,
  });
}
