import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// правила выведения четвертной оценки
/// каждая оценка задаётся диапазоном [min, max] среднего балла
/// диапазоны соседних оценок могут перекрываться, это пограничная зона,
/// где учитель вправе поставить любую из двух
/// пример (ФМЛ № 30):
/// двойка при a < 2.7
/// 3: 2.5 ≤ a ≤ 3.66   (перекрытие с 2 в [2.5, 2.7), с 4 в [3.5, 3.66])
/// 4: 3.5 ≤ a ≤ 4.66   (перекрытие с 3 в [3.5, 3.66], с 5 в [4.4, 4.66])
/// пятёрка при a ≥ 4.4
class GradingRules {
  /// нижняя граница пятёрки
  final double grade5Min;
  /// нижняя граница четвёрки
  final double grade4Min;
  /// верхняя граница четвёрки, выше уже только пять
  final double grade4Max;
  /// нижняя граница тройки
  final double grade3Min;
  /// верхняя граница тройки, выше уже четыре или пять
  final double grade3Max;
  /// верхняя граница двойки
  final double grade2Max;

  const GradingRules({
    required this.grade5Min,
    required this.grade4Min,
    required this.grade4Max,
    required this.grade3Min,
    required this.grade3Max,
    required this.grade2Max,
  });

  Map<String, dynamic> toJson() => {
        'grade5Min': grade5Min,
        'grade4Min': grade4Min,
        'grade4Max': grade4Max,
        'grade3Min': grade3Min,
        'grade3Max': grade3Max,
        'grade2Max': grade2Max,
      };

  factory GradingRules.fromJson(Map<String, dynamic> j) => GradingRules(
        grade5Min: (j['grade5Min'] as num).toDouble(),
        grade4Min: (j['grade4Min'] as num).toDouble(),
        grade4Max: (j['grade4Max'] as num).toDouble(),
        grade3Min: (j['grade3Min'] as num).toDouble(),
        grade3Max: (j['grade3Max'] as num).toDouble(),
        grade2Max: (j['grade2Max'] as num).toDouble(),
      );

  /// предсказывает четвертную оценку
  /// в пограничной зоне отдаёт две цифры через дефис, иначе одну
  String getPredictedGrade(double average) {
    final List<int> possible = [];
    if (average >= grade5Min) possible.add(5);
    if (average >= grade4Min && average <= grade4Max) possible.add(4);
    if (average >= grade3Min && average <= grade3Max) possible.add(3);
    if (average < grade2Max) possible.add(2);

    if (possible.isEmpty) {
      return average.round().clamp(2, 5).toString();
    }
    possible.sort();
    return possible.length == 1
        ? possible.first.toString()
        : '${possible.first}-${possible.last}';
  }

  /// самая высокая из возможных оценок, по ней красим
  int getPrimaryGrade(double average) {
    if (average >= grade5Min) return 5;
    if (average >= grade4Min) return 4;
    if (average >= grade3Min) return 3;
    return 2;
  }
}

/// пресет системы оценивания
class GradingPreset {
  final String id;
  final String name;
  final String description;
  final GradingRules rules;
  final bool isUserCreated;

  const GradingPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.rules,
    this.isUserCreated = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'rules': rules.toJson(),
        'isUserCreated': isUserCreated,
      };

  factory GradingPreset.fromJson(Map<String, dynamic> j) => GradingPreset(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        rules: GradingRules.fromJson(j['rules'] as Map<String, dynamic>),
        isUserCreated: j['isUserCreated'] as bool? ?? true,
      );
}

class GradingProvider extends ChangeNotifier {
  static const String _presetIdKey = 'grading_preset_id';
  static const String _showPredictedKey = 'show_predicted_grade';
  static const String _userPresetsKey = 'grading_user_presets';

  // встроенные пресеты

