import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/game_widgets.dart';
import '../../widgets/ui/app_ui.dart';

/// Graha Quest: the player's nine planets as a team, and three real-life
/// missions a day chosen from today's sky and the player's chart.
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
    final wasAllDone = before.missions.allDone;

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
      // Roll back: the mission opens again.
      final code = service.lastErrorCode;
      setState(() => _pending.remove(mission.id));
      showAppSnack(
        context,
        code == 'MISSION_NOT_FOUND'
            ? 'A new day has started. Here are today\'s missions.'
            : (service.lastError ?? 'Could not save that. Please try again.'),
        error: code != 'MISSION_NOT_FOUND',
      );
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
      ConfettiBurst.show(context);
      await _celebrate(
        icon: Icons.military_tech_rounded,
        title: 'Level ${r.player.level}!',
        message: 'You are now a ${r.player.title}. Keep the streak going.',
        primary: 'Continue',
      );
      if (!mounted) return;
    }
    if (allDoneNow) {
      ConfettiBurst.show(context);
      final bonus = r.bonusXp > 0 ? r.bonusXp : (_server?.missions.allDoneBonusXp ?? 0);
      final roll = await _celebrate(
        icon: Icons.task_alt_rounded,
        title: 'All 3 missions done!',
        message: '${bonus > 0 ? '+$bonus bonus XP. ' : ''}Bonus roll unlocked in Moksha Patam',
        primary: 'Roll the dice',
        secondary: 'Later',
      );
      if (!mounted) return;
      if (roll == true) Navigator.pushNamed(context, AppRoutes.gamesMoksha);
    }
  }

  Future<bool?> _celebrate({
    required IconData icon,
    required String title,
    required String message,
    required String primary,
    String? secondary,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => _CelebrationDialog(
        icon: icon,
        title: title,
        message: message,
        primary: primary,
        secondary: secondary,
      ),
    );
  }

  void _showPlanet(GamePlanet planet) {
    showAppSheet<void>(context, builder: (_) => _PlanetSheet(planet: planet));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: gameAppBar(title: 'Graha Quest', subtitle: 'Daily missions from your chart'),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
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
      return const [
        GameSkeleton(blocks: [130, 110, 110, 110, 170])
      ];
    }

    final missions = s.missions;
    final planets = {for (final p in s.planets) p.planet: p};
    return [
      _playerStrip(s.player),
      if (_planetBanner != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _PlanetLevelBanner(
          planet: _planetBanner!,
          level: planets[_planetBanner!]?.level,
          onClose: () => setState(() => _planetBanner = null),
        ),
      ],
      GameSectionTitle(
        "Today's missions",
        trailing: GamePill(
          '${missions.completedCount}/${missions.total}',
          color: missions.allDone ? GameColors.good : GameColors.ink,
          solid: missions.allDone,
          fontSize: 12.5,
        ),
      ),
      if (missions.items.isEmpty)
        const AppCard(child: Text('No missions right now. Pull down to refresh.', style: AppText.body))
      else
        for (final m in missions.items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _MissionCard(
              key: ValueKey<String>('mission-${m.id}'),
              mission: m,
              xpKey: _keyFor(m.id),
              busy: _pending.contains(m.id),
              onComplete: () => _complete(m),
            ),
          ),
      if (missions.items.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xxs),
        missions.allDone ? _allDoneCard(missions) : _bonusHint(missions),
      ],
      const GameSectionTitle('Your team', trailing: Text('Tap a planet', style: AppText.caption)),
      if (s.planets.isEmpty)
        const AppCard(child: Text('Your planets are still lining up. Pull down to refresh.', style: AppText.body))
      else
        _team(s.planets),
    ];
  }

  Widget _playerStrip(GamePlayer p) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              LevelBadge(level: p.level, size: 46),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.subtitle.copyWith(color: Colors.white)),
                    const SizedBox(height: AppSpacing.xs),
                    XpBar(
                      key: _xpBarKey,
                      progress: p.progress,
                      onDark: true,
                      label: '${p.xpIntoLevel} / ${p.xpForNext} XP',
                      semanticLabel: 'Experience: ${p.xpIntoLevel} of ${p.xpForNext} to level ${p.level + 1}',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StreakFlame(streak: p.streak, alive: p.streakAliveToday, size: 24, onDark: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_streakHint(p), style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
        ],
      ),
    );
  }

  static String _streakHint(GamePlayer p) {
    final next = _milestones.firstWhere((m) => m > p.streak, orElse: () => p.streak + 1);
    final left = next - p.streak;
    if (!p.streakAliveToday) {
      return p.streak > 0
          ? 'Do one mission today to keep your ${p.streak}-day streak alive'
          : 'Do one mission today to start your streak';
    }
    if (_milestones.contains(p.streak)) return '${p.streak}-day streak. Milestone reached.';
    return 'Streak safe for today. ${left == 1 ? '1 more day' : '$left more days'} to a $next-day streak.';
  }

  Widget _bonusHint(MissionsDay m) {
    return AppCard(
      color: AppColors.surfaceMuted,
      border: false,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.casino_outlined, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Finish all ${m.total} for ${m.allDoneBonusXp > 0 ? '+${m.allDoneBonusXp} XP and ' : ''}'
              'a bonus roll in Moksha Patam',
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _allDoneCard(MissionsDay m) {
    return AppCard(
      color: AppColors.successSoft,
      border: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.task_alt_rounded, color: AppColors.success, size: 22),
              SizedBox(width: AppSpacing.xs),
              Expanded(child: Text('All done for today', style: AppText.subtitle)),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text('Your bonus roll is waiting in Moksha Patam. New missions arrive tomorrow.', style: AppText.body),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Play Moksha Patam',
            icon: Icons.casino_rounded,
            variant: AppButtonVariant.dark,
            height: 46,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.gamesMoksha),
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
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: SizedBox(width: 132, child: _PlanetCard(planet: p, onTap: () => _showPlanet(p))),
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

const Map<String, String> _categoryLabel = {
  'action': 'Action',
  'kindness': 'Kindness',
  'mind': 'Mind',
  'body': 'Body',
  'learn': 'Learn',
};

const Map<String, IconData> _categoryIcon = {
  'action': Icons.bolt_rounded,
  'kindness': Icons.volunteer_activism_rounded,
  'mind': Icons.self_improvement_rounded,
  'body': Icons.directions_walk_rounded,
  'learn': Icons.menu_book_rounded,
};

class _MissionCard extends StatelessWidget {
  final GameMission mission;
  final GlobalKey xpKey;
  final bool busy;
  final VoidCallback onComplete;

  const _MissionCard(
      {super.key, required this.mission, required this.xpKey, required this.busy, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final color = GameColors.planet(m.planet);
    final done = m.done;
    final category = _categoryLabel[m.category];
    return GameCard(
      onTap: done ? null : onComplete,
      semanticLabel: done
          ? 'Mission done: ${m.title}'
          : 'Mission: ${m.title}. ${m.why} Worth ${m.xp} XP. Double tap to mark done.',
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlanetAvatar(planet: m.planet, size: 40, dimmed: done),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.title,
                    style: AppText.bodyStrong.copyWith(
                      height: 1.3,
                      color: done ? AppColors.textTertiary : AppColors.textPrimary,
                    ),
                  ),
                  if (m.why.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(m.why, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      KeyedSubtree(
                        key: xpKey,
                        child: GamePill(done ? '+${m.xp} XP earned' : '+${m.xp} XP',
                            color: done ? GameColors.good : GameColors.goldDeep, icon: Icons.bolt_rounded),
                      ),
                      GamePill(category == null ? '${m.planet} mission' : '${m.planet} · $category',
                          color: color, icon: _categoryIcon[m.category]),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _CheckButton(done: done),
          ],
        ),
      ),
    );
  }
}

/// Round check that fills in when the mission flips to done.
class _CheckButton extends StatelessWidget {
  final bool done;
  const _CheckButton({required this.done});

  @override
  Widget build(BuildContext context) {
    final reduce = gameReduceMotion(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduce ? 0 : 200),
          curve: Curves.easeOut,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? GameColors.good : AppColors.surface,
            border: Border.all(color: done ? GameColors.good : AppColors.border, width: 1.5),
          ),
          child: Icon(Icons.check_rounded, size: 20, color: done ? Colors.white : AppColors.textTertiary),
        ),
      ),
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
    return Semantics(
      liveRegion: true,
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs),
        child: Row(
          children: [
            PlanetAvatar(planet: planet, size: 34),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$planet levelled up${level != null ? ' to level $level' : ''}',
                style: AppText.bodyStrong,
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _CelebrationDialog extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String primary;
  final String? secondary;
  const _CelebrationDialog({
    required this.icon,
    required this.title,
    required this.message,
    required this.primary,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GameColors.gold.withValues(alpha: 0.14),
                  border: Border.all(color: GameColors.gold, width: 1.5),
                ),
                child: Icon(icon, size: 30, color: GameColors.goldDeep),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center, style: AppText.headline),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center, style: AppText.body),
            const SizedBox(height: AppSpacing.xl),
            AppButton(label: primary, onPressed: () => Navigator.pop(context, true)),
            if (secondary != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              AppButton(
                label: secondary!,
                variant: AppButtonVariant.ghost,
                height: 44,
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ],
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
      borderColor: p.needsCare ? GameColors.bad.withValues(alpha: 0.45) : null,
      glow: p.needsCare,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlanetAvatar(planet: p.planet, size: 54, level: p.level, power: p.power, highlight: p.needsCare),
            const SizedBox(height: AppSpacing.xs),
            Text(p.planet, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
            if (p.role.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(p.role,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.textSecondary)),
            ],
            const Spacer(),
            const SizedBox(height: AppSpacing.xs),
            XpBar(progress: p.power / 100, color: color, height: 4, semanticLabel: '${p.planet} power'),
            const SizedBox(height: AppSpacing.xs),
            GamePill(PlanetStatus.label(p.status),
                color: statusColor, icon: p.needsCare ? Icons.favorite_rounded : null),
          ],
        ),
      ),
    );
  }
}

