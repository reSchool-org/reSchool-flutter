import 'dart:convert';
import '../models/profile_models.dart';
import '../models/chat_models.dart';
import '../utils/html_content.dart';

class DemoData {
  final int userId = 1001;
  final int prsId = 2001;
  final String login = "s.mironova";
  final String firstName = "Софья";
  final String lastName = "Миронова";
  final String middleName = "Андреевна";
  final String phone = "+7 900 123-45-67";

  late final DateTime periodStart;
  late final DateTime periodEnd;

  final List<_DemoSubject> _subjects = [
    _DemoSubject(
      id: 11,
      name: "Математика",
      teacher: _DemoTeacher("Иванова", "Елена", "Викторовна"),
      topics: [
        "Квадратные уравнения",
        "Функции и графики",
        "Тригонометрия",
        "Системы неравенств",
      ],
    ),
    _DemoSubject(
      id: 12,
      name: "Русский язык",
      teacher: _DemoTeacher("Соколова", "Мария", "Олеговна"),
      topics: [
        "Сложные предложения",
        "Пунктуация",
        "Причастия и деепричастия",
        "Орфография",
      ],
    ),
    _DemoSubject(
      id: 13,
      name: "Физика",
      teacher: _DemoTeacher("Кузнецов", "Павел", "Ильич"),
      topics: [
        "Законы Ньютона",
        "Электрический ток",
        "Оптика",
        "Механические колебания",
      ],
    ),
    _DemoSubject(
      id: 14,
      name: "История",
      teacher: _DemoTeacher("Петрова", "Анна", "Сергеевна"),
      topics: [
        "Реформы XIX века",
        "Первая мировая война",
        "Экономика начала XX века",
        "Культура эпохи",
      ],
    ),
    _DemoSubject(
      id: 15,
      name: "Английский язык",
      teacher: _DemoTeacher("Федоров", "Сергей", "Анатольевич"),
      topics: [
        "Present Perfect",
        "Reported Speech",
        "Modal Verbs",
        "Conditionals",
      ],
    ),
  ];

  final List<Map<String, dynamic>> _threads = [];
  final Map<int, List<Map<String, dynamic>>> _messagesByThread = {};
  int _nextThreadId = 9001;
  int _nextMessageId = 50001;
  int _nextFileId = 70001;
  final Map<int, List<int>> _fileData = {};

  DemoData() {
    final now = DateTime.now();
    periodStart = now.subtract(const Duration(days: 20));
    periodEnd = now.add(const Duration(days: 40));
    _initChats();
  }

  Profile get profile => Profile.fromJson({
    "prsId": prsId,
    "firstName": firstName,
    "lastName": lastName,
    "middleName": middleName,
    "phoneMob": phone,
  });

  String get fullName => "$lastName $firstName $middleName";

  Map<String, dynamic> stateJson() {
    return {
      "userId": userId,
      "user": {"prsId": prsId},
      "profile": {
        "prsId": prsId,
        "firstName": firstName,
        "lastName": lastName,
        "middleName": middleName,
        "phoneMob": phone,
      },
    };
  }

  Map<String, dynamic> profileNewJson(int prsIdInput) {
    return {
      "fio": fullName,
      "login": login,
      "birthDate": "12.04.2008",
      "data": {"prsId": prsIdInput, "gender": 2},
      "pupil": [
        {
          "yearId": 2024,
          "eduYear": "2024/2025",
          "className": "10А",
          "bvt": "Основная программа",
          "evt": "Профильный уровень",
          "isReady": 1,
        },
      ],
      "prsRel": [
        {
          "relName": "Мама",
          "data": {
            "lastName": "Миронова",
            "firstName": "Ирина",
            "middleName": "Александровна",
            "mobilePhone": "+7 903 555-12-34",
            "email": "irina.mironova@example.com",
          },
        },
        {
          "relName": "Папа",
          "data": {
            "lastName": "Миронов",
            "firstName": "Андрей",
            "middleName": "Петрович",
            "mobilePhone": "+7 901 111-22-33",
            "email": "andrey.mironov@example.com",
          },
        },
      ],
    };
  }

  List<Map<String, dynamic>> classByUserJson() {
    return [
      {
        "groupId": 501,
        "groupName": "10А класс",
        "begDate": periodStart.millisecondsSinceEpoch.toDouble(),
      },
    ];
  }

  Map<String, dynamic> periodsJson() {
    return {
      "items": [
        {
          "id": 9001,
          "periodId": 9001,
          "name": "1 четверть",
          "date1": periodStart.millisecondsSinceEpoch.toDouble(),
          "date2": periodEnd.millisecondsSinceEpoch.toDouble(),
          "typeCode": "Q",
          "parentId": null,
          "items": [],
        },
      ],
    };
  }

