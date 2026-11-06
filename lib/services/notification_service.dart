import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/forecast.dart';
import '../screens/buddy/buddy_chat_screen.dart';
import '../widgets/notification_permission_sheet.dart';
import 'backend_service.dart';
import 'notification_router.dart';
import 'notification_schedule.dart';
import 'rewards_service.dart';

export 'notification_schedule.dart';

// =============================================================================
// Platform abstractions (faked in tests)
// =============================================================================

/// The on-device notification plugin, behind an interface so tests don't need
/// platform channels.
abstract class LocalNotifier {
  /// Sets up channels and tap handling. [onTap] gets the decoded payload.
  Future<void> init(void Function(Map<String, dynamic> data) onTap);

  /// Payload of the notification that launched the app (cold start), if any.
  Future<Map<String, dynamic>?> launchPayload();

  Future<void> show(int id, String title, String body, String channel, Map<String, String> payload);
  Future<void> schedule(PlannedNotification n);
  Future<void> cancel(int id);

  /// Whether the OS lets the app post notifications (null = unknown).
  Future<bool?> permissionGranted();

  /// Shows the OS permission dialog. Returns whether permission is granted.
  Future<bool> requestPermission();
  Future<void> openSettings();
}

/// A received push message.
class PushMessage {
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  const PushMessage({this.title, this.body, this.data = const {}});
}

/// Firebase Cloud Messaging, behind an interface (null in tests / when
/// Firebase is not configured).
abstract class PushClient {
  Future<String?> token();
  Stream<String> get onTokenRefresh;
  Stream<PushMessage> get onMessage;
  Stream<PushMessage> get onOpened;
  Future<PushMessage?> initialMessage();
  Future<void> requestPermission();
  Future<void> subscribe(String topic);
  Future<void> unsubscribe(String topic);
}

const _channelInfo = <String, (String, String, Importance)>{
  NotificationChannels.reminders: (
    'Daily reminders',
    'Daily horoscope, check-in and gentle reminders',
    Importance.defaultImportance
  ),
  NotificationChannels.buddy: ('Buddies & messages', 'Buddy requests, chats and trip updates', Importance.high),
  NotificationChannels.rewards: ('Coins & rewards', 'Daily check-in and coin rewards', Importance.defaultImportance),
  NotificationChannels.festivals: ('Festivals & Panchang', 'Festival and vrat alerts', Importance.defaultImportance),
  NotificationChannels.announcements: (
    'Updates',
    'News and announcements from CosmicGuide',
    Importance.defaultImportance
  ),
};

const _androidIcon = 'ic_stat_notify';
const _accent = Color(0xFFFF7A00);

NotificationDetails _details(String channel, [String? body]) {
  final info = _channelInfo[channel] ?? _channelInfo[NotificationChannels.announcements]!;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      channel,
      info.$1,
      channelDescription: info.$2,
      importance: info.$3,
      priority: info.$3 == Importance.high ? Priority.high : Priority.defaultPriority,
      icon: _androidIcon,
      color: _accent,
      styleInformation: (body == null || body.isEmpty) ? null : BigTextStyleInformation(body),
    ),
    iOS: DarwinNotificationDetails(threadIdentifier: channel),
  );
}

Map<String, dynamic>? _decodePayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final v = json.decode(raw);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  } catch (_) {
    return null;
  }
}

