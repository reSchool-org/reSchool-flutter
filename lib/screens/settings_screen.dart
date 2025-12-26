import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/widget_config_provider.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/widget_data_service.dart';
import '../widgets/responsive_layout.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<String> _getRealDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        return "${webInfo.browserName.name} (Web)";
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return "${androidInfo.brand} ${androidInfo.model}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return "${iosInfo.name} (${iosInfo.model})";
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return "${macInfo.computerName} (macOS)";
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        return "${windowsInfo.computerName} (Windows)";
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return "${linuxInfo.prettyName}";
      }
    } catch (e) {
      debugPrint("Error getting device info: $e");
    }
    return "Unknown Device";
  }

  Future<String?> _getCurrentGradeClass() async {
    try {
      final prsId = _api.currentPrsId;
      if (prsId == null) return null;

      final profileData = await _api.getProfileNew(prsId);
      final pupilList = profileData['pupil'] as List<dynamic>?;

      if (pupilList != null && pupilList.isNotEmpty) {
        final latestPupil = pupilList.reduce((a, b) {
          final aYear = a['yearId'] ?? 0;
          final bYear = b['yearId'] ?? 0;
          return aYear > bYear ? a : b;
        });
        return latestPupil['className'] as String?;
      }
    } catch (e) {
      debugPrint("Error getting grade class: $e");
    }
    return null;
  }

  Future<void> _showLanguageDialog(BuildContext context, SettingsProvider settings) async {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.selectLanguage,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text("Русский", style: GoogleFonts.inter()),
              trailing: settings.locale.languageCode == 'ru'
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              onTap: () {
                settings.setLocale(const Locale('ru'));
                Navigator.pop(context);
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            ListTile(
              title: Text("English", style: GoogleFonts.inter()),
              trailing: settings.locale.languageCode == 'en'
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              onTap: () {
                settings.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }

  Future<int?> _showNumberInputDialog(
      BuildContext context, String title, int initialValue) async {
    final controller = TextEditingController(text: initialValue.toString());
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.of(context).viewInsets.bottom > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    onPressed: _dismissKeyboard,
                  ),
                ),
              ),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onEditingComplete: _dismissKeyboard,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 16),
              decoration: InputDecoration(
                labelText: l10n.numberOfDays,
                labelStyle:
                    GoogleFonts.inter(color: colorScheme.onSurface.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: GoogleFonts.inter(color: colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              Navigator.pop(context, value);
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l10n.save, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _logRequest(String method, String url, Map<String, String>? headers, Object? body) {
    debugPrint("\n========== LOCAL SERVER REQUEST ==========");
    debugPrint("URL: $url");
    debugPrint("Method: $method");
    if (headers != null) {
      headers.forEach((key, value) => debugPrint("  $key: $value"));
    }
    if (body != null) {
      debugPrint("Body: $body");
    }
    debugPrint("==========================================\n");
  }

  void _logResponse(http.Response response) {
    debugPrint("\n========== LOCAL SERVER RESPONSE ==========");
    debugPrint("URL: ${response.request?.url}");
    debugPrint("Status Code: ${response.statusCode}");
    if (response.body.isNotEmpty) {
      debugPrint("Response Body: ${response.body}");
    }
    debugPrint("===========================================\n");
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _disableCloudFeatures({bool showSnackbar = true}) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    await settings.setCloudFeaturesEnabled(false);
    await settings.setCloudToken(null);
    await settings.setServerThreadId(null);
    await _api.updateCloudSettings(enabled: false, token: null, threadId: null);
    if (showSnackbar && mounted) {
      _showSnackBar(l10n.tokenInvalid);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _showConnectedDevices() async {
    final token = _api.cloudToken;
    if (token == null) return;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final url = Uri.parse('${AppConfig.cloudFunctionsBaseUrl}/list-devices');
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({'token': token});

      _logRequest("POST", url.toString(), headers, body);
      final response = await http.post(url, headers: headers, body: body);
      _logResponse(response);

      if (!mounted) return;
      Navigator.pop(context);

      if (response.statusCode == 401) {
        await _disableCloudFeatures();
        return;
      }

      if (response.statusCode != 200) {
        _showSnackBar("${l10n.error}: ${response.body}");
        return;
      }

      final data = jsonDecode(response.body);
      final List<dynamic> devices = data['devices'] ?? [];
      final colorScheme = Theme.of(context).colorScheme;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            l10n.connectedDevices,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? Text(
                    l10n.noConnectedDevices,
                    style: GoogleFonts.inter(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final isCurrent = device['isCurrent'] == true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? colorScheme.primary.withValues(alpha: 0.1)
                                : colorScheme.onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.smartphone_rounded,
                            size: 20,
                            color: isCurrent ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        title: Text(
                          device['deviceName'] ?? l10n.unknownDevice,
                          style: GoogleFonts.inter(
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                            color: isCurrent ? colorScheme.primary : colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          isCurrent ? l10n.thisDevice : device['createdAt']?.substring(0, 10) ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        trailing: isCurrent
                            ? null
                            : IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: colorScheme.error,
                                ),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      title: Text(l10n.revokeDeviceQuestion, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                      content: Text("${l10n.revoke} ${device['deviceName']}?", style: GoogleFonts.inter()),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: Text(l10n.cancel, style: GoogleFonts.inter()),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
                                          child: Text(l10n.revoke, style: GoogleFonts.inter()),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await _revokeOtherDevice(device['token']);
                                    if (mounted) Navigator.pop(context);
                                    _showConnectedDevices();
                                  }
                                },
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close, style: GoogleFonts.inter()),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final l10n = AppLocalizations.of(context)!;
        _showSnackBar("${l10n.error}: $e");
      }
    }
  }

  Future<void> _revokeOtherDevice(String deviceToken) async {
    try {
      final url = Uri.parse('${AppConfig.cloudFunctionsBaseUrl}/revoke-token');
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({'token': deviceToken});

      _logRequest("POST", url.toString(), headers, body);
      final response = await http.post(url, headers: headers, body: body);
      _logResponse(response);

      if (mounted && response.statusCode == 200) {
        final l10n = AppLocalizations.of(context)!;
        _showSnackBar(l10n.deviceRevoked);
      }
    } catch (e) {
      debugPrint("Error revoking device: $e");
    }
  }

  Future<void> _handleCloudToggle(bool value, SettingsProvider settingsProvider) async {
    HapticFeedback.lightImpact();

    if (!value) {
      final token = _api.cloudToken;
      if (token != null) {
        try {
          final url = Uri.parse('${AppConfig.cloudFunctionsBaseUrl}/revoke-token');
          final headers = {'Content-Type': 'application/json'};
          final body = jsonEncode({'token': token});

          _logRequest("POST", url.toString(), headers, body);
          final response = await http.post(url, headers: headers, body: body);
          _logResponse(response);
        } catch (e) {
          debugPrint("Error revoking token: $e");
        }
      }

      await _api.updateCloudSettings(enabled: false, token: null, threadId: null);
      setState(() {});
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.cloud_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            Text(l10n.cloudFeatures, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(
          l10n.cloudDisclaimer,
          style: GoogleFonts.inter(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: GoogleFonts.inter(color: colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(l10n.continueText, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      await _api.updateCloudSettings(enabled: false);
      setState(() {});
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final reqUrl = Uri.parse('${AppConfig.cloudFunctionsBaseUrl}/request-verification');
      _logRequest("POST", reqUrl.toString(), null, null);

      final reqResp = await http.post(reqUrl);
      _logResponse(reqResp);

      if (reqResp.statusCode != 200) {
        throw Exception('Server error: ${reqResp.body}');
      }

      final reqData = jsonDecode(reqResp.body);
      final String code = reqData['code'];
      final int targetPrsId = reqData['targetPrsId'];

      final threadId = await _api.saveThread(interlocutorId: targetPrsId);
      if (threadId == 0) throw Exception('Failed to create chat');

      await _api.sendMessage(threadId, "Verification code: $code");

      await Future.delayed(const Duration(seconds: 10));

      final checkUrl = Uri.parse('${AppConfig.cloudFunctionsBaseUrl}/check-verification');
      final headers = {'Content-Type': 'application/json'};
      final realDeviceName = await _getRealDeviceName();
      final fullName = _api.userProfile?.fullName;
      final gradeClass = await _getCurrentGradeClass();
      final body = jsonEncode({
        'code': code,
        'threadId': threadId,
        'deviceName': realDeviceName,
        'fullName': fullName,
        'gradeClass': gradeClass,
      });

      _logRequest("POST", checkUrl.toString(), headers, body);

      final checkResp = await http.post(checkUrl, headers: headers, body: body);
      _logResponse(checkResp);

      final checkData = jsonDecode(checkResp.body);
      if (checkData['verified'] == true) {
        if (mounted) {
          final token = checkData['token'];
          Navigator.pop(context);

          await _api.updateCloudSettings(enabled: true, token: token, threadId: threadId);
          setState(() {});

          _showSnackBar(l10n.cloudActivated);
        }
      } else {
        throw Exception('Verification failed');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("${l10n.verificationError}: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            l10n.settings,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop(context) ? 600.0 : double.infinity),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    _buildSectionHeader(l10n.general, colorScheme),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      colorScheme: colorScheme,
                      children: [
                         _SettingsRow(
                          icon: Icons.language_rounded,
                          title: l10n.language,
                          subtitle: settingsProvider.locale.languageCode == 'ru' ? 'Русский' : 'English',
                          onTap: () => _showLanguageDialog(context, settingsProvider),
                          colorScheme: colorScheme,
                        ),
                        _SettingsDivider(colorScheme: colorScheme),
                        _SettingsSwitch(
                          icon: Icons.calendar_today_rounded,
                          title: l10n.onlyCurrentYear,
                          subtitle: l10n.hideOldDiaries,
                          value: settingsProvider.displayOnlyCurrentClass,
                          onChanged: (v) => settingsProvider.setDisplayOnlyCurrentClass(v),
                          colorScheme: colorScheme,
                        ),
                        _SettingsDivider(colorScheme: colorScheme),
                        _SettingsSwitch(
                          icon: Icons.cloud_outlined,
                          title: l10n.cloudFeatures,
                          subtitle: l10n.verificationRequired,
                          value: _api.isCloudEnabled,
                          onChanged: (v) => _handleCloudToggle(v, settingsProvider),
                          colorScheme: colorScheme,
                        ),
                        if (_api.isCloudEnabled) ...[
                          _SettingsDivider(colorScheme: colorScheme),
                          _SettingsRow(
                            icon: Icons.devices_rounded,
                            title: l10n.devices,
                            subtitle: l10n.manageConnections,
                            trailing: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            onTap: _showConnectedDevices,
                            colorScheme: colorScheme,
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 24),

                    _buildSectionHeader(l10n.homework, colorScheme),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      colorScheme: colorScheme,
                      children: [
                        _SettingsRow(
                          icon: Icons.history_rounded,
                          title: l10n.daysInPast,
                          subtitle: "${settingsProvider.hwDaysPast} д.",
                          onTap: () async {
                            final newValue = await _showNumberInputDialog(
                              context,
                              l10n.daysInPast,
                              settingsProvider.hwDaysPast,
                            );
                            if (newValue != null && newValue >= 0) {
                              settingsProvider.setHwDaysPast(newValue);
                            }
                          },
                          colorScheme: colorScheme,
                        ),
                        _SettingsDivider(colorScheme: colorScheme),
                        _SettingsRow(
                          icon: Icons.update_rounded,
                          title: l10n.daysInFuture,
                          subtitle: "${settingsProvider.hwDaysFuture} д.",
                          onTap: () async {
                            final newValue = await _showNumberInputDialog(
                              context,
                              l10n.daysInFuture,
                              settingsProvider.hwDaysFuture,
                            );
                            if (newValue != null && newValue >= 0) {
                              settingsProvider.setHwDaysFuture(newValue);
                            }
                          },
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    _buildSectionHeader(l10n.appearance, colorScheme),
                    const SizedBox(height: 12),
                    _buildThemeSelector(themeProvider, colorScheme, l10n),

                    const SizedBox(height: 24),

                    _buildSectionHeader(l10n.emulation, colorScheme),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      colorScheme: colorScheme,
                      children: [
                        _SettingsRow(
                          icon: Icons.smartphone_rounded,
                          title: _api.deviceModel,
                          subtitle: l10n.usedForLogin,
                          trailing: IconButton(
                            icon: Icon(
                              Icons.shuffle_rounded,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await _api.randomizeDeviceModel();
                              setState(() {});
                              if (mounted) {
                                _showSnackBar("Device: ${_api.deviceModel}");
                              }
                            },
                          ),
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),

                    if (WidgetDataService().isSupported) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader(l10n.widgets, colorScheme),
                      const SizedBox(height: 12),
                      _buildWidgetSettingsSection(context, colorScheme, l10n),
                    ],

                    const SizedBox(height: 24),

                    _buildSectionHeader(l10n.aboutApp, colorScheme),
                    const SizedBox(height: 12),
                    _SettingsCard(
                      colorScheme: colorScheme,
                      children: [
                        _SettingsRow(
                          icon: Icons.info_outline_rounded,
                          title: l10n.version,
                          trailing: Text(
                            "1.0.1",
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildThemeSelector(ThemeProvider themeProvider, ColorScheme colorScheme, AppLocalizations l10n) {
    return _SettingsCard(
      colorScheme: colorScheme,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _ThemeOption(
              icon: Icons.light_mode_rounded,
              label: l10n.light,
              isSelected: themeProvider.themeMode == ThemeMode.light,
              onTap: () => themeProvider.setTheme(ThemeMode.light),
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 12),
            _ThemeOption(
              icon: Icons.dark_mode_rounded,
              label: l10n.dark,
              isSelected: themeProvider.themeMode == ThemeMode.dark,
              onTap: () => themeProvider.setTheme(ThemeMode.dark),
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 12),
            _ThemeOption(
              icon: Icons.contrast_rounded,
              label: l10n.auto,
              isSelected: themeProvider.themeMode == ThemeMode.system,
              onTap: () => themeProvider.setTheme(ThemeMode.system),
              colorScheme: colorScheme,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWidgetSettingsSection(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    final widgetConfig = Provider.of<WidgetConfigProvider>(context);

    return Column(
      children: [
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _WidgetSettingsTile(
              icon: Icons.calendar_today_rounded,
              gradientColors: const [Color(0xFF6A11CB), Color(0xFF2575FC)],
              title: l10n.schedule,
              subtitle: l10n.lessonsForToday,
              value: widgetConfig.scheduleEnabled,
              onChanged: (v) => widgetConfig.setScheduleEnabled(v),
              colorScheme: colorScheme,
              expandedContent: widgetConfig.scheduleEnabled
                  ? _SettingsSwitch(
                      icon: Icons.person_outline_rounded,
                      title: l10n.showTeacher,
                      value: widgetConfig.showTeacherInSchedule,
                      onChanged: (v) => widgetConfig.setShowTeacherInSchedule(v),
                      colorScheme: colorScheme,
                      compact: true,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _WidgetSettingsTile(
              icon: Icons.assignment_rounded,
              gradientColors: const [Color(0xFFFF512F), Color(0xFFDD2476)],
              title: l10n.homework,
              subtitle: l10n.upcomingAssignments,
              value: widgetConfig.homeworkEnabled,
              onChanged: (v) => widgetConfig.setHomeworkEnabled(v),
              colorScheme: colorScheme,
              expandedContent: widgetConfig.homeworkEnabled
                  ? Column(
                      children: [
                        _SettingsDropdown(
                          title: l10n.count,
                          value: widgetConfig.homeworkItemsCount,
                          items: const [3, 5, 7, 10],
                          onChanged: (v) => widgetConfig.setHomeworkItemsCount(v),
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(height: 8),
                        _SettingsSwitch(
                          icon: Icons.schedule_rounded,
                          title: l10n.showDeadline,
                          value: widgetConfig.showDeadlineInHomework,
                          onChanged: (v) => widgetConfig.setShowDeadlineInHomework(v),
                          colorScheme: colorScheme,
                          compact: true,
                        ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _WidgetSettingsTile(
              icon: Icons.grade_rounded,
              gradientColors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
              title: l10n.grades,
              subtitle: l10n.averageScores,
              value: widgetConfig.gradesEnabled,
              onChanged: (v) => widgetConfig.setGradesEnabled(v),
              colorScheme: colorScheme,
              expandedContent: widgetConfig.gradesEnabled
                  ? _SettingsDropdown(
                      title: l10n.subjects,
                      value: widgetConfig.gradesSubjectsCount,
                      items: const [4, 6, 8, 10],
                      onChanged: (v) => widgetConfig.setGradesSubjectsCount(v),
                      colorScheme: colorScheme,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _SettingsRow(
              icon: Icons.refresh_rounded,
              title: l10n.updateWidgets,
              subtitle: l10n.syncNow,
              onTap: () async {
                HapticFeedback.lightImpact();
                await WidgetDataService().updateAllWidgets();
                if (mounted) {
                  _showSnackBar(l10n.widgetsUpdated);
                }
              },
              colorScheme: colorScheme,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildWidgetHint(colorScheme),
      ],
    );
  }

  Widget _buildWidgetHint(ColorScheme colorScheme) {
    final hint = _getWidgetInstructions();
    if (hint.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hint,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getWidgetInstructions() {
    if (kIsWeb) return "";
    if (Platform.isIOS) {
      return "Удерживайте главный экран, нажмите + и найдите reSchool";
    } else if (Platform.isAndroid) {
      return "Удерживайте главный экран, выберите «Виджеты» и найдите reSchool";
    } else if (Platform.isMacOS) {
      return "Нажмите на дату в строке меню и выберите «Редактировать виджеты»";
    }
    return "";
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final ColorScheme colorScheme;
  final EdgeInsets padding;

  const _SettingsCard({
    required this.children,
    required this.colorScheme,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      padding: padding,
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  final ColorScheme colorScheme;

  const _SettingsDivider({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      color: colorScheme.outline.withValues(alpha: 0.08),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;
  final bool compact;

  const _SettingsSwitch({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 8 : 10,
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 32 : 36,
            height: compact ? 32 : 36,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(compact ? 8 : 10),
            ),
            child: Icon(icon, size: compact ? 16 : 18, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          Transform.scale(
            scale: compact ? 0.85 : 0.9,
            child: Switch.adaptive(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              activeColor: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outline.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WidgetSettingsTile extends StatelessWidget {
  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;
  final Widget? expandedContent;

  const _WidgetSettingsTile({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
    this.expandedContent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch.adaptive(
                  value: value,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  },
                  activeColor: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        if (expandedContent != null)
          Padding(
            padding: const EdgeInsets.only(left: 60, right: 12, bottom: 12),
            child: expandedContent!,
          ),
      ],
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  final String title;
  final int value;
  final List<int> items;
  final ValueChanged<int> onChanged;
  final ColorScheme colorScheme;

  const _SettingsDropdown({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<int>(
            value: value,
            underline: const SizedBox(),
            isDense: true,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
            dropdownColor: colorScheme.surface,
            items: items
                .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                HapticFeedback.selectionClick();
                onChanged(v);
              }
            },
          ),
        ),
      ],
    );
  }
}