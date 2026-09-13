class PupilUnitsResponse {
  final List<PupilUnit> result;

  PupilUnitsResponse({required this.result});

  factory PupilUnitsResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['result'] as List?) ?? const [];
    return PupilUnitsResponse(
      result: list.map((e) => PupilUnit.fromJson(e)).toList(),
    );
  }
}

class PupilUnit {
  final int unitId;
  final String name;
  final String? shortName;
  final int? isOdod;
  final int? orgId;

  PupilUnit({
    required this.unitId,
    required this.name,
    this.shortName,
    this.isOdod,
    this.orgId,
  });

  factory PupilUnit.fromJson(Map<String, dynamic> json) {
    return PupilUnit(
      unitId: (json['unitId'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      shortName: json['shortName'] as String?,
      isOdod: (json['isOdod'] as num?)?.toInt(),
      orgId: (json['orgId'] as num?)?.toInt(),
    );
  }
}

