class PrsDiaryResponse {
  final List<PrsDiaryLesson>? lesson;
  final List<PrsDiaryUser>? user;

  PrsDiaryResponse({this.lesson, this.user});

  factory PrsDiaryResponse.fromJson(Map<String, dynamic> json) {
    return PrsDiaryResponse(
      lesson: json['lesson'] != null
          ? (json['lesson'] as List)
                .map((i) => PrsDiaryLesson.fromJson(i))
                .toList()
          : null,
      user: json['user'] != null
          ? (json['user'] as List).map((i) => PrsDiaryUser.fromJson(i)).toList()
          : null,
    );
  }
}

class PrsDiaryUser {
  final int? id;
  final List<PrsDiaryMark>? mark;

  PrsDiaryUser({this.id, this.mark});

  factory PrsDiaryUser.fromJson(Map<String, dynamic> json) {
    return PrsDiaryUser(
      id: json['id'],
      mark: json['mark'] != null
          ? (json['mark'] as List).map((i) => PrsDiaryMark.fromJson(i)).toList()
          : null,
    );
  }
}

class PrsDiaryMark {
  final int? id;
  final String? value;
  final int? lessonID;
  final String? partType;
  final int? partID;

  PrsDiaryMark({
    this.id,
    this.value,
    this.lessonID,
    this.partType,
    this.partID,
  });

  factory PrsDiaryMark.fromJson(Map<String, dynamic> json) {
    return PrsDiaryMark(
      id: json['id'],
      value: json['value'],
      lessonID: json['lessonID'],
      partType: json['partType'],
      partID: json['partID'],
    );
  }
}

class PrsDiaryLesson {
  final int? id;
  final double? date;
  final int? numInDay;
  final PrsDiaryUnit? unit;
  final PrsDiaryTeacher? teacher;

  /// список tchrs.tch учитывает замену учителя; null означает старый ответ, пустой список отменяет назначение
  final List<PrsDiaryTeacher>? teachers;
  final int? groupId;
  final int? orgId;
  final String? subject;
  final List<PrsDiaryPart>? part;

  PrsDiaryLesson({
    this.id,
    this.date,
    this.numInDay,
    this.unit,
    this.teacher,
    this.teachers,
    this.groupId,
    this.orgId,
    this.subject,
    this.part,
  });

  factory PrsDiaryLesson.fromJson(Map<String, dynamic> json) {
    return PrsDiaryLesson(
      id: json['id'],
      date: (json['date'] as num?)?.toDouble(),
      numInDay: json['numInDay'],
      unit: json['unit'] != null ? PrsDiaryUnit.fromJson(json['unit']) : null,
      teacher: json['teacher'] != null
          ? PrsDiaryTeacher.fromJson(json['teacher'])
          : null,
      teachers: json['tchrs'] is Map && json['tchrs']['tch'] is List
          ? (json['tchrs']['tch'] as List)
                .whereType<Map<String, dynamic>>()
                .map(PrsDiaryTeacher.fromJson)
                .toList()
          : null,
      groupId: json['clazz']?['id'],
      orgId: json['orgId'],
      subject: json['subject'],
      part: json['part'] != null
          ? (json['part'] as List).map((i) => PrsDiaryPart.fromJson(i)).toList()
          : null,
    );
  }

  bool get hasTeacherAssignment =>
      teachers != null || teacherFullName.isNotEmpty;

  List<PrsDiaryTeacher> get resolvedTeachers =>
      teachers ?? (teacher == null ? [] : [teacher!]);

  String get teacherShortName => resolvedTeachers
      .map((t) => t.shortName)
      .where((n) => n.isNotEmpty)
      .join(', ');
  String get teacherFullName => resolvedTeachers
      .map((t) => t.fullName)
      .where((n) => n.isNotEmpty)
      .join(', ');
}

class PrsDiaryUnit {
  final int? id;
  final String? name;

  PrsDiaryUnit({this.id, this.name});

  factory PrsDiaryUnit.fromJson(Map<String, dynamic> json) {
    return PrsDiaryUnit(id: json['id'], name: json['name']);
  }
}

class PrsDiaryTeacher {
  final int? teacherId;
  final int? prsId;
  final String? factTeacherIN;
  final String? fio;
  final String? lastName;
  final String? firstName;
  final String? middleName;
  final String? tchType;
  final bool isHeld;

  PrsDiaryTeacher({
    this.teacherId,
    this.prsId,
    this.factTeacherIN,
    this.fio,
    this.lastName,
    this.firstName,
    this.middleName,
    this.tchType,
    this.isHeld = false,
  });

  factory PrsDiaryTeacher.fromJson(Map<String, dynamic> json) {
    return PrsDiaryTeacher(
      teacherId: json['teacherId'] ?? json['factID'],
      prsId: json['prsId'],
      factTeacherIN: json['factTeacherIN'],
      fio: json['fio'],
      lastName: json['lastName'],
      firstName: json['firstName'],
      middleName: json['middleName'],
      tchType: json['tchType'],
      isHeld: json['isHeld'] == true || json['isHeld'] == 1,
    );
  }

  static String _clean(String? value) => (value ?? '').trim();

  String get fullName {
    final parts = [
      lastName,
      firstName,
      middleName,
    ].map(_clean).where((p) => p.isNotEmpty).toList();
    final name = parts.isNotEmpty
        ? parts.join(' ')
        : _clean(fio).isNotEmpty
        ? _clean(fio)
        : _clean(factTeacherIN);
    return name == 'Учитель' ? '' : name;
  }

  String get shortName {
    // сохраняем сокращённое имя и несколько имён в старых данных
    if (fullName.contains('.') ||
        fullName.contains(',') ||
        fullName.contains(';')) {
      return fullName;
    }
    final parts = fullName.split(RegExp(r'\s+'));
    if (parts.length < 2) return fullName;
    return '${parts.first} ${parts.skip(1).map((p) => '${p[0]}.').join()}';
  }
}

class PrsDiaryPart {
  final int? id;
  final String? cat;
  final List<PrsDiaryVariant>? variant;
  final double? mrkWt;

  PrsDiaryPart({this.id, this.cat, this.variant, this.mrkWt});

  factory PrsDiaryPart.fromJson(Map<String, dynamic> json) {
    return PrsDiaryPart(
      id: json['id'],
      cat: json['cat'],
      variant: json['variant'] != null
          ? (json['variant'] as List)
                .map((i) => PrsDiaryVariant.fromJson(i))
                .toList()
          : null,
      mrkWt: (json['mrkWt'] as num?)?.toDouble(),
    );
  }
}

class PrsDiaryVariant {
  final int? id;
  final String? text;
  final List<PrsDiaryFile>? file;
  final double? deadLine;

  PrsDiaryVariant({this.id, this.text, this.file, this.deadLine});

  factory PrsDiaryVariant.fromJson(Map<String, dynamic> json) {
    return PrsDiaryVariant(
      id: json['id'],
      text: json['text'],
      file: json['file'] != null
          ? (json['file'] as List).map((i) => PrsDiaryFile.fromJson(i)).toList()
          : null,
      deadLine: (json['deadLine'] as num?)?.toDouble(),
    );
  }
}

class PrsDiaryFile {
  final int? id;
  final String? fileName;

  PrsDiaryFile({this.id, this.fileName});

  factory PrsDiaryFile.fromJson(Map<String, dynamic> json) {
    return PrsDiaryFile(id: json['id'], fileName: json['fileName']);
  }
}
