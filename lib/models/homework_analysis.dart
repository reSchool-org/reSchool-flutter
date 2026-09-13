// разбор домашнего задания: сколько займёт, насколько сложно и вырезки из учебника

class AnalysisItem {
  final String label;
  final int difficulty;
  final int minutes;
  final List<String> skills;
  final String note;
  final String? modeConflict;

  const AnalysisItem({
    required this.label,
    required this.difficulty,
    required this.minutes,
    required this.skills,
    required this.note,
    this.modeConflict,
  });

  factory AnalysisItem.fromJson(Map<String, dynamic> json) {
    return AnalysisItem(
      label: json['label'] as String? ?? '',
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 0,
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      skills: (json['skills'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      note: json['note'] as String? ?? '',
      modeConflict: json['mode_conflict'] as String?,
    );
  }
}

class AnalysisImage {
  final int id;
  final String label;
  final String? subitem;
  final String targetType;
  final int? printedPage;
  final String url;

  const AnalysisImage({
    required this.id,
    required this.label,
    this.subitem,
    required this.targetType,
    this.printedPage,
    required this.url,
  });

  factory AnalysisImage.fromJson(Map<String, dynamic> json) {
    return AnalysisImage(
      id: json['id'] as int,
      label: json['label'] as String? ?? '',
      subitem: json['subitem'] as String?,
      targetType: json['targetType'] as String? ?? 'exercise',
      printedPage: (json['printedPage'] as num?)?.toInt(),
      url: json['url'] as String? ?? '',
    );
  }

  String get title {
    final base = targetType == 'paragraph' ? '§ $label' : '№ $label';
    return subitem != null && subitem!.isNotEmpty ? '$base ($subitem)' : base;
  }
}

/// в каком состоянии разбор
enum AnalysisStatus {
  none,
  pending,
  processing,
  done,
  failed,
  rejected;

  static AnalysisStatus parse(String? raw) {
    switch (raw) {
      case 'pending':
        return AnalysisStatus.pending;
      case 'processing':
        return AnalysisStatus.processing;
      case 'done':
        return AnalysisStatus.done;
      case 'failed':
        return AnalysisStatus.failed;
      case 'rejected':
        return AnalysisStatus.rejected;
      default:
        return AnalysisStatus.none;
    }
  }

  bool get isWorking =>
      this == AnalysisStatus.pending || this == AnalysisStatus.processing;
}

class HomeworkAnalysis {
  final int? id;
  final AnalysisStatus status;
  final int? totalMinutes;
  final int? rangeMin;
  final int? rangeMax;
  final String? hardest;
  final String? why;
  final List<AnalysisItem> items;
  final List<AnalysisImage> images;

  /// заполнено, только если добавленное домашнее задание не прошло проверку
  final String? rejectReason;
  final String? rejectDetail;

  /// задание держится на листочке или классной работе, которых у нас нет
  final bool estimable;
  final String? unestimableReason;

  const HomeworkAnalysis({
    this.id,
    required this.status,
    this.totalMinutes,
    this.rangeMin,
    this.rangeMax,
    this.hardest,
    this.why,
    this.items = const [],
    this.images = const [],
    this.rejectReason,
    this.rejectDetail,
    this.estimable = true,
    this.unestimableReason,
  });

  static const HomeworkAnalysis empty =
      HomeworkAnalysis(status: AnalysisStatus.none);

  factory HomeworkAnalysis.fromJson(Map<String, dynamic> json) {
    final range = (json['rangeMinutes'] as List<dynamic>?) ?? const [];
    return HomeworkAnalysis(
      id: (json['analysisId'] as num?)?.toInt(),
      status: AnalysisStatus.parse(json['status'] as String?),
      totalMinutes: (json['totalMinutes'] as num?)?.toInt(),
      rangeMin: range.isNotEmpty ? (range[0] as num?)?.toInt() : null,
      rangeMax: range.length > 1 ? (range[1] as num?)?.toInt() : null,
      hardest: json['hardest'] as String?,
      why: json['why'] as String?,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => AnalysisItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => AnalysisImage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      rejectReason: json['rejectReason'] as String?,
      rejectDetail: json['rejectDetail'] as String?,
      estimable: json['estimable'] as bool? ?? true,
      unestimableReason: json['unestimableReason'] as String?,
    );
  }

  bool get hasEstimate =>
      status == AnalysisStatus.done && estimable && totalMinutes != null;

  /// сервер разобрался, но оценить не смог: не хватает самого материала
  bool get needsMaterial => status == AnalysisStatus.done && !estimable;

  /// самое сложное из заданий, по нему подсвечиваем предупреждение
  AnalysisItem? get hardestItem {
    if (items.isEmpty) return null;
    final sorted = [...items]..sort((a, b) {
        final byDifficulty = b.difficulty.compareTo(a.difficulty);
        return byDifficulty != 0 ? byDifficulty : b.minutes.compareTo(a.minutes);
      });
    return sorted.first;
  }

  String? get firstConflict {
    for (final item in items) {
      final conflict = item.modeConflict;
      if (conflict != null && conflict.trim().isNotEmpty) return conflict;
    }
    return null;
  }

  /// человеческая подпись под оценкой времени
  String get formattedTime {
    final total = totalMinutes;
    if (total == null) return '';
    if (total < 60) return '$total мин';
    final hours = total ~/ 60;
    final minutes = total % 60;
    return minutes == 0 ? '$hours ч' : '$hours ч $minutes мин';
  }
}

/// учебник, загруженный на сервер
class Textbook {
  final int id;
  final String subject;
  final int? grade;
  final String? title;
  final String? authors;
  final String? part;
  final String kind;
  final int pageCount;
  final int indexedPages;
  final String status;
  final String? statusDetail;

  Textbook({
    required this.id,
    required this.subject,
    this.grade,
    this.title,
    this.authors,
    this.part,
    required this.kind,
    required this.pageCount,
    required this.indexedPages,
    required this.status,
    this.statusDetail,
  });

  factory Textbook.fromJson(Map<String, dynamic> json) {
    return Textbook(
      id: json['id'] as int,
      subject: json['subject'] as String? ?? '',
      grade: (json['grade'] as num?)?.toInt(),
      title: json['title'] as String?,
      authors: json['authors'] as String?,
      part: json['part'] as String?,
      kind: json['kind'] as String? ?? 'textbook',
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      indexedPages: (json['indexedPages'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      statusDetail: json['statusDetail'] as String?,
    );
  }

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';
  bool get isWorking => status == 'pending' || status == 'indexing';

  double get progress =>
      pageCount == 0 ? 0 : (indexedPages / pageCount).clamp(0.0, 1.0);

  String get displayTitle {
    final name = (title ?? '').trim();
    return name.isEmpty ? subject : name;
  }

  String get kindLabel {
    switch (kind) {
      case 'workbook':
        return 'Рабочая тетрадь';
      case 'other':
        return 'Пособие';
      default:
        return 'Учебник';
    }
  }
}


/// картинка в сводке: вырезка из учебника или приложенное фото
class SummaryImage {
  final String kind;
  final String label;
  final String? subitem;
  final String? targetType;
  final int? printedPage;
  final String author;
  final String url;

  const SummaryImage({
    required this.kind,
    required this.label,
    this.subitem,
    this.targetType,
    this.printedPage,
    required this.author,
    required this.url,
  });

  factory SummaryImage.fromJson(Map<String, dynamic> json) {
    return SummaryImage(
      kind: json['kind'] as String? ?? 'textbook',
      label: json['label'] as String? ?? '',
      subitem: json['subitem'] as String?,
      targetType: json['targetType'] as String?,
      printedPage: (json['printedPage'] as num?)?.toInt(),
      author: json['author'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  bool get isAttachment => kind == 'attachment';

  String get title {
    if (isAttachment) return label;
    final base = targetType == 'paragraph' ? '§ $label' : '№ $label';
    return subitem != null && subitem!.isNotEmpty ? '$base ($subitem)' : base;
  }

  /// в просмотрщик отдаём тот же вид, что и обычные вырезки
  AnalysisImage toAnalysisImage(int index) => AnalysisImage(
        id: index,
        label: label,
        subitem: subitem,
        targetType: targetType ?? (isAttachment ? 'attachment' : 'exercise'),
        printedPage: printedPage,
        url: url,
      );
}

/// сводка урока: несколько записей на один слот одной карточкой
class HomeworkSummary {
  final int id;
  final String text;
  final List<String> authors;
  final List<String> highlights;
  final int partCount;
  final int? totalMinutes;
  final List<SummaryImage> images;

  const HomeworkSummary({
    required this.id,
    required this.text,
    required this.authors,
    required this.highlights,
    required this.partCount,
    this.totalMinutes,
    required this.images,
  });

  static HomeworkSummary? fromJson(Map<String, dynamic> json) {
    if (json['status'] != 'ready') return null;
    return HomeworkSummary(
      id: (json['summaryId'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      authors: ((json['authors'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      highlights: ((json['highlights'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      partCount: (json['partCount'] as num?)?.toInt() ?? 0,
      totalMinutes: (json['totalMinutes'] as num?)?.toInt(),
      images: ((json['images'] as List<dynamic>?) ?? const [])
          .map((e) => SummaryImage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  String get formattedTime {
    final total = totalMinutes;
    if (total == null) return '';
    if (total < 60) return '$total мин';
    final hours = total ~/ 60;
    final minutes = total % 60;
    return minutes == 0 ? '$hours ч' : '$hours ч $minutes мин';
  }
}
