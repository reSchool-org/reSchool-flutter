class LPartTeacher {
  final String? tF;
  final String? tL;
  final String? tM;
  final int? tId;
  final int? tPId;
  final String? t;
  final bool? tS;

  LPartTeacher({this.tF, this.tL, this.tM, this.tId, this.tPId, this.t, this.tS});

  factory LPartTeacher.fromJson(Map<String, dynamic> json) {
    return LPartTeacher(
      tF: json['tF'],
      tL: json['tL'],
      tM: json['tM'],
      tId: json['tId'],
      tPId: json['tPId'],
      t: json['t'],
      tS: json['tS'],
    );
  }

  String get fullName => '${tL ?? ''} ${tF ?? ''} ${tM ?? ''}'.trim();
}

class LPartMark {
  final int? markValId;
  final String? date;
  final String? markValue;

  LPartMark({this.markValId, this.date, this.markValue});

  factory LPartMark.fromJson(Map<String, dynamic> json) {
    return LPartMark(
      markValId: json['mark_val_id'],
      date: json['date'],
      markValue: json['mark_value'],
    );
  }
}

class LPartAttachment {
  final int? fileId;
  final String? fileName;
  final int? fileSize;
  final String? fileType;
  final int? isResult;

  LPartAttachment({this.fileId, this.fileName, this.fileSize, this.fileType, this.isResult});

  factory LPartAttachment.fromJson(Map<String, dynamic> json) {
    return LPartAttachment(
      fileId: json['fileId'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      fileType: json['fileType'],
      isResult: json['is_result'],
    );
  }
}

class LPartListItem {
  final int? partId;
  final String? partName;
  final int? passDt;
  final int? passlesId;
  final String? sysCode;
  final int? checkTypeId;
  final int? teacherId;
  final int? groupId;
  final String? groupName;
  final String? parentGroupName;
  final int? unitId;
  final String? unitName;
  final int? partTypeId;
  final int? maxPoint;
  final int? catId;
  final String? catName;
  final String? lptColor;
  final String? preview;
  final int? attachCnt;
  final int? isDone;
  final int? isVerified;
  final double? mrkWt;
  final bool? needRecheck;
  final int? hasTask;
  final int? timeToComplite;
  final int? orgId;
  final String? orgName;
  final int? resultCnt;
  final List<LPartTeacher> tchArray;
  final List<LPartMark>? mark;

  LPartListItem({
    this.partId,
    this.partName,
    this.passDt,
    this.passlesId,
    this.sysCode,
    this.checkTypeId,
    this.teacherId,
    this.groupId,
    this.groupName,
    this.parentGroupName,
    this.unitId,
    this.unitName,
    this.partTypeId,
    this.maxPoint,
    this.catId,
    this.catName,
    this.lptColor,
    this.preview,
    this.attachCnt,
    this.isDone,
    this.isVerified,
    this.mrkWt,
    this.needRecheck,
    this.hasTask,
    this.timeToComplite,
    this.orgId,
    this.orgName,
    this.resultCnt,
    this.tchArray = const [],
    this.mark,
  });

  factory LPartListItem.fromJson(Map<String, dynamic> json) {
    return LPartListItem(
      partId: json['partId'],
      partName: json['partName'],
      passDt: json['passDt'],
      passlesId: json['passlesId'],
      sysCode: json['sysCode'],
      checkTypeId: json['checkTypeId'],
      teacherId: json['teacherId'],
      groupId: json['groupId'],
      groupName: json['groupName'],
      parentGroupName: json['parentGroupName'],
      unitId: json['unitId'],
      unitName: json['unitName'],
      partTypeId: json['partTypeId'],
      maxPoint: json['maxPoint'],
      catId: json['catId'],
      catName: json['catName'],
      lptColor: json['lptColor'],
      preview: json['preview'],
      attachCnt: json['attachCnt'],
      isDone: json['isDone'],
      isVerified: json['isVerified'],
      mrkWt: (json['mrkWt'] as num?)?.toDouble(),
      needRecheck: json['needRecheck'],
      hasTask: json['hasTask'],
      timeToComplite: json['timeToComplite'],
      orgId: json['orgId'],
      orgName: json['orgName'],
      resultCnt: json['resultCnt'],
      tchArray: json['tchArray'] != null
          ? (json['tchArray'] as List).map((e) => LPartTeacher.fromJson(e)).toList()
          : [],
      mark: json['mark'] != null
          ? (json['mark'] as List).map((e) => LPartMark.fromJson(e)).toList()
          : null,
    );
  }
}

class LPartDetail {
  final int? partId;
  final String? partName;
  final int? passDt;
  final int? passlesId;
  final int? markSysId;
  final String? markSysName;
  final int? checkTypeId;
  final int? groupId;
  final String? groupName;
  final int? unitId;
  final String? unitName;
  final int? partTypeId;
  final int? maxPoint;
  final int? catId;
  final String? cat;
  final int? isBonus;
  final int? attachCnt;
  final double? mrkWt;
  final String? taskText;
  final bool? needRecheck;
  final int? varId;
  final int? hasTask;
  final int? orgId;
  final List<LPartAttachment> attach;
  final List<LPartTeacher> tchArray;

  LPartDetail({
    this.partId,
    this.partName,
    this.passDt,
    this.passlesId,
    this.markSysId,
    this.markSysName,
    this.checkTypeId,
    this.groupId,
    this.groupName,
    this.unitId,
    this.unitName,
    this.partTypeId,
    this.maxPoint,
    this.catId,
    this.cat,
    this.isBonus,
    this.attachCnt,
    this.mrkWt,
    this.taskText,
    this.needRecheck,
    this.varId,
    this.hasTask,
    this.orgId,
    this.attach = const [],
    this.tchArray = const [],
  });

  factory LPartDetail.fromJson(Map<String, dynamic> json) {
    return LPartDetail(
      partId: json['partId'],
      partName: json['partName'],
      passDt: json['passDt'],
      passlesId: json['passlesId'],
      markSysId: json['markSysId'],
      markSysName: json['markSysName'],
      checkTypeId: json['checkTypeId'],
      groupId: json['groupId'],
      groupName: json['groupName'],
      unitId: json['unitId'],
      unitName: json['unitName'],
      partTypeId: json['partTypeId'],
      maxPoint: json['maxPoint'],
      catId: json['catId'],
      cat: json['cat'],
      isBonus: json['isBonus'],
      attachCnt: json['attachCnt'],
      mrkWt: (json['mrkWt'] as num?)?.toDouble(),
      taskText: json['taskText'],
      needRecheck: json['needRecheck'],
      varId: json['varId'],
      hasTask: json['hasTask'],
      orgId: json['orgId'],
      attach: json['attach'] != null
          ? (json['attach'] as List).map((e) => LPartAttachment.fromJson(e)).toList()
          : [],
      tchArray: json['tchArray'] != null
          ? (json['tchArray'] as List).map((e) => LPartTeacher.fromJson(e)).toList()
          : [],
    );
  }
}
