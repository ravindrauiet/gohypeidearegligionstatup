import 'package:timezone/timezone.dart' as tz;

/// Pure scheduling rules for on-device reminders (no plugin, no I/O), so the
/// timing logic can be unit tested. [NotificationService] turns the plan into
/// real scheduled notifications.

/// Android channel ids (also used to group iOS threads).
class NotificationChannels {
  NotificationChannels._();
  static const reminders = 'reminders';
  static const buddy = 'buddy';
  static const rewards = 'rewards';
  static const festivals = 'festivals';
  static const announcements = 'announcements';
}

/// Fixed notification ids per category, so rescheduling replaces instead of
/// duplicating.
class NotificationIds {
  NotificationIds._();
  static const dailyHoroscope = 100;
  static const checkinBase = 200; // 200..202
  static const checkinCount = 3;
  static const festivalBase = 300; // 300..315 (eve, morning) x 8 days
  static const festivalDays = 8;
  static const reengage3 = 400;
  static const reengage7 = 401;
  static const mindsetWeekly = 500;

  /// Foreground pushes: per-chat ids (collapse) and a rolling range for the rest.
  static const chatBase = 20000;
  static const pushBase = 30000;

  /// Every id the scheduler owns (cancelled when not part of the plan).
  static List<int> get managed => [
        dailyHoroscope,
        for (var i = 0; i < checkinCount; i++) checkinBase + i,
        for (var i = 0; i < festivalDays * 2; i++) festivalBase + i,
        reengage3,
        reengage7,
        mindsetWeekly,
      ];
}

enum NotificationRepeat { none, daily, weekly }

/// User notification preferences (stored locally; a subset is synced to the server).
class NotificationPrefs {
  final bool master;
  final bool horoscope;
  final int horoscopeHour;
  final int horoscopeMinute;
  final bool checkin; // check-in & coins ("rewards" on the server)
  final bool festivals;
  final bool nudges; // re-engagement + weekly mindset nudge
  final bool buddy;
  final bool messages;
  final bool trips;
  final bool announcements;

  const NotificationPrefs({
    this.master = true,
    this.horoscope = true,
    this.horoscopeHour = 7,
    this.horoscopeMinute = 30,
    this.checkin = true,
    this.festivals = true,
    this.nudges = true,
    this.buddy = true,
    this.messages = true,
    this.trips = true,
    this.announcements = true,
  });

  NotificationPrefs copyWith({
    bool? master,
    bool? horoscope,
    int? horoscopeHour,
    int? horoscopeMinute,
    bool? checkin,
    bool? festivals,
    bool? nudges,
    bool? buddy,
    bool? messages,
    bool? trips,
    bool? announcements,
  }) =>
      NotificationPrefs(
        master: master ?? this.master,
        horoscope: horoscope ?? this.horoscope,
        horoscopeHour: horoscopeHour ?? this.horoscopeHour,
        horoscopeMinute: horoscopeMinute ?? this.horoscopeMinute,
        checkin: checkin ?? this.checkin,
        festivals: festivals ?? this.festivals,
        nudges: nudges ?? this.nudges,
        buddy: buddy ?? this.buddy,
        messages: messages ?? this.messages,
        trips: trips ?? this.trips,
        announcements: announcements ?? this.announcements,
      );

  Map<String, dynamic> toJson() => {
        'master': master,
        'horoscope': horoscope,
        'horoscopeHour': horoscopeHour,
        'horoscopeMinute': horoscopeMinute,
        'checkin': checkin,
        'festivals': festivals,
        'nudges': nudges,
        'buddy': buddy,
        'messages': messages,
        'trips': trips,
        'announcements': announcements,
      };

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    int i(String k, int d, int max) {
      final v = j[k];
      final n = v is int ? v : int.tryParse('${v ?? ''}');
      return (n == null || n < 0 || n > max) ? d : n;
    }

    return NotificationPrefs(
      master: b('master', true),
      horoscope: b('horoscope', true),
      horoscopeHour: i('horoscopeHour', 7, 23),
      horoscopeMinute: i('horoscopeMinute', 30, 59),
      checkin: b('checkin', true),
      festivals: b('festivals', true),
      nudges: b('nudges', true),
      buddy: b('buddy', true),
      messages: b('messages', true),
      trips: b('trips', true),
      announcements: b('announcements', true),
    );
  }

  /// Body for `PUT /notifications/prefs`.
  Map<String, bool> toServer() => {
        'buddy': buddy,
        'messages': messages,
        'trips': trips,
        'rewards': checkin,
        'announcements': announcements,
      };

  /// Adopts the server-side categories from a `GET /notifications/prefs` body.
  NotificationPrefs mergeServer(Map<String, dynamic> s) {
    bool? b(String k) => s[k] is bool ? s[k] as bool : null;
    return copyWith(
      buddy: b('buddy'),
      messages: b('messages'),
      trips: b('trips'),
      checkin: b('rewards'),
      announcements: b('announcements'),
    );
  }

  /// Whether a pushed payload of [type] may be shown (local category toggle).
  bool allowsPushType(String? type) {
    if (!master) return false;
    switch (type) {
      case 'buddy_request':
      case 'buddy_accepted':
      case 'nearby_buddy':
        return buddy;
      case 'buddy_message':
        return messages;
      case 'trip_update':
        return trips;
      case 'coins':
      case 'checkin':
        return checkin;
      case 'festival':
        return festivals;
      case 'daily_horoscope':
        return horoscope;
      case 'announcement':
        return announcements;
      default:
        return true;
    }
  }
}