const Map<String, List<String>> _powerUps = {
  'Sun': [
    'Catch the morning light for a few minutes',
    'Take the lead on one small thing',
    'Thank your father or a mentor'
  ],
  'Moon': [
    'Drink water and rest properly',
    'Call your mother or someone who cares for you',
    'Spend quiet time near water or under the Moon'
  ],
  'Mars': [
    'Move your body: walk, stretch, play',
    'Finish a task you have been avoiding',
    'Stand up for someone kindly'
  ],
  'Mercury': ['Learn one new thing today', 'Write down your thoughts', 'Send that message you have been putting off'],
  'Jupiter': [
    'Teach or share something you know',
    'Give a little to someone in need',
    'Read a few pages of something wise'
  ],
  'Venus': [
    'Make something beautiful or tidy your space',
    'Say something loving out loud',
    'Enjoy music, art or good food slowly'
  ],
  'Saturn': ['Do one boring job with full attention', 'Help an elder or someone who works hard', 'Be on time, all day'],
  'Rahu': ['Try something new and a little unusual', 'Take a break from scrolling', 'Ask a bold question'],
  'Ketu': [
    'Sit quietly for five minutes',
    'Let go of one thing you no longer need',
    'Do a kindness without telling anyone'
  ],
};

class _PlanetSheet extends StatelessWidget {
  final GamePlanet planet;
  const _PlanetSheet({required this.planet});

