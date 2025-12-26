import 'dart:convert';

class WidgetScheduleData {
  final String date;
  final List<WidgetLesson> lessons;
  final String lastUpdated;

  WidgetScheduleData({
    required this.date,
    required this.lessons,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'lessons': lessons.map((l) => l.toJson()).toList(),
    'lastUpdated': lastUpdated,
  };

  factory WidgetScheduleData.fromJson(Map<String, dynamic> json) {
    return WidgetScheduleData(
      date: json['date'] ?? '',
      lessons: (json['lessons'] as List?)
          ?.map((l) => WidgetLesson.fromJson(l))
          .toList() ?? [],
      lastUpdated: json['lastUpdated'] ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory WidgetScheduleData.fromJsonString(String jsonString) {
    return WidgetScheduleData.fromJson(jsonDecode(jsonString));
  }

  factory WidgetScheduleData.empty() {
    return WidgetScheduleData(
      date: '',
      lessons: [],
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }
}

class WidgetLesson {
  final int num;
  final String subject;
  final String teacher;
  final String startTime;
  final String endTime;
  final String? mark;
  final bool isPlaceholder;

  WidgetLesson({
    required this.num,
    required this.subject,
    required this.teacher,
    required this.startTime,
    required this.endTime,
    this.mark,
    this.isPlaceholder = false,
  });

  Map<String, dynamic> toJson() => {
    'num': num,
    'subject': subject,
    'teacher': teacher,
    'startTime': startTime,
    'endTime': endTime,
    'mark': mark,
    'isPlaceholder': isPlaceholder,
  };

  factory WidgetLesson.fromJson(Map<String, dynamic> json) {
    return WidgetLesson(
      num: json['num'] ?? 0,
      subject: json['subject'] ?? '',
      teacher: json['teacher'] ?? '',
      startTime: json['startTime'] ?? '',
      endTime: json['endTime'] ?? '',
      mark: json['mark'],
      isPlaceholder: json['isPlaceholder'] ?? false,
    );
  }
}

class WidgetHomeworkData {
  final List<WidgetHomeworkItem> items;
  final String lastUpdated;

  WidgetHomeworkData({
    required this.items,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'items': items.map((i) => i.toJson()).toList(),
    'lastUpdated': lastUpdated,
  };

  factory WidgetHomeworkData.fromJson(Map<String, dynamic> json) {
    return WidgetHomeworkData(
      items: (json['items'] as List?)
          ?.map((i) => WidgetHomeworkItem.fromJson(i))
          .toList() ?? [],
      lastUpdated: json['lastUpdated'] ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory WidgetHomeworkData.fromJsonString(String jsonString) {
    return WidgetHomeworkData.fromJson(jsonDecode(jsonString));
  }

  factory WidgetHomeworkData.empty() {
    return WidgetHomeworkData(
      items: [],
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }
}

class WidgetHomeworkItem {
  final String subject;
  final String text;
  final String date;
  final String? deadline;
  final bool hasFiles;

  WidgetHomeworkItem({
    required this.subject,
    required this.text,
    required this.date,
    this.deadline,
    this.hasFiles = false,
  });

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'text': text,
    'date': date,
    'deadline': deadline,
    'hasFiles': hasFiles,
  };

  factory WidgetHomeworkItem.fromJson(Map<String, dynamic> json) {
    return WidgetHomeworkItem(
      subject: json['subject'] ?? '',
      text: json['text'] ?? '',
      date: json['date'] ?? '',
      deadline: json['deadline'],
      hasFiles: json['hasFiles'] ?? false,
    );
  }
}

class WidgetGradesData {
  final String periodName;
  final List<WidgetGrade> grades;
  final String lastUpdated;

  WidgetGradesData({
    required this.periodName,
    required this.grades,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'periodName': periodName,
    'grades': grades.map((g) => g.toJson()).toList(),
    'lastUpdated': lastUpdated,
  };

  factory WidgetGradesData.fromJson(Map<String, dynamic> json) {
    return WidgetGradesData(
      periodName: json['periodName'] ?? '',
      grades: (json['grades'] as List?)
          ?.map((g) => WidgetGrade.fromJson(g))
          .toList() ?? [],
      lastUpdated: json['lastUpdated'] ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory WidgetGradesData.fromJsonString(String jsonString) {
    return WidgetGradesData.fromJson(jsonDecode(jsonString));
  }

  factory WidgetGradesData.empty() {
    return WidgetGradesData(
      periodName: '',
      grades: [],
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }
}

class WidgetGrade {
  final String subject;
  final String average;
  final String? rating;
  final int? totalMarks;

  WidgetGrade({
    required this.subject,
    required this.average,
    this.rating,
    this.totalMarks,
  });

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'average': average,
    'rating': rating,
    'totalMarks': totalMarks,
  };

  factory WidgetGrade.fromJson(Map<String, dynamic> json) {
    return WidgetGrade(
      subject: json['subject'] ?? '',
      average: json['average'] ?? '',
      rating: json['rating'],
      totalMarks: json['totalMarks'],
    );
  }
}

class WidgetDataKeys {
  static const String scheduleData = 'widget_schedule_data';
  static const String homeworkData = 'widget_homework_data';
  static const String gradesData = 'widget_grades_data';
  static const String widgetConfig = 'widget_config';
  static const String appGroup = 'group.com.magisky.reschoolbeta';
}

enum WidgetType {
  schedule,
  homework,
  grades,
}

class WidgetConfig {
  final bool scheduleEnabled;
  final bool homeworkEnabled;
  final bool gradesEnabled;
  final int homeworkItemsCount;
  final int gradesSubjectsCount;
  final bool showTeacherInSchedule;
  final bool showDeadlineInHomework;

  WidgetConfig({
    this.scheduleEnabled = true,
    this.homeworkEnabled = true,
    this.gradesEnabled = true,
    this.homeworkItemsCount = 5,
    this.gradesSubjectsCount = 6,
    this.showTeacherInSchedule = true,
    this.showDeadlineInHomework = true,
  });

  Map<String, dynamic> toJson() => {
    'scheduleEnabled': scheduleEnabled,
    'homeworkEnabled': homeworkEnabled,
    'gradesEnabled': gradesEnabled,
    'homeworkItemsCount': homeworkItemsCount,
    'gradesSubjectsCount': gradesSubjectsCount,
    'showTeacherInSchedule': showTeacherInSchedule,
    'showDeadlineInHomework': showDeadlineInHomework,
  };

  factory WidgetConfig.fromJson(Map<String, dynamic> json) {
    return WidgetConfig(
      scheduleEnabled: json['scheduleEnabled'] ?? true,
      homeworkEnabled: json['homeworkEnabled'] ?? true,
      gradesEnabled: json['gradesEnabled'] ?? true,
      homeworkItemsCount: json['homeworkItemsCount'] ?? 5,
      gradesSubjectsCount: json['gradesSubjectsCount'] ?? 6,
      showTeacherInSchedule: json['showTeacherInSchedule'] ?? true,
      showDeadlineInHomework: json['showDeadlineInHomework'] ?? true,
    );
  }

  WidgetConfig copyWith({
    bool? scheduleEnabled,
    bool? homeworkEnabled,
    bool? gradesEnabled,
    int? homeworkItemsCount,
    int? gradesSubjectsCount,
    bool? showTeacherInSchedule,
    bool? showDeadlineInHomework,
  }) {
    return WidgetConfig(
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      homeworkEnabled: homeworkEnabled ?? this.homeworkEnabled,
      gradesEnabled: gradesEnabled ?? this.gradesEnabled,
      homeworkItemsCount: homeworkItemsCount ?? this.homeworkItemsCount,
      gradesSubjectsCount: gradesSubjectsCount ?? this.gradesSubjectsCount,
      showTeacherInSchedule: showTeacherInSchedule ?? this.showTeacherInSchedule,
      showDeadlineInHomework: showDeadlineInHomework ?? this.showDeadlineInHomework,
    );
  }
}