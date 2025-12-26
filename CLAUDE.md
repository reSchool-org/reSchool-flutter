# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReSchool is a Flutter mobile application that serves as a student information portal integrating with the eSchool Center API (`https://app.eschool.center/ec-server`). It provides access to homework, diary/schedules, grades, and user profiles. The app is localized for Russian language.

## Build & Development Commands

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run                  # Default device/emulator
flutter run -d windows       # Windows desktop
flutter run -d web           # Web browser

# Testing
flutter test                 # Run all tests
flutter test test/widget_test.dart  # Run specific test

# Code quality
flutter analyze              # Static analysis
flutter format lib/          # Format code

# Building
flutter build apk            # Android APK
flutter build appbundle      # Android App Bundle
flutter build windows        # Windows executable
flutter build web            # Web deployment

# Generate app icons
flutter pub run flutter_launcher_icons:main
```

## Architecture

**Pattern:** MVVM with Provider state management

**Layer Structure:**
- `lib/models/` - Data classes with JSON serialization (HomeworkItem, Profile, Lesson, Mark)
- `lib/services/api_service.dart` - Singleton API client handling all eSchool Center HTTP requests
- `lib/providers/` - Global state (ThemeProvider, SettingsProvider) extending ChangeNotifier
- `lib/viewmodels/` - Business logic layer (AssignmentsViewModel, DiaryViewModel, MarksViewModel, ProfileViewModel)
- `lib/screens/` - UI pages consuming ViewModels via Provider.of()
- `lib/widgets/` - Reusable UI components

**State Flow:**
```
Screen → ViewModel (ChangeNotifier) → ApiService → eSchool API
              ↓
       notifyListeners() → UI updates
```

**Entry Point:** `lib/main.dart` sets up MultiProvider with ThemeProvider, SettingsProvider, and AssignmentsViewModel. Initial route is LoginScreen.

## API Integration

ApiService is a singleton with session-based authentication:
- SHA256 password hashing for login
- JSESSIONID cookie management
- Auto-login from SharedPreferences
- Device spoofing using `assets/devices.json` (mimics Android mobile app)

Key endpoints: `/login`, `/student/getPrsDiary`, `/profile/getProfile_new`, `/student/getDiaryUnits`

## Theme & UI

- Material Design 3 (`useMaterial3: true`)
- Primary color: #6A11CB (Purple)
- Google Fonts (Inter)
- Light/Dark theme persistence via SharedPreferences
- Russian locale (`ru`)

## Key Patterns

Providers and ViewModels use ChangeNotifier:
```dart
class MyViewModel extends ChangeNotifier {
  void updateState() {
    notifyListeners();
  }
}
```

Consume state in screens:
```dart
final viewmodel = Provider.of<AssignmentsViewModel>(context);
```

## Dependencies

Core: `flutter`, `provider`, `http`, `shared_preferences`, `google_fonts`, `crypto`

File handling: `path_provider`, `open_filex`, `permission_handler`, `share_plus`

Dev: `flutter_lints`, `flutter_launcher_icons`
