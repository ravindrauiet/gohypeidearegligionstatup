import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/buddy/buddy_chat_screen.dart';
import '../screens/buddy/buddy_hub_tab.dart';
import '../screens/guides/guide_detail_screen.dart';
import '../screens/guides/guides_screen.dart';
import '../screens/home_screen.dart';
import '../screens/muhurat/muhurat_finder_screen.dart';
import '../screens/jap/jap_counter_screen.dart';
import '../screens/meetups/meetup_detail_screen.dart';
import '../screens/meetups/meetups_screen.dart';
import '../screens/trust/family_notes_screen.dart';
import '../screens/trust/verification_screen.dart';
import '../screens/notifications/notification_inbox_screen.dart';
import '../screens/rewards/coins_screen.dart';
import '../screens/rewards/mindset_quiz_screen.dart';
import '../screens/rewards/temple_trip_screen.dart';
import '../screens/videos/playlist_screen.dart';
import '../screens/videos/videos_screen.dart';
import '../utils/app_routes.dart';
import 'backend_service.dart';
import 'buddy_service.dart';

/// Where a notification payload leads (see the payload table in the contract).
enum NotificationDestination {
  home,
  buddyRequests,
  buddyDiscover,
  buddyChat,
  templeTrip,
  coins,
  forecast,
  videos,
  playlist,
  mindset,
  inbox,
  jap,
  meetup,
  verification,
  familyNotes,
  guide,
  muhurat,
}

/// A resolved deep link: the destination plus the ids it needs.
class NotificationTarget {
  final NotificationDestination destination;
  final int? connectionId;
  final String? playlistId;
  final String? title;
  final int? meetupId;
  final String? itemId;

  const NotificationTarget(this.destination, {this.connectionId, this.playlistId, this.title, this.meetupId, this.itemId});

  @override
  String toString() => 'NotificationTarget($destination, connectionId: $connectionId, playlistId: $playlistId)';
}

/// Opens the screen a notification (local, push or inbox item) points at.
///
/// [open] is safe to call at any time: until the [HomeScreen] is mounted (the
/// user is past splash / login / onboarding) the latest payload is queued and
/// replayed by [onHomeReady].
class NotificationRouter {
  NotificationRouter._();

  /// Attached to the app's MaterialApp.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Map<String, dynamic>? _pending;
  static bool _homeReady = false;

  /// Test hook: when set, resolved targets are handed here instead of being
  /// navigated to.
  @visibleForTesting
  static FutureOr<void> Function(NotificationTarget target)? debugHandler;

  /// Payload waiting for the Home screen (exposed for tests).
  @visibleForTesting
  static Map<String, dynamic>? get pending => _pending;

  @visibleForTesting
  static void debugReset() {
    _pending = null;
    _homeReady = false;
    debugHandler = null;
  }

