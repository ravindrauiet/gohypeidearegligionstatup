import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/game_widgets.dart';

/// Graha Quest: the player's nine planets as a team of characters, and three
/// real-life missions a day chosen from today's sky and the player's chart.
class GrahaQuestScreen extends StatefulWidget {
  const GrahaQuestScreen({super.key});

  @override
  State<GrahaQuestScreen> createState() => _GrahaQuestScreenState();
}

class _GrahaQuestScreenState extends State<GrahaQuestScreen> with WidgetsBindingObserver {
  /// Last state confirmed by the server.
  GameState? _server;

  /// Missions tapped "done" whose request is still in flight (optimistic UI).
  final Set<String> _pending = {};

  bool _loading = true;
  bool _noKundli = false;
  String? _error;
  int _token = 0;
  String _loadedDay = '';
  String? _planetBanner;

  final GlobalKey _xpBarKey = GlobalKey();
  final Map<String, GlobalKey> _missionKeys = {};

  static const _milestones = [3, 7, 14, 21, 30, 50, 75, 100, 150, 200, 365];

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // After midnight yesterday's missions are gone: fetch today's.
    if (state == AppLifecycleState.resumed && mounted && _loadedDay.isNotEmpty && _loadedDay != _today()) {
      _load(force: true);
    }
  }

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    final token = ++_token;
    if (_server == null) {
      setState(() {
        _loading = true;
        _error = null;
        _noKundli = false;
      });
    }
    Map<String, dynamic>? raw;
    try {
      raw = await service.fetchGameState(forceRefresh: force);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token) return;
    setState(() {
      _loading = false;
      if (raw != null) {
        _server = GameState.fromJson(raw);
        _error = null;
        _noKundli = false;
        _loadedDay = _today();
      } else if (service.lastErrorCode == 'NO_KUNDLI') {
        _server = null;
        _noKundli = true;
      } else if (_server == null) {
        _error = service.lastError ?? 'Could not load your quest. Please try again.';
      }
    });
  }

  /// What the player sees: the server state plus any in-flight completions.
  GameState? get _view {
    final s = _server;
    if (s == null || _pending.isEmpty) return s;
    var missions = s.missions;
    var gain = 0;
    for (final m in s.missions.items) {
      if (_pending.contains(m.id) && !m.done) {
        missions = missions.withDone(m.id, true);
        gain += m.xp;
      }
    }
    return s.copyWith(missions: missions, player: gain > 0 ? s.player.withXpGain(gain) : s.player);
  }

  GlobalKey _keyFor(String id) => _missionKeys.putIfAbsent(id, () => GlobalKey());

  Future<void> _complete(GameMission mission) async {
    final before = _server;
    if (before == null || mission.done || _pending.contains(mission.id)) return;
    final service = Provider.of<BackendService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final wasAllDone = before.missions.allDone;

    HapticFeedback.mediumImpact();
    setState(() => _pending.add(mission.id)); // optimistic: checked right away
    XpFlight.fly(context, from: _keyFor(mission.id), to: _xpBarKey, text: '+${mission.xp} XP');

    Map<String, dynamic>? raw;
    try {
      raw = await service.completeMission(mission.id);
    } catch (_) {
      raw = null;
    }
    if (!mounted) return;

    if (raw == null) {
      // Roll back: the mission pops open again.
      final code = service.lastErrorCode;
      setState(() => _pending.remove(mission.id));
      HapticFeedback.heavyImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(code == 'MISSION_NOT_FOUND'
              ? 'A new day has started — here are today\'s missions.'
              : (service.lastError ?? 'Could not save that. Please try again.')),
        ));
      if (code == 'MISSION_NOT_FOUND') await _load(force: true);
      return;
    }

    final r = MissionCompleteResult.fromJson(raw);
    final current = _server ?? before;
    setState(() {
      _pending.remove(mission.id);
      _server = current.copyWith(
        player: raw!['player'] is Map ? r.player : current.player.withXpGain(r.xpGained + r.bonusXp),
        planets: r.planets.isNotEmpty ? r.planets : null,
        missions: r.missions.items.isNotEmpty ? r.missions : current.missions.withDone(mission.id, true),
      );
      if (r.planetLeveledUp != null) _planetBanner = r.planetLeveledUp;
    });

    final allDoneNow = (_server?.missions.allDone ?? false) && !wasAllDone;
    if (r.leveledUp) {
      HapticFeedback.heavyImpact();
      ConfettiBurst.show(context);
      await _celebrate(
        emoji: '🏅',
        title: 'Level ${r.player.level}!',
        message: 'You are now a ${r.player.title}. Your planets are proud of you.',
        primary: 'Yay!',
      );
      if (!mounted) return;
    }
    if (allDoneNow) {
      HapticFeedback.heavyImpact();
      ConfettiBurst.show(context);
      final bonus = r.bonusXp > 0 ? r.bonusXp : (_server?.missions.allDoneBonusXp ?? 0);
      final roll = await _celebrate(
        emoji: '🎉',
        title: 'All 3 missions done!',
        message: '${bonus > 0 ? '+$bonus bonus XP. ' : ''}Bonus roll unlocked in Moksha Patam',
        primary: 'Roll the dice 🎲',
        secondary: 'Later',
      );
      if (!mounted) return;
      if (roll == true) Navigator.pushNamed(context, AppRoutes.gamesMoksha);
    }
  }

  Future<bool?> _celebrate({
    required String emoji,
    required String title,
    required String message,
    required String primary,
    String? secondary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => _CelebrationDialog(
        emoji: emoji,
        title: title,
        message: message,
        primary: primary,
        secondary: secondary,
      ),
    );
  }

  void _showPlanet(GamePlanet planet) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanetSheet(planet: planet),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameColors.bg,
      appBar: AppBar(
        backgroundColor: GameColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Graha Quest', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: RefreshIndicator(
        color: GameColors.accent,
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: _content(),
        ),
      ),
    );
  }

  List<Widget> _content() {
    final s = _view;
    if (s == null) {
      if (_noKundli) {
        return [
          const SizedBox(height: 12),
          GameNoKundli(
            title: 'Meet your planet team',
            message: 'Add your birth details and your nine planets show up as your own team, with missions made '
                'for your chart.',
            onCreate: () async {
              await Navigator.pushNamed(context, AppRoutes.birthDetails);
              if (mounted) _load(force: true);
            },
          ),
        ];
      }
      if (_error != null && !_loading) {
        return [GameError(message: _error!, onRetry: () => _load(force: true))];
      }
      return const [GameSkeleton(blocks: [130, 110, 110, 110, 170])];
    }

    final missions = s.missions;
    final planets = {for (final p in s.planets) p.planet: p};
    return [
      _playerStrip(s.player),
      if (_planetBanner != null) ...[
        const SizedBox(height: 12),
        _PlanetLevelBanner(
          planet: _planetBanner!,
          level: planets[_planetBanner!]?.level,
          onClose: () => setState(() => _planetBanner = null),
        ),
      ],
      GameSectionTitle(
        "Today's missions",
        emoji: '🎯',
        trailing: GamePill(
          '${missions.completedCount}/${missions.total}',
          color: missions.allDone ? GameColors.good : GameColors.violet,
          solid: true,
          fontSize: 12.5,
        ),
      ),
      if (missions.items.isEmpty)
        const GameCard(child: Text('No missions right now. Pull down to refresh.', style: TextStyle(fontSize: 13.5)))
      else
        for (final m in missions.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MissionCard(
              key: ValueKey<String>('mission-${m.id}'),
              mission: m,
              xpKey: _keyFor(m.id),
              busy: _pending.contains(m.id),
              onComplete: () => _complete(m),
            ),
          ),
      if (missions.items.isNotEmpty)
        missions.allDone ? _allDoneCard(missions) : _bonusHint(missions),
      GameSectionTitle('Your team', emoji: '🪐', trailing: Text('Tap a planet', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      if (s.planets.isEmpty)
        const GameCard(child: Text('Your planets are still lining up. Pull down to refresh.', style: TextStyle(fontSize: 13.5)))
      else
        _team(s.planets),
    ];
  }

  Widget _playerStrip(GamePlayer p) {
    return GameCard(
      gradient: GameColors.night,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              LevelBadge(level: p.level, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 8),
                    XpBar(
                      key: _xpBarKey,
                      progress: p.progress,
                      onDark: true,
                      height: 10,
                      label: '${p.xpIntoLevel} / ${p.xpForNext} XP',
                      semanticLabel: 'Experience: ${p.xpIntoLevel} of ${p.xpForNext} to level ${p.level + 1}',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              StreakFlame(streak: p.streak, alive: p.streakAliveToday, size: 28, onDark: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(_streakHint(p),
              style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.white.withValues(alpha: 0.88))),
        ],
      ),
    );
  }

  static String _streakHint(GamePlayer p) {
    final next = _milestones.firstWhere((m) => m > p.streak, orElse: () => p.streak + 1);
    final left = next - p.streak;
    if (!p.streakAliveToday) {
      return p.streak > 0
          ? 'Do one mission today to keep your ${p.streak}-day streak alive 🔥'
          : 'Do one mission today to light your streak 🔥';
    }
    if (_milestones.contains(p.streak)) return '${p.streak}-day streak — milestone reached! 🏆';
    return 'Streak safe for today. ${left == 1 ? '1 more day' : '$left more days'} to a $next-day streak 🔥';
  }

  Widget _bonusHint(MissionsDay m) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: GameColors.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GameColors.gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const ExcludeSemantics(child: Text('🎲', style: TextStyle(fontSize: 18))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Finish all ${m.total} for ${m.allDoneBonusXp > 0 ? '+${m.allDoneBonusXp} XP and ' : ''}'
              'a bonus roll in Moksha Patam',
              style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w700, color: Colors.grey.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _allDoneCard(MissionsDay m) {
    return GameCard(
      gradient: const [Color(0xFF059669), Color(0xFF0EA5E9)],
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('All done for today! 🎉',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 4),
          Text('Your bonus roll is waiting in Moksha Patam. New missions arrive tomorrow.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.white.withValues(alpha: 0.92))),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.gamesMoksha),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: GameColors.ink),
            icon: const Icon(Icons.casino_rounded, size: 18),
            label: const Text('Play Moksha Patam', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _team(List<GamePlanet> planets) {
    // Planets that need care come first: they are today's "needs you" picks.
    final sorted = [...planets]..sort((a, b) => (b.needsCare ? 1 : 0) - (a.needsCare ? 1 : 0));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in sorted)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(width: 136, child: _PlanetCard(planet: p, onTap: () => _showPlanet(p))),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Missions
// ---------------------------------------------------------------------------

const Map<String, String> _categoryEmoji = {
  'action': '⚡',
  'kindness': '💛',
  'mind': '🧠',
  'body': '💪',
  'learn': '📚',
};

class _MissionCard extends StatelessWidget {
  final GameMission mission;
  final GlobalKey xpKey;
  final bool busy;
  final VoidCallback onComplete;

  const _MissionCard({super.key, required this.mission, required this.xpKey, required this.busy, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final color = GameColors.planet(m.planet);
    final done = m.done;
    return GameCard(
      onTap: done ? null : onComplete,
      semanticLabel: done
          ? 'Mission done: ${m.title}'
          : 'Mission: ${m.title}. ${m.why} Worth ${m.xp} XP. Double tap to mark done.',
      color: done ? const Color(0xFFECFDF5) : Colors.white,
      borderColor: done ? GameColors.good.withValues(alpha: 0.45) : color.withValues(alpha: 0.25),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlanetAvatar(planet: m.planet, size: 42, dimmed: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: done ? Colors.grey.shade700 : GameColors.ink,
                    ),
                  ),
                  if (m.why.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(m.why, style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.grey.shade700)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      KeyedSubtree(
                        key: xpKey,
                        child: GamePill(done ? '+${m.xp} XP earned' : '+${m.xp} XP',
                            color: done ? GameColors.good : GameColors.goldDeep, icon: Icons.bolt_rounded),
                      ),
                      GamePill('${_categoryEmoji[m.category] ?? '⚡'} ${m.planet}', color: color),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CheckButton(done: done, color: color),
          ],
        ),
      ),
    );
  }
}

/// Round check that pops (elastic) when the mission flips to done.
class _CheckButton extends StatelessWidget {
  final bool done;
  final Color color;
  const _CheckButton({required this.done, required this.color});

  @override
  Widget build(BuildContext context) {
    final reduce = gameReduceMotion(context);
    final circle = AnimatedContainer(
      duration: Duration(milliseconds: reduce ? 0 : 220),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? GameColors.good : Colors.white,
        border: Border.all(color: done ? GameColors.good : color.withValues(alpha: 0.6), width: 2.5),
        boxShadow: done ? [BoxShadow(color: GameColors.good.withValues(alpha: 0.4), blurRadius: 10)] : null,
      ),
      child: Icon(Icons.check_rounded, size: 24, color: done ? Colors.white : color.withValues(alpha: 0.25)),
    );
    if (reduce) return circle;
    return TweenAnimationBuilder<double>(
      key: ValueKey<bool>(done),
      tween: Tween<double>(begin: done ? 0.4 : 1, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: circle,
    );
  }
}

class _PlanetLevelBanner extends StatelessWidget {
  final String planet;
  final int? level;
  final VoidCallback onClose;
  const _PlanetLevelBanner({required this.planet, required this.level, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final color = GameColors.planet(planet);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            PlanetAvatar(planet: planet, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$planet levelled up${level != null ? ' to level $level' : ''}! ⬆️',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: GameColors.ink),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _CelebrationDialog extends StatelessWidget {
  final String emoji;
  final String title;
  final String message;
  final String primary;
  final String? secondary;
  const _CelebrationDialog({
    required this.emoji,
    required this.title,
    required this.message,
    required this.primary,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: GameColors.night),
          borderRadius: BorderRadius.circular(26),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: gameReduceMotion(context)
                    ? Text(emoji, style: const TextStyle(fontSize: 54))
                    : TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.3, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.elasticOut,
                        builder: (context, v, child) => Transform.scale(scale: v, child: child),
                        child: Text(emoji, style: const TextStyle(fontSize: 54)),
                      ),
              ),
              const SizedBox(height: 8),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.4, color: Colors.white.withValues(alpha: 0.9))),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GameColors.gold,
                    foregroundColor: const Color(0xFF3D2400),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(primary, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
              if (secondary != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(secondary!, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team
// ---------------------------------------------------------------------------

class _PlanetCard extends StatelessWidget {
  final GamePlanet planet;
  final VoidCallback onTap;
  const _PlanetCard({required this.planet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = planet;
    final color = GameColors.planet(p.planet);
    final statusColor = GameColors.status(p.status);
    return GameCard(
      onTap: onTap,
      semanticLabel: '${p.planet}, ${p.role}. Level ${p.level}, power ${p.power} percent, '
          '${PlanetStatus.label(p.status)}. Double tap for details.',
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      color: p.needsCare ? const Color(0xFFFFF5F5) : Colors.white,
      borderColor: p.needsCare ? GameColors.bad.withValues(alpha: 0.55) : color.withValues(alpha: 0.22),
      glow: p.needsCare,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlanetAvatar(planet: p.planet, size: 56, level: p.level, power: p.power, highlight: p.needsCare),
            const SizedBox(height: 8),
            Text(p.planet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: GameColors.ink)),
            if (p.role.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(p.role,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.25, color: Colors.grey.shade700)),
            ],
            const SizedBox(height: 8),
            XpBar(progress: p.power / 100, color: color, height: 7, semanticLabel: '${p.planet} power'),
            const SizedBox(height: 8),
            GamePill(PlanetStatus.label(p.status),
                color: statusColor, solid: p.needsCare, icon: p.needsCare ? Icons.favorite_rounded : null),
          ],
        ),
      ),
    );
  }
}

const Map<String, List<String>> _powerUps = {
  'Sun': ['Catch the morning light for a few minutes', 'Take the lead on one small thing', 'Thank your father or a mentor'],
  'Moon': ['Drink water and rest properly', 'Call your mother or someone who cares for you', 'Spend quiet time near water or under the Moon'],
  'Mars': ['Move your body — walk, stretch, play', 'Finish a task you have been avoiding', 'Stand up for someone kindly'],
  'Mercury': ['Learn one new thing today', 'Write down your thoughts', 'Send that message you have been putting off'],
  'Jupiter': ['Teach or share something you know', 'Give a little to someone in need', 'Read a few pages of something wise'],
  'Venus': ['Make something beautiful or tidy your space', 'Say something loving out loud', 'Enjoy music, art or good food slowly'],
  'Saturn': ['Do one boring job with full attention', 'Help an elder or someone who works hard', 'Be on time, all day'],
  'Rahu': ['Try something new and a little unusual', 'Take a break from scrolling', 'Ask a bold question'],
  'Ketu': ['Sit quietly for five minutes', 'Let go of one thing you no longer need', 'Do a kindness without telling anyone'],
};

class _PlanetSheet extends StatelessWidget {
  final GamePlanet planet;
  const _PlanetSheet({required this.planet});

  @override
  Widget build(BuildContext context) {
    final p = planet;
    final color = GameColors.planet(p.planet);
    final tips = _powerUps[p.planet] ?? const ['Complete its missions when they show up'];
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      decoration: const BoxDecoration(
        color: GameColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  PlanetAvatar(planet: p.planet, size: 68, level: p.level, power: p.power),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.planet,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: GameColors.ink)),
                        if (p.role.isNotEmpty)
                          Text(p.role, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            GamePill('Level ${p.level}', color: GameColors.ink, solid: true),
                            GamePill(PlanetStatus.label(p.status), color: GameColors.status(p.status)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              XpBar(
                progress: p.power / 100,
                color: color,
                label: 'Power ${p.power}/100',
                trailingLabel: p.level >= 10 ? 'Max level' : null,
                semanticLabel: '${p.planet} power',
              ),
              if (p.personality != null) ...[
                const SizedBox(height: 14),
                Text(p.personality!, style: TextStyle(fontSize: 14, height: 1.4, fontStyle: FontStyle.italic, color: Colors.grey.shade800)),
              ],
              if (p.natal.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('In your chart', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(p.natal, style: const TextStyle(fontSize: 14.5, height: 1.4, color: GameColors.ink)),
              ],
              const SizedBox(height: 16),
              Text(p.needsCare ? 'It needs you — power it up' : 'What powers it up',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.grey)),
              const SizedBox(height: 6),
              for (final t in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.bolt_rounded, size: 16, color: color),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t, style: const TextStyle(fontSize: 14, height: 1.35))),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Every ${p.planet} mission you finish adds to its power and helps it level up.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