  Map<String, dynamic> diaryUnitsJson() {
    final lessons = _buildLessons(periodStart, periodEnd);
    final Map<int, List<int>> marksByUnit = {};
    for (final lesson in lessons) {
      if (lesson.markValue != null) {
        marksByUnit.putIfAbsent(lesson.unitId, () => []).add(lesson.markValue!);
      }
    }

    final result = _subjects.map((subject) {
      final marks = marksByUnit[subject.id] ?? [];
      final avg = marks.isEmpty
          ? null
          : marks.reduce((a, b) => a + b) / marks.length;
      final total = marks.isEmpty ? null : avg;
      return {
        "unitId": subject.id,
        "unitName": subject.name,
        "overMark": avg,
        "totalMark": total,
        "rating": _ratingForAverage(avg),
      };
    }).toList();

    return {"result": result};
  }

  Map<String, dynamic> diaryPeriodJson() {
    final lessons = _buildLessons(periodStart, periodEnd);
    final result = lessons.map((lesson) {
      return {
        "lessonId": lesson.id,
        "unitId": lesson.unitId,
        "startDt": lesson.date.toIso8601String(),
        "lesNum": lesson.numInDay,
        "subject": lesson.topic,
        "teacherFio": lesson.teacher.fullName,
        "part": [
          {
            "lptName": "Работа на уроке",
            "cat": "O",
            "mrkWt": lesson.markWeight,
            "mark": lesson.markValue != null
                ? [
                    {"markValue": lesson.markValue},
                  ]
                : [],
          },
        ],
      };
    }).toList();

    return {"result": result};
  }

  Map<String, dynamic> prsDiaryJson(DateTime start, DateTime end) {
    final lessons = _buildLessons(start, end);
    final lessonJson = lessons.map((lesson) {
      return {
        "id": lesson.id,
        "date": lesson.date.millisecondsSinceEpoch.toDouble(),
        "numInDay": lesson.numInDay,
        "unit": {"name": lesson.unitName},
        "teacher": {
          "lastName": lesson.teacher.lastName,
          "firstName": lesson.teacher.firstName,
          "middleName": lesson.teacher.middleName,
        },
        "subject": lesson.topic,
        "part": [
          {
            "cat": "DZ",
            "variant": lesson.homeworkText != null
                ? [
                    {
                      "id": lesson.id * 10 + 1,
                      "text": lesson.numInDay == 1
                          ? '<p><strong>${lesson.homeworkText}</strong></p><p>Разберите пример: \\(x^2 + 2x + 1 = (x+1)^2\\)</p><table border="1" cellpadding="8"><tr><th>x</th><th>x²</th></tr><tr><td>2</td><td>4</td></tr></table><p><a href="https://ru.wikipedia.org/wiki/Квадратное_уравнение">Дополнительный материал</a></p>'
                          : lesson.homeworkText,
                      "deadLine": lesson
                          .homeworkDeadline
                          ?.millisecondsSinceEpoch
                          .toDouble(),
                      "file": [],
                    },
                  ]
                : [],
            "mrkWt": lesson.markWeight,
          },
        ],
      };
    }).toList();

    final marks = lessons
        .where((lesson) => lesson.markValue != null)
        .map(
          (lesson) => {
            "id": lesson.id + 5000,
            "value": lesson.markValue.toString(),
            "lessonID": lesson.id,
            "partType": "Оценка",
            "partID": 1,
          },
        )
        .toList();

    return {
      "lesson": lessonJson,
      "user": [
        {"id": userId, "mark": marks},
      ],
    };
  }

  List<Map<String, dynamic>> getThreads() {
    return List<Map<String, dynamic>>.from(_threads);
  }

  List<Map<String, dynamic>> getMessages(int threadId) {
    return List<Map<String, dynamic>>.from(_messagesByThread[threadId] ?? []);
  }