  static const List<GradingPreset> availablePresets = [
    GradingPreset(
      id: 'standard',
      name: 'Стандартный',
      description: 'Округление по математическим правилам',
      rules: GradingRules(
        grade5Min: 4.5,
        grade4Min: 3.5,
        grade4Max: 4.49,
        grade3Min: 2.5,
        grade3Max: 3.49,
        grade2Max: 2.5,
      ),
    ),
    GradingPreset(
      id: 'fml30',
      name: 'ФМЛ № 30',
      description: 'Санкт-Петербург',
      rules: GradingRules(
        grade5Min: 4.4,
        grade4Min: 3.5,
        grade4Max: 4.66,
        grade3Min: 2.5,
        grade3Max: 3.66,
        grade2Max: 2.7,
      ),
    ),
  ];

  // состояние

  String _selectedPresetId = 'standard';
  bool _showPredictedGrade = true;
  List<GradingPreset> _userPresets = [];

  String get selectedPresetId => _selectedPresetId;
  bool get showPredictedGrade => _showPredictedGrade;
  List<GradingPreset> get userPresets => List.unmodifiable(_userPresets);
  List<GradingPreset> get allPresets => [...availablePresets, ..._userPresets];

  GradingPreset get selectedPreset => allPresets.firstWhere(
        (p) => p.id == _selectedPresetId,
        orElse: () => availablePresets.first,
      );

  GradingRules get rules => selectedPreset.rules;

  GradingProvider() {
    _load();
  }

  // загрузка и сохранение

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedPresetId = prefs.getString(_presetIdKey) ?? 'standard';
    _showPredictedGrade = prefs.getBool(_showPredictedKey) ?? true;

    final json = prefs.getString(_userPresetsKey);
    if (json != null) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _userPresets = list
            .map((e) => GradingPreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _userPresets = [];
      }
    }
    notifyListeners();
  }

  Future<void> _saveUserPresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _userPresetsKey,
      jsonEncode(_userPresets.map((p) => p.toJson()).toList()),
    );
  }

  // публичные методы

  Future<void> setPreset(String presetId) async {
    _selectedPresetId = presetId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetIdKey, presetId);
  }

  Future<void> setShowPredictedGrade(bool value) async {
    _showPredictedGrade = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showPredictedKey, value);
  }

  Future<GradingPreset> createUserPreset({
    required String name,
    required String description,
    required GradingRules rules,
  }) async {
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final preset = GradingPreset(
      id: id,
      name: name,
      description: description,
      rules: rules,
      isUserCreated: true,
    );
    _userPresets.add(preset);
    notifyListeners();
    await _saveUserPresets();
    return preset;
  }

  Future<void> updateUserPreset({
    required String id,
    required String name,
    required String description,
    required GradingRules rules,
  }) async {
    final idx = _userPresets.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    _userPresets[idx] = GradingPreset(
      id: id,
      name: name,
      description: description,
      rules: rules,
      isUserCreated: true,
    );
    notifyListeners();
    await _saveUserPresets();
  }

  Future<void> deleteUserPreset(String id) async {
    _userPresets.removeWhere((p) => p.id == id);
    if (_selectedPresetId == id) {
      _selectedPresetId = 'standard';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_presetIdKey, 'standard');
    }
    notifyListeners();
    await _saveUserPresets();
  }

  // цвета и мелочи

  Color getAverageColor(double average) => average <= 0
      ? Colors.grey
      : getColorForGrade(rules.getPrimaryGrade(average));

  Color getAverageColorFromString(String avgStr) {
    final avg = double.tryParse(avgStr);
    if (avg == null) return Colors.grey;
    return getAverageColor(avg);
  }

  Color getColorForGrade(int grade) {
    switch (grade) {
      case 5:  return Colors.green;
      case 4:  return Colors.blue;
      case 3:  return Colors.orange;
      default: return Colors.red;
    }
  }

  String getPredictedGrade(String avgStr) {
    final avg = double.tryParse(avgStr);
    if (avg == null) return '-';
    return rules.getPredictedGrade(avg);
  }
}
