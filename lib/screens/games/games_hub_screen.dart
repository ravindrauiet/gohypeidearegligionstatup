import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/game_widgets.dart';

/// Games hub: the player (level, XP, streak), today's luck and the four
/// connected games with their live status.
class GamesHubScreen extends StatefulWidget {
  const GamesHubScreen({super.key});

  @override
  State<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends State<GamesHubScreen> with WidgetsBindingObserver {
  GameState? _state;
  bool _loading = true;
  bool _noKundli = false;
  String? _error;
  int _token = 0;
  String _loadedDay = '';

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
    // A new local day means new missions, a new card and fresh rolls.
    if (state == AppLifecycleState.resumed && mounted && _loadedDay.isNotEmpty && _loadedDay != _today()) {
      _load(force: true);
    }
  }

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    final token = ++_token;
    if (_state == null) {
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
        _state = GameState.fromJson(raw);
        _error = null;
        _noKundli = false;
        _loadedDay = _today();
      } else if (service.lastErrorCode == 'NO_KUNDLI') {
        _state = null;
        _noKundli = true;
      } else if (_state == null) {
        _error = service.lastError ?? 'Could not load the games. Please try again.';
      }
    });
  }

  Future<void> _open(String route) async {
    HapticFeedback.selectionClick();
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    // Whatever happened in the game (XP, rolls, cards) shows up on return.
    await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameColors.bg,
      appBar: AppBar(
        backgroundColor: GameColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Play', style: TextStyle(fontWeight: FontWeight.w900)),
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
    final s = _state;
    if (s != null) return _loaded(s);
    if (_noKundli) {
      return [
        const SizedBox(height: 12),
        GameNoKundli(onCreate: () => _open(AppRoutes.birthDetails)),
      ];
    }
    if (_error != null && !_loading) {
      return [GameError(message: _error!, onRetry: () => _load(force: true))];
    }
    return const [GameSkeleton(blocks: [160, 48, 104, 104, 104, 104])];
  }

  List<Widget> _loaded(GameState s) {
    final m = s.missions;
    final card = s.card;
    final questDone = m.allDone;
    final rolls = s.moksha.rollsLeft;
    final members = s.circle.memberCount;

    return [
      _PlayerHeader(player: s.player),
      if (!s.luck.isEmpty) ...[
        const SizedBox(height: 12),
        _LuckLine(luck: s.luck),
      ],
      const SizedBox(height: 18),
      _GameTile(
        emoji: '🪐',
        title: 'Graha Quest',
        gradient: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        semanticLabel: 'Graha Quest. ${m.completedCount} of ${m.total} missions done'
            '${questDone ? '' : ', ${m.xpAvailable} XP available'}',
        onTap: () => _open(AppRoutes.gamesQuest),
        status: [
          _MissionDots(done: m.completedCount, total: m.total == 0 ? 3 : m.total),
          _TileChip('${m.completedCount}/${m.total == 0 ? 3 : m.total} missions'),
          if (questDone)
            const _TileChip('All done! 🎉', highlight: true)
          else if (m.xpAvailable > 0)
            _TileChip('+${m.xpAvailable} XP waiting', highlight: true),
        ],
      ),
      const SizedBox(height: 12),
      _GameTile(
        emoji: card.today.isEmpty ? '🃏' : card.today.symbol,
        title: 'Nakshatra Cards',
        gradient: const [Color(0xFFDB2777), Color(0xFFF97316)],
        semanticLabel: 'Nakshatra Cards. '
            '${card.today.isEmpty ? '' : "Today's card ${card.today.name}. "}'
            '${card.canCollect ? 'Tap to collect. ' : ''}${card.collectedCount} of ${card.total} collected',
        onTap: () => _open(AppRoutes.gamesCards),
        badge: card.canCollect ? const PulseDot(color: GameColors.gold, size: 12) : null,
        status: [
          if (!card.today.isEmpty) _TileChip('Today: ${card.today.name}'),
          if (card.canCollect)
            const PulseDot(child: _TileChip('Tap to collect ✨', highlight: true))
          else if (!card.today.isEmpty)
            const _TileChip('Collected ✓'),
          _TileChip('${card.collectedCount}/${card.total} cards'),
          if (card.rareCount > 0) _TileChip('${card.rareCount} rare'),
        ],
      ),
      const SizedBox(height: 12),
      _GameTile(
        emoji: '🎲',
        title: 'Moksha Patam',
        gradient: const [Color(0xFF059669), Color(0xFF0EA5E9)],
        semanticLabel: 'Moksha Patam. Square ${s.moksha.position}. '
            '${rolls == 1 ? '1 roll left' : '$rolls rolls left'}',
        onTap: () => _open(AppRoutes.gamesMoksha),
        badge: rolls > 0 ? const PulseDot(color: GameColors.gold, size: 12) : null,
        status: [
          _TileChip('Square ${s.moksha.position}'),
          _TileChip(rolls == 1 ? '1 roll left' : '$rolls rolls left', highlight: rolls > 0),
          if (s.moksha.wins > 0) _TileChip('🏆 ${s.moksha.wins}'),
          if (rolls == 0 && !questDone) const _TileChip('Finish missions for a bonus roll'),
        ],
      ),
      const SizedBox(height: 12),
      _GameTile(
        emoji: '💞',
        title: 'Cosmic Match',
        gradient: const [Color(0xFFBE185D), Color(0xFF7C3AED)],
        semanticLabel: 'Cosmic Match. '
            '${members > 0 ? '$members in your circle' : 'Invite a friend to start your circle'}',
        onTap: () => _open(AppRoutes.gamesCircle),
        status: [
          if (members > 0) _TileChip(members == 1 ? '1 in your circle' : '$members in your circle'),
          _TileChip(members > 1 ? 'See who matches you' : 'Invite a friend 💌', highlight: members <= 1),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        'Your real chart and today\'s sky set up every game. Come back tomorrow for new missions, a new card and fresh rolls.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey.shade600),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------

class _PlayerHeader extends StatelessWidget {
  final GamePlayer player;
  const _PlayerHeader({required this.player});

  @override
  Widget build(BuildContext context) {
    final p = player;
    final String streakLine;
    if (p.streakAliveToday && p.streak > 0) {
      streakLine = 'Streak alive today — ${p.streak} ${p.streak == 1 ? 'day' : 'days'} and counting';
    } else if (p.streak > 0) {
      streakLine = 'Do 1 mission today to keep your ${p.streak}-day streak';
    } else {
      streakLine = 'Do 1 mission today to light your streak';
    }
    return GameCard(
      gradient: GameColors.night,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              LevelBadge(level: p.level),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 2),
                    AnimatedCounter(
                      value: p.xp,
                      suffix: ' XP earned',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StreakFlame(streak: p.streak, alive: p.streakAliveToday, size: 30, onDark: true),
            ],
          ),
          const SizedBox(height: 14),
          XpBar(
            progress: p.progress,
            onDark: true,
            label: '${p.xpIntoLevel} / ${p.xpForNext} XP',
            trailingLabel: 'Lv ${p.level + 1}',
            semanticLabel: 'Experience: ${p.xpIntoLevel} of ${p.xpForNext} to level ${p.level + 1}',
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                p.streakAliveToday ? Icons.check_circle_rounded : Icons.bolt_rounded,
                size: 15,
                color: p.streakAliveToday ? const Color(0xFF34D399) : GameColors.gold,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(streakLine,
                    style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.white.withValues(alpha: 0.9))),
              ),
            ],
          ),
          if (p.bestStreak > p.streak) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 21),
              child: Text('Best streak: ${p.bestStreak} days',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.6))),
            ),
          ],
        ],
      ),
    );
  }
}

