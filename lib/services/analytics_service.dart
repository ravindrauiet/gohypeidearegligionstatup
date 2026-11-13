import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'clarity/clarity.dart';
import 'notification_service.dart';

/// Google Analytics (via Firebase) for the Android/iOS app.
///
/// Active only when Firebase started (NotificationService.bootstrap set `firebaseReady`, which
/// needs android/app/google-services.json or ios/Runner/GoogleService-Info.plist). Otherwise —
/// web, tests, missing config — every call is a no-op. The website is measured separately by
/// the gtag snippet in web/index.html.
class AnalyticsService {
  AnalyticsService._();

  static bool get _enabled => !kIsWeb && NotificationService.firebaseReady;

  static FirebaseAnalytics? get _ga => _enabled ? FirebaseAnalytics.instance : null;

  /// Logs a screen_view for every named route push/pop. Add to MaterialApp.navigatorObservers.
  static NavigatorObserver observer() {
    final ga = _ga;
    return ga == null ? NavigatorObserver() : FirebaseAnalyticsObserver(analytics: ga);
  }

  /// Custom event. Never throws. Keep parameters free of personal data (no names, emails,
  /// birth details or chat text).
  static Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    final ga = _ga;
    if (ga == null) return;
    try {
      await ga.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('Analytics event $name failed: $e');
    }
  }

  static String? _lastUserId;

  /// Ties GA events and Clarity recordings to the backend user id (a number, never an email).
  static Future<void> setUserId(String? id) async {
    if (id == _lastUserId) return;
    _lastUserId = id;
    if (id != null && id.isNotEmpty) claritySetUserId(id);
    final ga = _ga;
    if (ga == null) return;
    try {
      await ga.setUserId(id: id);
    } catch (_) {}
  }
}

/// Tells Clarity which screen is showing (by route name) so heatmaps group per screen.
class ScreenNameObserver extends NavigatorObserver {
  void _set(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) claritySetScreen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _set(newRoute);
}