  static int? _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}');

  static String? _str(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Maps a payload to its destination. Unknown / missing type → Home.
  static NotificationTarget resolve(Map<String, dynamic> data) {
    final type = _str(data['type'])?.toLowerCase();
    switch (type) {
      case 'buddy_request':
        return NotificationTarget(NotificationDestination.buddyRequests, connectionId: _int(data['connectionId']));
      case 'buddy_accepted':
      case 'buddy_message':
        final id = _int(data['connectionId']);
        if (id == null) return const NotificationTarget(NotificationDestination.buddyRequests);
        return NotificationTarget(NotificationDestination.buddyChat, connectionId: id, title: _str(data['name']));
      case 'nearby_buddy':
        return const NotificationTarget(NotificationDestination.buddyDiscover);
      case 'trip_update':
        return const NotificationTarget(NotificationDestination.templeTrip);
      case 'coins':
        return const NotificationTarget(NotificationDestination.coins);
      case 'daily_horoscope':
        return const NotificationTarget(NotificationDestination.forecast);
      case 'videos':
        final pid = _str(data['playlistId']);
        if (pid != null) {
          return NotificationTarget(NotificationDestination.playlist, playlistId: pid, title: _str(data['title']));
        }
        return const NotificationTarget(NotificationDestination.videos);
      case 'mindset':
        return const NotificationTarget(NotificationDestination.mindset);
      case 'jap':
        return const NotificationTarget(NotificationDestination.jap);
      case 'meetup_update':
        final mid = _int(data['meetupId']);
        if (mid == null) return const NotificationTarget(NotificationDestination.meetup);
        return NotificationTarget(NotificationDestination.meetup, meetupId: mid);
      case 'verification_update':
        return const NotificationTarget(NotificationDestination.verification);
      case 'family_note':
        return const NotificationTarget(NotificationDestination.familyNotes);
      case 'guide':
        return NotificationTarget(NotificationDestination.guide, itemId: _str(data['guideId']));
      case 'muhurat':
        return NotificationTarget(NotificationDestination.muhurat, itemId: _str(data['event']));
      case 'announcement':
      case 'inbox':
        return const NotificationTarget(NotificationDestination.inbox);
      case 'checkin':
      case 'festival':
      default:
        return const NotificationTarget(NotificationDestination.home);
    }
  }

  /// Opens the destination for [data], or queues it until Home is ready.
  static Future<void> open(Map<String, dynamic> data) async {
    if (!_homeReady || navigatorKey.currentState == null && debugHandler == null) {
      _pending = Map<String, dynamic>.from(data);
      return;
    }
    await _go(resolve(data));
  }

  /// Called by [HomeScreen] once it is mounted; replays a queued payload.
  static void onHomeReady() {
    _homeReady = true;
    final p = _pending;
    _pending = null;
    if (p != null) {
      // Let the first Home frame settle before pushing on top of it.
      WidgetsBinding.instance.addPostFrameCallback((_) => open(p));
    }
  }

  /// Called by [HomeScreen] when it is disposed (logout, account switch).
  static void onHomeGone() => _homeReady = false;

  static Future<void> _go(NotificationTarget t) async {
    final handler = debugHandler;
    if (handler != null) {
      await handler(t);
      return;
    }
    final nav = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    if (nav == null || context == null) return;

    void push(Widget page) => nav.push(MaterialPageRoute(builder: (_) => page));
    void toHome() => nav.popUntil((r) => r.settings.name == AppRoutes.home || r.isFirst);
    void tab(int index) {
      toHome();
      final home = HomeScreenState.current;
      if (home != null) HomeScreen.switchTab(home.context, index);
    }

    void buddySection(int section) {
      BuddyHubTab.sectionNotifier.value = section;
      tab(4);
    }

    switch (t.destination) {
      case NotificationDestination.home:
        tab(0);
      case NotificationDestination.buddyRequests:
        buddySection(BuddyHubSection.requests);
      case NotificationDestination.buddyDiscover:
        buddySection(BuddyHubSection.discover);
      case NotificationDestination.buddyChat:
        final id = t.connectionId!;
        if (BuddyChatScreen.openConnectionId.value == id) return;
        final buddy = context.read<BuddyService>();
        try {
          final conns = await buddy.loadConnections(fresh: true);
          final match = conns.buddies.where((c) => c.id == id).toList();
          if (match.isNotEmpty) {
            toHome();
            push(BuddyChatScreen(connection: match.first));
            return;
          }
        } catch (e) {
          debugPrint('NotificationRouter: could not load buddy connections: $e');
        }
        buddySection(BuddyHubSection.buddies);
      case NotificationDestination.templeTrip:
        push(const TempleTripScreen());
      case NotificationDestination.coins:
        push(CoinsScreen(onOpenVideos: () => push(const VideosScreen())));
      case NotificationDestination.forecast:
        final backend = context.read<BackendService>();
        if (backend.hasBirthDetails) {
          nav.pushNamed(AppRoutes.forecast);
        } else {
          tab(0);
        }
      case NotificationDestination.videos:
        push(const VideosScreen());
      case NotificationDestination.playlist:
        push(PlaylistScreen(playlistId: t.playlistId!, title: t.title ?? 'Playlist'));
      case NotificationDestination.mindset:
        push(const MindsetQuizScreen());
      case NotificationDestination.inbox:
        push(const NotificationInboxScreen());
      case NotificationDestination.jap:
        push(const JapCounterScreen());
      case NotificationDestination.meetup:
        final mid = t.meetupId;
        push(mid == null ? const MeetupsScreen() : MeetupDetailScreen(meetupId: mid));
      case NotificationDestination.verification:
        push(const VerificationScreen());
      case NotificationDestination.familyNotes:
        push(const FamilyNotesScreen());
      case NotificationDestination.guide:
        final id = t.itemId;
        push(id == null ? const GuidesScreen() : GuideDetailScreen(guideId: id));
      case NotificationDestination.muhurat:
        push(MuhuratFinderScreen(initialEventId: t.itemId, onAskPandit: () => tab(3)));
    }
  }
}