class _LuckLine extends StatelessWidget {
  final GameLuck luck;
  const _LuckLine({required this.luck});

  @override
  Widget build(BuildContext context) {
    final color = luck.chandrashtama ? GameColors.violet : (luck.favorable ? GameColors.good : GameColors.accent);
    final emoji = luck.chandrashtama ? '🌙' : (luck.favorable ? '🍀' : '🌤️');
    final text = luck.line.isNotEmpty ? luck.line : '${luck.tara} Tara today';
    return Semantics(
      label: "Today's luck: $text",
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w700, color: Colors.grey.shade900)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final String emoji;
  final String title;
  final List<Color> gradient;
  final List<Widget> status;
  final VoidCallback onTap;
  final String semanticLabel;
  final Widget? badge;

  const _GameTile({
    required this.emoji,
    required this.title,
    required this.gradient,
    required this.status,
    required this.onTap,
    required this.semanticLabel,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GameCard(
      gradient: gradient,
      onTap: onTap,
      semanticLabel: semanticLabel,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Text(emoji, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 28)),
                ),
                if (badge != null) Positioned(right: 0, top: 0, child: badge!),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: status),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
          ],
        ),
      ),
    );
  }
}

class _TileChip extends StatelessWidget {
  final String text;
  final bool highlight;
  const _TileChip(this.text, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? Colors.white : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: highlight ? GameColors.ink : Colors.white,
        ),
      ),
    );
  }
}

class _MissionDots extends StatelessWidget {
  final int done;
  final int total;
  const _MissionDots({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < done ? GameColors.gold : Colors.white.withValues(alpha: 0.25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
            ),
          ),
      ],
    );
  }
}
