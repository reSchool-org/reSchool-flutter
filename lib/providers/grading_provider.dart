import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GradingPreset {
  final String id;
  final String name;
  final String description;
  final GradingRules rules;

  const GradingPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.rules,
  });
}

class GradingRules {
  final double grade5Min;
  final double grade4Min;
  final double grade4Max;
  final double grade3Min;
  final double grade3Max;
  final double grade2Max;

  const GradingRules({
    required this.grade5Min,
    required this.grade4Min,
    required this.grade4Max,
    required this.grade3Min,
    required this.grade3Max,
    required this.grade2Max,
  });

  String getPredictedGrade(double average) {
    List<int> possibleGrades = [];

    if (average >= grade5Min) {
      possibleGrades.add(5);
    }

    if (average >= grade4Min && average <= grade4Max) {
      possibleGrades.add(4);
    }

    if (average >= grade3Min && average <= grade3Max) {
      possibleGrades.add(3);
    }

    if (average < grade2Max) {
      possibleGrades.add(2);
    }

    if (possibleGrades.isEmpty) {
      final rounded = average.round();
      return rounded.clamp(2, 5).toString();
    }

    possibleGrades.sort();

    if (possibleGrades.length == 1) {
      return possibleGrades.first.toString();
    } else {
      return "${possibleGrades.first}-${possibleGrades.last}";
    }
  }

  int getPrimaryGrade(double average) {
    if (average >= grade5Min) return 5;
    if (average >= grade4Min) return 4;
    if (average >= grade3Min) return 3;
    return 2;
  }
}

class GradingProvider extends ChangeNotifier {
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

  String _selectedPresetId = 'standard';
  bool _showPredictedGrade = true;

  String get selectedPresetId => _selectedPresetId;
  bool get showPredictedGrade => _showPredictedGrade;

  GradingPreset get selectedPreset {
    return availablePresets.firstWhere(
      (p) => p.id == _selectedPresetId,
      orElse: () => availablePresets.first,
    );
  }

  GradingRules get rules => selectedPreset.rules;

  GradingProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedPresetId = prefs.getString('grading_preset_id') ?? 'standard';
    _showPredictedGrade = prefs.getBool('show_predicted_grade') ?? true;
    notifyListeners();
  }

  Future<void> setPreset(String presetId) async {
    _selectedPresetId = presetId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('grading_preset_id', presetId);
  }

  Future<void> setShowPredictedGrade(bool value) async {
    _showPredictedGrade = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_predicted_grade', value);
  }

  Color getAverageColor(double average) {
    final grade = rules.getPrimaryGrade(average);
    return getColorForGrade(grade);
  }

  Color getAverageColorFromString(String avgStr) {
    final avg = double.tryParse(avgStr);
    if (avg == null) return Colors.grey;
    return getAverageColor(avg);
  }

  Color getColorForGrade(int grade) {
    switch (grade) {
      case 5:
        return Colors.green;
      case 4:
        return Colors.blue;
      case 3:
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String getPredictedGrade(String avgStr) {
    final avg = double.tryParse(avgStr);
    if (avg == null) return "-";
    return rules.getPredictedGrade(avg);
  }
}