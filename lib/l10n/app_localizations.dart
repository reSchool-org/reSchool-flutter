import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/login_failure.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [Locale('ru'), Locale('en')];

  static final Map<String, Map<String, String>> _localizedValues = {
    'ru': {
      'employeeDirectory': 'Сотрудники',
      'employeeDirectoryHint': 'Школа, подразделения и должности',
      'directorySearch': 'Поиск сотрудников',
      'directoryEmpty': 'В этом разделе пока никого нет',
      'directoryLoadError': 'Не удалось загрузить сотрудников',
      'directoryRoot': 'Школа',
      'directoryNoResults': 'Сотрудники не найдены',
      'startChat': 'Написать сообщение',
      'chatOpenError': 'Не удалось открыть чат',
      'searchMessages': 'Поиск по сообщениям',
      'searchMessagesHint': 'Введите не менее трёх символов',
      'searchNoResults': 'Сообщения не найдены',
      'searchMessagesError': 'Не удалось выполнить поиск',
      'olderMessages': 'Предыдущие сообщения',
      'chatLoadError': 'Не удалось загрузить сообщения',
      'chatMoreError': 'Не удалось загрузить историю',
      'chatAttachments': 'Вложения беседы',
      'chatPhotos': 'Фотографии',
      'chatDocuments': 'Документы',
      'chatMediaEmpty': 'Вложений пока нет',
      'chatMediaError': 'Не удалось загрузить вложения',
      'chatMediaNoMatches': 'Таких вложений нет',
      'chatFileSearch': 'Найти файл по имени',
      'editMessage': 'Редактировать сообщение',
      'deleteMessage': 'Удалить сообщение',
      'deleteMessageWarning':
          'Сообщение будет удалено у всех участников беседы.',
      'messageEditError': 'Не удалось сохранить сообщение. Возможно, время редактирования истекло.',
      'messageDeleteError': 'Не удалось удалить сообщение',
      'messageEdited': 'изменено',
      'chatPermissionsError': 'Не удалось проверить возможность редактирования',
      'messageCopy': 'Копировать текст',
      'sendMessageError': 'Сообщение не отправлено. Текст и файлы сохранены.',
      'refreshContent': 'Обновить',
      'imageLoadError': 'Не удалось загрузить изображение',
      'openImage': 'Открыть изображение',
      'linkOpenError': 'Не удалось открыть ссылку',
      'fileOpenError': 'Не удалось открыть файл',
      'downloadFileError': 'Не удалось загрузить файл',
      'fileActionOpen': 'Открыть',
      'fileActionShare': 'Поделиться',
      'searchExit': 'Вернуться к переписке',
      'previousMatch': 'Предыдущее совпадение',
      'nextMatch': 'Следующее совпадение',
      'chatReadOnly': 'В этой беседе нельзя отправлять сообщения',
      // общее
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'close': 'Закрыть',
      'error': 'Ошибка',
      'continueText': 'Продолжить',
      'version': 'Версия',
      'language': 'Язык',
      'selectLanguage': 'Выберите язык',

      // экран входа
      'loginTitle': 'Добро пожаловать',
      'loginSubtitle': 'Войдите в свой аккаунт eSchool',
      'enterCredentials': 'Введите логин и пароль',
      'invalidCredentials': 'Неверный логин или пароль',
      'loginFailed': 'Не удалось войти. Попробуйте ещё раз.',
      'loginTimeout': 'Сервер не ответил вовремя. Попробуйте ещё раз.',
      'loginNetworkError': 'Не удалось подключиться к серверу. Проверьте соединение с интернетом.',
      'loginInvalidResponse': 'Сервер вернул некорректный ответ при входе.',
      'loginForbidden': 'Сервер запретил доступ.',
      'loginRateLimited': 'Слишком много попыток входа. Попробуйте позже.',
      'loginServerError': 'Сервер временно недоступен. Попробуйте позже.',
      'loginStateError': 'Не удалось проверить сессию после входа.',
      'loginProxyError': 'Ошибка прокси-сервера.',
      'loginErrorCode': 'Код ошибки',
      'electronicDiary': 'Электронный дневник',
      'scheduleTitle': 'Расписание уроков',
      'gradesTitle': 'Оценки и успеваемость',
      'username': 'Логин',
      'password': 'Пароль',
      'rememberMe': 'Запомнить меня',
      'login': 'Войти',
      'acceptTermsPrefix': 'Я принимаю ',
      'acceptTermsSuffix': '',
      'termsOfUse': 'Условия использования',
      'legalTermsSubtitle': 'Правила работы с приложением и своим сервером',
      'legalPrivacySubtitle': 'Какие данные обрабатываются и где',
      'termsOfUseText': '1. Назначение приложения\nreSchool - неофициальный клиент eSchool Center. Используйте его только с аккаунтом, к которому у вас есть законный доступ, и соблюдайте правила электронного дневника. Приложение не заменяет официальный источник учебной информации.\n\n2. Собственный сервер\nОбщего официального облачного сервера reSchool нет. Дополнительные функции работают на сервере, который вы выбрали или развернули сами. До подключения узнайте, кто его администратор, какие данные он хранит, какие сервисы подключает и как запросить удаление. Передавайте данные входа только серверу, которому доверяете.\n\n3. Мониторинг и уведомления\nМониторинг использует переданные серверу логин и пароль eSchool для фоновых проверок. История хранится на выбранном сервере, а доставка уведомлений возможна через настроенного Telegram-бота. Push-доставки в приложение нет. Уведомления могут задерживаться или не приходить при недоступности сервера, eSchool или Telegram; проверяйте важную информацию в дневнике.\n\n4. Доступ и публикация\nХраните пароли, API-ключи, приглашения и токены ботов в тайне. Не передавайте чужие личные данные, переписку или файлы в общие чаты и внешние сервисы без необходимого разрешения. При настройке группы проверьте получателей и темы: уведомления по предметам без назначенной темы могут попадать в общий чат группы.\n\n5. Дополнительные функции\nАнализ заданий с помощью ИИ может содержать ошибки; проверяйте результаты и оценку времени. Экспорт и интеграции передают данные выбранным получателям согласно политике конфиденциальности. Администратор сервера отвечает за его настройки, доступность, хранение данных и подключённые сервисы в пределах своих обязанностей.\n\n6. Доступность и прекращение использования\nПриложение предоставляется «как есть»: непрерывная работа, совместимость с изменениями eSchool и точность автоматического анализа не гарантируются. Вы можете прекратить использование, отключить интеграции и запросить удаление данных. Отключение или выход не означают, что все серверные копии удалены. Эти условия не ограничивают права и ответственность, которые нельзя исключить по применимому законодательству.\n\n7. Документы и связь\nПолитика конфиденциальности и актуальные условия доступны в разделе «О приложении». По вопросам конкретного сервера обращайтесь к его администратору, по ошибкам приложения - через ссылки проекта в этом разделе. Для отдельных внешних сервисов действуют их собственные правила.\n\nПоследнее обновление: 11 сентября 2026',
      'unofficialAppDisclaimer': 'reSchool — неофициальный клиент eSchool Center, не связанный с его разработчиками. Используя приложение, вы принимаете все связанные риски. Облачные функции работают на выбранном вами сервере.',
      'acceptTermsRequired': 'Необходимо принять условия использования',

      // настройки
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

      // обновления
      'checkForUpdates': 'Проверить обновления',
      'checkingForUpdates': 'Проверка обновлений...',
      'updateAvailable': 'Доступно обновление',
      'updateAvailableMessage':
          'Доступна новая версия {version}. Хотите обновить?',
      'updateAvailableTestFlight':
          'Доступна новая версия {version} в TestFlight. Хотите открыть?',
      'updatePendingReview':
          'Версия {version} проходит проверку в App Store. Попробуйте позже.',
      'openTestFlight': 'Открыть TestFlight',
      'noUpdatesAvailable': 'У вас установлена последняя версия',
      'updateNow': 'Обновить',
      'skipUpdate': 'Пропустить',
      'later': 'Позже',
      'downloading': 'Загрузка...',
      'downloadingUpdate': 'Загрузка обновления',
      'pleaseWait': 'Пожалуйста, подождите...',
      'updateError': 'Ошибка обновления',
      'whatsNew': 'Что нового',
      'currentVersion': 'Текущая версия',

      // облако и устройства
      'tokenInvalid': 'Токен недействителен. Облачные функции отключены.',
      'connectedDevices': 'Подключенные устройства',
      'noConnectedDevices': 'Нет подключенных устройств',
      'thisDevice': 'Это устройство',
      'revokeDeviceQuestion': 'Отключить устройство?',
      'revoke': 'Отключить',
      'deviceRevoked': 'Устройство отключено',
      'cloudDisclaimer': 'Для верификации сохраняется имя пользователя; сервер также получает IP-адрес и PRS ID. При включении облачной проверки домашних заданий и оценок выбранному серверу передаются логин и пароль от аккаунта eSchool Center. Сервер хранит пароль в зашифрованном виде и может повторно использовать его для входа без вашего участия.',
      'cloudActivated': 'Облачные функции активированы',
      'cloudNotAvailableDemo': 'Облачные функции недоступны на демо-аккаунте',
      'verifying': 'Верификация...',
      'verificationError': 'Ошибка верификации',
      'unknownDevice': 'Неизвестное устройство',

      // навигация
      'diary': 'Дневник',
      'marks': 'Оценки',
      'assignments': 'Задания',
      'chats': 'Чаты',
      'more': 'Ещё',

      // экран «ещё»
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

      // дневник
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

      // оценки
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
      'analyticsViewTitle': 'Аналитика',
      'analyticsSelectSubject': 'Выберите предмет',
      'analyticsChartTitle': 'Диаграмма',
      'analyticsClassLabel': 'Класс',
      'analyticsStudentLabel': 'Ученик',
      'analyticsClassAvgYear': 'Средний класса (год)',
      'analyticsStudentAvgYear': 'Средний ученика (год)',
      'analyticsByTopicTitle': 'По датам и темам',
      'analyticsNoData': 'Нет данных',
      'analyticsNoDataHint': 'Попробуйте выбрать другой предмет или обновить',
      'analyticsNoSubjectTitle': 'Выберите предмет',
      'analyticsNoSubjectSubtitle':
          'Чтобы показать диаграмму и средние значения',
      'analyticsLessonsCount': '{count} уроков',

      // профиль
      'profileTitle': 'Профиль',
      'profileFamily': 'Семья',
      'profileEducation': 'Обучение',
      'profileEducationReady': 'Данные готовы',
      'loadingProfile': 'Загрузка профиля...',
      'infoCaps': 'ИНФОРМАЦИЯ',
      'familyCaps': 'СЕМЬЯ',
      'relative': 'Родственник',
      'educationCaps': 'ОБУЧЕНИЕ',
      'birthday': 'День рождения',
      'phone': 'Телефон',
      'gender': 'Пол',
      'male': 'Мужской',
      'female': 'Женский',

      // задания
      'homeworkTitle': 'Домашняя работа',
      'start': 'Начало',
      'end': 'Конец',
      'apply': 'Применить',
      'week': 'Неделя',
      'month': 'Месяц',
      'threeMonths': '3 месяца',
      'loadingAssignments': 'Загрузка заданий',
      'noAssignments': 'Нет заданий',
      'noAssignmentsInPeriod':
          'За выбранный период\nдомашние задания не найдены',
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

      // чаты
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
      'selectChatPrompt':
          'Выберите чат из списка слева\nили начните новый диалог',

      // карточка урока
      'lessonEnd': 'До конца урока:',
      'homeworkWithFiles': 'ДЗ + {count} файл',
      'homeworkLabel': 'Домашнее задание',
      'lessonHeader': 'Урок {num} • {start} - {end}',
      'lessonTeacher': 'Учитель',
      'lessonTopic': 'Тема урока',
      'markLabel': 'Оценка',
      'markWeight': 'Вес: {weight}',
      'homeworkCaps': 'ДОМАШНЕЕ ЗАДАНИЕ',
      'filesCount': '{count} файл(ов)',

      // карточка перемены
      'breakDuration': 'Перемена {duration} мин',
      'breakLabel': 'Отдыхаем:',

      // своё домашнее задание
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

      // уведомления
      'notifications': 'Уведомления',
      'notificationsSubtitle': 'История изменений дневника',

      // для разработчика
      'developer': 'Разработчик',
      'developerMode': 'Режим разработчика',
      'developerModeEnabled': 'Режим разработчика включен',
      'developerTools': 'Инструменты разработчика',

      // промо облака

      // политика конфиденциальности
      'privacyPolicy': 'Политика конфиденциальности',
      'privacyGeneral': 'Общие положения',
      'privacyGeneralText': 'reSchool - неофициальный клиент eSchool Center, не связанный с владельцем электронного дневника. У проекта нет общего официального сервера для хранения дневников или обработки облачных аккаунтов. Основные данные приложение получает из eSchool Center. Для облачных функций вы самостоятельно выбираете и подключаете свой сервер либо сервер другого администратора. Разработчик приложения не получает доступ к нему автоматически. Эта политика описывает работу данной версии; администратор выбранного сервера отдельно определяет условия обработки данных на нём.',
      'privacyDataCollected': 'Какие данные обрабатываются',
      'privacyDataCollectedText': 'На устройстве обрабатываются данные входа и сессии eSchool, профиль, расписание, домашние задания, оценки, переписка, вложения, настройки и локальный кэш.\n\nВ зависимости от подключённых функций выбранный сервер получает:\n• Имя пользователя, PRS ID, класс и имя устройства\n• IP-адрес и технические сведения о запросах\n• Логин и пароль eSchool для фонового мониторинга\n• Данные дневника, сообщения, задания, загруженные файлы и результаты анализа\n• Настройки доступа, Telegram ID, идентификаторы чатов и тем, а при настройке бота - его токен.\n\nПароль нужен для повторного входа в eSchool и не является одноразовым кодом. Push-токены приложение не получает и сервер не использует.',
      'privacyPurpose': 'Цели обработки',
      'privacyPurposeText': 'Данные нужны для входа в дневник, отображения учебной информации и переписки, проверки прав доступа, работы подключённых устройств, общих заданий и файлов, фонового мониторинга, истории уведомлений и доставки в Telegram. Анализ заданий и экспорт данных выполняются при использовании соответствующих функций.',
      'privacyStorage': 'Хранение данных',
      'privacyStorageText': 'Настройки и кэш хранятся на устройстве. Для сохранённых учётных данных eSchool используется защищённое хранилище платформы. Некоторые токены облачного доступа и настройки Telegram сохраняются в обычных настройках приложения без дополнительного шифрования.\n\nОблачные данные хранятся у администратора выбранного сервера, в его базе, файловом хранилище, кэше и резервных копиях. Пароль eSchool шифруется на сервере, но сервер может расшифровать его для входа в дневник; это не сквозное шифрование от администратора. Место хранения, сроки удаления, журналы, резервные копии и круг лиц с доступом определяет администратор сервера. Уточните их до подключения.',
      'privacyThirdParty': 'Сервисы и получатели данных',
      'privacyThirdPartyText': '• eSchool Center получает запросы для входа и работы с дневником. Если настроен веб-прокси, запросы проходят через выбранный вами сервер.\n• Telegram получает текст и вложения уведомлений при подключении бота. Сообщения доступны участникам выбранного чата; при отправке в группу учитывайте её состав.\n• Если администратор включил анализ заданий, сервер передаёт материалы для анализа в Google Gemini / Vertex AI либо через OpenRouter выбранному поставщику модели согласно настройкам сервера.\n• При экспорте в Obsidian зашифрованная заметка загружается на kmi.aeza.net; ключ передаётся локально в Obsidian.\n• Проверка обновлений и версии клиента eSchool обращается к GitHub. Загрузка шрифтов может обращаться к Google Fonts. При открытии внешних ссылок данные соединения получает соответствующий сайт. Эти сервисы видят технические данные запроса, включая IP-адрес.\n\nВ этой версии нет доставки push через Firebase или промежуточный сервер разработчика. Данные выбранного сервера не пересылаются разработчику для доставки уведомлений. Внешние сервисы работают по собственным условиям; отключение облака не отключает обычные запросы к eSchool и проверку обновлений.',
      'privacyRights': 'Права пользователя',
      'privacyRightsText': 'Вы можете отключить мониторинг и интеграции, отозвать доступ устройства, очистить локальные данные и запросить удаление серверных данных. За сведениями о хранящихся данных, исправлением, удалением и сроками хранения обратитесь к администратору именно того сервера, к которому подключились.\n\nВыход из аккаунта и отключение облака сами по себе не подтверждают удаление данных. Проверьте результат запроса на удаление; если сервер недоступен, повторите запрос или свяжитесь с его администратором. Копии в Telegram, экспортированные файлы, данные eSchool и резервные копии могут потребовать отдельного удаления у соответствующего получателя. Разработчик не может удалить данные на чужом сервере, к которому не имеет доступа.',
      'privacyDisclaimer': 'Роли и обращения',
      'privacyDisclaimerText': 'Разработчик поддерживает приложение и публикует его исходный код. Администратор выбранного сервера управляет его работой, доступом, подключёнными сервисами и обработкой данных. Эта политика не заменяет сведения об администраторе и его собственные условия. Используйте сервер, владельца и настройки которого вы знаете.\n\nОб ошибках приложения можно сообщить через ссылки проекта в разделе «О приложении»; не отправляйте пароли, токены или чужие данные. Права пользователей и обязанности участников, установленные применимым законодательством, сохраняются.',
      'privacyChanges': 'Изменения политики',
      'privacyChangesText': 'Актуальная редакция доступна в разделе «О приложении». При изменении функций описание обработки данных обновляется вместе с приложением. Дата редакции указана ниже. Изменения политики не подменяют отдельное согласие там, где оно необходимо. Условия конкретного сервера уточняйте у его администратора.',
      'privacyLastUpdated': 'Последнее обновление: 11 сентября 2026',

      // удаление данных
      'deleteAllData': 'Удалить данные',
      'deleteAllDataSubtitle': 'Удалить все данные с сервера',
      'deleteDataConfirmTitle': 'Удалить все данные?',
      'deleteDataConfirmText': 'Будет выполнен запрос на удаление серверных данных. Удалённый запрос может завершиться ошибкой, поэтому удаление всех данных не гарантируется. Успешное удаление необратимо. Вы также будете разлогинены; выход из аккаунта сам по себе не подтверждает удаление данных с сервера.',
      'deleteDataSuccess': 'Данные удалены',
      'deleteDataError': 'Ошибка удаления данных',

      // облачные функции
      'cloudFunctions': 'Облачные функции',
      'cloudFunctions3': 'Облачные функции',
      'cloudFunctions3Desc': 'Мониторинг дневника и уведомлений',
      'serverSettings': 'Настройки сервера',
      'useReSchoolServer': 'Подключить сервер',
      'useCustomServer': 'Указать свой сервер',
      'serverUrl': 'URL или домен сервера',
      'serverUrlHint': 'school.example.com',
      'reSchoolServerDefault': 'Сервер не выбран',
      'iosHttpWarning': 'На iOS HTTP-соединения запрещены. Используйте HTTPS.',
      'invalidServerUrl': 'Неверный URL сервера',
      'checkInterval': 'Интервал проверки',
      'checkIntervalMinutes': 'Каждые {minutes} минут',
      'minutes': 'мин',
      'minIntervalWarning': 'Минимальный интервал: 10 минут',
      'cf3CredentialsWarning': 'Внимание: при включении на сервер будут переданы логин и пароль от вашего аккаунта.',
      'cf3Description': 'Выбранный сервер проверяет новые задания, оценки и сообщения, сохраняет историю и отправляет уведомления в подключённый Telegram.',
      'configure': 'Настроить',
      'enabled': 'Включено',
      'disabled': 'Отключено',

      // история уведомлений
      'notificationHistory': 'История уведомлений',
      'noNotifications': 'Нет уведомлений',
      'noNotificationsDesc':
          'Здесь появятся уведомления о новых ДЗ, оценках и сообщениях',
      'cf3NotEnabled': 'Уведомления не включены',
      'cf3NotEnabledDesc': 'Подключите свой сервер и включите мониторинг в настройках облачных функций',
      'connectionError': 'Ошибка подключения',
      'checkInternet': 'Проверьте подключение к интернету',
      'tryAgainLater': 'Попробуйте позже',
      'loadMore': 'Загрузить ещё',

      // безопасность и пин код
      'security': 'Безопасность',
      'pinCode': 'Код-пароль',
      'pinCodeSubtitle': 'Защита входа в приложение',
      'pinCodeEnabled': 'Код-пароль установлен',
      'pinCodeDisabled': 'Не установлен',
      'changePin': 'Изменить код-пароль',
      'disablePin': 'Отключить код-пароль',
      'disablePinQuestion': 'Отключить код-пароль?',
      'disablePinWarning': 'Защита входа будет снята',
      'disable': 'Отключить',
      'biometrics': 'Биометрия',
      'biometricsSubtitle': 'Face ID / Touch ID вместо код-пароля',
      'pinRequiredFirst': 'Сначала установите код-пароль',
    },
    'en': {
      'employeeDirectory': 'Staff',
      'employeeDirectoryHint': 'School, departments and positions',
      'directorySearch': 'Search staff',
      'directoryEmpty': 'No staff in this section',
      'directoryLoadError': 'Could not load staff',
      'directoryRoot': 'School',
      'directoryNoResults': 'No staff found',
      'startChat': 'Send a message',
      'chatOpenError': 'Could not open chat',
      'searchMessages': 'Search messages',
      'searchMessagesHint': 'Enter at least three characters',
      'searchNoResults': 'No messages found',
      'searchMessagesError': 'Search failed',
      'olderMessages': 'Older messages',
      'chatLoadError': 'Could not load messages',
      'chatMoreError': 'Could not load history',
      'chatAttachments': 'Chat attachments',
      'chatPhotos': 'Photos',
      'chatDocuments': 'Documents',
      'chatMediaEmpty': 'No attachments yet',
      'chatMediaError': 'Could not load attachments',
      'chatMediaNoMatches': 'No matching attachments',
      'chatFileSearch': 'Find a file by name',
      'editMessage': 'Edit message',
      'deleteMessage': 'Delete message',
      'deleteMessageWarning':
          'The message will be deleted for everyone in the chat.',
      'messageEditError':
          'Could not save the message. The editing period may have expired.',
      'messageDeleteError': 'Could not delete message',
      'messageEdited': 'edited',
      'chatPermissionsError': 'Could not check editing permissions',
      'messageCopy': 'Copy text',
      'sendMessageError':
          'Message not sent. Your text and files have been kept.',
      'refreshContent': 'Refresh',
      'imageLoadError': 'Could not load image',
      'openImage': 'Open image',
      'linkOpenError': 'Could not open link',
      'fileOpenError': 'Could not open file',
      'downloadFileError': 'Could not download file',
      'fileActionOpen': 'Open',
      'fileActionShare': 'Share',
      'searchExit': 'Back to conversation',
      'previousMatch': 'Previous match',
      'nextMatch': 'Next match',
      'chatReadOnly': 'Sending messages is disabled in this chat',
      // общее
      'cancel': 'Cancel',
      'save': 'Save',
      'close': 'Close',
      'error': 'Error',
      'continueText': 'Continue',
      'version': 'Version',
      'language': 'Language',
      'selectLanguage': 'Select Language',

      // экран входа
      'loginTitle': 'Welcome',
      'loginSubtitle': 'Sign in to your eSchool account',
      'enterCredentials': 'Enter username and password',
      'invalidCredentials': 'Invalid username or password',
      'loginFailed': 'Unable to sign in. Please try again.',
      'loginTimeout': 'The server did not respond in time. Please try again.',
      'loginNetworkError':
          'Unable to connect to the server. Check your internet connection.',
      'loginInvalidResponse':
          'The server returned an invalid sign-in response.',
      'loginForbidden': 'The server denied access.',
      'loginRateLimited': 'Too many sign-in attempts. Please try again later.',
      'loginServerError':
          'The server is temporarily unavailable. Please try again later.',
      'loginStateError': 'Unable to verify the session after signing in.',
      'loginProxyError': 'Proxy server error.',
      'loginErrorCode': 'Error code',
      'electronicDiary': 'Electronic Diary',
      'scheduleTitle': 'Class Schedule',
      'gradesTitle': 'Grades & Performance',
      'username': 'Username',
      'password': 'Password',
      'rememberMe': 'Remember me',
      'login': 'Login',
      'acceptTermsPrefix': 'I accept the ',
      'acceptTermsSuffix': '',
      'termsOfUse': 'Terms of Use',
      'legalTermsSubtitle': 'Using the app and your server',
      'legalPrivacySubtitle': 'What data is processed and where',
      'termsOfUseText': '1. Purpose\nreSchool is an unofficial eSchool Center client. Use only an account you are authorized to access and follow the diary provider’s rules. The app does not replace the official source of school information.\n\n2. Your server\nThere is no shared official reSchool cloud server. Extra features run on a server you choose or deploy. Before connecting, identify its administrator, stored data, integrations and deletion process. Send sign-in credentials only to a server you trust.\n\n3. Monitoring and notifications\nMonitoring uses the eSchool username and password sent to the selected server for background checks. History is kept on that server; delivery is available through a configured Telegram bot. There is no push delivery to the app. Notifications may be delayed or missing when the server, eSchool or Telegram is unavailable. Check important information in the diary.\n\n4. Access and sharing\nKeep passwords, API keys, invitations and bot tokens private. Do not share other people’s personal data, conversations or files with groups or external services without the required permission. Check group recipients and topics: subject notifications without an assigned topic may reach the general group chat.\n\n5. Additional features\nAI analysis can be wrong; verify results and time estimates. Exports and integrations send data to recipients described in the privacy policy. Server administrators manage configuration, availability, storage and integrations within their responsibilities.\n\n6. Availability and stopping use\nThe app is provided as is. Continuous operation, compatibility with eSchool changes and accurate automated analysis are not guaranteed. You may stop using it, disable integrations and request deletion. Disconnecting or signing out does not mean all server copies are deleted. These terms do not exclude rights or liability that cannot be excluded under applicable law.\n\n7. Documents and contact\nThe current terms and privacy policy are available in About. Contact the administrator for server issues and use the project links there for app issues. External services have their own rules.\n\nLast updated: September 11, 2026',
      'unofficialAppDisclaimer': 'reSchool is an unofficial eSchool Center client and is not affiliated with its developers. By using the app, you accept all associated risks. Cloud features run on your chosen server.',
      'acceptTermsRequired': 'You must accept the terms of use',

      // настройки
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

      // обновления
      'checkForUpdates': 'Check for updates',
      'checkingForUpdates': 'Checking for updates...',
      'updateAvailable': 'Update available',
      'updateAvailableMessage':
          'Version {version} is available. Would you like to update?',
      'updateAvailableTestFlight': 'Version {version} is available on TestFlight. Would you like to open it?',
      'updatePendingReview': 'Version {version} is under App Store review. Please try again later.',
      'openTestFlight': 'Open TestFlight',
      'noUpdatesAvailable': 'You have the latest version',
      'updateNow': 'Update',
      'skipUpdate': 'Skip',
      'later': 'Later',
      'downloading': 'Downloading...',
      'downloadingUpdate': 'Downloading update',
      'pleaseWait': 'Please wait...',
      'updateError': 'Update error',
      'whatsNew': "What's new",
      'currentVersion': 'Current version',

      // облако и устройства
      'tokenInvalid': 'Token invalid. Cloud features disabled.',
      'connectedDevices': 'Connected devices',
      'noConnectedDevices': 'No connected devices',
      'thisDevice': 'This device',
      'revokeDeviceQuestion': 'Revoke device?',
      'revoke': 'Revoke',
      'deviceRevoked': 'Device revoked',
      'cloudDisclaimer': 'Your username is saved for verification; the server also receives your IP address and PRS ID. Enabling cloud checks for homework and grades sends your eSchool Center username and password to the chosen server. The server stores the password encrypted and can reuse it to sign in without your involvement.',
      'cloudActivated': 'Cloud features activated',
      'cloudNotAvailableDemo':
          'Cloud features are not available on demo account',
      'verifying': 'Verifying...',
      'verificationError': 'Verification error',
      'unknownDevice': 'Unknown device',

      // навигация
      'diary': 'Diary',
      'marks': 'Grades',
      'assignments': 'Homework',
      'chats': 'Chats',
      'more': 'More',

      // экран «ещё»
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

      // дневник
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

      // оценки
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
      'analyticsViewTitle': 'Analytics',
      'analyticsSelectSubject': 'Select subject',
      'analyticsChartTitle': 'Chart',
      'analyticsClassLabel': 'Class',
      'analyticsStudentLabel': 'Student',
      'analyticsClassAvgYear': 'Class avg (year)',
      'analyticsStudentAvgYear': 'Student avg (year)',
      'analyticsByTopicTitle': 'By date/topic',
      'analyticsNoData': 'No data',
      'analyticsNoDataHint': 'Try another subject or refresh',
      'analyticsNoSubjectTitle': 'Select a subject',
      'analyticsNoSubjectSubtitle': 'To show the chart and averages',
      'analyticsLessonsCount': '{count} lessons',

      // профиль
      'profileTitle': 'Profile',
      'profileFamily': 'Family',
      'profileEducation': 'Education',
      'profileEducationReady': 'Data ready',
      'loadingProfile': 'Loading profile...',
      'infoCaps': 'INFORMATION',
      'familyCaps': 'FAMILY',
      'relative': 'Relative',
      'educationCaps': 'EDUCATION',
      'birthday': 'Birthday',
      'phone': 'Phone',
      'gender': 'Gender',
      'male': 'Male',
      'female': 'Female',

      // задания
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

      // чаты
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

      // карточка урока
      'lessonEnd': 'Lesson ends in:',
      'homeworkWithFiles': 'HW + {count} file',
      'homeworkLabel': 'Homework',
      'lessonHeader': 'Lesson {num} • {start} - {end}',
      'lessonTeacher': 'Teacher',
      'lessonTopic': 'Lesson topic',
      'markLabel': 'Grade',
      'markWeight': 'Weight: {weight}',
      'homeworkCaps': 'HOMEWORK',
      'filesCount': '{count} file(s)',

      // карточка перемены
      'breakDuration': 'Break {duration} min',
      'breakLabel': 'Break:',

      // своё домашнее задание
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

      // уведомления
      'notifications': 'Notifications',
      'notificationsSubtitle': 'Diary change history',

      // для разработчика
      'developer': 'Developer',
      'developerMode': 'Developer mode',
      'developerModeEnabled': 'Developer mode enabled',
      'developerTools': 'Developer tools',

      // промо облака

      // политика конфиденциальности
      'privacyPolicy': 'Privacy Policy',
      'privacyGeneral': 'General',
      'privacyGeneralText': 'reSchool is an unofficial eSchool Center client and is not affiliated with the diary provider. The project has no shared official server for storing diaries or processing cloud accounts. The app retrieves core school data from eSchool Center. For cloud features, you choose and connect your own server or one run by another administrator. The app developer does not automatically receive access to it. This policy describes this version; the selected server administrator separately determines how data is processed on that server.',
      'privacyDataCollected': 'Data processed',
      'privacyDataCollectedText': 'The device processes eSchool credentials and sessions, profile, timetable, homework, grades, conversations, attachments, settings and local cache.\n\nDepending on enabled features, your selected server receives:\n• Name, PRS ID, class and device name\n• IP address and technical request information\n• eSchool username and password for background monitoring\n• Diary data, messages, assignments, uploaded files and analysis results\n• Access settings, Telegram user, chat and topic IDs and, when configuring a bot, its token.\n\nThe password is a reusable eSchool credential, not a one-time code. The app does not obtain push tokens and the server does not use them.',
      'privacyPurpose': 'Purpose of Processing',
      'privacyPurposeText': 'Data is used to sign in, display school information and conversations, verify access, support connected devices, shared homework and files, monitor changes, keep notification history and deliver messages to Telegram. Assignment analysis and export process data when those features are used.',
      'privacyStorage': 'Data Storage',
      'privacyStorageText': 'Settings and cache are stored on the device. Saved eSchool credentials use platform secure storage. Some cloud access tokens and Telegram settings are stored in ordinary app preferences without additional encryption.\n\nCloud data is stored by the selected server administrator in its database, file storage, cache and backups. The eSchool password is encrypted on the server, but the server can decrypt it for sign-in; this is not end-to-end encryption against the administrator. The administrator determines storage location, retention, logs, backups and access. Ask about these before connecting.',
      'privacyThirdParty': 'Services and recipients',
      'privacyThirdPartyText': '• eSchool Center receives requests for sign-in and diary access. A configured web proxy routes requests through your chosen server.\n• Telegram receives notification text and attachments when a bot is connected. Members of the selected chat can read messages.\n• If the administrator enables assignment analysis, the server sends materials to Google Gemini / Vertex AI or through OpenRouter to the selected model provider according to its configuration.\n• Export to Obsidian uploads an encrypted note to kmi.aeza.net and passes the key locally to Obsidian.\n• Update and eSchool client version checks contact GitHub. Font loading may contact Google Fonts. Opening external links contacts the respective website. These services receive technical request data, including IP addresses.\n\nThis version does not deliver push through Firebase or a developer intermediary. Your selected server does not forward data to the developer for notification delivery. External services have their own terms; disabling cloud features does not disable ordinary eSchool requests or update checks.',
      'privacyRights': 'User Rights',
      'privacyRightsText': 'You can disable monitoring and integrations, revoke device access, clear local data and request deletion of server data. Contact the administrator of the server you connected to for information, corrections, deletion and retention periods.\n\nSigning out or disabling cloud features does not confirm deletion. Check the deletion result; if the server is unavailable, retry or contact its administrator. Telegram copies, exported files, eSchool data and backups may require separate deletion with the respective recipient. The developer cannot delete data from someone else’s server without access.',
      'privacyDisclaimer': 'Roles and contact',
      'privacyDisclaimerText': 'The developer maintains the app and publishes its source code. The selected server administrator manages its operation, access, integrations and data processing. This policy does not replace information about that administrator or their terms. Use a server whose owner and settings you know.\n\nReport app issues through the project links in About; do not send passwords, tokens or other people’s data. Rights and obligations under applicable law remain in effect.',
      'privacyChanges': 'Policy Changes',
      'privacyChangesText': 'The current policy is available in About. Data processing descriptions are updated with the app when features change. The revision date is shown below. Policy changes do not replace separate consent where required. Ask the administrator about the terms of a particular server.',
      'privacyLastUpdated': 'Last updated: September 11, 2026',

      // удаление данных
      'deleteAllData': 'Delete data',
      'deleteAllDataSubtitle': 'Delete all data from server',
      'deleteDataConfirmTitle': 'Delete all data?',
      'deleteDataConfirmText': 'A request to delete server data will be made. The remote request may fail, so deletion of all data is not guaranteed. Successful deletion is irreversible. You will also be logged out; signing out alone does not confirm deletion of server data.',
      'deleteDataSuccess': 'Data deleted',
      'deleteDataError': 'Error deleting data',

      // облачные функции
      'cloudFunctions': 'Cloud Functions',
      'cloudFunctions3': 'Cloud Functions',
      'cloudFunctions3Desc': 'Diary monitoring and Telegram notifications',
      'serverSettings': 'Server settings',
      'useReSchoolServer': 'Connect a server',
      'useCustomServer': 'Use custom server',
      'serverUrl': 'Server URL or domain',
      'serverUrlHint': 'school.example.com',
      'reSchoolServerDefault': 'No server selected',
      'iosHttpWarning': 'HTTP connections are not allowed on iOS. Use HTTPS.',
      'invalidServerUrl': 'Invalid server URL',
      'checkInterval': 'Check interval',
      'checkIntervalMinutes': 'Every {minutes} minutes',
      'minutes': 'min',
      'minIntervalWarning': 'Minimum interval: 10 minutes',
      'cf3CredentialsWarning': 'Warning: your account login and password will be sent to the server when enabled.',
      'cf3Description': 'Your selected server checks homework, grades and messages, keeps history and delivers notifications to connected Telegram chats.',
      'configure': 'Configure',
      'enabled': 'Enabled',
      'disabled': 'Disabled',

      // история уведомлений
      'notificationHistory': 'Notification History',
      'noNotifications': 'No notifications',
      'noNotificationsDesc': 'Notifications about new homework, grades and messages will appear here',
      'cf3NotEnabled': 'Notifications not enabled',
      'cf3NotEnabledDesc':
          'Connect your server and enable monitoring in cloud settings',
      'connectionError': 'Connection error',
      'checkInternet': 'Check your internet connection',
      'tryAgainLater': 'Try again later',
      'loadMore': 'Load more',

      // безопасность и пин код
      'security': 'Security',
      'pinCode': 'Passcode',
      'pinCodeSubtitle': 'App entry protection',
      'pinCodeEnabled': 'Passcode is set',
      'pinCodeDisabled': 'Not set',
      'changePin': 'Change passcode',
      'disablePin': 'Disable passcode',
      'disablePinQuestion': 'Disable passcode?',
      'disablePinWarning': 'App entry protection will be removed',
      'disable': 'Disable',
      'biometrics': 'Biometrics',
      'biometricsSubtitle': 'Face ID / Touch ID instead of passcode',
      'pinRequiredFirst': 'Set a passcode first',
    },
  };

  String get employeeDirectory =>
      _localizedValues[locale.languageCode]!['employeeDirectory']!;
  String get employeeDirectoryHint =>
      _localizedValues[locale.languageCode]!['employeeDirectoryHint']!;
  String get directorySearch =>
      _localizedValues[locale.languageCode]!['directorySearch']!;
  String get directoryEmpty =>
      _localizedValues[locale.languageCode]!['directoryEmpty']!;
  String get directoryLoadError =>
      _localizedValues[locale.languageCode]!['directoryLoadError']!;
  String get directoryRoot =>
      _localizedValues[locale.languageCode]!['directoryRoot']!;
  String get directoryNoResults =>
      _localizedValues[locale.languageCode]!['directoryNoResults']!;
  String get startChat => _localizedValues[locale.languageCode]!['startChat']!;
  String get chatOpenError =>
      _localizedValues[locale.languageCode]!['chatOpenError']!;
  String get searchMessages =>
      _localizedValues[locale.languageCode]!['searchMessages']!;
  String get searchMessagesHint =>
      _localizedValues[locale.languageCode]!['searchMessagesHint']!;
  String get searchNoResults =>
      _localizedValues[locale.languageCode]!['searchNoResults']!;
  String get searchMessagesError =>
      _localizedValues[locale.languageCode]!['searchMessagesError']!;
  String get olderMessages =>
      _localizedValues[locale.languageCode]!['olderMessages']!;
  String get chatLoadError =>
      _localizedValues[locale.languageCode]!['chatLoadError']!;
  String get chatMoreError =>
      _localizedValues[locale.languageCode]!['chatMoreError']!;
  String get chatAttachments =>
      _localizedValues[locale.languageCode]!['chatAttachments']!;
  String get chatPhotos =>
      _localizedValues[locale.languageCode]!['chatPhotos']!;
  String get chatDocuments =>
      _localizedValues[locale.languageCode]!['chatDocuments']!;
  String get chatMediaEmpty =>
      _localizedValues[locale.languageCode]!['chatMediaEmpty']!;
  String get chatMediaError =>
      _localizedValues[locale.languageCode]!['chatMediaError']!;
  String get chatMediaNoMatches =>
      _localizedValues[locale.languageCode]!['chatMediaNoMatches']!;
  String get chatFileSearch =>
      _localizedValues[locale.languageCode]!['chatFileSearch']!;
  String get editMessage =>
      _localizedValues[locale.languageCode]!['editMessage']!;
  String get deleteMessage =>
      _localizedValues[locale.languageCode]!['deleteMessage']!;
  String get deleteMessageWarning =>
      _localizedValues[locale.languageCode]!['deleteMessageWarning']!;
  String get messageEditError =>
      _localizedValues[locale.languageCode]!['messageEditError']!;
  String get messageDeleteError =>
      _localizedValues[locale.languageCode]!['messageDeleteError']!;
  String get messageEdited =>
      _localizedValues[locale.languageCode]!['messageEdited']!;
  String get chatPermissionsError =>
      _localizedValues[locale.languageCode]!['chatPermissionsError']!;
  String get messageCopy =>
      _localizedValues[locale.languageCode]!['messageCopy']!;
  String get sendMessageError =>
      _localizedValues[locale.languageCode]!['sendMessageError']!;
  String get refreshContent =>
      _localizedValues[locale.languageCode]!['refreshContent']!;
  String get imageLoadError =>
      _localizedValues[locale.languageCode]!['imageLoadError']!;
  String get openImage => _localizedValues[locale.languageCode]!['openImage']!;
  String get linkOpenError =>
      _localizedValues[locale.languageCode]!['linkOpenError']!;
  String get fileOpenError =>
      _localizedValues[locale.languageCode]!['fileOpenError']!;
  String get downloadFileError =>
      _localizedValues[locale.languageCode]!['downloadFileError']!;
  String get fileActionOpen =>
      _localizedValues[locale.languageCode]!['fileActionOpen']!;
  String get fileActionShare =>
      _localizedValues[locale.languageCode]!['fileActionShare']!;
  String get searchExit =>
      _localizedValues[locale.languageCode]!['searchExit']!;
  String get previousMatch =>
      _localizedValues[locale.languageCode]!['previousMatch']!;
  String get nextMatch => _localizedValues[locale.languageCode]!['nextMatch']!;
  String get chatReadOnly =>
      _localizedValues[locale.languageCode]!['chatReadOnly']!;

  String get cancel => _localizedValues[locale.languageCode]!['cancel']!;
  String get save => _localizedValues[locale.languageCode]!['save']!;
  String get close => _localizedValues[locale.languageCode]!['close']!;
  String get error => _localizedValues[locale.languageCode]!['error']!;
  String get continueText =>
      _localizedValues[locale.languageCode]!['continueText']!;
  String get version => _localizedValues[locale.languageCode]!['version']!;
  String get language => _localizedValues[locale.languageCode]!['language']!;
  String get selectLanguage =>
      _localizedValues[locale.languageCode]!['selectLanguage']!;

  String get loginTitle =>
      _localizedValues[locale.languageCode]!['loginTitle']!;
  String get loginSubtitle =>
      _localizedValues[locale.languageCode]!['loginSubtitle']!;
  String get enterCredentials =>
      _localizedValues[locale.languageCode]!['enterCredentials']!;
  String get invalidCredentials =>
      _localizedValues[locale.languageCode]!['invalidCredentials']!;
  String loginFailureMessage(LoginFailure? failure) {
    final values = _localizedValues[locale.languageCode]!;
    final key = switch (failure?.kind) {
      LoginFailureKind.timeout => 'loginTimeout',
      LoginFailureKind.network => 'loginNetworkError',
      LoginFailureKind.invalidResponse => 'loginInvalidResponse',
      LoginFailureKind.http => switch (failure!.statusCode) {
        401 when failure.source == LoginFailureSource.login =>
          'invalidCredentials',
        403 => 'loginForbidden',
        429 => 'loginRateLimited',
        final status? when status >= 500 => 'loginServerError',
        _ => 'loginFailed',
      },
      _ => 'loginFailed',
    };
    final source = switch (failure?.source) {
      LoginFailureSource.state => values['loginStateError'],
      LoginFailureSource.proxy => values['loginProxyError'],
      _ => null,
    };
    return [
      if (source != null) source,
      values[key]!,
      if (failure?.statusCode != null) 'HTTP ${failure!.statusCode}',
      if (failure?.serverCode != null)
        "${values['loginErrorCode']}: ${failure!.serverCode}",
      if (failure?.serverMessage != null) failure!.serverMessage!,
    ].join('\n');
  }

  String get electronicDiary =>
      _localizedValues[locale.languageCode]!['electronicDiary']!;
  String get scheduleTitle =>
      _localizedValues[locale.languageCode]!['scheduleTitle']!;
  String get gradesTitle =>
      _localizedValues[locale.languageCode]!['gradesTitle']!;
  String get username => _localizedValues[locale.languageCode]!['username']!;
  String get password => _localizedValues[locale.languageCode]!['password']!;
  String get rememberMe =>
      _localizedValues[locale.languageCode]!['rememberMe']!;
  String get login => _localizedValues[locale.languageCode]!['login']!;
  String get acceptTermsPrefix =>
      _localizedValues[locale.languageCode]!['acceptTermsPrefix']!;
  String get acceptTermsSuffix =>
      _localizedValues[locale.languageCode]!['acceptTermsSuffix']!;
  String get legalTermsSubtitle =>
      _localizedValues[locale.languageCode]!['legalTermsSubtitle']!;
  String get legalPrivacySubtitle =>
      _localizedValues[locale.languageCode]!['legalPrivacySubtitle']!;
  String get termsOfUse =>
      _localizedValues[locale.languageCode]!['termsOfUse']!;
  String get termsOfUseText =>
      _localizedValues[locale.languageCode]!['termsOfUseText']!;
  String get unofficialAppDisclaimer =>
      _localizedValues[locale.languageCode]!['unofficialAppDisclaimer']!;
  String get acceptTermsRequired =>
      _localizedValues[locale.languageCode]!['acceptTermsRequired']!;

  String get settings => _localizedValues[locale.languageCode]!['settings']!;
  String get general => _localizedValues[locale.languageCode]!['general']!;
  String get onlyCurrentYear =>
      _localizedValues[locale.languageCode]!['onlyCurrentYear']!;
  String get hideOldDiaries =>
      _localizedValues[locale.languageCode]!['hideOldDiaries']!;
  String get cloudFeatures =>
      _localizedValues[locale.languageCode]!['cloudFeatures']!;
  String get verificationRequired =>
      _localizedValues[locale.languageCode]!['verificationRequired']!;
  String get devices => _localizedValues[locale.languageCode]!['devices']!;
  String get manageConnections =>
      _localizedValues[locale.languageCode]!['manageConnections']!;
  String get homework => _localizedValues[locale.languageCode]!['homework']!;
  String get daysInPast =>
      _localizedValues[locale.languageCode]!['daysInPast']!;
  String get numberOfDays =>
      _localizedValues[locale.languageCode]!['numberOfDays']!;
  String get daysInFuture =>
      _localizedValues[locale.languageCode]!['daysInFuture']!;
  String get appearance =>
      _localizedValues[locale.languageCode]!['appearance']!;
  String get light => _localizedValues[locale.languageCode]!['light']!;
  String get dark => _localizedValues[locale.languageCode]!['dark']!;
  String get auto => _localizedValues[locale.languageCode]!['auto']!;
  String get emulation => _localizedValues[locale.languageCode]!['emulation']!;
  String get usedForLogin =>
      _localizedValues[locale.languageCode]!['usedForLogin']!;
  String get widgets => _localizedValues[locale.languageCode]!['widgets']!;
  String get schedule => _localizedValues[locale.languageCode]!['schedule']!;
  String get lessonsForToday =>
      _localizedValues[locale.languageCode]!['lessonsForToday']!;
  String get showTeacher =>
      _localizedValues[locale.languageCode]!['showTeacher']!;
  String get upcomingAssignments =>
      _localizedValues[locale.languageCode]!['upcomingAssignments']!;
  String get count => _localizedValues[locale.languageCode]!['count']!;
  String get showDeadline =>
      _localizedValues[locale.languageCode]!['showDeadline']!;
  String get grades => _localizedValues[locale.languageCode]!['grades']!;
  String get averageScores =>
      _localizedValues[locale.languageCode]!['averageScores']!;
  String get subjects => _localizedValues[locale.languageCode]!['subjects']!;
  String get updateWidgets =>
      _localizedValues[locale.languageCode]!['updateWidgets']!;
  String get syncNow => _localizedValues[locale.languageCode]!['syncNow']!;
  String get widgetsUpdated =>
      _localizedValues[locale.languageCode]!['widgetsUpdated']!;
  String get aboutApp => _localizedValues[locale.languageCode]!['aboutApp']!;

  // обновления
  String get checkForUpdates =>
      _localizedValues[locale.languageCode]!['checkForUpdates']!;
  String get checkingForUpdates =>
      _localizedValues[locale.languageCode]!['checkingForUpdates']!;
  String get updateAvailable =>
      _localizedValues[locale.languageCode]!['updateAvailable']!;
  String updateAvailableMessage(String version) =>
      _localizedValues[locale.languageCode]!['updateAvailableMessage']!
          .replaceAll('{version}', version);
  String updateAvailableTestFlight(String version) =>
      _localizedValues[locale.languageCode]!['updateAvailableTestFlight']!
          .replaceAll('{version}', version);
  String updatePendingReview(String version) =>
      _localizedValues[locale.languageCode]!['updatePendingReview']!.replaceAll(
        '{version}',
        version,
      );
  String get openTestFlight =>
      _localizedValues[locale.languageCode]!['openTestFlight']!;
  String get noUpdatesAvailable =>
      _localizedValues[locale.languageCode]!['noUpdatesAvailable']!;
  String get updateNow => _localizedValues[locale.languageCode]!['updateNow']!;
  String get skipUpdate =>
      _localizedValues[locale.languageCode]!['skipUpdate']!;
  String get later => _localizedValues[locale.languageCode]!['later']!;
  String get downloading =>
      _localizedValues[locale.languageCode]!['downloading']!;
  String get downloadingUpdate =>
      _localizedValues[locale.languageCode]!['downloadingUpdate']!;
  String get pleaseWait =>
      _localizedValues[locale.languageCode]!['pleaseWait']!;
  String get updateError =>
      _localizedValues[locale.languageCode]!['updateError']!;
  String get whatsNew => _localizedValues[locale.languageCode]!['whatsNew']!;
  String get currentVersion =>
      _localizedValues[locale.languageCode]!['currentVersion']!;

  String get tokenInvalid =>
      _localizedValues[locale.languageCode]!['tokenInvalid']!;
  String get connectedDevices =>
      _localizedValues[locale.languageCode]!['connectedDevices']!;
  String get noConnectedDevices =>
      _localizedValues[locale.languageCode]!['noConnectedDevices']!;
  String get thisDevice =>
      _localizedValues[locale.languageCode]!['thisDevice']!;
  String get revokeDeviceQuestion =>
      _localizedValues[locale.languageCode]!['revokeDeviceQuestion']!;
  String get revoke => _localizedValues[locale.languageCode]!['revoke']!;
  String get deviceRevoked =>
      _localizedValues[locale.languageCode]!['deviceRevoked']!;
  String get cloudDisclaimer =>
      _localizedValues[locale.languageCode]!['cloudDisclaimer']!;
  String get cloudActivated =>
      _localizedValues[locale.languageCode]!['cloudActivated']!;
  String get cloudNotAvailableDemo =>
      _localizedValues[locale.languageCode]!['cloudNotAvailableDemo']!;
  String get verifying => _localizedValues[locale.languageCode]!['verifying']!;
  String get verificationError =>
      _localizedValues[locale.languageCode]!['verificationError']!;
  String get unknownDevice =>
      _localizedValues[locale.languageCode]!['unknownDevice']!;

  // навигация
  String get diary => _localizedValues[locale.languageCode]!['diary']!;
  String get marks => _localizedValues[locale.languageCode]!['marks']!;
  String get assignments =>
      _localizedValues[locale.languageCode]!['assignments']!;
  String get chats => _localizedValues[locale.languageCode]!['chats']!;
  String get more => _localizedValues[locale.languageCode]!['more']!;

  // экран «ещё»
  String get info => _localizedValues[locale.languageCode]!['info']!;
  String get help => _localizedValues[locale.languageCode]!['help']!;
  String get soon => _localizedValues[locale.languageCode]!['soon']!;
  String get logoutQuestion =>
      _localizedValues[locale.languageCode]!['logoutQuestion']!;
  String get logoutWarning =>
      _localizedValues[locale.languageCode]!['logoutWarning']!;
  String get logout => _localizedValues[locale.languageCode]!['logout']!;
  String get selectTheme =>
      _localizedValues[locale.languageCode]!['selectTheme']!;
  String get theme => _localizedValues[locale.languageCode]!['theme']!;
  String get calls => _localizedValues[locale.languageCode]!['calls']!;
  String get gradingSystem =>
      _localizedValues[locale.languageCode]!['gradingSystem']!;
  String get gradingPresetSelect =>
      _localizedValues[locale.languageCode]!['gradingPresetSelect']!;
  String get predictedGrade =>
      _localizedValues[locale.languageCode]!['predictedGrade']!;
  String get showQuarterGrade =>
      _localizedValues[locale.languageCode]!['showQuarterGrade']!;

  // дневник
  String get loading => _localizedValues[locale.languageCode]!['loading']!;
  String get noLessons => _localizedValues[locale.languageCode]!['noLessons']!;
  String get noLessonsScheduled =>
      _localizedValues[locale.languageCode]!['noLessonsScheduled']!;
  String get loadingError =>
      _localizedValues[locale.languageCode]!['loadingError']!;
  String get retry => _localizedValues[locale.languageCode]!['retry']!;
  String get today => _localizedValues[locale.languageCode]!['today']!;
  String get yesterday => _localizedValues[locale.languageCode]!['yesterday']!;
  String get tomorrow => _localizedValues[locale.languageCode]!['tomorrow']!;
  String get weekSchedule =>
      _localizedValues[locale.languageCode]!['weekSchedule']!;
  String lessonsCount(int count) =>
      _localizedValues[locale.languageCode]!['lessonsCount']!.replaceAll(
        '{count}',
        count.toString(),
      );
  String get selectedDay =>
      _localizedValues[locale.languageCode]!['selectedDay']!;

  // оценки
  String get loadingMarks =>
      _localizedValues[locale.languageCode]!['loadingMarks']!;
  String get period => _localizedValues[locale.languageCode]!['period']!;
  String get selectPeriod =>
      _localizedValues[locale.languageCode]!['selectPeriod']!;
  String get updateMarks =>
      _localizedValues[locale.languageCode]!['updateMarks']!;
  String get updating => _localizedValues[locale.languageCode]!['updating']!;
  String get noMarks => _localizedValues[locale.languageCode]!['noMarks']!;
  String get noMarksInPeriod =>
      _localizedValues[locale.languageCode]!['noMarksInPeriod']!;
  String get teacher => _localizedValues[locale.languageCode]!['teacher']!;
  String get rating => _localizedValues[locale.languageCode]!['rating']!;
  String get noData => _localizedValues[locale.languageCode]!['noData']!;
  String get finalMark => _localizedValues[locale.languageCode]!['finalMark']!;
  String get prediction =>
      _localizedValues[locale.languageCode]!['prediction']!;
  String get modifiedAverage =>
      _localizedValues[locale.languageCode]!['modifiedAverage']!;
  String get calculatedAverage =>
      _localizedValues[locale.languageCode]!['calculatedAverage']!;
  String get averageScoreApi =>
      _localizedValues[locale.languageCode]!['averageScoreApi']!;
  String get editMark => _localizedValues[locale.languageCode]!['editMark']!;
  String get replaceWithAnother =>
      _localizedValues[locale.languageCode]!['replaceWithAnother']!;
  String get excludeFromCalc =>
      _localizedValues[locale.languageCode]!['excludeFromCalc']!;
  String get markNotCounted =>
      _localizedValues[locale.languageCode]!['markNotCounted']!;
  String get markExcluded =>
      _localizedValues[locale.languageCode]!['markExcluded']!;
  String get resetChanges =>
      _localizedValues[locale.languageCode]!['resetChanges']!;
  String get edit => _localizedValues[locale.languageCode]!['edit']!;
  String get addMark => _localizedValues[locale.languageCode]!['addMark']!;
  String get markCaps => _localizedValues[locale.languageCode]!['markCaps']!;
  String get markWeightCaps =>
      _localizedValues[locale.languageCode]!['markWeightCaps']!;
  String get other => _localizedValues[locale.languageCode]!['other']!;
  String get add => _localizedValues[locale.languageCode]!['add']!;
  String markExcludedMessage(String mark) =>
      _localizedValues[locale.languageCode]!['markExcludedMessage']!.replaceAll(
        '{mark}',
        mark,
      );
  String get averageScore =>
      _localizedValues[locale.languageCode]!['averageScore']!;
  String get allMarks => _localizedValues[locale.languageCode]!['allMarks']!;
  String get marksCount =>
      _localizedValues[locale.languageCode]!['marksCount']!;
  String get virtualMarks =>
      _localizedValues[locale.languageCode]!['virtualMarks']!;
  String get analyticsViewTitle =>
      _localizedValues[locale.languageCode]!['analyticsViewTitle']!;
  String get analyticsSelectSubject =>
      _localizedValues[locale.languageCode]!['analyticsSelectSubject']!;
  String get analyticsChartTitle =>
      _localizedValues[locale.languageCode]!['analyticsChartTitle']!;
  String get analyticsClassLabel =>
      _localizedValues[locale.languageCode]!['analyticsClassLabel']!;
  String get analyticsStudentLabel =>
      _localizedValues[locale.languageCode]!['analyticsStudentLabel']!;
  String get analyticsClassAvgYear =>
      _localizedValues[locale.languageCode]!['analyticsClassAvgYear']!;
  String get analyticsStudentAvgYear =>
      _localizedValues[locale.languageCode]!['analyticsStudentAvgYear']!;
  String get analyticsByTopicTitle =>
      _localizedValues[locale.languageCode]!['analyticsByTopicTitle']!;
  String get analyticsNoData =>
      _localizedValues[locale.languageCode]!['analyticsNoData']!;
  String get analyticsNoDataHint =>
      _localizedValues[locale.languageCode]!['analyticsNoDataHint']!;
  String get analyticsNoSubjectTitle =>
      _localizedValues[locale.languageCode]!['analyticsNoSubjectTitle']!;
  String get analyticsNoSubjectSubtitle =>
      _localizedValues[locale.languageCode]!['analyticsNoSubjectSubtitle']!;
  String analyticsLessonsCount(int count) =>
      _localizedValues[locale.languageCode]!['analyticsLessonsCount']!
          .replaceAll('{count}', count.toString());

  // профиль
  String get profileTitle =>
      _localizedValues[locale.languageCode]!['profileTitle']!;
  String get profileFamily =>
      _localizedValues[locale.languageCode]!['profileFamily']!;
  String get profileEducation =>
      _localizedValues[locale.languageCode]!['profileEducation']!;
  String get profileEducationReady =>
      _localizedValues[locale.languageCode]!['profileEducationReady']!;
  String get loadingProfile =>
      _localizedValues[locale.languageCode]!['loadingProfile']!;
  String get infoCaps => _localizedValues[locale.languageCode]!['infoCaps']!;
  String get familyCaps =>
      _localizedValues[locale.languageCode]!['familyCaps']!;
  String get relative => _localizedValues[locale.languageCode]!['relative']!;
  String get educationCaps =>
      _localizedValues[locale.languageCode]!['educationCaps']!;
  String get birthday => _localizedValues[locale.languageCode]!['birthday']!;
  String get phone => _localizedValues[locale.languageCode]!['phone']!;
  String get gender => _localizedValues[locale.languageCode]!['gender']!;
  String get male => _localizedValues[locale.languageCode]!['male']!;
  String get female => _localizedValues[locale.languageCode]!['female']!;

  // задания
  String get homeworkTitle =>
      _localizedValues[locale.languageCode]!['homeworkTitle']!;
  String get start => _localizedValues[locale.languageCode]!['start']!;
  String get end => _localizedValues[locale.languageCode]!['end']!;
  String get apply => _localizedValues[locale.languageCode]!['apply']!;
  String get week => _localizedValues[locale.languageCode]!['week']!;
  String get month => _localizedValues[locale.languageCode]!['month']!;
  String get threeMonths =>
      _localizedValues[locale.languageCode]!['threeMonths']!;
  String get loadingAssignments =>
      _localizedValues[locale.languageCode]!['loadingAssignments']!;
  String get noAssignments =>
      _localizedValues[locale.languageCode]!['noAssignments']!;
  String get noAssignmentsInPeriod =>
      _localizedValues[locale.languageCode]!['noAssignmentsInPeriod']!;
  String get overdue => _localizedValues[locale.languageCode]!['overdue']!;
  String get until => _localizedValues[locale.languageCode]!['until']!;
  String get attachment1 =>
      _localizedValues[locale.languageCode]!['attachment1']!;
  String get attachment24 =>
      _localizedValues[locale.languageCode]!['attachment24']!;
  String get attachment5 =>
      _localizedValues[locale.languageCode]!['attachment5']!;
  String get byDates => _localizedValues[locale.languageCode]!['byDates']!;
  String get allAssignments =>
      _localizedValues[locale.languageCode]!['allAssignments']!;
  String tasksTotal(int count) =>
      _localizedValues[locale.languageCode]!['tasksTotal']!.replaceAll(
        '{count}',
        count.toString(),
      );
  String get tasksLabel =>
      _localizedValues[locale.languageCode]!['tasksLabel']!;
  String get all => _localizedValues[locale.languageCode]!['all']!;
  String get showAll => _localizedValues[locale.languageCode]!['showAll']!;

  // чаты
  String get messages => _localizedValues[locale.languageCode]!['messages']!;
  String get chatsAndDialogs =>
      _localizedValues[locale.languageCode]!['chatsAndDialogs']!;
  String get searchPlaceholder =>
      _localizedValues[locale.languageCode]!['searchPlaceholder']!;
  String get globalSearchCaps =>
      _localizedValues[locale.languageCode]!['globalSearchCaps']!;
  String get noOneFound =>
      _localizedValues[locale.languageCode]!['noOneFound']!;
  String get foundChatsCaps =>
      _localizedValues[locale.languageCode]!['foundChatsCaps']!;
  String get loadingMessages =>
      _localizedValues[locale.languageCode]!['loadingMessages']!;
  String get noMessages =>
      _localizedValues[locale.languageCode]!['noMessages']!;
  String get startChatting =>
      _localizedValues[locale.languageCode]!['startChatting']!;
  String get newGroup => _localizedValues[locale.languageCode]!['newGroup']!;
  String get create => _localizedValues[locale.languageCode]!['create']!;
  String get groupName => _localizedValues[locale.languageCode]!['groupName']!;
  String get searchParticipants =>
      _localizedValues[locale.languageCode]!['searchParticipants']!;
  String get chat => _localizedValues[locale.languageCode]!['chat']!;
  String get noName => _localizedValues[locale.languageCode]!['noName']!;
  String get selectChat =>
      _localizedValues[locale.languageCode]!['selectChat']!;
  String get selectChatPrompt =>
      _localizedValues[locale.languageCode]!['selectChatPrompt']!;

  // карточка урока
  String get lessonEnd => _localizedValues[locale.languageCode]!['lessonEnd']!;
  String homeworkWithFiles(int count) =>
      _localizedValues[locale.languageCode]!['homeworkWithFiles']!.replaceAll(
        '{count}',
        count.toString(),
      );
  String get homeworkLabel =>
      _localizedValues[locale.languageCode]!['homeworkLabel']!;
  String lessonHeader(int num, String start, String end) =>
      _localizedValues[locale.languageCode]!['lessonHeader']!
          .replaceAll('{num}', num.toString())
          .replaceAll('{start}', start)
          .replaceAll('{end}', end);
  String get lessonTeacher =>
      _localizedValues[locale.languageCode]!['lessonTeacher']!;
  String get lessonTopic =>
      _localizedValues[locale.languageCode]!['lessonTopic']!;
  String get markLabel => _localizedValues[locale.languageCode]!['markLabel']!;
  String markWeight(double weight) =>
      _localizedValues[locale.languageCode]!['markWeight']!.replaceAll(
        '{weight}',
        weight.toStringAsFixed(1),
      );
  String get homeworkCaps =>
      _localizedValues[locale.languageCode]!['homeworkCaps']!;
  String filesCount(int count) =>
      _localizedValues[locale.languageCode]!['filesCount']!.replaceAll(
        '{count}',
        count.toString(),
      );

  // карточка перемены
  String breakDuration(int duration) =>
      _localizedValues[locale.languageCode]!['breakDuration']!.replaceAll(
        '{duration}',
        duration.toString(),
      );
  String get breakLabel =>
      _localizedValues[locale.languageCode]!['breakLabel']!;

  // своё домашнее задание
  String get addCustomHomework =>
      _localizedValues[locale.languageCode]!['addCustomHomework']!;
  String get editCustomHomework =>
      _localizedValues[locale.languageCode]!['editCustomHomework']!;
  String get deleteCustomHomework =>
      _localizedValues[locale.languageCode]!['deleteCustomHomework']!;
  String get customHomework =>
      _localizedValues[locale.languageCode]!['customHomework']!;
  String get customHomeworkFrom =>
      _localizedValues[locale.languageCode]!['customHomeworkFrom']!;
  String get homeworkText =>
      _localizedValues[locale.languageCode]!['homeworkText']!;
  String get homeworkTextHint =>
      _localizedValues[locale.languageCode]!['homeworkTextHint']!;
  String get attachFiles =>
      _localizedValues[locale.languageCode]!['attachFiles']!;
  String maxFilesLimit(int count) =>
      _localizedValues[locale.languageCode]!['maxFilesLimit']!.replaceAll(
        '{count}',
        count.toString(),
      );
  String maxFileSize(int size) =>
      _localizedValues[locale.languageCode]!['maxFileSize']!.replaceAll(
        '{size}',
        size.toString(),
      );
  String get fileTooLarge =>
      _localizedValues[locale.languageCode]!['fileTooLarge']!;
  String get homeworkCreated =>
      _localizedValues[locale.languageCode]!['homeworkCreated']!;
  String get homeworkUpdated =>
      _localizedValues[locale.languageCode]!['homeworkUpdated']!;
  String get homeworkDeleted =>
      _localizedValues[locale.languageCode]!['homeworkDeleted']!;
  String get deleteHomeworkQuestion =>
      _localizedValues[locale.languageCode]!['deleteHomeworkQuestion']!;
  String get deleteHomeworkWarning =>
      _localizedValues[locale.languageCode]!['deleteHomeworkWarning']!;
  String get delete => _localizedValues[locale.languageCode]!['delete']!;
  String get noCustomHomework =>
      _localizedValues[locale.languageCode]!['noCustomHomework']!;
  String get cloudRequiredForHomework =>
      _localizedValues[locale.languageCode]!['cloudRequiredForHomework']!;

  // уведомления
  String get notifications =>
      _localizedValues[locale.languageCode]!['notifications']!;
  String get notificationsSubtitle =>
      _localizedValues[locale.languageCode]!['notificationsSubtitle']!;

  // для разработчика
  String get developer => _localizedValues[locale.languageCode]!['developer']!;
  String get developerMode =>
      _localizedValues[locale.languageCode]!['developerMode']!;
  String get developerModeEnabled =>
      _localizedValues[locale.languageCode]!['developerModeEnabled']!;
  String get developerTools =>
      _localizedValues[locale.languageCode]!['developerTools']!;

  // промо облака

  // политика конфиденциальности
  String get privacyPolicy =>
      _localizedValues[locale.languageCode]!['privacyPolicy']!;
  String get privacyGeneral =>
      _localizedValues[locale.languageCode]!['privacyGeneral']!;
  String get privacyGeneralText =>
      _localizedValues[locale.languageCode]!['privacyGeneralText']!;
  String get privacyDataCollected =>
      _localizedValues[locale.languageCode]!['privacyDataCollected']!;
  String get privacyDataCollectedText =>
      _localizedValues[locale.languageCode]!['privacyDataCollectedText']!;
  String get privacyPurpose =>
      _localizedValues[locale.languageCode]!['privacyPurpose']!;
  String get privacyPurposeText =>
      _localizedValues[locale.languageCode]!['privacyPurposeText']!;
  String get privacyStorage =>
      _localizedValues[locale.languageCode]!['privacyStorage']!;
  String get privacyStorageText =>
      _localizedValues[locale.languageCode]!['privacyStorageText']!;
  String get privacyThirdParty =>
      _localizedValues[locale.languageCode]!['privacyThirdParty']!;
  String get privacyThirdPartyText =>
      _localizedValues[locale.languageCode]!['privacyThirdPartyText']!;
  String get privacyRights =>
      _localizedValues[locale.languageCode]!['privacyRights']!;
  String get privacyRightsText =>
      _localizedValues[locale.languageCode]!['privacyRightsText']!;
  String get privacyDisclaimer =>
      _localizedValues[locale.languageCode]!['privacyDisclaimer']!;
  String get privacyDisclaimerText =>
      _localizedValues[locale.languageCode]!['privacyDisclaimerText']!;
  String get privacyChanges =>
      _localizedValues[locale.languageCode]!['privacyChanges']!;
  String get privacyChangesText =>
      _localizedValues[locale.languageCode]!['privacyChangesText']!;
  String get privacyLastUpdated =>
      _localizedValues[locale.languageCode]!['privacyLastUpdated']!;

  // удаление данных
  String get deleteAllData =>
      _localizedValues[locale.languageCode]!['deleteAllData']!;
  String get deleteAllDataSubtitle =>
      _localizedValues[locale.languageCode]!['deleteAllDataSubtitle']!;
  String get deleteDataConfirmTitle =>
      _localizedValues[locale.languageCode]!['deleteDataConfirmTitle']!;
  String get deleteDataConfirmText =>
      _localizedValues[locale.languageCode]!['deleteDataConfirmText']!;
  String get deleteDataSuccess =>
      _localizedValues[locale.languageCode]!['deleteDataSuccess']!;
  String get deleteDataError =>
      _localizedValues[locale.languageCode]!['deleteDataError']!;

  // облачные функции
  String get cloudFunctions =>
      _localizedValues[locale.languageCode]!['cloudFunctions']!;
  String get cloudFunctions3 =>
      _localizedValues[locale.languageCode]!['cloudFunctions3']!;
  String get cloudFunctions3Desc =>
      _localizedValues[locale.languageCode]!['cloudFunctions3Desc']!;
  String get serverSettings =>
      _localizedValues[locale.languageCode]!['serverSettings']!;
  String get useReSchoolServer =>
      _localizedValues[locale.languageCode]!['useReSchoolServer']!;
  String get useCustomServer =>
      _localizedValues[locale.languageCode]!['useCustomServer']!;
  String get serverUrl => _localizedValues[locale.languageCode]!['serverUrl']!;
  String get serverUrlHint =>
      _localizedValues[locale.languageCode]!['serverUrlHint']!;
  String get reSchoolServerDefault =>
      _localizedValues[locale.languageCode]!['reSchoolServerDefault']!;
  String get iosHttpWarning =>
      _localizedValues[locale.languageCode]!['iosHttpWarning']!;
  String get invalidServerUrl =>
      _localizedValues[locale.languageCode]!['invalidServerUrl']!;
  String get checkInterval =>
      _localizedValues[locale.languageCode]!['checkInterval']!;
  String checkIntervalMinutes(int minutes) =>
      _localizedValues[locale.languageCode]!['checkIntervalMinutes']!
          .replaceAll('{minutes}', minutes.toString());
  String get minutes => _localizedValues[locale.languageCode]!['minutes']!;
  String get minIntervalWarning =>
      _localizedValues[locale.languageCode]!['minIntervalWarning']!;
  String get cf3CredentialsWarning =>
      _localizedValues[locale.languageCode]!['cf3CredentialsWarning']!;
  String get cf3Description =>
      _localizedValues[locale.languageCode]!['cf3Description']!;
  String get configure => _localizedValues[locale.languageCode]!['configure']!;
  String get enabled => _localizedValues[locale.languageCode]!['enabled']!;
  String get disabled => _localizedValues[locale.languageCode]!['disabled']!;

  // история уведомлений
  String get notificationHistory =>
      _localizedValues[locale.languageCode]!['notificationHistory']!;
  String get noNotifications =>
      _localizedValues[locale.languageCode]!['noNotifications']!;
  String get noNotificationsDesc =>
      _localizedValues[locale.languageCode]!['noNotificationsDesc']!;
  String get cf3NotEnabled =>
      _localizedValues[locale.languageCode]!['cf3NotEnabled']!;
  String get cf3NotEnabledDesc =>
      _localizedValues[locale.languageCode]!['cf3NotEnabledDesc']!;
  String get connectionError =>
      _localizedValues[locale.languageCode]!['connectionError']!;
  String get checkInternet =>
      _localizedValues[locale.languageCode]!['checkInternet']!;
  String get tryAgainLater =>
      _localizedValues[locale.languageCode]!['tryAgainLater']!;
  String get loadMore => _localizedValues[locale.languageCode]!['loadMore']!;

  // безопасность и пин код
  String get security => _localizedValues[locale.languageCode]!['security']!;
  String get pinCode => _localizedValues[locale.languageCode]!['pinCode']!;
  String get pinCodeSubtitle =>
      _localizedValues[locale.languageCode]!['pinCodeSubtitle']!;
  String get pinCodeEnabled =>
      _localizedValues[locale.languageCode]!['pinCodeEnabled']!;
  String get pinCodeDisabled =>
      _localizedValues[locale.languageCode]!['pinCodeDisabled']!;
  String get changePin => _localizedValues[locale.languageCode]!['changePin']!;
  String get disablePin =>
      _localizedValues[locale.languageCode]!['disablePin']!;
  String get disablePinQuestion =>
      _localizedValues[locale.languageCode]!['disablePinQuestion']!;
  String get disablePinWarning =>
      _localizedValues[locale.languageCode]!['disablePinWarning']!;
  String get disable => _localizedValues[locale.languageCode]!['disable']!;
  String get biometrics =>
      _localizedValues[locale.languageCode]!['biometrics']!;
  String get biometricsSubtitle =>
      _localizedValues[locale.languageCode]!['biometricsSubtitle']!;
  String get pinRequiredFirst =>
      _localizedValues[locale.languageCode]!['pinRequiredFirst']!;
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
