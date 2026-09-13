import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../widgets/responsive_layout.dart';
import '../utils/app_font.dart';
import '../services/diary_navigation_service.dart';
import 'chat_detail_screen.dart';
import '../widgets/app_card.dart';
import '../services/reschool_http.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  String? _error;
  int _total = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('cf3_registered_server');
      final registrationId = prefs.getString('cf3_registration_id');
      final isClassmate = prefs.getBool('is_classmate') ?? false;

      // у одноклассников нет cf3_registration_id, сервер узнаёт их по токену
      if (serverUrl == null || (!isClassmate && registrationId == null)) {
        setState(() {
          _isLoading = false;
          _error = 'not_registered';
        });
        return;
      }

      final offset = loadMore ? _notifications.length : 0;
      final url = Uri.parse('$serverUrl/notification-history');
      final apiToken = prefs.getString('cloud_api_token') ?? '';
      final registrationSecret =
          prefs.getString('cf3_registration_secret') ?? '';
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (apiToken.isNotEmpty) headers['X-API-Token'] = apiToken;
      final bodyMap = <String, dynamic>{'limit': 20, 'offset': offset};
      // registrationId кладём только для админских аккаунтов
      if (!isClassmate && registrationId != null) {
        bodyMap['registrationId'] = registrationId;
        if (registrationSecret.isNotEmpty) {
          bodyMap['registrationSecret'] = registrationSecret;
        }
      }
      final response = await reschoolHttp.post(
        url,
        headers: headers,
        body: jsonEncode(bodyMap),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final notifications = (data['notifications'] as List)
            .map((n) => NotificationItem.fromJson(n))
            .toList();

        setState(() {
          if (loadMore) {
            _notifications.addAll(notifications);
          } else {
            _notifications = notifications;
          }
          _total = data['total'] ?? 0;
          _hasMore = _notifications.length < _total;
          _isLoading = false;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _isLoading = false;
          _error = 'not_registered';
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = 'server_error';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'connection_error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          l10n.notificationHistory,
          style: appFont(context, fontWeight: FontWeight.w600),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _buildBody(colorScheme, l10n, settings),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, AppLocalizations l10n,
      SettingsProvider settings) {
    if (_isLoading && _notifications.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState(colorScheme, l10n, settings);
    }

    if (_notifications.isEmpty) {
      return _buildEmptyState(colorScheme, l10n);
    }

    return RefreshIndicator(
      onRefresh: () => _loadNotifications(),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop(context) ? 48 : 16,
          vertical: 16,
        ),
        itemCount: _notifications.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _notifications.length) {
            return _buildLoadMoreButton(colorScheme, l10n);
          }
          return _buildNotificationCard(
              _notifications[index], colorScheme, l10n);
        },
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme, AppLocalizations l10n,
      SettingsProvider settings) {
    IconData icon;
    String title;
    String subtitle;

    if (_error == 'not_registered') {
      icon = Icons.notifications_off_outlined;
      title = l10n.cf3NotEnabled;
      subtitle = l10n.cf3NotEnabledDesc;
    } else if (_error == 'connection_error') {
      icon = Icons.wifi_off_rounded;
      title = l10n.connectionError;
      subtitle = l10n.checkInternet;
    } else {
      icon = Icons.error_outline_rounded;
      title = l10n.error;
      subtitle = l10n.tryAgainLater;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: colorScheme.error.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: appFont(context,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: appFont(context,
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (_error != 'not_registered') ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _loadNotifications(),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.retry, style: appFont(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 40,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noNotifications,
              style: appFont(context,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noNotificationsDesc,
              style: appFont(context,
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _openNotification(NotificationItem notification) {
    HapticFeedback.selectionClick();
    final data = notification.data;

    switch (notification.type) {
      case 'message':
        final threadId =
            data != null ? int.tryParse(data['id']?.toString() ?? '') : null;
        if (threadId == null) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            threadId: threadId,
            title: notification.title.replaceAll('💬 ', '').split(':').first,
            isGroup: false,
          ),
        ));
        break;

      case 'homework':
        final dateStr = data?['date'] as String?;
        final subject = data?['subject'] as String?;
        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
        // уводим на вкладку дневника с датой и предметом, экран закрываем, чтобы стал виден HomeScreen
        DiaryNavigationService.instance
            .switchTab(0, date: date, subject: subject);
        Navigator.of(context).pop();
        break;

      case 'grade':
        // уводим на вкладку оценок, экран так же закрываем
        DiaryNavigationService.instance.switchTab(1);
        Navigator.of(context).pop();
        break;

      default:
        break;
    }
  }

  Widget _buildNotificationCard(NotificationItem notification,
      ColorScheme colorScheme, AppLocalizations l10n) {
    final typeInfo = _typeInfo(notification.type, colorScheme);
    final tappable = notification.type == 'message' ||
        notification.type == 'homework' ||
        notification.type == 'grade';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: appCardFill(context),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: tappable ? () => _openNotification(notification) : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // иконка
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: typeInfo.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeInfo.icon, size: 21, color: typeInfo.color),
                ),
                const SizedBox(width: 13),
                // текст
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: appFont(context,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (notification.body != null &&
                          notification.body!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          notification.body!,
                          style: appFont(context,
                            fontSize: 13,
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.65),
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        _formatDate(notification.sentAt),
                        style: appFont(context,
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tappable) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.25),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  _NotifTypeInfo _typeInfo(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'homework':
        return _NotifTypeInfo(Icons.book_outlined, colorScheme.primary);
      case 'grade':
        return _NotifTypeInfo(Icons.bar_chart_rounded, colorScheme.tertiary);
      case 'message':
        return _NotifTypeInfo(
            Icons.chat_bubble_outline_rounded, colorScheme.secondary);
      case 'welcome':
        return _NotifTypeInfo(Icons.celebration_outlined, colorScheme.primary);
      default:
        return _NotifTypeInfo(
            Icons.notifications_outlined, colorScheme.primary);
    }
  }

  Widget _buildLoadMoreButton(ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: TextButton.icon(
          onPressed: () => _loadNotifications(loadMore: true),
          icon: const Icon(Icons.expand_more_rounded),
          label: Text(l10n.loadMore, style: appFont(context)),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return 'Только что';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} мин. назад';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} ч. назад';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} дн. назад';
    } else {
      return '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
  }
}

class _NotifTypeInfo {
  final IconData icon;
  final Color color;
  const _NotifTypeInfo(this.icon, this.color);
}

class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic>? data;
  final DateTime? sentAt;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.data,
    this.sentAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'],
      type: json['type'] ?? 'message',
      title: json['title'] ?? '',
      body: json['body'],
      data: json['data'],
      sentAt: json['sentAt'] != null ? DateTime.tryParse(json['sentAt']) : null,
    );
  }
}
