import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../screens/kundli_view_screen.dart' show Vedic;
import '../services/backend_service.dart';
import 'forecast_widgets.dart';

/// Home "Today for you" card: plain-language guidance (good for / be careful /
/// best time) plus "Your planet weather", one simple sentence per planet.
/// Uses the same day forecast as [YourDayCard], so it costs no extra request.
class TodaySimpleCard extends StatefulWidget {
  const TodaySimpleCard({super.key});

  @override
  State<TodaySimpleCard> createState() => _TodaySimpleCardState();
}

class _TodaySimpleCardState extends State<TodaySimpleCard> {
  DayForecast? _day;
  bool _loading = false;
  String? _error;
  String? _profileKey;
  int _token = 0;

  // Slow planets first (they set the tone for weeks or months), then any fast
  // planet doing something clearly good or difficult.
  static const _weatherOrder = ['Saturn', 'Jupiter', 'Rahu', 'Ketu', 'Sun', 'Venus', 'Mars', 'Mercury'];
  static const _maxWeather = 5;

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await service.fetchDayForecast(familyId: activeFamilyId(service), forceRefresh: force);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token) return;
    DayForecast? parsed;
    if (raw != null) {
      try {
        parsed = DayForecast.fromJson(raw);
      } catch (_) {}
    }
    setState(() {
      _loading = false;
      if (parsed != null) {
        _day = parsed;
      } else {
        _error = service.lastError ?? "Couldn't load today's guidance.";
      }
    });
  }

  void _openDay() => Navigator.pushNamed(context, '/forecast', arguments: {'tab': 'day'});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    // Without a Kundli, YourDayCard above already shows the create-Kundli prompt.
    if (kundli == null) return const SizedBox.shrink();

    final key = '${activeFamilyId(service)}|${Vedic.identity(kundli)}';
    if (key != _profileKey) {
      _profileKey = key;
      _day = null;
      _error = null;
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    final day = _day;
    if (day == null) {
      if (_error != null && !_loading) {
        return ForecastCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: ForecastError(message: _error!, onRetry: () => _load(force: true), compact: true),
        );
      }
      return const ForecastCard(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: FC.accent)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _todayCard(day),
        const SizedBox(height: 12),
        _weatherCard(day),
      ],
    );
  }

  // ---------------------------------------------------------------- today
  Widget _todayCard(DayForecast day) {
    // Rahu Kaal gets its own "avoid" time line, so drop it from the list.
    final avoid = day.avoid.where((a) => !a.contains('Rahu Kaal')).take(3).toList();
    final best = day.bestTimes.isNotEmpty ? day.bestTimes.first : null;
    final rahu = day.panchang.rahuKaal.trim();

    return ForecastCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today for you · ${DateFormat('EEE, d MMM').format(day.date)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          if (day.goodFor.isNotEmpty)
            _line('😊', 'A good day for', day.goodFor.take(3).join(' · '), FC.good),
          if (avoid.isNotEmpty) _line('⚠️', 'Be careful with', avoid.join(' · '), FC.bad),
          if (best != null || rahu.isNotEmpty)
            _line(
              '🕐',
              'Your best time today',
              [
                if (best != null) '${best.start} – ${best.end} (${_plainTimeLabel(best.label)})',
                if (rahu.isNotEmpty && rahu != '--') 'Avoid $rahu for new starts (Rahu Kaal)',
              ].join('\n'),
              FC.blue,
            ),
          _line('💡', 'Why', _why(day), FC.accent),
          const SizedBox(height: 4),
          _moreLink('See full day'),
        ],
      ),
    );
  }

  // A link whose text can wrap on narrow screens with large text.
  Widget _moreLink(String text) {
    return InkWell(
      onTap: _openDay,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Flexible(child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _line(String emoji, String label, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 14, height: 1.35, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _plainTimeLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('amrit')) return 'very lucky';
    if (l.contains('abhijit')) return 'lucky midday window';
    if (l.contains('shubh')) return 'auspicious';
    if (l.contains('labh')) return 'good for gains';
    if (l.contains('hora')) return 'good planetary hour';
    return 'good time';
  }

  String _why(DayForecast day) {
    final m = day.moon;
    if (m.chandrashtama) {
      return 'The Moon is in a sensitive spot for you today, so feelings run high. Keep plans simple and rest well.';
    }
    if (m.taraBala.favorable) {
      return 'The Moon is in a friendly star (${m.taraBala.name}) for you today, so things tend to go your way.';
    }
    return 'The Moon is in a testing star (${m.taraBala.name}) for you today. Go slowly and double-check important things.';
  }

  // -------------------------------------------------------------- weather
  List<Transit> _weatherTransits(DayForecast day) {
    final byPlanet = {for (final t in day.transits) t.planet: t};
    final picked = <Transit>[];
    for (final p in _weatherOrder) {
      final t = byPlanet[p];
      if (t == null) continue;
      final slow = Transit.slowPlanets.contains(p);
      if (slow || t.effect != Effect.neutral) picked.add(t);
      if (picked.length == _maxWeather) break;
    }
    return picked;
  }

  String _until(Transit t) {
    final u = t.until;
    if (u == null) return '';
    final sameYear = u.year == DateTime.now().year;
    return 'until ${DateFormat(sameYear ? 'd MMM' : 'MMM yyyy').format(u)}';
  }

  Widget _weatherCard(DayForecast day) {
    final items = _weatherTransits(day);
    if (items.isEmpty) return const SizedBox.shrink();
    return ForecastCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your planet weather', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('How the planets are touching your life right now',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          for (final t in items) _weatherRow(t),
          _moreLink('What does this mean?'),
        ],
      ),
    );
  }

  Widget _weatherRow(Transit t) {
    final color = FC.effect(t.effect);
    final until = _until(t);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showTransit(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.simple, style: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600)),
                  if (until.isNotEmpty)
                    Text(until, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showTransit(Transit t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.simple, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.3)),
                if (_until(t).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_until(t), style: TextStyle(color: Colors.grey.shade600)),
                ],
                if (t.realLife.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('You may notice', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  BulletList(t.realLife),
                ],
                if (t.doList.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('What helps', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  BulletList(t.doList, color: FC.good),
                ],
                if (t.avoidList.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Better to avoid', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  BulletList(t.avoidList, color: FC.bad),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      askAstrologer(this.context, transitQuestion(t));
                    },
                    child: const Text('Ask an astrologer about this'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
