import '../utils/html_content.dart';

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

  DateTime get sendDateTime =>
      DateTime.fromMillisecondsSinceEpoch(sendDate.toInt());
}

class ChatMessage {
  final int? msgNum;
  final double? sendDate;
  final double? editDate;
  final int? stateId;
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
    this.msgNum,
    this.sendDate,
    this.editDate,
    this.stateId,
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
      msgNum: (json['msgNum'] as num?)?.toInt(),
      sendDate: (json['sendDate'] as num?)?.toDouble(),
      editDate: (json['editDate'] as num?)?.toDouble(),
      stateId: (json['stateId'] as num?)?.toInt(),
      msgId: json['msgId'],
      msg: json['msg'],
      senderFio: json['senderFio'],
      createDate: (json['sendDate'] ?? json['createDate'] ?? 0).toDouble(),
      isOwner: json['isOwner'],
      senderId: json['senderId'],
      senderPrsId: json['senderPrsId'],
      imageId: json['imageId'],
      imgObjType: json['imgObjType'],
      imgObjId: json['imgObjId'],
      attachInfo: json['attachInfo'] != null
          ? (json['attachInfo'] as List)
                .map((e) => AttachInfo.fromJson(e))
                .toList()
          : null,
    );
  }

  int? get avatarPrsId => senderPrsId ?? imgObjId ?? senderId;

  int get id => msgId ?? createDate.toInt();

  DateTime get createDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createDate.toInt());

  String get cleanMsg {
    return htmlToPlainText(msg ?? '');
  }

  ChatMessage withText(String value) => ChatMessage(
    msgId: msgId,
    msgNum: msgNum,
    msg: plainTextToHtml(value),
    senderFio: senderFio,
    createDate: createDate,
    sendDate: sendDate,
    editDate: DateTime.now().millisecondsSinceEpoch.toDouble(),
    stateId: stateId,
    isOwner: isOwner,
    senderId: senderId,
    senderPrsId: senderPrsId,
    imageId: imageId,
    imgObjType: imgObjType,
    imgObjId: imgObjId,
    attachInfo: attachInfo,
  );
}

class AttachInfo {
  final int? fileId;
  final String? fileName;
  final int? fileSize;
  final String? fileType;
  final bool isInline;

  AttachInfo({
    this.fileId,
    this.fileName,
    this.fileSize,
    this.fileType,
    this.isInline = false,
  });

  factory AttachInfo.fromJson(Map<String, dynamic> json) {
    return AttachInfo(
      fileId: json['fileId'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      fileType: json['fileType'],
      isInline: json['isInline'] == 1 || json['isInline'] == true,
    );
  }

  String get formattedSize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isImage =>
      fileType?.startsWith('image/') ??
      RegExp(
        r'\.(png|jpe?g|gif|webp|bmp)$',
        caseSensitive: false,
      ).hasMatch(fileName ?? '');
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

class ShortProfile {
  final int prsId;
  final String? lastName;
  final String? firstName;
  final String? middleName;
  final DateTime? birthDate;
  final int? fotoId;
  final List<ShortProfileTeacher>? teachers;

  ShortProfile({
    required this.prsId,
    this.lastName,
    this.firstName,
    this.middleName,
    this.birthDate,
    this.fotoId,
    this.teachers,
  });

  factory ShortProfile.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] ?? json;
    final basic = profile['prsBasic'] ?? {};
    final teachersJson = profile['teachers']?['teacher'];
    return ShortProfile(
      prsId: basic['prsId'] ?? 0,
      lastName: basic['lastName'],
      firstName: basic['firstName'],
      middleName: basic['middleName'],
      birthDate: basic['birthDate'] != null
          ? DateTime.tryParse(basic['birthDate'])
          : null,
      fotoId: basic['fotoId'],
      teachers: teachersJson != null
          ? (teachersJson as List)
                .map((e) => ShortProfileTeacher.fromJson(e))
                .toList()
          : null,
    );
  }

  String get fullName {
    final parts = [
      lastName,
      firstName,
      middleName,
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.join(' ');
  }
}

class ShortProfileTeacher {
  final String? type;
  final List<String>? discips;
  final String? groupName;

  ShortProfileTeacher({this.type, this.discips, this.groupName});

  factory ShortProfileTeacher.fromJson(Map<String, dynamic> json) {
    final clazz = json['clazz'];
    return ShortProfileTeacher(
      type: json['type'],
      discips: json['discips'] != null
          ? List<String>.from(json['discips'])
          : null,
      groupName: clazz != null && (clazz as List).isNotEmpty
          ? clazz[0]['groupName']
          : null,
    );
  }

  bool get isClassTeacher => type == 'CT';
}

class UploadFile {
  final List<int> data;
  final String name;
  final String mimeType;

  UploadFile({required this.data, required this.name, required this.mimeType});

  int get size => data.length;
}

class ChatPermissions {
  final bool canWrite;
  final int editMinutes;
  final Duration serverOffset;

  const ChatPermissions({
    required this.canWrite,
    required this.editMinutes,
    this.serverOffset = Duration.zero,
  });

  bool canModify(ChatMessage message, {required bool isMine, DateTime? now}) {
    final sent = message.sendDate ?? message.createDate;
    if (!canWrite ||
        !isMine ||
        message.msgId == null ||
        sent <= 0 ||
        (message.stateId != null && message.stateId! <= 1) ||
        editMinutes <= 0) {
      return false;
    }
    final serverNow = (now ?? DateTime.now()).add(serverOffset);
    final expires = DateTime.fromMillisecondsSinceEpoch(
      sent.toInt(),
    ).add(Duration(minutes: editMinutes));
    return serverNow.isBefore(expires);
  }
}

class ChatSearchHit {
  final ChatThread thread;
  final int? cursor;
  final List<int> messageNumbers;
  final String preview;
  final String query;

  const ChatSearchHit({
    required this.thread,
    this.cursor,
    required this.messageNumbers,
    required this.preview,
    this.query = '',
  });

  factory ChatSearchHit.fromJson(Map<String, dynamic> json) => ChatSearchHit(
    thread: ChatThread.fromJson(json),
    cursor: (json['msgNum'] as num?)?.toInt(),
    messageNumbers: (json['filterNumbers'] as List? ?? [json['msgNum']])
        .whereType<num>()
        .map((n) => n.toInt())
        .toSet()
        .toList(),
    preview: htmlToPlainText(json['msgPreview']?.toString() ?? ''),
    query: json['filterText']?.toString() ?? '',
  );
}

class ChatMediaItem {
  final ChatMessage message;
  final AttachInfo attachment;
  const ChatMediaItem(this.message, this.attachment);
  String get key => '${message.msgId}:${attachment.fileId}';
}
