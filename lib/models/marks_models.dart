class GroupResponse {
  final int? groupId;
  final String? groupName;
  final double? begDate;

  GroupResponse({this.groupId, this.groupName, this.begDate});

  factory GroupResponse.fromJson(Map<String, dynamic> json) {
    return GroupResponse(
      groupId: json['groupId'],
      groupName: json['groupName'],
      begDate: (json['begDate'] as num?)?.toDouble(),
    );
  }
}

class PeriodResponse {
  final int? id;
  final int? periodId;
  final String? name;
  final double? date1;
  final double? date2;
  final String? typeCode;
  final int? parentId;
  final List<PeriodResponse>? items;

  PeriodResponse({
    this.id,
    this.periodId,
    this.name,
    this.date1,
    this.date2,
    this.typeCode,
    this.parentId,
    this.items,
  });

  factory PeriodResponse.fromJson(Map<String, dynamic> json) {
    return PeriodResponse(
      id: json['id'],
      periodId: json['periodId'],
      name: json['name'],
      date1: (json['date1'] as num?)?.toDouble(),
      date2: (json['date2'] as num?)?.toDouble(),
      typeCode: json['typeCode'],
      parentId: json['parentId'],
      items: json['items'] != null
          ? (json['items'] as List).map((i) => PeriodResponse.fromJson(i)).toList()
          : null,
    );
  }
}

class DiaryUnitResponse {
  final List<DiaryUnit>? result;

  DiaryUnitResponse({this.result});

  factory DiaryUnitResponse.fromJson(Map<String, dynamic> json) {
    return DiaryUnitResponse(
      result: json['result'] != null
          ? (json['result'] as List).map((i) => DiaryUnit.fromJson(i)).toList()
          : null,
    );
  }
}

class DiaryUnit {
  final int? unitId;
  final String? unitName;
  final double? overMark;
  final double? totalMark;
  final String? rating;

  DiaryUnit({
    this.unitId,
    this.unitName,
    this.overMark,
    this.totalMark,
    this.rating,
  });

  factory DiaryUnit.fromJson(Map<String, dynamic> json) {
    return DiaryUnit(
      unitId: json['unitId'],
      unitName: json['unitName'],
      overMark: (json['overMark'] as num?)?.toDouble(),
      totalMark: _parseDouble(json['totalMark']),
      rating: json['rating'],
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class TotalMarksResponse {
  final TotalMarksReport? report;

  TotalMarksResponse({this.report});

  factory TotalMarksResponse.fromJson(Map<String, dynamic> json) {
    return TotalMarksResponse(
      report: json['report'] != null
          ? TotalMarksReport.fromJson(json['report'])
          : null,
    );
  }
}

class TotalMarksReport {
  final UserMarksData? user;

  TotalMarksReport({this.user});

  factory TotalMarksReport.fromJson(Map<String, dynamic> json) {
    return TotalMarksReport(
      user: json['user'] != null ? UserMarksData.fromJson(json['user']) : null,
    );
  }
}

class UserMarksData {
  final List<TotalMarkItem>? mark;

  UserMarksData({this.mark});

  factory UserMarksData.fromJson(Map<String, dynamic> json) {
    return UserMarksData(
      mark: json['mark'] != null
          ? (json['mark'] as List).map((i) => TotalMarkItem.fromJson(i)).toList()
          : null,
    );
  }
}

class TotalMarkItem {
  final dynamic markVal;
  final String? periodName;
  final int? unitId;

  TotalMarkItem({this.markVal, this.periodName, this.unitId});

  factory TotalMarkItem.fromJson(Map<String, dynamic> json) {
    return TotalMarkItem(
      markVal: json['markVal'],
      periodName: json['periodName'],
      unitId: json['unitId'],
    );
  }

  String get valueStr => markVal?.toString() ?? "";
}

class DiaryPeriodResponse {
  final List<DiaryPeriodLesson>? result;

  DiaryPeriodResponse({this.result});

  factory DiaryPeriodResponse.fromJson(Map<String, dynamic> json) {
    return DiaryPeriodResponse(
      result: json['result'] != null
          ? (json['result'] as List).map((i) => DiaryPeriodLesson.fromJson(i)).toList()
          : null,
    );
  }
}

class DiaryPeriodLesson {
  final int? lessonId;
  final int? unitId;
  final String? startDt;
  final int? lesNum;
  final String? subject;
  final String? teacherFio;
  final List<DiaryPeriodPart>? part;

  DiaryPeriodLesson({
    this.lessonId,
    this.unitId,
    this.startDt,
    this.lesNum,
    this.subject,
    this.teacherFio,
    this.part,
  });

  factory DiaryPeriodLesson.fromJson(Map<String, dynamic> json) {
    return DiaryPeriodLesson(
      lessonId: json['lessonId'],
      unitId: json['unitId'],
      startDt: json['startDt'],
      lesNum: json['lesNum'],
      subject: json['subject'],
      teacherFio: json['teacherFio'],
      part: json['part'] != null
          ? (json['part'] as List).map((i) => DiaryPeriodPart.fromJson(i)).toList()
          : null,
    );
  }

  DateTime? get date {
    if (startDt == null) return null;
    try {
      return DateTime.parse(startDt!);
    } catch (_) {
      return null;
    }
  }
}

class DiaryPeriodPart {
  final String? lptName;
  final String? cat;
  final double? mrkWt;
  final List<DiaryPeriodMark>? mark;
  final List<DiaryPeriodVariant>? variant;

  DiaryPeriodPart({this.lptName, this.cat, this.mrkWt, this.mark, this.variant});

  factory DiaryPeriodPart.fromJson(Map<String, dynamic> json) {
    return DiaryPeriodPart(
      lptName: json['lptName'],
      cat: json['cat'],
      mrkWt: (json['mrkWt'] as num?)?.toDouble(),
      mark: json['mark'] != null
          ? (json['mark'] as List).map((i) => DiaryPeriodMark.fromJson(i)).toList()
          : null,
      variant: json['variant'] != null
          ? (json['variant'] as List).map((i) => DiaryPeriodVariant.fromJson(i)).toList()
          : null,
    );
  }
}

class DiaryPeriodVariant {
  final int? id;
  final String? text;

  DiaryPeriodVariant({this.id, this.text});

  factory DiaryPeriodVariant.fromJson(Map<String, dynamic> json) {
    return DiaryPeriodVariant(
      id: json['id'],
      text: json['text'],
    );
  }
}

class DiaryPeriodMark {
  final String? markValue;

  DiaryPeriodMark({this.markValue});

  factory DiaryPeriodMark.fromJson(Map<String, dynamic> json) {
    return DiaryPeriodMark(
      markValue: json['markValue']?.toString(),
    );
  }
}