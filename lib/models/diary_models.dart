class PrsDiaryResponse {
  final List<PrsDiaryLesson>? lesson;
  final List<PrsDiaryUser>? user;

  PrsDiaryResponse({this.lesson, this.user});

  factory PrsDiaryResponse.fromJson(Map<String, dynamic> json) {
    return PrsDiaryResponse(
      lesson: json['lesson'] != null
          ? (json['lesson'] as List).map((i) => PrsDiaryLesson.fromJson(i)).toList()
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

  PrsDiaryMark({this.id, this.value, this.lessonID, this.partType, this.partID});

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
  final String? subject;
  final List<PrsDiaryPart>? part;

  PrsDiaryLesson({
    this.id,
    this.date,
    this.numInDay,
    this.unit,
    this.teacher,
    this.subject,
    this.part,
  });

  factory PrsDiaryLesson.fromJson(Map<String, dynamic> json) {
    return PrsDiaryLesson(
      id: json['id'],
      date: (json['date'] as num?)?.toDouble(),
      numInDay: json['numInDay'],
      unit: json['unit'] != null ? PrsDiaryUnit.fromJson(json['unit']) : null,
      teacher: json['teacher'] != null ? PrsDiaryTeacher.fromJson(json['teacher']) : null,
      subject: json['subject'],
      part: json['part'] != null
          ? (json['part'] as List).map((i) => PrsDiaryPart.fromJson(i)).toList()
          : null,
    );
  }
}

class PrsDiaryUnit {
  final String? name;

  PrsDiaryUnit({this.name});

  factory PrsDiaryUnit.fromJson(Map<String, dynamic> json) {
    return PrsDiaryUnit(
      name: json['name'],
    );
  }
}

class PrsDiaryTeacher {
  final String? factTeacherIN;
  final String? lastName;
  final String? firstName;
  final String? middleName;

  PrsDiaryTeacher({this.factTeacherIN, this.lastName, this.firstName, this.middleName});

  factory PrsDiaryTeacher.fromJson(Map<String, dynamic> json) {
    return PrsDiaryTeacher(
      factTeacherIN: json['factTeacherIN'],
      lastName: json['lastName'],
      firstName: json['firstName'],
      middleName: json['middleName'],
    );
  }

  String get shortName {
    if (lastName != null && lastName!.isNotEmpty) {
      String result = lastName!;
      if (firstName != null && firstName!.isNotEmpty) {
        result += " ${firstName![0]}.";
        if (middleName != null && middleName!.isNotEmpty) {
          result += "${middleName![0]}.";
        }
      }
      return result;
    }
    if (factTeacherIN != null && factTeacherIN!.isNotEmpty) {
      return factTeacherIN!;
    }
    return "";
  }

  String get fullName {
    List<String?> parts = [lastName, firstName, middleName];
    parts.removeWhere((element) => element == null);
    if (parts.isNotEmpty) {
      return parts.join(" ");
    }
    return factTeacherIN ?? "";
  }
}

class PrsDiaryPart {
  final String? cat;
  final List<PrsDiaryVariant>? variant;
  final double? mrkWt;

  PrsDiaryPart({this.cat, this.variant, this.mrkWt});

  factory PrsDiaryPart.fromJson(Map<String, dynamic> json) {
    return PrsDiaryPart(
      cat: json['cat'],
      variant: json['variant'] != null
          ? (json['variant'] as List).map((i) => PrsDiaryVariant.fromJson(i)).toList()
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
    return PrsDiaryFile(
      id: json['id'],
      fileName: json['fileName'],
    );
  }
}