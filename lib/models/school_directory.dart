import 'chat_models.dart';

class SchoolDirectoryGroup {
  final String name;
  final bool isOrganization;
  final List<SchoolDirectoryGroup> groups;
  final List<UserSearchItem> users;

  const SchoolDirectoryGroup({
    required this.name,
    this.isOrganization = false,
    this.groups = const [],
    this.users = const [],
  });

  factory SchoolDirectoryGroup.fromJson(
    Map<String, dynamic> json,
  ) => SchoolDirectoryGroup(
    name: json['groupName'] ?? json['groupTypeName'] ?? json['orgName'] ?? '',
    isOrganization: json['orgName'] != null,
    groups: (json['groups'] as List? ?? [])
        .map(
          (value) =>
              SchoolDirectoryGroup.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
    users: (json['users'] as List? ?? [])
        .map(
          (value) => UserSearchItem.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
  );

  Iterable<UserSearchItem> get descendants sync* {
    yield* users;
    for (final group in groups) {
      yield* group.descendants;
    }
  }
}
