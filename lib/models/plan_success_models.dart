class PlanSuccessResponse {
  final PlanSuccessRoot? root;

  PlanSuccessResponse({this.root});

  factory PlanSuccessResponse.fromJson(Map<String, dynamic> json) {
    return PlanSuccessResponse(
      root: json['root'] != null ? PlanSuccessRoot.fromJson(json['root']) : null,
    );
  }
}

class PlanSuccessRoot {
  final List<PlanSuccessTopic> topics;
  final List<PlanSuccessAvgItem> userAvg;
  final PlanSuccessUser? user;
  final int? markSysId;
  final int? isUseAccumMarkSys;
  final String? orgNameShort;

  PlanSuccessRoot({
    required this.topics,
    required this.userAvg,
    this.user,
    this.markSysId,
    this.isUseAccumMarkSys,
    this.orgNameShort,
  });

  factory PlanSuccessRoot.fromJson(Map<String, dynamic> json) {
    final topicsJson = (json['topic'] as List?) ?? const [];
    final userAvgJson = (json['user_avg'] as List?) ?? const [];

    return PlanSuccessRoot(
      topics: topicsJson.map((e) => PlanSuccessTopic.fromJson(e)).toList(),
      userAvg: userAvgJson.map((e) => PlanSuccessAvgItem.fromJson(e)).toList(),
      user: json['user'] != null ? PlanSuccessUser.fromJson(json['user']) : null,
      markSysId: json['mark_sys_id'] as int?,
      isUseAccumMarkSys: json['is_use_accum_mark_sys'] as int?,
      orgNameShort: json['org_name_short'] as String?,
    );
  }
}

class PlanSuccessTopic {
  final DateTime? minLessonDate;
  final DateTime? maxLessonDate;
  final int rn;
  final String topicName;
  final String sectionName;
  final int lessonCount;

  PlanSuccessTopic({
    required this.minLessonDate,
    required this.maxLessonDate,
    required this.rn,
    required this.topicName,
    required this.sectionName,
    required this.lessonCount,
  });

  factory PlanSuccessTopic.fromJson(Map<String, dynamic> json) {
    return PlanSuccessTopic(
      minLessonDate: _parseDateTime(json['min_les_dt']),
      maxLessonDate: _parseDateTime(json['max_les_dt']),
      rn: (json['rn'] as num?)?.toInt() ?? 0,
      topicName: (json['topicname'] as String?) ?? '',
      sectionName: (json['sectionname'] as String?) ?? '',
      lessonCount: (json['les_cnt'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlanSuccessAvgItem {
  final int rn;
  final int? userId;
  final double? groupAvg;
  final double? overMark;

  PlanSuccessAvgItem({
    required this.rn,
    this.userId,
    this.groupAvg,
    this.overMark,
  });

  factory PlanSuccessAvgItem.fromJson(Map<String, dynamic> json) {
    return PlanSuccessAvgItem(
      rn: (json['rn'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt(),
      groupAvg: _parseDouble(json['group_avg']),
      overMark: _parseDouble(json['over_mark']),
    );
  }
}

class PlanSuccessUser {
  final int? userId;
  final double? groupAvgYear;
  final double? overMarkYear;
  final String? lastName;
  final String? firstName;
  final String? middleName;

  PlanSuccessUser({
    this.userId,
    this.groupAvgYear,
    this.overMarkYear,
    this.lastName,
    this.firstName,
    this.middleName,
  });

  factory PlanSuccessUser.fromJson(Map<String, dynamic> json) {
    return PlanSuccessUser(
      userId: (json['user_id'] as num?)?.toInt(),
      groupAvgYear: _parseDouble(json['group_avg_year']),
      overMarkYear: _parseDouble(json['over_mark_year']),
      lastName: json['last_name'] as String?,
      firstName: json['first_name'] as String?,
      middleName: json['middle_name'] as String?,
    );
  }
}

DateTime? _parseDateTime(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    if (v.trim().isEmpty) return null;
    return DateTime.tryParse(v);
  }
  return null;
}

double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
  return null;
}

