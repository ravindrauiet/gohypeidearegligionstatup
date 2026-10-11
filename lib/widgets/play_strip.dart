import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import 'game_widgets.dart';

/// Compact Home "Play" strip: streak flame, level, today's mission progress,
/// a "card waiting" dot and rolls left. Opens the games hub.
///
/// Stays quiet on failure (a plain invitation to play, never an error) and
/// hides itself when there is no Kundli yet. Bump [refreshTick] to re-fetch
/// (e.g. on Home pull-to-refresh).
class PlayStrip extends StatefulWidget {
  final int refreshTick;
  const PlayStrip({super.key, this.refreshTick = 0});

  @override
  State<PlayStrip> createState() => _PlayStripState();
}

class _PlayStripState extends State<PlayStrip> {
  GameState? _state;
  bool _hidden = false;
  String? _identity;
  int _token = 0;

  @override
  void didUpdateWidget(PlayStrip old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    final token = ++_token;
    Map<String, dynamic>? raw;
    try {
      raw = await service.fetchGameState(forceRefresh: force);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token) return;
    setState(() {
      if (raw != null) {
        _state = GameState.fromJson(raw);
        _hidden = false;
      } else if (service.lastErrorCode == 'NO_KUNDLI') {
        _state = null;
        _hidden = true;
      }
    });
  }

  Future<void> _open() async {
    await Navigator.pushNamed(context, AppRoutes.games);
    if (mounted) _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<BackendService>(context);
    final kundli = service.kundliData;
    if (kundli == null) return const SizedBox.shrink();

    // Re-fetch when the account or the chart changes.
    final birth = kundli['birthDetails'];
    final identity = '${service.isAuthenticated}|${kundli['ascendant']}|${kundli['moonSign']}|'
        '${birth is Map ? '${birth['dateOfBirth']}|${birth['timeOfBirth']}' : ''}';
    if (identity != _identity) {
      _identity = identity;
      _state = null;
      _hidden = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    if (_hidden) return const SizedBox.shrink();

    final s = _state;
    final label = s == null
        ? 'Play. Open your games'
        : 'Play. Level ${s.player.level}, streak ${s.player.streak} days, '
            '${s.missions.completedCount} of ${s.missions.total} missions done'
            '${s.card.canCollect ? ', a card is waiting' : ''}, '
            '${s.moksha.rollsLeft} dice rolls left. Opens games.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GameCard(
        onTap: _open,
        semanticLabel: label,
        gradient: GameColors.night,
        radius: 20,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: ExcludeSemantics(
          child: Row(
            children: [
              if (s != null) LevelBadge(level: s.player.level, size: 40) else const _PlayIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text("Play today's games",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                        if (s != null) ...[
                          const SizedBox(width: 8),
                          StreakFlame(streak: s.player.streak, alive: s.player.streakAliveToday, size: 18, onDark: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (s == null)
                      Text('Missions, cards and a dice roll are waiting',
                          style: TextStyle(fontSize: 12, height: 1.3, color: Colors.white.withValues(alpha: 0.8)))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StripChip('🎯 ${s.missions.completedCount}/${s.missions.total == 0 ? 3 : s.missions.total}',
                              done: s.missions.allDone),
                          _StripChip(s.card.canCollect ? '🃏 Card waiting' : '🃏 ${s.card.collectedCount}/${s.card.total}',
                              dot: s.card.canCollect),
                          _StripChip('🎲 ${s.moksha.rollsLeft}', dot: s.moksha.rollsLeft > 0),
                        ],
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayIcon extends StatelessWidget {
  const _PlayIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: const Text('🎲', textScaler: TextScaler.noScaling, style: TextStyle(fontSize: 20)),
      );
}

class _StripChip extends StatelessWidget {
  final String text;
  final bool dot;
  final bool done;
  const _StripChip(this.text, {this.dot = false, this.done = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done ? const Color(0xFF34D399).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          if (dot) ...[
            const SizedBox(width: 5),
            // Static (not pulsing): Home must stay calm and never animate forever.
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: GameColors.gold, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}