  @override
  Widget build(BuildContext context) {
    final p = planet;
    final color = GameColors.planet(p.planet);
    final tips = _powerUps[p.planet] ?? const ['Complete its missions when they show up'];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  PlanetAvatar(planet: p.planet, size: 64, level: p.level, power: p.power),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.planet, style: AppText.headline),
                        if (p.role.isNotEmpty) Text(p.role, style: AppText.bodyStrong.copyWith(color: color)),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            GamePill('Level ${p.level}', color: GameColors.ink),
                            GamePill(PlanetStatus.label(p.status), color: GameColors.status(p.status)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              XpBar(
                progress: p.power / 100,
                color: color,
                label: 'Power ${p.power}/100',
                trailingLabel: p.level >= 10 ? 'Max level' : null,
                semanticLabel: '${p.planet} power',
              ),
              if (p.personality != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(p.personality!, style: AppText.body.copyWith(fontStyle: FontStyle.italic)),
              ],
              if (p.natal.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const Text('In your chart', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.xxs),
                Text(p.natal, style: AppText.body),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(p.needsCare ? 'It needs you — power it up' : 'What powers it up', style: AppText.subtitle),
              const SizedBox(height: AppSpacing.xs),
              for (final t in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(Icons.check_circle_outline_rounded, size: 16, color: color),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(t, style: AppText.body.copyWith(color: AppColors.textPrimary))),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Every ${p.planet} mission you finish adds to its power and helps it level up.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
