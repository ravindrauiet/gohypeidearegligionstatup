import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../screens/kundli_view_screen.dart' show Vedic;
import '../services/backend_service.dart';
import 'forecast_widgets.dart';

/// Personal "Your Day" summary shown at the top of Home, plus entry tiles for
/// the Life Timeline and the "Why did this happen?" explorer.
class YourDayCard extends StatefulWidget {
  const YourDayCard({super.key});

  @override
  State<YourDayCard> createState() => _YourDayCardState();
}

class _YourDayCardState extends State<YourDayCard> {
  DayForecast? _day;
  bool _loading = false;
  String? _error;
  bool _noKundli = false;
  String? _profileKey;
  int _token = 0;

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _noKundli = false;
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
        _noKundli = service.lastErrorCode == 'NO_KUNDLI';
        _error = service.lastError ?? "Couldn't load your day.";
      }
    });
  }

  void _openForecast(String tab) =>
      Navigator.pushNamed(context, '/forecast', arguments: {'tab': tab});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = Vedic.activeKundli(service);
    final key = '${activeFamilyId(service)}|${kundli == null ? '' : Vedic.identity(kundli)}';
    if (key != _profileKey) {
      _profileKey = key;
      _day = null;
      _error = null;
      _noKundli = false;
      if (kundli != null) {
        _loading = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      } else {
        _token++;
        _loading = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kundli == null || (_noKundli && _day == null))
          _createKundliCta()
        else if (_day != null)
          _dayCard(_day!)
        else if (_error != null && !_loading)
          ForecastCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: ForecastError(message: "Couldn't load your day. $_error", onRetry: () => _load(force: true), compact: true),
          )
        else
          _skeleton(),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _EntryTile(
                icon: Icons.timeline_rounded,
                color: FC.violet,
                title: 'Life Timeline',
                subtitle: 'Sade Sati, dashas & big transits',
                onTap: () => Navigator.pushNamed(context, '/life-timeline'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EntryTile(
                icon: Icons.manage_search_rounded,
                color: FC.accent,
                title: 'Why did this happen?',
                subtitle: 'Decode any date of your life',
                onTap: () => Navigator.pushNamed(context, '/date-explorer'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _skeleton() => Semantics(
        label: 'Loading your day',
        child: Container(
          height: 210,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [FC.heroA.withValues(alpha: 0.85), FC.heroB.withValues(alpha: 0.85)]),
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: FC.accent)),
              SizedBox(height: 12),
              Text('Reading your chart for today…', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _createKundliCta() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [FC.heroA, FC.heroB], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR DAY, DECODED',
              style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          const Text('See how today, this week and this month unfold for you',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 6),
          const Text(
            'Add your birth details and we will read your own Kundli, dasha and planetary transits every day.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/birth-details'),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Create my Kundli'),
            style: ElevatedButton.styleFrom(
              backgroundColor: FC.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCard(DayForecast d) {
    final moodColor = FC.moodOnDark(d.summary.mood);
    final tara = d.moon.taraBala;
    final hint = d.moon.chandrashtama
        ? 'Chandrashtama today: go gently, avoid big decisions.'
        : (tara.name.isNotEmpty
            ? '${tara.name} Tara: ${tara.favorable ? 'a supportive star for you today.' : 'a testing star, so be patient.'}'
            : '');

    return Semantics(
      container: true,
      label: 'Your day: ${d.summary.headline}. Score ${d.summary.overallScore} out of 100',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _openForecast('day'),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [FC.heroA, FC.heroB], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: FC.heroA.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR DAY · ${FC.date(d.date, 'EEE d MMM').toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            d.summary.headline.isEmpty ? 'Your personal guidance is ready' : d.summary.headline,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25),
                          ),
                          const SizedBox(height: 8),
                          Pill(Mood.label(d.summary.mood), color: moodColor),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ScoreRing(score: d.summary.overallScore, color: moodColor, size: 74),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final k in LifeArea.all)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Semantics(
                            label: '${LifeArea.label(k)} ${d.scores[k].score}',
                            child: ExcludeSemantics(
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 14,
                                    child: FittedBox(
                                      child: Text(LifeArea.label(k),
                                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: d.scores[k].score / 100),
                                    duration: const Duration(milliseconds: 700),
                                    builder: (context, v, _) => ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: v,
                                        minHeight: 5,
                                        color: FC.area(k),
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        d.moon.chandrashtama ? Icons.warning_amber_rounded : Icons.nightlight_round,
                        size: 15,
                        color: d.moon.chandrashtama ? const Color(0xFFFCA5A5) : const Color(0xFFC4B5FD),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _quick('Today', 'day')),
                    const SizedBox(width: 8),
                    Expanded(child: _quick('Week', 'week')),
                    const SizedBox(width: 8),
                    Expanded(child: _quick('Month', 'month')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quick(String label, String tab) {
    return Semantics(
      button: true,
      label: 'Open $label forecast',
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openForecast(tab),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Center(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _EntryTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.2)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}
