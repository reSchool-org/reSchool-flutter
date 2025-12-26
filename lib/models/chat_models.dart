class ChatThread {
  final int threadId;
  final String? subject;
  final String? msgPreview;
  final String? senderFio;
  final double sendDate;
  final int? imageId;
  final String? imgObjType;
  final int? imgObjId;
  final int? dlgType;
  final int? senderId;

  ChatThread({
    required this.threadId,
    this.subject,
    this.msgPreview,
    this.senderFio,
    required this.sendDate,
    this.imageId,
    this.imgObjType,
    this.imgObjId,
    this.dlgType,
    this.senderId,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    return ChatThread(
      threadId: json['threadId'] ?? 0,
      subject: json['subject'],
      msgPreview: json['msgPreview'],
      senderFio: json['senderFio'],
      sendDate: (json['sendDate'] ?? 0).toDouble(),
      imageId: json['imageId'],
      imgObjType: json['imgObjType'],
      imgObjId: json['imgObjId'],
      dlgType: json['dlgType'],
      senderId: json['senderId'],
    );
  }

  String get title {
    if (subject != null && subject!.trim().isNotEmpty) {
      return subject!;
    }
    return senderFio ?? 'Без темы';
  }

  bool get isGroup => dlgType == 2;

  DateTime get sendDateTime => DateTime.fromMillisecondsSinceEpoch(sendDate.toInt());
}

class ChatMessage {
  final int? msgId;
  final String? msg;
  final String? senderFio;
  final double createDate;
  final bool? isOwner;
  final int? senderId;
  final int? senderPrsId;
  final int? imageId;
  final String? imgObjType;
  final int? imgObjId;
  final List<AttachInfo>? attachInfo;

  ChatMessage({
    this.msgId,
    this.msg,
    this.senderFio,
    required this.createDate,
    this.isOwner,
    this.senderId,
    this.senderPrsId,
    this.imageId,
    this.imgObjType,
    this.imgObjId,
    this.attachInfo,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      msgId: json['msgId'],
      msg: json['msg'],
      senderFio: json['senderFio'],
      createDate: (json['createDate'] ?? 0).toDouble(),
      isOwner: json['isOwner'],
      senderId: json['senderId'],
      senderPrsId: json['senderPrsId'],
      imageId: json['imageId'],
      imgObjType: json['imgObjType'],
      imgObjId: json['imgObjId'],
      attachInfo: json['attachInfo'] != null
          ? (json['attachInfo'] as List).map((e) => AttachInfo.fromJson(e)).toList()
          : null,
    );
  }

  int? get avatarPrsId => senderPrsId ?? imgObjId ?? senderId;

  int get id => msgId ?? createDate.toInt();

  DateTime get createDateTime => DateTime.fromMillisecondsSinceEpoch(createDate.toInt());

  String get cleanMsg {
    if (msg == null) return '';
    return msg!
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }
}

class AttachInfo {
  final int? fileId;
  final String? fileName;
  final int? fileSize;
  final String? fileType;

  AttachInfo({
    this.fileId,
    this.fileName,
    this.fileSize,
    this.fileType,
  });

  factory AttachInfo.fromJson(Map<String, dynamic> json) {
    return AttachInfo(
      fileId: json['fileId'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      fileType: json['fileType'],
    );
  }

  String get formattedSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class UserSearchItem {
  final int? prsId;
  final String? fio;
  final String? groupName;
  final int? isStudent;
  final int? isEmp;
  final int? isParent;
  final int? imageId;
  final List<UserPosition>? pos;

  UserSearchItem({
    this.prsId,
    this.fio,
    this.groupName,
    this.isStudent,
    this.isEmp,
    this.isParent,
    this.imageId,
    this.pos,
  });

  factory UserSearchItem.fromJson(Map<String, dynamic> json) {
    return UserSearchItem(
      prsId: json['prsId'],
      fio: json['fio'],
      groupName: json['groupName'],
      isStudent: json['isStudent'],
      isEmp: json['isEmp'],
      isParent: json['isParent'],
      imageId: json['imageId'],
      pos: json['pos'] != null
          ? (json['pos'] as List).map((e) => UserPosition.fromJson(e)).toList()
          : null,
    );
  }

  int get id => prsId ?? 0;

  String? get positionName => pos?.firstOrNull?.posTypeName;
}

class UserPosition {
  final String? posTypeName;

  UserPosition({this.posTypeName});

  factory UserPosition.fromJson(Map<String, dynamic> json) {
    return UserPosition(posTypeName: json['posTypeName']);
  }
}

class UploadFile {
  final List<int> data;
  final String name;
  final String mimeType;

  UploadFile({
    required this.data,
    required this.name,
    required this.mimeType,
  });

  int get size => data.length;
}