  Map<String, dynamic> sendMessage(
    int threadId,
    String msgText, {
    List<UploadFile>? files,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final message = {
      "msgId": _nextMessageId++,
      "msg": plainTextToHtml(msgText),
      "senderFio": fullName,
      "createDate": now,
      "isOwner": true,
      "senderId": userId,
      "senderPrsId": prsId,
      "imageId": null,
      "imgObjType": null,
      "imgObjId": null,
      "attachInfo": [
        for (final file in files ?? <UploadFile>[]) _addFile(file),
      ],
    };

    message['msgNum'] = message['msgId'];
    message['sendDate'] = now;
    message['stateId'] = 2;
    _messagesByThread.putIfAbsent(threadId, () => []);
    _messagesByThread[threadId]!.add(message);
    _updateThreadPreview(threadId, msgText, now, fullName);
    return message;
  }

  Map<String, dynamic> _addFile(UploadFile file) {
    final id = _nextFileId++;
    _fileData[id] = file.data;
    return {
      'fileId': id,
      'fileName': file.name,
      'fileSize': file.size,
      'fileType': file.mimeType,
    };
  }

  List<int>? fileBytes(Uri uri) =>
      _fileData[int.tryParse(uri.pathSegments.last)];

  List<Map<String, dynamic>> messagePage(
    int threadId, {
    int rowStart = 1,
    int rowsCount = 50,
    int? msgStart,
    bool getNew = false,
    bool isSearch = false,
  }) {
    var rows = getMessages(threadId)
        .map(
          (item) => <String, dynamic>{
            ...item,
            'msgNum': item['msgNum'] ?? item['msgId'],
            'sendDate': item['sendDate'] ?? item['createDate'],
            'stateId': item['stateId'] ?? 2,
          },
        )
        .toList();
    if (msgStart != null) {
      rows = rows
          .where(
            (item) => getNew
                ? item['msgNum'] > msgStart
                : isSearch
                ? item['msgNum'] <= msgStart
                : item['msgNum'] < msgStart,
          )
          .toList();
    }
    rows.sort(
      (a, b) => getNew
          ? (a['msgNum'] as int).compareTo(b['msgNum'])
          : (b['msgNum'] as int).compareTo(a['msgNum']),
    );
    return rows.skip(rowStart - 1).take(rowsCount).toList();
  }

  List<Map<String, dynamic>> mediaPage(
    int threadId, {
    int rowStart = 1,
    int rowsCount = 50,
    int? msgStart,
  }) =>
      messagePage(
            threadId,
            rowsCount: _messagesByThread[threadId]?.length ?? 0,
            msgStart: msgStart,
          )
          .where((item) => (item['attachInfo'] as List).isNotEmpty)
          .skip(rowStart - 1)
          .take(rowsCount)
          .toList();

  List<Map<String, dynamic>> searchMessages(String text, {int? msgStart}) {
    final query = text.trim().toLowerCase();
    final result = <Map<String, dynamic>>[];
    for (final thread in _threads) {
      final matches = messagePage(thread['threadId'], rowsCount: 100000)
          .where(
            (message) => htmlToPlainText(
              message['msg'] ?? '',
            ).toLowerCase().contains(query),
          )
          .toList();
      if (matches.isEmpty) continue;
      final latest = matches.first;
      if (msgStart != null && latest['msgNum'] >= msgStart) continue;
      result.add({
        ...thread,
        'msgId': latest['msgId'],
        'msgNum': latest['msgNum'],
        'filterNumbers': matches.map((m) => m['msgNum']).toList(),
        'msgPreview': latest['msg'],
        'filterText': text,
      });
    }
    result.sort((a, b) => (b['msgNum'] as int).compareTo(a['msgNum']));
    return result.take(25).toList();
  }

  void editMessage(int id, String text) {
    for (final entry in _messagesByThread.entries) {
      for (final message in entry.value) {
        if (message['msgId'] != id) continue;
        message['msg'] = plainTextToHtml(text);
        message['editDate'] = DateTime.now().millisecondsSinceEpoch;
        if (identical(message, entry.value.last)) {
          _updateThreadPreview(
            entry.key,
            text,
            message['createDate'],
            message['senderFio'],
          );
        }
        return;
      }
    }
    throw StateError('Message not found');
  }

  void deleteMessage(int id) {
    for (final entry in _messagesByThread.entries) {
      entry.value.removeWhere((message) => message['msgId'] == id);
      if (entry.value.isNotEmpty) {
        final last = entry.value.last;
        _updateThreadPreview(
          entry.key,
          htmlToPlainText(last['msg']),
          last['createDate'],
          last['senderFio'],
        );
      }
    }
  }

  List<Map<String, dynamic>> employeeGroups() => [
    {
      'orgName': 'Школа № 30',
      'groups': [
        {
          'groupTypeName': 'Сотрудники',
          'groups': [
            {
              'groupName': 'Учителя',
              'users': [
                {
                  'prsId': 4010,
                  'fio': 'Ковалев Дмитрий Сергеевич',
                  'pos': [
                    {'posTypeName': 'Учитель физики'},
                  ],
                },
                {
                  'prsId': 4011,
                  'fio': 'Иванова Елена Викторовна',
                  'pos': [
                    {'posTypeName': 'Учитель математики'},
                  ],
                },
              ],
            },
            {
              'groupName': 'Администрация',
              'users': [
                {
                  'prsId': 4012,
                  'fio': 'Петрова Анна Сергеевна',
                  'pos': [
                    {'posTypeName': 'Заместитель директора'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ];

  int saveThread({int? interlocutorId, String? subject, bool isGroup = false}) {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final threadId = _nextThreadId++;
    final title = subject ?? "Новая беседа";
    final senderName = isGroup ? fullName : "Новый собеседник";
    final thread = {
      "threadId": threadId,
      "subject": isGroup ? title : null,
      "msgPreview": "Чат создан",
      "senderFio": senderName,
      "sendDate": now,
      "imageId": null,
      "imgObjType": null,
      "imgObjId": interlocutorId,
      "dlgType": isGroup ? 2 : 1,
      "senderId": interlocutorId,
    };
    _threads.add(thread);
    _messagesByThread[threadId] = [
      {
        "msgId": _nextMessageId++,
        "msg": "Чат создан",
        "senderFio": senderName,
        "createDate": now,
        "isOwner": false,
        "senderId": interlocutorId,
        "senderPrsId": interlocutorId,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": null,
        "attachInfo": [],
      },
    ];
    return threadId;
  }

  List<Map<String, dynamic>> searchUsers(String query) {
    final users = [
      {
        "prsId": 3011,
        "fio": "Никита Орлов",
        "groupName": "10А",
        "isStudent": 1,
        "isEmp": 0,
        "isParent": 0,
      },
      {
        "prsId": 3012,
        "fio": "Валерия Лукина",
        "groupName": "10Б",
        "isStudent": 1,
        "isEmp": 0,
        "isParent": 0,
      },
      {
        "prsId": 4010,
        "fio": "Дмитрий Ковалев",
        "groupName": "Учителя",
        "isStudent": 0,
        "isEmp": 1,
        "isParent": 0,
      },
    ];

    if (query.trim().isEmpty) return users;
    final lower = query.toLowerCase();
    return users.where((u) {
      final fio = (u["fio"] ?? "").toString().toLowerCase();
      final prs = (u["prsId"] ?? "").toString();
      return fio.contains(lower) || prs == query;
    }).toList();
  }

  void _initChats() {
    final now = DateTime.now();
    final t1 = now
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch
        .toDouble();
    final t2 = now
        .subtract(const Duration(days: 1, hours: 3))
        .millisecondsSinceEpoch
        .toDouble();
    final t3 = now
        .subtract(const Duration(days: 2))
        .millisecondsSinceEpoch
        .toDouble();

    _threads.addAll([
      {
        "threadId": _nextThreadId++,
        "subject": null,
        "msgPreview": "Не забудь про контрольную по математике.",
        "senderFio": "Илья Н.",
        "sendDate": t1,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": 3011,
        "dlgType": 1,
        "senderId": 3011,
      },
      {
        "threadId": _nextThreadId++,
        "subject": "Проект по физике",
        "msgPreview": "Согласуем презентацию к пятнице.",
        "senderFio": "Группа проекта",
        "sendDate": t2,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": null,
        "dlgType": 2,
        "senderId": 4010,
      },
      {
        "threadId": _nextThreadId++,
        "subject": null,
        "msgPreview": "Спасибо за помощь!",
        "senderFio": "Алина П.",
        "sendDate": t3,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": 3012,
        "dlgType": 1,
        "senderId": 3012,
      },
    ]);

    for (final thread in _threads) {
      final threadId = thread["threadId"] as int;
      _messagesByThread[threadId] = _seedMessagesForThread(threadId);
    }
  }

  List<Map<String, dynamic>> _seedMessagesForThread(int threadId) {
    final now = DateTime.now();
    final messages = [
      for (var i = 0; i < 65; i++)
        {
          'msgId': _nextMessageId++,
          'msg': 'Материалы к занятию №${i + 1}',
          'senderFio': 'Дмитрий Ковалев',
          'createDate': now
              .subtract(Duration(days: 7, minutes: 65 - i))
              .millisecondsSinceEpoch
              .toDouble(),
          'isOwner': false,
          'senderId': 4010,
          'senderPrsId': 4010,
          'attachInfo': i == 0
              ? [
                  _addFile(
                    UploadFile(
                      data: utf8.encode(
                        'План проекта\n1. Подготовить материалы\n2. Провести опыт',
                      ),
                      name: 'План проекта.txt',
                      mimeType: 'text/plain',
                    ),
                  ),
                ]
              : [],
        },
      {
        "msgId": _nextMessageId++,
        "msg": "Привет! Есть минутка?",
        "senderFio": "Илья Н.",
        "createDate": now
            .subtract(const Duration(hours: 4))
            .millisecondsSinceEpoch
            .toDouble(),
        "isOwner": false,
        "senderId": 3011,
        "senderPrsId": 3011,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": null,
        "attachInfo": [],
      },
      {
        "msgId": _nextMessageId++,
        "msg": "Да, что нужно?",
        "senderFio": fullName,
        "createDate": now
            .subtract(const Duration(hours: 3, minutes: 20))
            .millisecondsSinceEpoch
            .toDouble(),
        "isOwner": true,
        "senderId": userId,
        "senderPrsId": prsId,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": null,
        "attachInfo": [],
      },
      {
        "msgId": _nextMessageId++,
        "msg": "Не забудь про контрольную по математике.",
        "senderFio": "Илья Н.",
        "createDate": now
            .subtract(const Duration(hours: 2, minutes: 10))
            .millisecondsSinceEpoch
            .toDouble(),
        "isOwner": false,
        "senderId": 3011,
        "senderPrsId": 3011,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": null,
        "attachInfo": [],
      },
    ];
    messages.last['attachInfo'] = [
      _addFile(
        UploadFile(
          data: base64Decode(
            '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',
          ),
          name: 'Схема.png',
          mimeType: 'image/png',
        ),
      ),
    ];
    return messages;
  }

  void _updateThreadPreview(
    int threadId,
    String msg,
    double sendDate,
    String sender,
  ) {
    final index = _threads.indexWhere((t) => t["threadId"] == threadId);
    if (index == -1) return;
    final thread = Map<String, dynamic>.from(_threads[index]);
    thread["msgPreview"] = msg;
    thread["sendDate"] = sendDate;
    thread["senderFio"] = sender;
    _threads[index] = thread;
  }

  List<_DemoLesson> _buildLessons(DateTime start, DateTime end) {
    final List<_DemoLesson> lessons = [];
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    final marks = [5, 5, 4, 4, 3];

    for (
      var date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      if (date.weekday > 5) continue;
      const lessonsPerDay = 5;
      for (int num = 1; num <= lessonsPerDay; num++) {
        final subject = _subjects[(num + date.weekday) % _subjects.length];
        final topic = subject.topics[(date.day + num) % subject.topics.length];
        final lessonDate = DateTime(
          date.year,
          date.month,
          date.day,
          8 + num,
          0,
        );
        final lessonId = (lessonDate.millisecondsSinceEpoch ~/ 1000) + num;
        final markValue = num.isEven
            ? marks[(date.day + num) % marks.length]
            : null;
        final homeworkText = num.isOdd
            ? "Повторить тему: $topic. Выполнить задания №${10 + num}."
            : null;
        final deadline = homeworkText != null
            ? lessonDate.add(const Duration(days: 1, hours: 12))
            : null;

        lessons.add(
          _DemoLesson(
            id: lessonId,
            unitId: subject.id,
            unitName: subject.name,
            date: lessonDate,
            numInDay: num,
            topic: topic,
            teacher: subject.teacher,
            markValue: markValue,
            markWeight: markValue != null ? 1.0 : null,
            homeworkText: homeworkText,
            homeworkDeadline: deadline,
          ),
        );
      }
    }
    return lessons;
  }

  String _ratingForAverage(double? avg) {
    if (avg == null) return "-";
    if (avg >= 4.5) return "A";
    if (avg >= 3.8) return "B";
    if (avg >= 3.0) return "C";
    return "D";
  }
}

class _DemoSubject {
  final int id;
  final String name;
  final _DemoTeacher teacher;
  final List<String> topics;

  _DemoSubject({
    required this.id,
    required this.name,
    required this.teacher,
    required this.topics,
  });
}

class _DemoTeacher {
  final String lastName;
  final String firstName;
  final String middleName;

  _DemoTeacher(this.lastName, this.firstName, this.middleName);

  String get fullName => "$lastName $firstName $middleName";
}

class _DemoLesson {
  final int id;
  final int unitId;
  final String unitName;
  final DateTime date;
  final int numInDay;
  final String topic;
  final _DemoTeacher teacher;
  final int? markValue;
  final double? markWeight;
  final String? homeworkText;
  final DateTime? homeworkDeadline;

  _DemoLesson({
    required this.id,
    required this.unitId,
    required this.unitName,
    required this.date,
    required this.numInDay,
    required this.topic,
    required this.teacher,
    required this.markValue,
    required this.markWeight,
    required this.homeworkText,
    required this.homeworkDeadline,
  });
}