/// [LocalNotifier] backed by flutter_local_notifications.
class PluginLocalNotifier implements LocalNotifier {
  final FlutterLocalNotificationsPlugin _plugin;
  PluginLocalNotifier([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// False until [init] succeeds (no plugin: tests, unsupported platforms);
  /// every call is then a no-op.
  bool _ready = false;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  AndroidFlutterLocalNotificationsPlugin? get _a =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _i =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init(void Function(Map<String, dynamic> data) onTap) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_androidIcon),
        // Permission is asked later, after the friendly pre-prompt.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final data = _decodePayload(r.payload);
        if (data != null) onTap(data);
      },
    );
    if (_android) {
      for (final e in _channelInfo.entries) {
        await _a?.createNotificationChannel(
          AndroidNotificationChannel(e.key, e.value.$1, description: e.value.$2, importance: e.value.$3),
        );
      }
    }
    _ready = true;
  }

  @override
  Future<Map<String, dynamic>?> launchPayload() async {
    if (!_ready) return null;
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    return _decodePayload(d.notificationResponse?.payload);
  }

  @override
  Future<void> show(int id, String title, String body, String channel, Map<String, String> payload) async {
    if (!_ready) return;
    await _plugin.show(
        id: id, title: title, body: body, notificationDetails: _details(channel, body), payload: json.encode(payload));
  }

  @override
  Future<void> schedule(PlannedNotification n) async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      id: n.id,
      title: n.title,
      body: n.body,
      scheduledDate: n.when,
      notificationDetails: _details(n.channel, n.body),
      // Inexact on purpose: no SCHEDULE_EXACT_ALARM permission needed.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: json.encode(n.payload),
      matchDateTimeComponents: switch (n.repeat) {
        NotificationRepeat.daily => DateTimeComponents.time,
        NotificationRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
        NotificationRepeat.none => null,
      },
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (_ready) await _plugin.cancel(id: id);
  }

  @override
  Future<bool?> permissionGranted() async {
    if (!_ready) return null;
    if (_android) return _a?.areNotificationsEnabled();
    if (_ios) return (await _i?.checkPermissions())?.isEnabled;
    return null;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    if (_android) return await _a?.requestNotificationsPermission() ?? false;
    if (_ios) return await _i?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<void> openSettings() async {
    if (!_ready) return;
    await _plugin.openAppNotificationSettings();
  }
}

PushMessage _fromRemote(RemoteMessage m) => PushMessage(
      title: m.notification?.title ?? m.data['title']?.toString(),
      body: m.notification?.body ?? m.data['body']?.toString(),
      data: Map<String, dynamic>.from(m.data),
    );

/// [PushClient] backed by firebase_messaging.
class FirebasePushClient implements PushClient {
  FirebaseMessaging get _m => FirebaseMessaging.instance;

  @override
  Future<String?> token() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // getToken throws until APNs has handed out a device token.
      for (var i = 0; i < 5 && await _m.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    // The classic FCM registration token is what the backend (firebase-admin
    // send-to-token) expects; the newer FID register() flow is not used.
    // ignore: deprecated_member_use
    return _m.getToken();
  }

  @override
  // ignore: deprecated_member_use
  Stream<String> get onTokenRefresh => _m.onTokenRefresh;
  @override
  Stream<PushMessage> get onMessage => FirebaseMessaging.onMessage.map(_fromRemote);
  @override
  Stream<PushMessage> get onOpened => FirebaseMessaging.onMessageOpenedApp.map(_fromRemote);
  @override
  Future<PushMessage?> initialMessage() async {
    final m = await _m.getInitialMessage();
    return m == null ? null : _fromRemote(m);
  }

  @override
  Future<void> requestPermission() async {
    await _m.requestPermission();
    // Foreground messages are shown by us as local notifications.
    await _m.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false);
  }

  @override
  Future<void> subscribe(String topic) => _m.subscribeToTopic(topic);
  @override
  Future<void> unsubscribe(String topic) => _m.unsubscribeFromTopic(topic);
}

/// Background / terminated FCM handler. Messages with a `notification` block
/// are displayed by the OS; data-only messages carrying title/body are shown
/// here as a local notification.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    if (message.notification != null) return;
    final m = _fromRemote(message);
    if ((m.title ?? '').isEmpty && (m.body ?? '').isEmpty) return;
    final local = PluginLocalNotifier();
    await local.init((_) {});
    final type = m.data['type']?.toString();
    await local.show(
      NotificationService.pushIdFor(m.data),
      m.title ?? 'CosmicGuide',
      m.body ?? '',
      NotificationService.channelForType(type),
      m.data.map((k, v) => MapEntry(k, '$v')),
    );
  } catch (e) {
    debugPrint('Background push failed: $e');
  }
}

// =============================================================================
// Service
// =============================================================================

/// On-device reminders, FCM push, permission pre-prompt and notification
/// settings. Works without Firebase (push is then simply disabled).
class NotificationService extends ChangeNotifier with WidgetsBindingObserver {
  /// The app-wide instance (set by the constructor).
  static NotificationService? instance;

