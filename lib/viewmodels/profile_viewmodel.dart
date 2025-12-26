import 'package:flutter/material.dart';
import '../models/profile_models.dart';
import '../services/api_service.dart';

class ProfileViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();

  ProfileNewResponse? extendedProfile;
  bool isLoading = false;
  String? error;

  Profile? get userProfile => _api.userProfile;
  int? get userId => _api.userId;
  int? get currentPrsId => _api.currentPrsId;
  int? get userImageId => _api.userProfile?.imageId;

  Future<void> loadProfile() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      if (_api.userId == null || _api.currentPrsId == null) {
      }

      if (_api.currentPrsId != null) {
        final json = await _api.getProfileNew(_api.currentPrsId!);
        extendedProfile = ProfileNewResponse.fromJson(json);
      } else {
        error = "Не удалось получить ID пользователя";
      }

    } catch (e) {
      error = e.toString();
      print("Error loading profile: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout(BuildContext context) async {
    await _api.logout();
    if (context.mounted) {
       Navigator.of(context).pushReplacementNamed('/');
    }
  }

  String getFullName() {
    if (extendedProfile?.fio != null) return extendedProfile!.fio!;
    return userProfile?.fullName ?? "Загрузка...";
  }

  String getInitials() {
    final name = getFullName();
    final components = name.trim().split(RegExp(r'\s+'));
    if (components.isNotEmpty) {
      String initials = "";
      if (components.isNotEmpty) initials += components.first[0];
      if (components.length > 1) initials += components.last[0];
      return initials.toUpperCase();
    }
    return "?";
  }
}