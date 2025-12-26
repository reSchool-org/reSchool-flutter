class CustomHomeworkFile {
  final int id;
  final String fileName;
  final int fileSize;
  final String? mimeType;

  CustomHomeworkFile({
    required this.id,
    required this.fileName,
    required this.fileSize,
    this.mimeType,
  });

  factory CustomHomeworkFile.fromJson(Map<String, dynamic> json) {
    return CustomHomeworkFile(
      id: json['id'] as int,
      fileName: json['fileName'] as String,
      fileSize: json['fileSize'] as int,
      mimeType: json['mimeType'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'fileSize': fileSize,
    'mimeType': mimeType,
  };

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class CustomHomework {
  final int id;
  final int authorPrsId;
  final String authorFullName;
  final String subject;
  final DateTime lessonDate;
  final String text;
  final List<CustomHomeworkFile> files;
  final bool isMine;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CustomHomework({
    required this.id,
    required this.authorPrsId,
    required this.authorFullName,
    required this.subject,
    required this.lessonDate,
    required this.text,
    required this.files,
    required this.isMine,
    required this.createdAt,
    this.updatedAt,
  });

  factory CustomHomework.fromJson(Map<String, dynamic> json) {
    return CustomHomework(
      id: json['id'] as int,
      authorPrsId: json['authorPrsId'] as int,
      authorFullName: json['authorFullName'] as String? ?? 'Unknown',
      subject: json['subject'] as String,
      lessonDate: DateTime.parse(json['lessonDate'] as String),
      text: json['text'] as String,
      files: (json['files'] as List<dynamic>?)
          ?.map((e) => CustomHomeworkFile.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      isMine: json['isMine'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorPrsId': authorPrsId,
    'authorFullName': authorFullName,
    'subject': subject,
    'lessonDate': lessonDate.toIso8601String(),
    'text': text,
    'files': files.map((e) => e.toJson()).toList(),
    'isMine': isMine,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  CustomHomework copyWith({
    int? id,
    int? authorPrsId,
    String? authorFullName,
    String? subject,
    DateTime? lessonDate,
    String? text,
    List<CustomHomeworkFile>? files,
    bool? isMine,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomHomework(
      id: id ?? this.id,
      authorPrsId: authorPrsId ?? this.authorPrsId,
      authorFullName: authorFullName ?? this.authorFullName,
      subject: subject ?? this.subject,
      lessonDate: lessonDate ?? this.lessonDate,
      text: text ?? this.text,
      files: files ?? this.files,
      isMine: isMine ?? this.isMine,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}