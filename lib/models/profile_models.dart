class ProfileNewResponse {
  final String? fio;
  final String? login;
  final String? birthDate;
  final ProfileNewData? data;
  final List<ProfileNewPupil>? pupil;
  final List<ProfileNewRelation>? prsRel;

  ProfileNewResponse({
    this.fio,
    this.login,
    this.birthDate,
    this.data,
    this.pupil,
    this.prsRel,
  });

  factory ProfileNewResponse.fromJson(Map<String, dynamic> json) {
    return ProfileNewResponse(
      fio: json['fio'],
      login: json['login'],
      birthDate: json['birthDate'],
      data: json['data'] != null ? ProfileNewData.fromJson(json['data']) : null,
      pupil: json['pupil'] != null
          ? (json['pupil'] as List).map((i) => ProfileNewPupil.fromJson(i)).toList()
          : null,
      prsRel: json['prsRel'] != null
          ? (json['prsRel'] as List).map((i) => ProfileNewRelation.fromJson(i)).toList()
          : null,
    );
  }
}

class ProfileNewData {
  final int? prsId;
  final int? gender;

  ProfileNewData({this.prsId, this.gender});

  factory ProfileNewData.fromJson(Map<String, dynamic> json) {
    return ProfileNewData(
      prsId: json['prsId'],
      gender: json['gender'],
    );
  }
}

class ProfileNewPupil {
  final int? yearId;
  final String? eduYear;
  final String? className;
  final String? bvt;
  final String? evt;
  final int? isReady;

  ProfileNewPupil({
    this.yearId,
    this.eduYear,
    this.className,
    this.bvt,
    this.evt,
    this.isReady,
  });

  factory ProfileNewPupil.fromJson(Map<String, dynamic> json) {
    return ProfileNewPupil(
      yearId: json['yearId'],
      eduYear: json['eduYear'],
      className: json['className'],
      bvt: json['bvt'],
      evt: json['evt'],
      isReady: json['isReady'],
    );
  }
}

class ProfileNewRelation {
  final String? relName;
  final ProfileNewRelationData? data;

  ProfileNewRelation({this.relName, this.data});

  factory ProfileNewRelation.fromJson(Map<String, dynamic> json) {
    return ProfileNewRelation(
      relName: json['relName'],
      data: json['data'] != null ? ProfileNewRelationData.fromJson(json['data']) : null,
    );
  }
}

class ProfileNewRelationData {
  final String? lastName;
  final String? firstName;
  final String? middleName;
  final String? mobilePhone;
  final String? homePhone;
  final String? email;

  ProfileNewRelationData({
    this.lastName,
    this.firstName,
    this.middleName,
    this.mobilePhone,
    this.homePhone,
    this.email,
  });

  factory ProfileNewRelationData.fromJson(Map<String, dynamic> json) {
    return ProfileNewRelationData(
      lastName: json['lastName'],
      firstName: json['firstName'],
      middleName: json['middleName'],
      mobilePhone: json['mobilePhone'],
      homePhone: json['homePhone'],
      email: json['email'],
    );
  }

  String get fullName {
    final parts = [lastName, firstName, middleName].where((e) => e != null && e.isNotEmpty).toList();
    return parts.join(" ");
  }
}

class Profile {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? middleName;
  final String? phoneMob;
  final int? imageId;

  Profile({
    this.id,
    this.firstName,
    this.lastName,
    this.middleName,
    this.phoneMob,
    this.imageId,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    return Profile(
      id: json['id'] ?? json['prsId'] ?? data?['prsId'],
      firstName: json['firstName'] ?? data?['firstName'],
      lastName: json['lastName'] ?? data?['lastName'],
      middleName: json['middleName'] ?? data?['middleName'],
      phoneMob: json['phoneMob'] ?? data?['mobilePhone'],
      imageId: json['imageId'] ?? data?['fotoId'],
    );
  }

  String get fullName {
    final parts = [lastName, firstName, middleName].where((e) => e != null && e.isNotEmpty).toList();
    return parts.join(" ");
  }
}