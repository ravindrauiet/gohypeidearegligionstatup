import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/game.dart';
import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import 'game_widgets.dart';
import 'ui/app_ui.dart';

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
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: GameCard(
        onTap: _open,
        semanticLabel: label,
        gradient: AppColors.cosmicGradient.colors,
        radius: AppRadius.lg,
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        child: ExcludeSemantics(
          child: Row(
            children: [
              if (s != null) LevelBadge(level: s.player.level, size: 40) else const _PlayIcon(),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text("Play today's games",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.subtitle.copyWith(color: AppColors.textOnDark)),
                        ),
                        if (s != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          StreakFlame(streak: s.player.streak, alive: s.player.streakAliveToday, size: 18, onDark: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (s == null)
                      Text('Missions, cards and a dice roll are waiting',
                          style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StripChip(
                              Icons.flag_rounded,
                              '${s.missions.completedCount}/${s.missions.total == 0 ? 3 : s.missions.total} missions',
                              done: s.missions.allDone),
                          _StripChip(Icons.style_rounded,
                              s.card.canCollect ? 'Card waiting' : '${s.card.collectedCount}/${s.card.total} cards',
                              dot: s.card.canCollect),
                          _StripChip(Icons.casino_rounded, '${s.moksha.rollsLeft} ${s.moksha.rollsLeft == 1 ? 'roll' : 'rolls'}',
                              dot: s.moksha.rollsLeft > 0),
                        ],
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textOnDark),
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
        child: const Icon(Icons.sports_esports_rounded, color: AppColors.gold, size: 22),
      );
}

class _StripChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool dot;
  final bool done;
  const _StripChip(this.icon, this.text, {this.dot = false, this.done = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: done ? AppColors.success.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textOnDarkMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          if (dot) ...[
            const SizedBox(width: 5),
            // Static (not pulsing): Home must stay calm and never animate forever.
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}