  /// Whether Firebase initialised in [bootstrap].
  static bool firebaseReady = false;

  static const topicAnnouncements = 'announcements';
  static const fallbackTimezone = 'Asia/Kolkata';

  static const _kPrefs = 'notif_prefs_v1';
  static const _kPromptAt = 'notif_preprompt_at';
  static const _kPermAsked = 'notif_perm_asked';
  static const _kCheckinDay = 'notif_checkin_day';
  static const _kStreak = 'notif_streak';
  static const _kMindsetRemaining = 'notif_mindset_remaining';
  static const _kFestivals = 'notif_festivals_v1';
  static const _kFestivalsAt = 'notif_festivals_at';
  static const _kPushToken = 'notif_push_token';

  static const prePromptCooldown = Duration(days: 14);
  static const _festivalRefresh = Duration(hours: 12);

  final BackendService? backend;
  final RewardsService? rewards;
  final LocalNotifier local;
  final PushClient? push;

  /// Called for each push received while the app is in the foreground (the
  /// inbox uses it to refresh its unread count).
  final void Function(Map<String, dynamic> data)? onPush;

  /// Clock override for tests.
  final tz.TZDateTime Function()? clock;

  NotificationService({
    this.backend,
    this.rewards,
    LocalNotifier? local,
    this.push,
    this.onPush,
    this.clock,
  }) : local = local ?? PluginLocalNotifier() {
    instance = this;
  }

  NotificationPrefs _prefs = const NotificationPrefs();
  NotificationPrefs get prefs => _prefs;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool? _permission;

  /// OS permission state (null until checked / unknown platform).
  bool? get permissionGranted => _permission;

  bool _started = false;
  bool _disposed = false;
  bool _wasAuthed = false;
  int _pushCounter = 0;
  Timer? _rescheduleDebounce;
  Timer? _syncDebounce;
  Future<void>? _rescheduling;
  final List<StreamSubscription<dynamic>> _subs = [];
  List<PlannedNotification> _lastPlan = const [];

  /// The most recent plan (for tests / debugging).
  List<PlannedNotification> get lastPlan => _lastPlan;

  bool get _registered => debugRegistered ?? backend?.isAuthenticated ?? false;

  /// Signed in with a registered (non-guest) account.
  bool get registered => _registered;

  /// Test override for [registered].
  @visibleForTesting
  bool? debugRegistered;
  bool get pushAvailable => push != null;

  tz.TZDateTime _now() {
    final c = clock;
    if (c != null) return c();
    if (!_tzReady) {
      // bootstrap() not run (tests): UTC-safe fallback zone.
      tz_data.initializeTimeZones();
      _tzReady = true;
      tz.setLocalLocation(tz.getLocation(fallbackTimezone));
    }
    return tz.TZDateTime.now(tz.local);
  }

  // ---------------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------------

