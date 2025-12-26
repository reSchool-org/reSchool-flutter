import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('ru'),
    Locale('en'),
  ];

  static final Map<String, Map<String, String>> _localizedValues = {
    'ru': {
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'close': 'Закрыть',
      'error': 'Ошибка',
      'continueText': 'Продолжить',
      'version': 'Версия',
      'language': 'Язык',
      'selectLanguage': 'Выберите язык',

      'enterCredentials': 'Введите логин и пароль',
      'invalidCredentials': 'Неверный логин или пароль',
      'electronicDiary': 'Электронный дневник',
      'username': 'Логин',
      'password': 'Пароль',
      'rememberMe': 'Запомнить меня',
      'login': 'Войти',

      'settings': 'Настройки',
      'general': 'Основные',
      'onlyCurrentYear': 'Только текущий год',
      'hideOldDiaries': 'Скрывать старые дневники',
      'cloudFeatures': 'Облачные функции',
      'verificationRequired': 'Требуется верификация',
      'devices': 'Устройства',
      'manageConnections': 'Управление подключениями',
      'homework': 'Домашние задания',
      'daysInPast': 'Дней в прошлом',
      'numberOfDays': 'Количество дней',
      'daysInFuture': 'Дней в будущем',
      'appearance': 'Оформление',
      'light': 'Светлая',
      'dark': 'Темная',
      'auto': 'Авто',
      'emulation': 'Эмуляция',
      'usedForLogin': 'Используется при входе',
      'widgets': 'Виджеты',
      'schedule': 'Расписание',
      'lessonsForToday': 'Уроки на сегодня',
      'showTeacher': 'Показывать учителя',
      'upcomingAssignments': 'Ближайшие задания',
      'count': 'Количество',
      'showDeadline': 'Показывать дедлайн',
      'grades': 'Оценки',
      'averageScores': 'Средние баллы',
      'subjects': 'Предметов',
      'updateWidgets': 'Обновить виджеты',
      'syncNow': 'Синхронизировать сейчас',
      'widgetsUpdated': 'Виджеты обновлены',
      'aboutApp': 'О приложении',

      'tokenInvalid': 'Токен недействителен. Облачные функции отключены.',
      'connectedDevices': 'Подключенные устройства',
      'noConnectedDevices': 'Нет подключенных устройств',
      'thisDevice': 'Это устройство',
      'revokeDeviceQuestion': 'Отключить устройство?',
      'revoke': 'Отключить',
      'deviceRevoked': 'Устройство отключено',
      'cloudDisclaimer': 'При включении ваше имя пользователя будет сохранено для верификации. Мы также увидим IP-адрес и PRS ID. Пароль и другие данные не передаются.',
      'cloudActivated': 'Облачные функции активированы',
      'verificationError': 'Ошибка верификации',
      'unknownDevice': 'Неизвестное устройство',

      'diary': 'Дневник',
      'marks': 'Оценки',
      'assignments': 'Задания',
      'chats': 'Чаты',
      'more': 'Ещё',

      'info': 'Информация',
      'help': 'Помощь',
      'soon': 'Скоро',
      'logoutQuestion': 'Выйти из аккаунта?',
      'logoutWarning': 'Вам нужно будет войти снова',
      'logout': 'Выйти',
      'selectTheme': 'Выберите тему',
      'theme': 'Тема',
      'calls': 'Звонки',
      'gradingSystem': 'Система оценивания',
      'gradingPresetSelect': 'Выберите пресет для расчёта среднего балла',
      'predictedGrade': 'Предварительная оценка',
      'showQuarterGrade': 'Показывать четвертную',

      'loading': 'Загрузка...',
      'noLessons': 'Нет уроков',
      'noLessonsScheduled': 'В этот день уроков не запланировано',
      'loadingError': 'Ошибка загрузки',
      'retry': 'Повторить',
      'today': 'Сегодня',
      'yesterday': 'Вчера',
      'tomorrow': 'Завтра',
      'weekSchedule': 'РАСПИСАНИЕ',
      'lessonsCount': '{count} уроков',
      'selectedDay': 'Выбранный день',

      'loadingMarks': 'Загрузка оценок...',
      'period': 'Период',
      'selectPeriod': 'Выберите период',
      'updateMarks': 'Обновить оценки',
      'updating': 'Обновление...',
      'noMarks': 'Нет оценок',
      'noMarksInPeriod': 'В этом периоде пока нет оценок',
      'teacher': 'Преподаватель',
      'rating': 'Рейтинг',
      'noData': 'Нет данных',
      'finalMark': 'Итоговая оценка',
      'prediction': 'Прогноз',
      'modifiedAverage': 'Изменённый средний',
      'calculatedAverage': 'Расчётный средний',
      'averageScoreApi': 'Средний балл (API)',
      'editMark': 'Изменить оценку',
      'replaceWithAnother': 'Заменить на другую',
      'excludeFromCalc': 'Исключить из расчёта',
      'markNotCounted': 'Оценка не будет учитываться',
      'markExcluded': 'Оценка исключена',
      'resetChanges': 'Сбросить изменения',
      'edit': 'Редактировать',
      'addMark': 'Добавить оценку',
      'markCaps': 'ОЦЕНКА',
      'markWeightCaps': 'ВЕС ОЦЕНКИ',
      'other': 'Другой',
      'add': 'Добавить',
      'markExcludedMessage': 'Оценка {mark} исключена',
      'averageScore': 'Средний балл',
      'allMarks': 'Все оценки',
      'marksCount': 'Количество оценок',
      'virtualMarks': 'Виртуальные оценки',

      'loadingProfile': 'Загрузка профиля...',
      'familyCaps': 'СЕМЬЯ',
      'relative': 'Родственник',
      'educationCaps': 'ОБУЧЕНИЕ',
      'birthday': 'День рождения',
      'phone': 'Телефон',
      'gender': 'Пол',
      'male': 'Мужской',
      'female': 'Женский',

      'homeworkTitle': 'Домашняя работа',
      'start': 'Начало',
      'end': 'Конец',
      'apply': 'Применить',
      'week': 'Неделя',
      'month': 'Месяц',
      'threeMonths': '3 месяца',
      'loadingAssignments': 'Загрузка заданий',
      'noAssignments': 'Нет заданий',
      'noAssignmentsInPeriod': 'За выбранный период\nдомашние задания не найдены',
      'overdue': 'Просрочено',
      'until': 'до',
      'attachment1': 'вложение',
      'attachment24': 'вложения',
      'attachment5': 'вложений',
      'byDates': 'ПО ДАТАМ',
      'allAssignments': 'Все задания',
      'tasksTotal': '{count} заданий',
      'tasksLabel': 'заданий',
      'all': 'Все',
      'showAll': 'Показать все',

      'messages': 'Сообщения',
      'chatsAndDialogs': 'Чаты и диалоги',
      'searchPlaceholder': 'Поиск чатов и людей',
      'globalSearchCaps': 'ГЛОБАЛЬНЫЙ ПОИСК',
      'noOneFound': 'Никого не найдено',
      'foundChatsCaps': 'НАЙДЕННЫЕ ЧАТЫ',
      'loadingMessages': 'Загрузка сообщений',
      'noMessages': 'Нет сообщений',
      'startChatting': 'Начните общение\nс одноклассниками и учителями',
      'newGroup': 'Новая группа',
      'create': 'Создать',
      'groupName': 'Название группы',
      'searchParticipants': 'Поиск участников',
      'chat': 'Чат',
      'noName': 'Без имени',
      'selectChat': 'Выберите чат',
      'selectChatPrompt': 'Выберите чат из списка слева\nили начните новый диалог',

      'lessonEnd': 'До конца урока:',
      'homeworkWithFiles': 'ДЗ + {count} файл',
      'homeworkLabel': 'Домашнее задание',
      'lessonHeader': 'Урок {num} • {start} — {end}',
      'lessonTeacher': 'Учитель',
      'lessonTopic': 'Тема урока',
      'markLabel': 'Оценка',
      'markWeight': 'Вес: {weight}',
      'homeworkCaps': 'ДОМАШНЕЕ ЗАДАНИЕ',
      'filesCount': '{count} файл(ов)',

      'breakDuration': 'Перемена {duration} мин',
      'breakLabel': 'Отдыхаем:',

      'addCustomHomework': 'Добавить ДЗ',
      'editCustomHomework': 'Редактировать ДЗ',
      'deleteCustomHomework': 'Удалить ДЗ',
      'customHomework': 'Кастомное ДЗ',
      'customHomeworkFrom': 'От одноклассника',
      'homeworkText': 'Текст задания',
      'homeworkTextHint': 'Введите текст домашнего задания...',
      'attachFiles': 'Прикрепить файлы',
      'maxFilesLimit': 'Максимум {count} файлов',
      'maxFileSize': 'Максимум {size} МБ на файл',
      'fileTooLarge': 'Файл слишком большой',
      'homeworkCreated': 'ДЗ добавлено',
      'homeworkUpdated': 'ДЗ обновлено',
      'homeworkDeleted': 'ДЗ удалено',
      'deleteHomeworkQuestion': 'Удалить домашнее задание?',
      'deleteHomeworkWarning': 'Это действие нельзя отменить',
      'delete': 'Удалить',
      'noCustomHomework': 'Нет кастомных ДЗ',
      'cloudRequiredForHomework': 'Включите облачные функции для добавления ДЗ',
    },
    'en': {
      'cancel': 'Cancel',
      'save': 'Save',
      'close': 'Close',
      'error': 'Error',
      'continueText': 'Continue',
      'version': 'Version',
      'language': 'Language',
      'selectLanguage': 'Select Language',

      'enterCredentials': 'Enter username and password',
      'invalidCredentials': 'Invalid username or password',
      'electronicDiary': 'Electronic Diary',
      'username': 'Username',
      'password': 'Password',
      'rememberMe': 'Remember me',
      'login': 'Login',

      'settings': 'Settings',
      'general': 'General',
      'onlyCurrentYear': 'Only current year',
      'hideOldDiaries': 'Hide old diaries',
      'cloudFeatures': 'Cloud features',
      'verificationRequired': 'Verification required',
      'devices': 'Devices',
      'manageConnections': 'Manage connections',
      'homework': 'Homework',
      'daysInPast': 'Days in past',
      'numberOfDays': 'Number of days',
      'daysInFuture': 'Days in future',
      'appearance': 'Appearance',
      'light': 'Light',
      'dark': 'Dark',
      'auto': 'Auto',
      'emulation': 'Emulation',
      'usedForLogin': 'Used for login',
      'widgets': 'Widgets',
      'schedule': 'Schedule',
      'lessonsForToday': 'Lessons for today',
      'showTeacher': 'Show teacher',
      'upcomingAssignments': 'Upcoming assignments',
      'count': 'Count',
      'showDeadline': 'Show deadline',
      'grades': 'Grades',
      'averageScores': 'Average scores',
      'subjects': 'Subjects',
      'updateWidgets': 'Update widgets',
      'syncNow': 'Sync now',
      'widgetsUpdated': 'Widgets updated',
      'aboutApp': 'About app',

      'tokenInvalid': 'Token invalid. Cloud features disabled.',
      'connectedDevices': 'Connected devices',
      'noConnectedDevices': 'No connected devices',
      'thisDevice': 'This device',
      'revokeDeviceQuestion': 'Revoke device?',
      'revoke': 'Revoke',
      'deviceRevoked': 'Device revoked',
      'cloudDisclaimer': 'Enabling this will save your username for verification. We will also see your IP address and PRS ID. Password and other data are not shared.',
      'cloudActivated': 'Cloud features activated',
      'verificationError': 'Verification error',
      'unknownDevice': 'Unknown device',

      'diary': 'Diary',
      'marks': 'Grades',
      'assignments': 'Homework',
      'chats': 'Chats',
      'more': 'More',

      'info': 'Info',
      'help': 'Help',
      'soon': 'Soon',
      'logoutQuestion': 'Log out?',
      'logoutWarning': 'You will need to login again',
      'logout': 'Log out',
      'selectTheme': 'Select theme',
      'theme': 'Theme',
      'calls': 'Bells',
      'gradingSystem': 'Grading system',
      'gradingPresetSelect': 'Select a preset to calculate GPA',
      'predictedGrade': 'Predicted grade',
      'showQuarterGrade': 'Show quarter grade',

      'loading': 'Loading...',
      'noLessons': 'No lessons',
      'noLessonsScheduled': 'No lessons scheduled for this day',
      'loadingError': 'Loading error',
      'retry': 'Retry',
      'today': 'Today',
      'yesterday': 'Yesterday',
      'tomorrow': 'Tomorrow',
      'weekSchedule': 'SCHEDULE',
      'lessonsCount': '{count} lessons',
      'selectedDay': 'Selected day',

      'loadingMarks': 'Loading grades...',
      'period': 'Period',
      'selectPeriod': 'Select period',
      'updateMarks': 'Update grades',
      'updating': 'Updating...',
      'noMarks': 'No grades',
      'noMarksInPeriod': 'No grades in this period yet',
      'teacher': 'Teacher',
      'rating': 'Rating',
      'noData': 'No data',
      'finalMark': 'Final grade',
      'prediction': 'Prediction',
      'modifiedAverage': 'Modified average',
      'calculatedAverage': 'Calculated average',
      'averageScoreApi': 'Average score (API)',
      'editMark': 'Edit grade',
      'replaceWithAnother': 'Replace with another',
      'excludeFromCalc': 'Exclude from calculation',
      'markNotCounted': 'The grade will not be counted',
      'markExcluded': 'Grade excluded',
      'resetChanges': 'Reset changes',
      'edit': 'Edit',
      'addMark': 'Add grade',
      'markCaps': 'GRADE',
      'markWeightCaps': 'GRADE WEIGHT',
      'other': 'Other',
      'add': 'Add',
      'markExcludedMessage': 'Grade {mark} excluded',
      'averageScore': 'Average score',
      'allMarks': 'All grades',
      'marksCount': 'Grades count',
      'virtualMarks': 'Virtual grades',

      'loadingProfile': 'Loading profile...',
      'familyCaps': 'FAMILY',
      'relative': 'Relative',
      'educationCaps': 'EDUCATION',
      'birthday': 'Birthday',
      'phone': 'Phone',
      'gender': 'Gender',
      'male': 'Male',
      'female': 'Female',

      'homeworkTitle': 'Homework',
      'start': 'Start',
      'end': 'End',
      'apply': 'Apply',
      'week': 'Week',
      'month': 'Month',
      'threeMonths': '3 months',
      'loadingAssignments': 'Loading assignments...',
      'noAssignments': 'No assignments',
      'noAssignmentsInPeriod': 'No homework found\nfor the selected period',
      'overdue': 'Overdue',
      'until': 'until',
      'attachment1': 'attachment',
      'attachment24': 'attachments',
      'attachment5': 'attachments',
      'byDates': 'BY DATES',
      'allAssignments': 'All assignments',
      'tasksTotal': '{count} tasks',
      'tasksLabel': 'tasks',
      'all': 'All',
      'showAll': 'Show all',

      'messages': 'Messages',
      'chatsAndDialogs': 'Chats and dialogs',
      'searchPlaceholder': 'Search chats and people',
      'globalSearchCaps': 'GLOBAL SEARCH',
      'noOneFound': 'No one found',
      'foundChatsCaps': 'FOUND CHATS',
      'loadingMessages': 'Loading messages...',
      'noMessages': 'No messages',
      'startChatting': 'Start chatting\nwith classmates and teachers',
      'newGroup': 'New group',
      'create': 'Create',
      'groupName': 'Group name',
      'searchParticipants': 'Search participants',
      'chat': 'Chat',
      'noName': 'No name',
      'selectChat': 'Select chat',
      'selectChatPrompt': 'Select a chat from the list\nor start a new dialog',

      'lessonEnd': 'Lesson ends in:',
      'homeworkWithFiles': 'HW + {count} file',
      'homeworkLabel': 'Homework',
      'lessonHeader': 'Lesson {num} • {start} — {end}',
      'lessonTeacher': 'Teacher',
      'lessonTopic': 'Lesson topic',
      'markLabel': 'Grade',
      'markWeight': 'Weight: {weight}',
      'homeworkCaps': 'HOMEWORK',
      'filesCount': '{count} file(s)',

      'breakDuration': 'Break {duration} min',
      'breakLabel': 'Break:',

      'addCustomHomework': 'Add Homework',
      'editCustomHomework': 'Edit Homework',
      'deleteCustomHomework': 'Delete Homework',
      'customHomework': 'Custom Homework',
      'customHomeworkFrom': 'From classmate',
      'homeworkText': 'Homework text',
      'homeworkTextHint': 'Enter homework text...',
      'attachFiles': 'Attach files',
      'maxFilesLimit': 'Maximum {count} files',
      'maxFileSize': 'Maximum {size} MB per file',
      'fileTooLarge': 'File too large',
      'homeworkCreated': 'Homework added',
      'homeworkUpdated': 'Homework updated',
      'homeworkDeleted': 'Homework deleted',
      'deleteHomeworkQuestion': 'Delete homework?',
      'deleteHomeworkWarning': 'This action cannot be undone',
      'delete': 'Delete',
      'noCustomHomework': 'No custom homework',
      'cloudRequiredForHomework': 'Enable cloud features to add homework',
    },
  };

  String get cancel => _localizedValues[locale.languageCode]!['cancel']!;
  String get save => _localizedValues[locale.languageCode]!['save']!;
  String get close => _localizedValues[locale.languageCode]!['close']!;
  String get error => _localizedValues[locale.languageCode]!['error']!;
  String get continueText => _localizedValues[locale.languageCode]!['continueText']!;
  String get version => _localizedValues[locale.languageCode]!['version']!;
  String get language => _localizedValues[locale.languageCode]!['language']!;
  String get selectLanguage => _localizedValues[locale.languageCode]!['selectLanguage']!;

  String get enterCredentials => _localizedValues[locale.languageCode]!['enterCredentials']!;
  String get invalidCredentials => _localizedValues[locale.languageCode]!['invalidCredentials']!;
  String get electronicDiary => _localizedValues[locale.languageCode]!['electronicDiary']!;
  String get username => _localizedValues[locale.languageCode]!['username']!;
  String get password => _localizedValues[locale.languageCode]!['password']!;
  String get rememberMe => _localizedValues[locale.languageCode]!['rememberMe']!;
  String get login => _localizedValues[locale.languageCode]!['login']!;

  String get settings => _localizedValues[locale.languageCode]!['settings']!;
  String get general => _localizedValues[locale.languageCode]!['general']!;
  String get onlyCurrentYear => _localizedValues[locale.languageCode]!['onlyCurrentYear']!;
  String get hideOldDiaries => _localizedValues[locale.languageCode]!['hideOldDiaries']!;
  String get cloudFeatures => _localizedValues[locale.languageCode]!['cloudFeatures']!;
  String get verificationRequired => _localizedValues[locale.languageCode]!['verificationRequired']!;
  String get devices => _localizedValues[locale.languageCode]!['devices']!;
  String get manageConnections => _localizedValues[locale.languageCode]!['manageConnections']!;
  String get homework => _localizedValues[locale.languageCode]!['homework']!;
  String get daysInPast => _localizedValues[locale.languageCode]!['daysInPast']!;
  String get numberOfDays => _localizedValues[locale.languageCode]!['numberOfDays']!;
  String get daysInFuture => _localizedValues[locale.languageCode]!['daysInFuture']!;
  String get appearance => _localizedValues[locale.languageCode]!['appearance']!;
  String get light => _localizedValues[locale.languageCode]!['light']!;
  String get dark => _localizedValues[locale.languageCode]!['dark']!;
  String get auto => _localizedValues[locale.languageCode]!['auto']!;
  String get emulation => _localizedValues[locale.languageCode]!['emulation']!;
  String get usedForLogin => _localizedValues[locale.languageCode]!['usedForLogin']!;
  String get widgets => _localizedValues[locale.languageCode]!['widgets']!;
  String get schedule => _localizedValues[locale.languageCode]!['schedule']!;
  String get lessonsForToday => _localizedValues[locale.languageCode]!['lessonsForToday']!;
  String get showTeacher => _localizedValues[locale.languageCode]!['showTeacher']!;
  String get upcomingAssignments => _localizedValues[locale.languageCode]!['upcomingAssignments']!;
  String get count => _localizedValues[locale.languageCode]!['count']!;
  String get showDeadline => _localizedValues[locale.languageCode]!['showDeadline']!;
  String get grades => _localizedValues[locale.languageCode]!['grades']!;
  String get averageScores => _localizedValues[locale.languageCode]!['averageScores']!;
  String get subjects => _localizedValues[locale.languageCode]!['subjects']!;
  String get updateWidgets => _localizedValues[locale.languageCode]!['updateWidgets']!;
  String get syncNow => _localizedValues[locale.languageCode]!['syncNow']!;
  String get widgetsUpdated => _localizedValues[locale.languageCode]!['widgetsUpdated']!;
  String get aboutApp => _localizedValues[locale.languageCode]!['aboutApp']!;

  String get tokenInvalid => _localizedValues[locale.languageCode]!['tokenInvalid']!;
  String get connectedDevices => _localizedValues[locale.languageCode]!['connectedDevices']!;
  String get noConnectedDevices => _localizedValues[locale.languageCode]!['noConnectedDevices']!;
  String get thisDevice => _localizedValues[locale.languageCode]!['thisDevice']!;
  String get revokeDeviceQuestion => _localizedValues[locale.languageCode]!['revokeDeviceQuestion']!;
  String get revoke => _localizedValues[locale.languageCode]!['revoke']!;
  String get deviceRevoked => _localizedValues[locale.languageCode]!['deviceRevoked']!;
  String get cloudDisclaimer => _localizedValues[locale.languageCode]!['cloudDisclaimer']!;
  String get cloudActivated => _localizedValues[locale.languageCode]!['cloudActivated']!;
  String get verificationError => _localizedValues[locale.languageCode]!['verificationError']!;
  String get unknownDevice => _localizedValues[locale.languageCode]!['unknownDevice']!;

  String get diary => _localizedValues[locale.languageCode]!['diary']!;
  String get marks => _localizedValues[locale.languageCode]!['marks']!;
  String get assignments => _localizedValues[locale.languageCode]!['assignments']!;
  String get chats => _localizedValues[locale.languageCode]!['chats']!;
  String get more => _localizedValues[locale.languageCode]!['more']!;

  String get info => _localizedValues[locale.languageCode]!['info']!;
  String get help => _localizedValues[locale.languageCode]!['help']!;
  String get soon => _localizedValues[locale.languageCode]!['soon']!;
  String get logoutQuestion => _localizedValues[locale.languageCode]!['logoutQuestion']!;
  String get logoutWarning => _localizedValues[locale.languageCode]!['logoutWarning']!;
  String get logout => _localizedValues[locale.languageCode]!['logout']!;
  String get selectTheme => _localizedValues[locale.languageCode]!['selectTheme']!;
  String get theme => _localizedValues[locale.languageCode]!['theme']!;
  String get calls => _localizedValues[locale.languageCode]!['calls']!;
  String get gradingSystem => _localizedValues[locale.languageCode]!['gradingSystem']!;
  String get gradingPresetSelect => _localizedValues[locale.languageCode]!['gradingPresetSelect']!;
  String get predictedGrade => _localizedValues[locale.languageCode]!['predictedGrade']!;
  String get showQuarterGrade => _localizedValues[locale.languageCode]!['showQuarterGrade']!;

  String get loading => _localizedValues[locale.languageCode]!['loading']!;
  String get noLessons => _localizedValues[locale.languageCode]!['noLessons']!;
  String get noLessonsScheduled => _localizedValues[locale.languageCode]!['noLessonsScheduled']!;
  String get loadingError => _localizedValues[locale.languageCode]!['loadingError']!;
  String get retry => _localizedValues[locale.languageCode]!['retry']!;
  String get today => _localizedValues[locale.languageCode]!['today']!;
  String get yesterday => _localizedValues[locale.languageCode]!['yesterday']!;
  String get tomorrow => _localizedValues[locale.languageCode]!['tomorrow']!;
  String get weekSchedule => _localizedValues[locale.languageCode]!['weekSchedule']!;
  String lessonsCount(int count) => _localizedValues[locale.languageCode]!['lessonsCount']!.replaceAll('{count}', count.toString());
  String get selectedDay => _localizedValues[locale.languageCode]!['selectedDay']!;

  String get loadingMarks => _localizedValues[locale.languageCode]!['loadingMarks']!;
  String get period => _localizedValues[locale.languageCode]!['period']!;
  String get selectPeriod => _localizedValues[locale.languageCode]!['selectPeriod']!;
  String get updateMarks => _localizedValues[locale.languageCode]!['updateMarks']!;
  String get updating => _localizedValues[locale.languageCode]!['updating']!;
  String get noMarks => _localizedValues[locale.languageCode]!['noMarks']!;
  String get noMarksInPeriod => _localizedValues[locale.languageCode]!['noMarksInPeriod']!;
  String get teacher => _localizedValues[locale.languageCode]!['teacher']!;
  String get rating => _localizedValues[locale.languageCode]!['rating']!;
  String get noData => _localizedValues[locale.languageCode]!['noData']!;
  String get finalMark => _localizedValues[locale.languageCode]!['finalMark']!;
  String get prediction => _localizedValues[locale.languageCode]!['prediction']!;
  String get modifiedAverage => _localizedValues[locale.languageCode]!['modifiedAverage']!;
  String get calculatedAverage => _localizedValues[locale.languageCode]!['calculatedAverage']!;
  String get averageScoreApi => _localizedValues[locale.languageCode]!['averageScoreApi']!;
  String get editMark => _localizedValues[locale.languageCode]!['editMark']!;
  String get replaceWithAnother => _localizedValues[locale.languageCode]!['replaceWithAnother']!;
  String get excludeFromCalc => _localizedValues[locale.languageCode]!['excludeFromCalc']!;
  String get markNotCounted => _localizedValues[locale.languageCode]!['markNotCounted']!;
  String get markExcluded => _localizedValues[locale.languageCode]!['markExcluded']!;
  String get resetChanges => _localizedValues[locale.languageCode]!['resetChanges']!;
  String get edit => _localizedValues[locale.languageCode]!['edit']!;
  String get addMark => _localizedValues[locale.languageCode]!['addMark']!;
  String get markCaps => _localizedValues[locale.languageCode]!['markCaps']!;
  String get markWeightCaps => _localizedValues[locale.languageCode]!['markWeightCaps']!;
  String get other => _localizedValues[locale.languageCode]!['other']!;
  String get add => _localizedValues[locale.languageCode]!['add']!;
  String markExcludedMessage(String mark) => _localizedValues[locale.languageCode]!['markExcludedMessage']!.replaceAll('{mark}', mark);
  String get averageScore => _localizedValues[locale.languageCode]!['averageScore']!;
  String get allMarks => _localizedValues[locale.languageCode]!['allMarks']!;
  String get marksCount => _localizedValues[locale.languageCode]!['marksCount']!;
  String get virtualMarks => _localizedValues[locale.languageCode]!['virtualMarks']!;

  String get loadingProfile => _localizedValues[locale.languageCode]!['loadingProfile']!;
  String get familyCaps => _localizedValues[locale.languageCode]!['familyCaps']!;
  String get relative => _localizedValues[locale.languageCode]!['relative']!;
  String get educationCaps => _localizedValues[locale.languageCode]!['educationCaps']!;
  String get birthday => _localizedValues[locale.languageCode]!['birthday']!;
  String get phone => _localizedValues[locale.languageCode]!['phone']!;
  String get gender => _localizedValues[locale.languageCode]!['gender']!;
  String get male => _localizedValues[locale.languageCode]!['male']!;
  String get female => _localizedValues[locale.languageCode]!['female']!;

  String get homeworkTitle => _localizedValues[locale.languageCode]!['homeworkTitle']!;
  String get start => _localizedValues[locale.languageCode]!['start']!;
  String get end => _localizedValues[locale.languageCode]!['end']!;
  String get apply => _localizedValues[locale.languageCode]!['apply']!;
  String get week => _localizedValues[locale.languageCode]!['week']!;
  String get month => _localizedValues[locale.languageCode]!['month']!;
  String get threeMonths => _localizedValues[locale.languageCode]!['threeMonths']!;
  String get loadingAssignments => _localizedValues[locale.languageCode]!['loadingAssignments']!;
  String get noAssignments => _localizedValues[locale.languageCode]!['noAssignments']!;
  String get noAssignmentsInPeriod => _localizedValues[locale.languageCode]!['noAssignmentsInPeriod']!;
  String get overdue => _localizedValues[locale.languageCode]!['overdue']!;
  String get until => _localizedValues[locale.languageCode]!['until']!;
  String get attachment1 => _localizedValues[locale.languageCode]!['attachment1']!;
  String get attachment24 => _localizedValues[locale.languageCode]!['attachment24']!;
  String get attachment5 => _localizedValues[locale.languageCode]!['attachment5']!;
  String get byDates => _localizedValues[locale.languageCode]!['byDates']!;
  String get allAssignments => _localizedValues[locale.languageCode]!['allAssignments']!;
  String tasksTotal(int count) => _localizedValues[locale.languageCode]!['tasksTotal']!.replaceAll('{count}', count.toString());
  String get tasksLabel => _localizedValues[locale.languageCode]!['tasksLabel']!;
  String get all => _localizedValues[locale.languageCode]!['all']!;
  String get showAll => _localizedValues[locale.languageCode]!['showAll']!;

  String get messages => _localizedValues[locale.languageCode]!['messages']!;
  String get chatsAndDialogs => _localizedValues[locale.languageCode]!['chatsAndDialogs']!;
  String get searchPlaceholder => _localizedValues[locale.languageCode]!['searchPlaceholder']!;
  String get globalSearchCaps => _localizedValues[locale.languageCode]!['globalSearchCaps']!;
  String get noOneFound => _localizedValues[locale.languageCode]!['noOneFound']!;
  String get foundChatsCaps => _localizedValues[locale.languageCode]!['foundChatsCaps']!;
  String get loadingMessages => _localizedValues[locale.languageCode]!['loadingMessages']!;
  String get noMessages => _localizedValues[locale.languageCode]!['noMessages']!;
  String get startChatting => _localizedValues[locale.languageCode]!['startChatting']!;
  String get newGroup => _localizedValues[locale.languageCode]!['newGroup']!;
  String get create => _localizedValues[locale.languageCode]!['create']!;
  String get groupName => _localizedValues[locale.languageCode]!['groupName']!;
  String get searchParticipants => _localizedValues[locale.languageCode]!['searchParticipants']!;
  String get chat => _localizedValues[locale.languageCode]!['chat']!;
  String get noName => _localizedValues[locale.languageCode]!['noName']!;
  String get selectChat => _localizedValues[locale.languageCode]!['selectChat']!;
  String get selectChatPrompt => _localizedValues[locale.languageCode]!['selectChatPrompt']!;

  String get lessonEnd => _localizedValues[locale.languageCode]!['lessonEnd']!;
  String homeworkWithFiles(int count) => _localizedValues[locale.languageCode]!['homeworkWithFiles']!.replaceAll('{count}', count.toString());
  String get homeworkLabel => _localizedValues[locale.languageCode]!['homeworkLabel']!;
  String lessonHeader(int num, String start, String end) => _localizedValues[locale.languageCode]!['lessonHeader']!.replaceAll('{num}', num.toString()).replaceAll('{start}', start).replaceAll('{end}', end);
  String get lessonTeacher => _localizedValues[locale.languageCode]!['lessonTeacher']!;
  String get lessonTopic => _localizedValues[locale.languageCode]!['lessonTopic']!;
  String get markLabel => _localizedValues[locale.languageCode]!['markLabel']!;
  String markWeight(double weight) => _localizedValues[locale.languageCode]!['markWeight']!.replaceAll('{weight}', weight.toStringAsFixed(1));
  String get homeworkCaps => _localizedValues[locale.languageCode]!['homeworkCaps']!;
  String filesCount(int count) => _localizedValues[locale.languageCode]!['filesCount']!.replaceAll('{count}', count.toString());

  String breakDuration(int duration) => _localizedValues[locale.languageCode]!['breakDuration']!.replaceAll('{duration}', duration.toString());
  String get breakLabel => _localizedValues[locale.languageCode]!['breakLabel']!;

  String get addCustomHomework => _localizedValues[locale.languageCode]!['addCustomHomework']!;
  String get editCustomHomework => _localizedValues[locale.languageCode]!['editCustomHomework']!;
  String get deleteCustomHomework => _localizedValues[locale.languageCode]!['deleteCustomHomework']!;
  String get customHomework => _localizedValues[locale.languageCode]!['customHomework']!;
  String get customHomeworkFrom => _localizedValues[locale.languageCode]!['customHomeworkFrom']!;
  String get homeworkText => _localizedValues[locale.languageCode]!['homeworkText']!;
  String get homeworkTextHint => _localizedValues[locale.languageCode]!['homeworkTextHint']!;
  String get attachFiles => _localizedValues[locale.languageCode]!['attachFiles']!;
  String maxFilesLimit(int count) => _localizedValues[locale.languageCode]!['maxFilesLimit']!.replaceAll('{count}', count.toString());
  String maxFileSize(int size) => _localizedValues[locale.languageCode]!['maxFileSize']!.replaceAll('{size}', size.toString());
  String get fileTooLarge => _localizedValues[locale.languageCode]!['fileTooLarge']!;
  String get homeworkCreated => _localizedValues[locale.languageCode]!['homeworkCreated']!;
  String get homeworkUpdated => _localizedValues[locale.languageCode]!['homeworkUpdated']!;
  String get homeworkDeleted => _localizedValues[locale.languageCode]!['homeworkDeleted']!;
  String get deleteHomeworkQuestion => _localizedValues[locale.languageCode]!['deleteHomeworkQuestion']!;
  String get deleteHomeworkWarning => _localizedValues[locale.languageCode]!['deleteHomeworkWarning']!;
  String get delete => _localizedValues[locale.languageCode]!['delete']!;
  String get noCustomHomework => _localizedValues[locale.languageCode]!['noCustomHomework']!;
  String get cloudRequiredForHomework => _localizedValues[locale.languageCode]!['cloudRequiredForHomework']!;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ru'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}