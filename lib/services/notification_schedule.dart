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

  /// The daily plan: [dailyPlanBase] + day * 10 + slot (day 0..planDays-1, slot 0..4).
  static const dailyPlanBase = 1000;
  static const planDays = 10;
  static const slotsPerDay = 5;
  static int planId(int day, int slot) => dailyPlanBase + day * 10 + slot;

  /// Foreground pushes: per-chat ids (collapse) and a rolling range for the rest.
  static const chatBase = 20000;
  static const pushBase = 30000;

  /// Every id the scheduler owns (cancelled when not part of the plan). The
  /// older per-category ids stay listed so upgrading users get them cleared.
  static List<int> get managed => [
        dailyHoroscope,
        for (var i = 0; i < checkinCount; i++) checkinBase + i,
        for (var i = 0; i < festivalDays * 2; i++) festivalBase + i,
        reengage3,
        reengage7,
        mindsetWeekly,
        for (var d = 0; d < planDays; d++)
          for (var s = 0; s < slotsPerDay; s++) planId(d, s),
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
    this.horoscopeHour = 10,
    this.horoscopeMinute = 0,
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
      horoscopeHour: i('horoscopeHour', 10, 23),
      horoscopeMinute: i('horoscopeMinute', 0, 59),
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

  // -------------------------------------------------------------- daily plan

  /// Every scheduled reminder lands inside this India-time window.
  static const windowStartHour = 10, windowEndHour = 22;

  /// The five daily slots (IST). Slot 0 follows the user's horoscope time,
  /// kept between 10:00 and 12:00.
  static const List<(int, int)> slotTimes = [(10, 0), (13, 0), (16, 30), (19, 30), (21, 15)];
  static const horoscopeLatestHour = 12;

  static tz.Location get ist => tz.getLocation('Asia/Kolkata');

  /// The user's horoscope time clamped into 10:00–12:00.
  static (int, int) horoscopeSlot(NotificationPrefs p) {
    final mins = (p.horoscopeHour * 60 + p.horoscopeMinute).clamp(windowStartHour * 60, horoscopeLatestHour * 60);
    return (mins ~/ 60, mins % 60);
  }

  /// [t] moved into the 10:00–22:00 IST window, never later than [t]: too
  /// early → 21:30 the evening before, too late → 21:30 the same day.
  static tz.TZDateTime clampEarlierIntoWindow(tz.TZDateTime t) {
    final i = tz.TZDateTime.from(t, ist);
    if (i.hour < windowStartHour) return tz.TZDateTime(ist, i.year, i.month, i.day - 1, 21, 30);
    if (i.hour >= windowEndHour) return tz.TZDateTime(ist, i.year, i.month, i.day, 21, 30);
    return i;
  }

  /// The full set of reminders for [input]: up to five a day for the next
  /// [NotificationIds.planDays] days, all between 10:00 and 22:00 IST. Empty
  /// when the master toggle is off.
  static List<PlannedNotification> plan(ScheduleInput input) {
    final p = input.prefs;
    final out = <PlannedNotification>[];
    if (!p.master) return out;

    final now = tz.TZDateTime.from(input.now, ist);
    final festivalsByDay = <DateTime, List<String>>{
      for (final e in upcomingFestivalDays(now, input.festivals)) e.key: e.value,
    };
    final dayOfYear = now.difference(tz.TZDateTime(ist, now.year)).inDays;
    final remaining = input.mindsetRemaining;
    final mindsetLeft = remaining == null || remaining > 0;

    for (var d = 0; d < NotificationIds.planDays; d++) {
      final date = DateTime(now.year, now.month, now.day + d);
      final today = festivalsByDay[date];
      final tomorrow = festivalsByDay[DateTime(date.year, date.month, date.day + 1)];
      final r = dayOfYear + d; // rotation index, so copy changes every day

      for (var s = 0; s < NotificationIds.slotsPerDay; s++) {
        final (h, m) = s == 0 ? horoscopeSlot(p) : slotTimes[s];
        final when = tz.TZDateTime(ist, date.year, date.month, date.day, h, m);
        if (!when.isAfter(now)) continue;
        final item = _slotItem(s, d, r, input, today, tomorrow, mindsetLeft);
        if (item == null) continue;
        out.add(PlannedNotification(
          id: NotificationIds.planId(d, s),
          channel: item.channel,
          title: item.title,
          body: item.body,
          when: when,
          payload: item.payload,
        ));
      }
    }
    return out;
  }

  static _Slot? _slotItem(int slot, int day, int r, ScheduleInput input, List<String>? today, List<String>? tomorrow,
      bool mindsetLeft) {
    final p = input.prefs;
    switch (slot) {
      case 0: // Morning: today's festival, else the horoscope.
        if (p.festivals && today != null) {
          final label = _join(today);
          return _Slot(NotificationChannels.festivals, 'Today: $label',
              "Wishing you a blessed $label. Tap for today's Panchang and rituals.", {'type': 'festival', 'name': label});
        }
        if (!p.horoscope) return null;
        final moon = input.moonSign?.trim();
        final hasMoon = moon != null && moon.isNotEmpty;
        const titles = ['Your day is ready', "Today's guidance is here", 'Good morning! Your stars today'];
        return _Slot(
          NotificationChannels.reminders,
          titles[r % titles.length],
          hasMoon ? 'See what today holds for your $moon Moon.' : 'See what the stars hold for you today.',
          const {'type': 'daily_horoscope'},
        );
      case 1: // Afternoon: something calm and devotional.
        if (!p.nudges) return null;
        const items = [
          ('Take a calm minute', 'Bhajans, aarti and katha are waiting for you. Earn 1 coin per new video.', 'videos'),
          ('Puja made simple', 'Step-by-step puja and vrat guides with a samagri checklist.', 'guide'),
          ('A mala before lunch?', 'Count 108 for your mantra and earn 5 coins.', 'jap'),
          ('Planning something big?', 'Find the best day for griha pravesh, a vehicle or a new job.', 'muhurat'),
        ];
        final it = items[r % items.length];
        return _Slot(_channelFor(it.$3), it.$1, it.$2, {'type': it.$3});
      case 2: // Late afternoon: people and rewards.
        if (!p.nudges) return null;
        final items = <(String, String, String)>[
          ('Someone may be looking for you', 'New buddies matched on Kundli and mindset are waiting.', 'nearby_buddy'),
          ('Satsang near you', 'Join a small group aarti or bhajan this week and meet people safely.', 'meetup_update'),
          if (input.registered && mindsetLeft)
            ('Earn ${input.coinsPerQuestion} coins in a minute', 'Answer a quick mindset question for better matches.', 'mindset'),
          ('Play & earn', 'A quick game pays up to 10 coins today.', 'games'),
          if (input.registered) ('Your temple trip is getting closer', 'See how many coins you need for a free trip.', 'trip_update'),
        ];
        final it = items[r % items.length];
        return _Slot(_channelFor(it.$3), it.$1, it.$2, {'type': it.$3});
      case 3: // Evening: daily coins / streak.
        if (p.checkin && input.registered && !(day == 0 && input.checkedInToday)) {
          // The next check-in that can still keep the streak alive.
          final keepStreak = input.streakDays > 0 && day == (input.checkedInToday ? 1 : 0);
          return _Slot(
            NotificationChannels.rewards,
            keepStreak ? 'Keep your ${input.streakDays}-day streak' : 'Your daily coins are waiting',
            keepStreak
                ? "Check in today to keep your streak going and collect today's coins."
                : 'Check in today to collect your coins and build a streak.',
            const {'type': 'checkin'},
          );
        }
        if (!p.nudges) return null;
        return const _Slot(NotificationChannels.reminders, 'Sandhya aarti time',
            'Close the day with a peaceful aarti.', {'type': 'videos'});
      case 4: // Night: tomorrow's festival, else a calm close.
        if (p.festivals && tomorrow != null) {
          final label = _join(tomorrow);
          return _Slot(NotificationChannels.festivals, 'Tomorrow: $label',
              'Get ready for $label tomorrow. Tap for the puja guide and timings.', {'type': 'festival', 'name': label});
        }
        if (!p.nudges) return null;
        const items = [
          ('End the day with a mala', 'A few quiet minutes of jap brings calm sleep.', 'jap'),
          ("Tomorrow's Panchang", 'See tithi, Rahu Kaal and good timings before you plan your day.', 'panchang'),
          ('Your stars have shifted', 'See what the planets have in store for you this week.', 'daily_horoscope'),
        ];
        final it = items[r % items.length];
        return _Slot(_channelFor(it.$3), it.$1, it.$2, {'type': it.$3});
    }
    return null;
  }

  static String _channelFor(String type) => switch (type) {
        'nearby_buddy' || 'meetup_update' || 'trip_update' => NotificationChannels.buddy,
        'mindset' || 'games' || 'jap' || 'checkin' => NotificationChannels.rewards,
        'guide' || 'muhurat' || 'panchang' || 'festival' => NotificationChannels.festivals,
        _ => NotificationChannels.reminders,
      };
}

class _Slot {
  final String channel;
  final String title;
  final String body;
  final Map<String, String> payload;
  const _Slot(this.channel, this.title, this.body, this.payload);
}