  /// Process-wide setup before runApp: time zones, Firebase and the background
  /// handler. Never throws.
  static Future<void> bootstrap() async {
    await initTimeZone();
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 5));
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      firebaseReady = true;
    } catch (e) {
      firebaseReady = false;
      debugPrint('Firebase not configured; push notifications disabled ($e)');
    }
  }

  static bool _tzReady = false;

  /// Loads the tz database and sets the device zone (fallback Asia/Kolkata).
  static Future<void> initTimeZone() async {
    if (!_tzReady) {
      tz_data.initializeTimeZones();
      _tzReady = true;
    }
    var name = fallbackTimezone;
    try {
      if (!kIsWeb) name = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {}
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation(fallbackTimezone));
    }
  }

  /// Loads settings, wires listeners, reschedules reminders and (when
  /// Firebase is available) sets up push. Safe to call once.
  Future<void> start() => _startFuture ??= _start();

  Future<void>? _startFuture;

  Future<void> _start() async {
    _started = true;
    if (!_tzReady) await initTimeZone();
    await load();
    WidgetsBinding.instance.addObserver(this);
    try {
      await local.init(NotificationRouter.open);
      final launch = await local.launchPayload();
      if (launch != null) unawaited(NotificationRouter.open(launch));
    } catch (e) {
      debugPrint('Local notifications unavailable: $e');
    }
    await backend?.ready;
    _wasAuthed = _registered;
    backend?.addListener(_onBackendChanged);
    backend?.logoutHooks.add(_onLogout);
    rewards?.addListener(_onRewardsChanged);
    RewardsService.onDailyClaimed = markCheckedIn;
    await refreshPermission();
    await rescheduleAll();
    await _initPush();
    if (_registered) unawaited(_pullServerPrefs());
  }

  /// Reads stored settings (no platform calls).
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kPrefs);
      final m = raw == null ? null : _decodePayload(raw);
      _prefs = m == null ? const NotificationPrefs() : NotificationPrefs.fromJson(m);
    } catch (_) {}
    _loaded = true;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshPermission());
      // Re-engagement reminders move forward on every open.
      _scheduleSoon();
      unawaited(_syncPushRegistration());
    }
  }

  void _onBackendChanged() {
    final now = _registered;
    if (now == _wasAuthed) return;
    _wasAuthed = now;
    _notify();
    _scheduleSoon();
    if (now) {
      unawaited(_syncPushRegistration(force: true));
      unawaited(_pullServerPrefs());
    }
  }

  bool _lastClaimed = false;
  int _lastStreak = -1;
  int _lastAnswered = -1;

  void _onRewardsChanged() {
    final r = rewards;
    if (r == null || !r.loaded) return;
    var changed = false;
    if (r.dailyClaimed != _lastClaimed || r.streakDays != _lastStreak) {
      _lastClaimed = r.dailyClaimed;
      _lastStreak = r.streakDays;
      changed = true;
      unawaited(_storeCheckin(r.dailyClaimed, r.streakDays));
    }
    if (r.questionsLoaded && r.answeredCount != _lastAnswered) {
      _lastAnswered = r.answeredCount;
      changed = true;
      unawaited(_storeInt(_kMindsetRemaining, (r.questionTotal - r.answeredCount).clamp(0, 1 << 20)));
    }
    if (changed) _scheduleSoon();
  }

  /// Hook from [RewardsService.claimDaily]: today's check-in is done, so the
  /// next reminder moves to tomorrow (with the new streak).
  void markCheckedIn(int streakDays) {
    _lastClaimed = true;
    _lastStreak = streakDays;
    unawaited(_storeCheckin(true, streakDays).then((_) => rescheduleAll()));
  }

  Future<void> _storeCheckin(bool claimedToday, int streak) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kStreak, streak);
      if (claimedToday) await sp.setString(_kCheckinDay, _dayKey(_now()));
    } catch (_) {}
  }

  Future<void> _storeInt(String key, int v) async {
    try {
      (await SharedPreferences.getInstance()).setInt(key, v);
    } catch (_) {}
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  void _scheduleSoon() {
    _rescheduleDebounce?.cancel();
    _rescheduleDebounce = Timer(const Duration(milliseconds: 600), () => unawaited(rescheduleAll()));
  }

  /// Builds the reminder plan from current state and applies it. Idempotent:
  /// fixed ids per category, anything not in the plan is cancelled.
  Future<void> rescheduleAll() {
    final running = _rescheduling;
    if (running != null) return running.then((_) => _rescheduleNow());
    return _rescheduling = _rescheduleNow().whenComplete(() => _rescheduling = null);
  }

  Future<void> _rescheduleNow() async {
    try {
      final input = await buildInput();
      final plan = NotificationSchedule.plan(input);
      _lastPlan = plan;
      final planned = {for (final p in plan) p.id};
      for (final id in NotificationIds.managed) {
        if (!planned.contains(id)) await local.cancel(id);
      }
      for (final p in plan) {
        await local.schedule(p);
      }
      await _syncJapReminderWithMaster();
    } catch (e) {
      debugPrint('Rescheduling notifications failed: $e');
    }
  }

  static const _japReminderKey = 'jap_reminder_time';

  /// The jap reminder lives outside the plan; follow the master switch here.
  Future<void> _syncJapReminderWithMaster() async {
    if (!_prefs.master) {
      await local.cancel(japReminderId);
      return;
    }
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString(_japReminderKey);
    if (saved == null) return;
    final parts = saved.split(':');
    final h = int.tryParse(parts.first);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null || await refreshPermission() != true) return;
    final now = _now();
    var when = tz.TZDateTime(now.location, now.year, now.month, now.day, h.clamp(0, 23), m.clamp(0, 59));
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await local.schedule(PlannedNotification(
      id: japReminderId,
      channel: NotificationChannels.reminders,
      title: 'Time for your jap',
      body: 'A few quiet minutes with your mala brings calm to the whole day.',
      when: when,
      repeat: NotificationRepeat.daily,
      payload: const {'type': 'jap'},
    ));
  }

  // v3 meetups (agent M): one-off local reminders outside the managed plan. Use ids >= 40000
  // (below that are the plan, chat and push ranges); [rescheduleAll] never cancels them.

  /// Schedules one local notification at [when]. Skipped (returns false) when
  /// [when] is in the past or notifications are switched off. Never throws.
  Future<bool> scheduleOneOff({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String channel = NotificationChannels.announcements,
    Map<String, String> payload = const {},
  }) async {
    try {
      if (!_prefs.master) return false;
      final now = _now();
      final at = tz.TZDateTime.from(when, now.location);
      if (!at.isAfter(now)) return false;
      await local.schedule(PlannedNotification(id: id, channel: channel, title: title, body: body, when: at, payload: payload));
      return true;
    } catch (e) {
      debugPrint('One-off notification failed: $e');
      return false;
    }
  }

  /// Cancels a notification scheduled with [scheduleOneOff]. Never throws.
  Future<void> cancelOneOff(int id) async {
    try {
      await local.cancel(id);
    } catch (_) {}
  }

  /// Gathers the scheduler input (stored state + live services).
  Future<ScheduleInput> buildInput() async {
    final now = _now();
    SharedPreferences? sp;
    try {
      sp = await SharedPreferences.getInstance();
    } catch (_) {}
    final r = rewards;
    final registered = _registered;
    bool checkedIn;
    int streak;
    if (r != null && r.loaded && r.loggedIn) {
      checkedIn = r.dailyClaimed;
      streak = r.streakDays;
    } else {
      checkedIn = sp?.getString(_kCheckinDay) == _dayKey(now);
      streak = sp?.getInt(_kStreak) ?? 0;
    }
    int? remaining = sp?.getInt(_kMindsetRemaining);
    if (r != null && r.questionsLoaded) remaining = (r.questionTotal - r.answeredCount).clamp(0, 1 << 20);
    final moon = backend?.kundliData?['moonSign']?.toString();
    return ScheduleInput(
      now: now,
      prefs: _prefs,
      registered: registered,
      checkedInToday: checkedIn,
      streakDays: streak,
      moonSign: moon,
      festivals: await _festivals(sp),
      mindsetRemaining: remaining,
      coinsPerQuestion: r?.coinsPerQuestion ?? 50,
    );
  }

  /// Festival days from the same source as the Home Panchang section (the
  /// backend month forecast, this month and next). Cached for 12 h so app
  /// resumes don't refetch; the cache is used when offline.
  Future<List<FestivalItem>> _festivals(SharedPreferences? sp) async {
    List<FestivalItem> cached() {
      final raw = sp?.getString(_kFestivals);
      if (raw == null) return const [];
      try {
        final list = json.decode(raw);
        if (list is! List) return const [];
        return list.map(FestivalItem.fromJson).whereType<FestivalItem>().toList();
      } catch (_) {
        return const [];
      }
    }

    final b = backend;
    if (!_prefs.master || !_prefs.festivals || b == null || !b.hasBirthDetails) return cached();
    final at = DateTime.tryParse(sp?.getString(_kFestivalsAt) ?? '');
    if (at != null && DateTime.now().difference(at) < _festivalRefresh) return cached();
    try {
      final now = DateTime.now();
      final months = await Future.wait([
        b.fetchMonthForecast(),
        b.fetchMonthForecast(month: DateTime(now.year, now.month + 1, 1)),
      ]);
      if (months.every((m) => m == null)) return cached();
      final items = festivalsFromForecast(months);
      await sp?.setString(_kFestivals, json.encode(items.map((f) => f.toJson()).toList()));
      await sp?.setString(_kFestivalsAt, DateTime.now().toIso8601String());
      return items;
    } catch (_) {
      return cached();
    }
  }

  /// Event types worth an alert (festivals and vrat days, not moon phases).
  static const festivalTypes = {'festival', 'ekadashi', 'sankranti', 'solar_eclipse', 'lunar_eclipse'};

  /// Extracts festival days from month forecast payloads.
  static List<FestivalItem> festivalsFromForecast(List<Map<String, dynamic>?> months) {
    final out = <FestivalItem>[];
    final seen = <String>{};
    for (final m in months) {
      final raw = m?['events'];
      if (raw is! List) continue;
      for (final item in raw) {
        final e = ForecastEvent.fromJson(item);
        final d = e.date;
        if (d == null || !festivalTypes.contains(e.type) || e.title.trim().isEmpty) continue;
        if (seen.add('${d.year}-${d.month}-${d.day}|${e.title}')) {
          out.add(FestivalItem(DateTime(d.year, d.month, d.day), e.title.trim()));
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  /// Saves new settings, reschedules and syncs the server categories.
  Future<void> updatePrefs(NotificationPrefs next) async {
    final before = _prefs;
    _prefs = next;
    _notify();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPrefs, json.encode(next.toJson()));
    } catch (_) {}
    await rescheduleAll();
    if (before.master != next.master || before.announcements != next.announcements) {
      unawaited(_syncPushRegistration(force: true));
    }
    final serverChanged = before.toServer().toString() != next.toServer().toString();
    if (serverChanged && _registered) {
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(milliseconds: 800), () => unawaited(_pushServerPrefs()));
    }
  }

  Future<void> _pushServerPrefs() async {
    try {
      await backend?.api('PUT', '/notifications/prefs', body: _prefs.toServer());
    } catch (e) {
      debugPrint('Saving notification prefs failed: $e');
    }
  }

  Future<void> _pullServerPrefs() async {
    final b = backend;
    if (b == null || !b.isAuthenticated) return;
    try {
      final res = await b.api('GET', '/notifications/prefs');
      final merged = _prefs.mergeServer(res);
      if (merged.toJson().toString() != _prefs.toJson().toString()) {
        _prefs = merged;
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_kPrefs, json.encode(merged.toJson()));
        _notify();
        _scheduleSoon();
      }
    } catch (_) {
      // Offline / endpoint missing: keep local settings.
    }
  }

  // ---------------------------------------------------------------------------
  // Permission
  // ---------------------------------------------------------------------------

  Future<bool?> refreshPermission() async {
    bool? granted;
    try {
      granted = await local.permissionGranted();
    } catch (_) {}
    if (granted != _permission) {
      _permission = granted;
      _notify();
    }
    return granted;
  }

  /// Asks the OS for permission (after the pre-prompt). Returns the result.
  Future<bool> requestPermission() async {
    var granted = false;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kPermAsked, true);
    } catch (_) {}
    try {
      granted = await local.requestPermission();
    } catch (_) {}
    try {
      await push?.requestPermission();
    } catch (_) {}
    _permission = granted;
    _notify();
    if (granted) {
      unawaited(rescheduleAll());
      unawaited(_syncPushRegistration(force: true));
    }
    return granted;
  }

  /// Settings banner action: ask once, afterwards open the system settings
  /// (the OS won't show its dialog again once denied).
  Future<void> turnOnFromSettings() async {
    var asked = false;
    try {
      asked = (await SharedPreferences.getInstance()).getBool(_kPermAsked) ?? false;
    } catch (_) {}
    if (!asked && await requestPermission()) return;
    try {
      await local.openSettings();
    } catch (_) {}
  }

  /// Whether the pre-prompt sheet should be shown now.
  @visibleForTesting
  Future<bool> shouldShowPrePrompt() async {
    if (_permission != false) return false; // granted, or unknown platform
    if (!_prefs.master) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      final at = DateTime.tryParse(sp.getString(_kPromptAt) ?? '');
      if (at != null && DateTime.now().difference(at) < prePromptCooldown) return false;
    } catch (_) {}
    return true;
  }

  bool _promptInFlight = false;

  /// Called when Home is first shown (after login / onboarding): shows the
  /// permission pre-prompt when appropriate (at most once per 14 days).
  Future<void> onHomeVisible(BuildContext homeContext) async {
    if (_promptInFlight) return;
    _promptInFlight = true;
    try {
      // Let the Home screen (and any daily check-in dialog) settle first.
      await Future<void>.delayed(const Duration(seconds: 3));
      await _startFuture;
      await refreshPermission();
      if (!homeContext.mounted || !await shouldShowPrePrompt()) return;
      if (!homeContext.mounted) return;
      if (ModalRoute.of(homeContext)?.isCurrent == false) return; // something on top; try next time
      try {
        (await SharedPreferences.getInstance()).setString(_kPromptAt, DateTime.now().toIso8601String());
      } catch (_) {}
      if (!homeContext.mounted) return;
      final accepted = await NotificationPermissionSheet.show(homeContext);
      if (accepted == true) await requestPermission();
    } finally {
      _promptInFlight = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  Future<void> _initPush() async {
    final p = push;
    if (p == null) return;
    try {
      _subs.add(p.onMessage.listen(handleForegroundMessage));
      _subs.add(p.onOpened.listen((m) => NotificationRouter.open(m.data)));
      _subs.add(p.onTokenRefresh.listen((t) => unawaited(_registerToken(t))));
      final initial = await p.initialMessage();
      if (initial != null) unawaited(NotificationRouter.open(initial.data));
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
    await _syncPushRegistration(force: true);
  }

  bool _syncing = false;
  DateTime? _lastSync;

  /// Registers (or unregisters) this device and the announcements topic to
  /// match login state, permission and settings. Guests never register.
  Future<void> _syncPushRegistration({bool force = false}) async {
    final p = push;
    if (p == null || _syncing) return;
    if (!force && _lastSync != null && DateTime.now().difference(_lastSync!) < const Duration(hours: 6)) return;
    _syncing = true;
    try {
      final wanted = _registered && _prefs.master && _permission != false;
      if (!wanted) {
        await _unregisterDevice();
        await p.unsubscribe(topicAnnouncements).catchError((_) {});
        return;
      }
      final t = await p.token();
      if (t != null && t.isNotEmpty) await _registerToken(t);
      if (_prefs.announcements) {
        await p.subscribe(topicAnnouncements);
      } else {
        await p.unsubscribe(topicAnnouncements);
      }
      _lastSync = DateTime.now();
    } catch (e) {
      debugPrint('Push registration failed: $e');
    } finally {
      _syncing = false;
    }
  }

  static String get _platform => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<void> _registerToken(String token) async {
    final b = backend;
    if (b == null || !b.isAuthenticated || !_prefs.master) return;
    try {
      await b.api('POST', '/notifications/devices', body: {'token': token, 'platform': _platform});
      (await SharedPreferences.getInstance()).setString(_kPushToken, token);
    } catch (e) {
      debugPrint('Device registration failed: $e');
    }
  }

  Future<void> _unregisterDevice() async {
    final b = backend;
    if (b == null || !b.isAuthenticated) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final token = sp.getString(_kPushToken);
      if (token == null) return;
      await b.api('DELETE', '/notifications/devices', body: {'token': token}, timeout: const Duration(seconds: 5));
      await sp.remove(_kPushToken);
    } catch (e) {
      debugPrint('Device unregistration failed: $e');
    }
  }

  /// Runs before [BackendService.logout] clears the session token.
  Future<void> _onLogout() async {
    if (push == null) return;
    await _unregisterDevice();
    try {
      await push!.unsubscribe(topicAnnouncements);
    } catch (_) {}
    _lastSync = null;
  }

  /// Local channel for a pushed payload type.
  static String channelForType(String? type) {
    switch (type) {
      case 'buddy_request':
      case 'buddy_accepted':
      case 'buddy_message':
      case 'nearby_buddy':
      case 'trip_update':
      case 'meetup_update':
      case 'verification_update':
      case 'family_note':
        return NotificationChannels.buddy;
      case 'coins':
      case 'checkin':
      case 'jap':
        return NotificationChannels.rewards;
      case 'festival':
      case 'guide':
      case 'muhurat':
        return NotificationChannels.festivals;
      default:
        return NotificationChannels.announcements;
    }
  }

  /// Chat messages reuse one id per connection, so a burst collapses.
  static int pushIdFor(Map<String, dynamic> data, [int counter = 0]) {
    final conn = int.tryParse('${data['connectionId'] ?? ''}');
    if (data['type'] == 'buddy_message' && conn != null) return NotificationIds.chatBase + conn % 10000;
    return NotificationIds.pushBase + counter % 10000;
  }

  /// Whether a foreground push should be shown: respects settings and hides
  /// messages for the chat that is currently open.
  static bool shouldPresentForeground(Map<String, dynamic> data, NotificationPrefs prefs, {int? openConnectionId}) {
    final type = data['type']?.toString();
    if (!prefs.allowsPushType(type)) return false;
    if (type == 'buddy_message' && openConnectionId != null) {
      final conn = int.tryParse('${data['connectionId'] ?? ''}');
      if (conn == openConnectionId) return false;
    }
    return true;
  }

  /// Foreground push: notify listeners (inbox badge) and show it locally
  /// unless suppressed.
  Future<void> handleForegroundMessage(PushMessage m) async {
    try {
      onPush?.call(m.data);
    } catch (_) {}
    if (!shouldPresentForeground(m.data, _prefs, openConnectionId: BuddyChatScreen.openConnectionId.value)) return;
    final title = (m.title ?? '').trim();
    final body = (m.body ?? '').trim();
    if (title.isEmpty && body.isEmpty) return;
    try {
      await local.show(
        pushIdFor(m.data, _pushCounter++),
        title.isEmpty ? 'CosmicGuide' : title,
        body,
        channelForType(m.data['type']?.toString()),
        m.data.map((k, v) => MapEntry(k, '$v')),
      );
    } catch (e) {
      debugPrint('Showing push failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // v3 jap (agent J): daily "Remind me to chant" reminder
  // ---------------------------------------------------------------------------

  /// Fixed id of the jap reminder. Not in [NotificationIds.managed], so
  /// [rescheduleAll] leaves it alone; only [setJapReminder] changes it.
  static const japReminderId = 600;

  /// Schedules (or cancels) the daily jap reminder at [hour]:[minute] local
  /// time. Payload `{type: 'jap'}`. Returns false when notifications are not
  /// permitted (nothing is scheduled then).
  Future<bool> setJapReminder({required bool enabled, required int hour, required int minute}) async {
    try {
      await local.cancel(japReminderId);
    } catch (_) {}
    // Remembered so the master switch can pause and later restore it.
    try {
      final sp = await SharedPreferences.getInstance();
      enabled ? await sp.setString(_japReminderKey, '$hour:$minute') : await sp.remove(_japReminderKey);
    } catch (_) {}
    if (!enabled || !_prefs.master) return true;
    final known = await refreshPermission();
    final granted = known == true || await requestPermission();
    if (!granted) return false;
    final now = _now();
    var when = tz.TZDateTime(now.location, now.year, now.month, now.day, hour.clamp(0, 23), minute.clamp(0, 59));
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    try {
      await local.schedule(PlannedNotification(
        id: japReminderId,
        channel: NotificationChannels.reminders,
        title: 'Time for your jap',
        body: 'A few quiet minutes with your mala brings calm to the whole day.',
        when: when,
        repeat: NotificationRepeat.daily,
        payload: const {'type': 'jap'},
      ));
    } catch (e) {
      debugPrint('Scheduling jap reminder failed: $e');
      return false;
    }
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rescheduleDebounce?.cancel();
    _syncDebounce?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (_started) WidgetsBinding.instance.removeObserver(this);
    backend?.removeListener(_onBackendChanged);
    backend?.logoutHooks.remove(_onLogout);
    rewards?.removeListener(_onRewardsChanged);
    if (RewardsService.onDailyClaimed == markCheckedIn) RewardsService.onDailyClaimed = null;
    if (identical(instance, this)) instance = null;
    super.dispose();
  }
}