/// A Panchang day with one or more festivals / vrats.
class FestivalItem {
  final DateTime date; // local calendar date
  final String name;

  const FestivalItem(this.date, this.name);

  Map<String, dynamic> toJson() => {'date': _ymd(date), 'name': name};

  static FestivalItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    final d = DateTime.tryParse('${j['date'] ?? ''}');
    final n = '${j['name'] ?? ''}'.trim();
    if (d == null || n.isEmpty) return null;
    return FestivalItem(DateTime(d.year, d.month, d.day), n);
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One notification to schedule.
class PlannedNotification {
  final int id;
  final String channel;
  final String title;
  final String body;
  final tz.TZDateTime when;
  final NotificationRepeat repeat;
  final Map<String, String> payload;

  const PlannedNotification({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.when,
    this.repeat = NotificationRepeat.none,
    required this.payload,
  });

  @override
  String toString() => 'Planned($id, $when, $title)';
}

/// Everything the scheduler needs to know about the user right now.
class ScheduleInput {
  final tz.TZDateTime now;
  final NotificationPrefs prefs;

  /// Registered (non-guest) user: coins, check-in and mindset need an account.
  final bool registered;
  final bool checkedInToday;
  final int streakDays;
  final String? moonSign;
  final List<FestivalItem> festivals;

  /// Unanswered mindset questions (null = unknown, treated as some remain).
  final int? mindsetRemaining;
  final int coinsPerQuestion;

  const ScheduleInput({
    required this.now,
    required this.prefs,
    this.registered = false,
    this.checkedInToday = false,
    this.streakDays = 0,
    this.moonSign,
    this.festivals = const [],
    this.mindsetRemaining,
    this.coinsPerQuestion = 50,
  });
}

class NotificationSchedule {
  NotificationSchedule._();

  static const checkinHour = 19, checkinMinute = 30;
  static const festivalEveHour = 18, festivalMorningHour = 7;
  static const festivalWindowDays = 30;
  static const mindsetWeekday = DateTime.sunday, mindsetHour = 11;

  /// Re-engagement reminders land between these hours (local).
  static const quietEndHour = 9, quietStartHour = 21, reengageHour = 10;

  static tz.TZDateTime _at(tz.TZDateTime day, int dayOffset, int hour, int minute) =>
      tz.TZDateTime(day.location, day.year, day.month, day.day + dayOffset, hour, minute);

  /// Next occurrence of [hour]:[minute] strictly after [now].
  static tz.TZDateTime nextAt(tz.TZDateTime now, int hour, int minute) {
    var t = _at(now, 0, hour, minute);
    if (!t.isAfter(now)) t = _at(now, 1, hour, minute);
    return t;
  }

  /// Check-in reminders: the next 19:30 the user still needs (today only if
  /// not checked in yet and it is still before 19:30), then the two following
  /// days as a safety net in case the app is not opened.
  static List<tz.TZDateTime> checkinTimes(tz.TZDateTime now, {required bool checkedInToday}) {
    final today = _at(now, 0, checkinHour, checkinMinute);
    final first = (!checkedInToday && today.isAfter(now)) ? 0 : 1;
    return [for (var i = 0; i < NotificationIds.checkinCount; i++) _at(now, first + i, checkinHour, checkinMinute)];
  }

  /// Evening before (18:00) and morning of (07:00) a festival day, keeping only
  /// times still in the future.
  static List<tz.TZDateTime> festivalTimes(tz.TZDateTime now, DateTime festivalDay) {
    final day = tz.TZDateTime(now.location, festivalDay.year, festivalDay.month, festivalDay.day);
    return [_at(day, -1, festivalEveHour, 0), _at(day, 0, festivalMorningHour, 0)]
        .where((t) => t.isAfter(now))
        .toList();
  }

  /// [days] after [now], moved out of the night (21:00–09:00) to 10:00.
  static tz.TZDateTime reengageTime(tz.TZDateTime now, int days) {
    final t = now.add(Duration(days: days));
    if (t.hour < quietEndHour) return _at(t, 0, reengageHour, 0);
    if (t.hour >= quietStartHour) return _at(t, 1, reengageHour, 0);
    return t;
  }

  /// Next [weekday] at [hour]:00 strictly after [now].
  static tz.TZDateTime nextWeekday(tz.TZDateTime now, int weekday, int hour, [int minute = 0]) {
    var t = _at(now, (weekday - now.weekday) % 7, hour, minute);
    if (!t.isAfter(now)) t = _at(t, 7, hour, minute);
    return t;
  }

