import '../models/profile_models.dart';

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
          "isReady": 1
        }
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
          }
        },
        {
          "relName": "Папа",
          "data": {
            "lastName": "Миронов",
            "firstName": "Андрей",
            "middleName": "Петрович",
            "mobilePhone": "+7 901 111-22-33",
            "email": "andrey.mironov@example.com",
          }
        }
      ],
    };
  }

  List<Map<String, dynamic>> classByUserJson() {
    return [
      {
        "groupId": 501,
        "groupName": "10А класс",
        "begDate": periodStart.millisecondsSinceEpoch.toDouble(),
      }
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
          "items": []
        }
      ]
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
                    {"markValue": lesson.markValue}
                  ]
                : []
          }
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
                      "text": lesson.homeworkText,
                      "deadLine": lesson.homeworkDeadline?.millisecondsSinceEpoch.toDouble(),
                      "file": []
                    }
                  ]
                : [],
            "mrkWt": lesson.markWeight,
          }
        ],
      };
    }).toList();

    final marks = lessons
        .where((lesson) => lesson.markValue != null)
        .map((lesson) => {
              "id": lesson.id + 5000,
              "value": lesson.markValue.toString(),
              "lessonID": lesson.id,
              "partType": "Оценка",
              "partID": 1,
            })
        .toList();

    return {
      "lesson": lessonJson,
      "user": [
        {"id": userId, "mark": marks}
      ],
    };
  }

  List<Map<String, dynamic>> getThreads() {
    return List<Map<String, dynamic>>.from(_threads);
  }

  List<Map<String, dynamic>> getMessages(int threadId) {
    return List<Map<String, dynamic>>.from(_messagesByThread[threadId] ?? []);
  }

  Map<String, dynamic> sendMessage(int threadId, String msgText) {
    final now = DateTime.now().millisecondsSinceEpoch.toDouble();
    final message = {
      "msgId": _nextMessageId++,
      "msg": msgText,
      "senderFio": fullName,
      "createDate": now,
      "isOwner": true,
      "senderId": userId,
      "senderPrsId": prsId,
      "imageId": null,
      "imgObjType": null,
      "imgObjId": null,
      "attachInfo": [],
    };

    _messagesByThread.putIfAbsent(threadId, () => []);
    _messagesByThread[threadId]!.add(message);
    _updateThreadPreview(threadId, msgText, now, fullName);
    return message;
  }

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
      }
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
    final t1 = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch.toDouble();
    final t2 = now.subtract(const Duration(days: 1, hours: 3)).millisecondsSinceEpoch.toDouble();
    final t3 = now.subtract(const Duration(days: 2)).millisecondsSinceEpoch.toDouble();

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
      {
        "msgId": _nextMessageId++,
        "msg": "Привет! Есть минутка?",
        "senderFio": "Илья Н.",
        "createDate": now.subtract(const Duration(hours: 4)).millisecondsSinceEpoch.toDouble(),
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
        "createDate": now.subtract(const Duration(hours: 3, minutes: 20)).millisecondsSinceEpoch.toDouble(),
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
        "createDate": now.subtract(const Duration(hours: 2, minutes: 10)).millisecondsSinceEpoch.toDouble(),
        "isOwner": false,
        "senderId": 3011,
        "senderPrsId": 3011,
        "imageId": null,
        "imgObjType": null,
        "imgObjId": null,
        "attachInfo": [],
      },
    ];
    return messages;
  }

  void _updateThreadPreview(int threadId, String msg, double sendDate, String sender) {
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

    for (var date = startDate; !date.isAfter(endDate); date = date.add(const Duration(days: 1))) {
      if (date.weekday > 5) continue;
      const lessonsPerDay = 5;
      for (int num = 1; num <= lessonsPerDay; num++) {
        final subject = _subjects[(num + date.weekday) % _subjects.length];
        final topic = subject.topics[(date.day + num) % subject.topics.length];
        final lessonDate = DateTime(date.year, date.month, date.day, 8 + num, 0);
        final lessonId = (lessonDate.millisecondsSinceEpoch ~/ 1000) + num;
        final markValue = num.isEven ? marks[(date.day + num) % marks.length] : null;
        final homeworkText = num.isOdd
            ? "Повторить тему: $topic. Выполнить задания №${10 + num}."
            : null;
        final deadline = homeworkText != null
            ? lessonDate.add(const Duration(days: 1, hours: 12))
            : null;

        lessons.add(_DemoLesson(
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
        ));
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