  /// Upcoming festival days within the window, grouped per day, soonest first.
  static List<MapEntry<DateTime, List<String>>> upcomingFestivalDays(tz.TZDateTime now, List<FestivalItem> items) {
    final today = DateTime(now.year, now.month, now.day);
    final byDay = <DateTime, List<String>>{};
    for (final f in items) {
      final d = DateTime(f.date.year, f.date.month, f.date.day);
      final diff = d.difference(today).inDays;
      if (diff < 0 || diff > festivalWindowDays) continue;
      final names = byDay.putIfAbsent(d, () => []);
      if (!names.contains(f.name)) names.add(f.name);
    }
    final days = byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return days.take(NotificationIds.festivalDays).toList();
  }

  static String _join(List<String> names) {
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    return '${names.take(2).join(', ')} & more';
  }

  static const _reengageTypes = ['daily_horoscope', 'mindset', 'videos'];

  /// The full set of reminders for [input]. Empty when the master toggle is off.
  static List<PlannedNotification> plan(ScheduleInput input) {
    final p = input.prefs;
    final now = input.now;
    final out = <PlannedNotification>[];
    if (!p.master) return out;

    if (p.horoscope) {
      final moon = input.moonSign?.trim();
      out.add(PlannedNotification(
        id: NotificationIds.dailyHoroscope,
        channel: NotificationChannels.reminders,
        title: 'Your daily horoscope is ready',
        body: (moon != null && moon.isNotEmpty)
            ? 'Good morning! See what today holds for your $moon Moon.'
            : 'Good morning! See what the stars hold for you today.',
        when: nextAt(now, p.horoscopeHour, p.horoscopeMinute),
        repeat: NotificationRepeat.daily,
        payload: const {'type': 'daily_horoscope'},
      ));
    }

    if (p.checkin && input.registered) {
      final times = checkinTimes(now, checkedInToday: input.checkedInToday);
      for (var i = 0; i < times.length; i++) {
        // The streak survives only until the first reminder is missed.
        final keepStreak = i == 0 && input.streakDays > 0;
        out.add(PlannedNotification(
          id: NotificationIds.checkinBase + i,
          channel: NotificationChannels.rewards,
          title: keepStreak ? 'Keep your ${input.streakDays}-day streak' : 'Your daily coins are waiting',
          body: keepStreak
              ? "Check in today to keep your streak going and collect today's coins."
              : 'Check in today to collect your coins and start a new streak.',
          when: times[i],
          payload: const {'type': 'checkin'},
        ));
      }
    }

    if (p.festivals) {
      final days = upcomingFestivalDays(now, input.festivals);
      for (var i = 0; i < days.length; i++) {
        final day = days[i].key;
        final label = _join(days[i].value);
        final date = _ymd(day);
        final times = festivalTimes(now, day);
        for (final t in times) {
          final eve = t.day != day.day || t.month != day.month;
          out.add(PlannedNotification(
            id: NotificationIds.festivalBase + i * 2 + (eve ? 0 : 1),
            channel: NotificationChannels.festivals,
            title: eve ? 'Tomorrow: $label' : 'Today: $label',
            body: eve
                ? 'Get ready for $label tomorrow. Tap for timings and rituals.'
                : 'Wishing you a blessed $label. Tap for today\'s Panchang.',
            when: t,
            payload: {'type': 'festival', 'name': label, 'date': date},
          ));
        }
      }
    }

    if (p.nudges) {
      final types = input.registered ? _reengageTypes : const ['daily_horoscope', 'videos'];
      final dayOfYear = now.difference(tz.TZDateTime(now.location, now.year)).inDays;
      for (final entry in const [(NotificationIds.reengage3, 3), (NotificationIds.reengage7, 7)]) {
        final type = types[(dayOfYear + entry.$2) % types.length];
        final copy = _reengageCopy(type, input);
        out.add(PlannedNotification(
          id: entry.$1,
          channel: NotificationChannels.reminders,
          title: copy.$1,
          body: copy.$2,
          when: reengageTime(now, entry.$2),
          payload: {'type': type},
        ));
      }

      final remaining = input.mindsetRemaining;
      if (input.registered && (remaining == null || remaining > 0)) {
        final n = remaining == null ? 3 : (remaining < 3 ? remaining : 3);
        out.add(PlannedNotification(
          id: NotificationIds.mindsetWeekly,
          channel: NotificationChannels.rewards,
          title: 'Answer $n question${n == 1 ? '' : 's'}, earn ${n * input.coinsPerQuestion} coins',
          body: 'A few quick mindset questions help us personalise your guidance.',
          when: nextWeekday(now, mindsetWeekday, mindsetHour),
          repeat: NotificationRepeat.weekly,
          payload: const {'type': 'mindset'},
        ));
      }
    }
    return out;
  }

  static (String, String) _reengageCopy(String type, ScheduleInput input) {
    switch (type) {
      case 'mindset':
        final n = 3 * input.coinsPerQuestion;
        return ('Your stars have shifted', 'Answer 3 quick questions and earn $n coins.');
      case 'videos':
        return ('Take a calm minute', 'Devotional videos and aartis are waiting for you.');
      default:
        return ('Your stars have shifted', 'See what the planets have in store for you this week.');
    }
  }
}
