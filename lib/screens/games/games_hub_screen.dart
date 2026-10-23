import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/game_widgets.dart';
import '../../widgets/ui/app_ui.dart';

/// Games hub: the player (level, XP, streak) in a cosmic header, today's luck,
/// the four connected games as cinematic cards and today's missions.
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
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    // Whatever happened in the game (XP, rolls, cards) shows up on return.
    await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cosmic,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: AppText.title.copyWith(color: Colors.white),
        title: const Text('Games'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: _content(),
        ),
      ),
    );
  }

  List<Widget> _content() {
    final s = _state;
    if (s != null) return _loaded(s);
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: w);
    if (_noKundli) return [pad(GameNoKundli(onCreate: () => _open(AppRoutes.birthDetails)))];
    if (_error != null && !_loading) {
      return [pad(GameError(message: _error!, onRetry: () => _load(force: true)))];
    }
    return [
      pad(const GameSkeleton(blocks: [180, 56, 200, 200, 200]))
    ];
  }

  List<Widget> _loaded(GameState s) {
    final m = s.missions;
    final card = s.card;
    final questDone = m.allDone;
    final total = m.total == 0 ? 3 : m.total;
    final rolls = s.moksha.rollsLeft;
    final members = s.circle.memberCount;
    final rollsText = rolls == 1 ? '1 roll left' : '$rolls rolls left';

    Widget gap(double h) => SizedBox(height: h);
    Widget pad(Widget w) => Padding(padding: AppSpacing.pagePadding, child: w);

    return [
      _HubHeader(player: s.player, luck: s.luck),
      gap(AppSpacing.md),
      pad(_ShowcaseGrid(children: [
        _GameShowcase(
          image: 'assets/images/topic_transits_today.jpg',
          tag: 'Daily quest',
          tagIcon: Icons.flag_rounded,
          title: 'Graha Quest',
          description: 'Three small missions picked for your planets today.',
          progress: total == 0 ? 0 : m.completedCount / total,
          semanticLabel: 'Graha Quest. ${m.completedCount} of ${m.total} missions done'
              '${questDone ? '' : ', ${m.xpAvailable} XP available'}',
          onTap: () => _open(AppRoutes.gamesQuest),
          status: [
            _TileChip('${m.completedCount}/$total missions'),
            if (questDone)
              const _TileChip('All done', highlight: true, icon: Icons.check_rounded)
            else if (m.xpAvailable > 0)
              _TileChip('+${m.xpAvailable} XP waiting', highlight: true),
          ],
        ),
        _GameShowcase(
          image: 'assets/images/topic_moon_calendar.jpg',
          tag: 'Collect',
          tagIcon: Icons.style_rounded,
          title: 'Nakshatra Cards',
          description: 'The Moon deals one of 27 star cards each day.',
          progress: card.total == 0 ? null : card.collectedCount / card.total,
          semanticLabel: 'Nakshatra Cards. '
              '${card.today.isEmpty ? '' : "Today's card ${card.today.name}. "}'
              '${card.canCollect ? 'Ready to collect. ' : ''}${card.collectedCount} of ${card.total} collected',
          onTap: () => _open(AppRoutes.gamesCards),
          status: [
            if (!card.today.isEmpty) _TileChip('Today: ${card.today.name}'),
            if (card.canCollect)
              const _TileChip('Ready to collect', highlight: true)
            else if (!card.today.isEmpty)
              const _TileChip('Collected today', icon: Icons.check_rounded),
            _TileChip('${card.collectedCount}/${card.total} cards'),
            if (card.rareCount > 0) _TileChip('${card.rareCount} rare'),
          ],
        ),
        _GameShowcase(
          image: 'assets/images/heroBanner.jpg',
          tag: 'Board game',
          tagIcon: Icons.casino_rounded,
          title: 'Moksha Patam',
          description: 'The original snakes and ladders, played with karma.',
          semanticLabel: 'Moksha Patam. Square ${s.moksha.position}. $rollsText',
          onTap: () => _open(AppRoutes.gamesMoksha),
          status: [
            _TileChip('Square ${s.moksha.position}'),
            _TileChip(rollsText, highlight: rolls > 0),
            if (s.moksha.wins > 0) _TileChip('${s.moksha.wins} Moksha', icon: Icons.emoji_events_rounded),
            if (rolls == 0 && !questDone) const _TileChip('Finish missions for a bonus roll'),
          ],
        ),
        _GameShowcase(
          image: 'assets/images/topic_love_compatibility.jpg',
          tag: 'With family & friends',
          tagIcon: Icons.diversity_3_rounded,
          title: 'Cosmic Match',
          description: 'See how your stars match the people you love.',
          semanticLabel: 'Cosmic Match. '
              '${members > 0 ? '$members in your circle' : 'Invite a friend to start your circle'}',
          onTap: () => _open(AppRoutes.gamesCircle),
          status: [
            if (members > 0) _TileChip(members == 1 ? '1 in your circle' : '$members in your circle'),
            _TileChip(members > 1 ? 'See who matches you' : 'Invite a friend', highlight: members <= 1),
          ],
        ),
      ])),
      if (m.items.isNotEmpty) ...[
        SectionHeader(
          title: 'Today\'s missions',
          subtitle: '${m.completedCount} of ${m.items.length} done',
          actionLabel: 'Open',
          onAction: () => _open(AppRoutes.gamesQuest),
        ),
        pad(_MissionChecklist(missions: m, onOpen: () => _open(AppRoutes.gamesQuest))),
      ],
      gap(AppSpacing.xl),
      pad(const Text(
        'Come back tomorrow for new missions, a new card and fresh rolls.',
        textAlign: TextAlign.center,
        style: AppText.caption,
      )),
    ];
  }
}

// ---------------------------------------------------------------------------

/// Cosmic header: level, title, XP bar, stat chips and today's luck.
class _HubHeader extends StatelessWidget {
  final GamePlayer player;
  final GameLuck luck;
  const _HubHeader({required this.player, required this.luck});

  @override
  Widget build(BuildContext context) {
    final p = player;
    final streakLit = p.streakAliveToday && p.streak > 0;
    final luckText = luck.isEmpty ? '' : (luck.line.isNotEmpty ? luck.line : '${luck.tara} Tara today');
    final luckIcon = luck.chandrashtama
        ? Icons.nightlight_round
        : (luck.favorable ? Icons.auto_awesome_rounded : Icons.wb_twilight_rounded);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xxs, AppSpacing.page, AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.cosmic, Color(0xFF110C30)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              LevelBadge(level: p.level, size: 48),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title.copyWith(color: Colors.white)),
                    const SizedBox(height: AppSpacing.xxs),
                    XpBar(
                      progress: p.progress,
                      onDark: true,
                      label: '${p.xpIntoLevel} / ${p.xpForNext} XP',
                      trailingLabel: 'Lv ${p.level + 1}',
                      semanticLabel: 'Experience: ${p.xpIntoLevel} of ${p.xpForNext} to level ${p.level + 1}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _StatChip(
                icon: Icons.bolt_rounded,
                semantic: '${p.xp} XP earned',
                child: AnimatedCounter(value: p.xp, suffix: ' XP', style: _StatChip.style),
              ),
              _StatChip(
                icon: Icons.local_fire_department_rounded,
                iconColor: streakLit ? AppColors.primary : AppColors.textOnDarkMuted,
                semantic: streakLit
                    ? 'Streak ${p.streak} days, alive today'
                    : (p.streak > 0
                        ? 'Streak ${p.streak} days. Do 1 mission today to keep it'
                        : 'No streak yet. Do 1 mission today to start one'),
                child: Text('${p.streak}-day streak', maxLines: 1, style: _StatChip.style),
              ),
              if (p.bestStreak > 0)
                _StatChip(
                  icon: Icons.emoji_events_rounded,
                  semantic: 'Best streak ${p.bestStreak} days',
                  child: Text('Best ${p.bestStreak}', maxLines: 1, style: _StatChip.style),
                ),
            ],
          ),
          if (luckText.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: "Today's luck: $luckText",
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(luckIcon, size: 16, color: GameColors.gold),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(luckText, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String semantic;
  final Widget child;
  const _StatChip({required this.icon, required this.semantic, required this.child, this.iconColor});

  static const style = TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w700, color: Colors.white);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantic,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: iconColor ?? GameColors.gold),
            const SizedBox(width: 4),
            Flexible(child: child),
          ]),
        ),
      ),
    );
  }
}

/// Large cinematic game card: photo, dark scrim, category tag, title, one-line
/// description, live status, optional progress and a Play button.
class _GameShowcase extends StatelessWidget {
  final String image;
  final String tag;
  final IconData tagIcon;
  final String title;
  final String description;
  final List<Widget> status;
  final double? progress;
  final VoidCallback onTap;
  final String semanticLabel;

  const _GameShowcase({
    required this.image,
    required this.tag,
    required this.tagIcon,
    required this.title,
    required this.description,
    required this.status,
    required this.onTap,
    required this.semanticLabel,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return GameCard(
      onTap: onTap,
      semanticLabel: semanticLabel,
      padding: EdgeInsets.zero,
      color: AppColors.cosmic,
      borderColor: Colors.transparent,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: AppRadius.card,
          child: Stack(
            alignment: Alignment.bottomLeft,
            children: [
              Positioned.fill(child: AppImage(image)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.35, 1],
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        AppColors.cosmic.withValues(alpha: 0.45),
                        const Color(0xFF0B0820).withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Tag(text: tag, icon: tagIcon),
                    const SizedBox(height: 40),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.headline.copyWith(color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(color: AppColors.textOnDarkMuted)),
                    if (progress != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      XpBar(progress: progress!, onDark: true, height: 4, color: GameColors.gold),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: status)),
                        const SizedBox(width: AppSpacing.xs),
                        _PlayButton(onTap: onTap),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Tag({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ]),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PlayButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: const SizedBox(
          height: 44,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.textPrimary),
              SizedBox(width: 2),
              Text('Play', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TileChip extends StatelessWidget {
  final String text;
  final bool highlight;
  final IconData? icon;
  const _TileChip(this.text, {this.highlight = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? AppColors.textPrimary : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? GameColors.gold : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 3)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, color: fg)),
        ),
      ]),
    );
  }
}

/// Tidy checklist of today's missions; tapping a row opens Graha Quest where
/// missions are completed.
class _MissionChecklist extends StatelessWidget {
  final MissionsDay missions;
  final VoidCallback onOpen;
  const _MissionChecklist({required this.missions, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final items = missions.items;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 56),
            Semantics(
              button: true,
              label: '${items[i].done ? 'Done' : 'To do'}: ${items[i].title}. ${items[i].xp} XP',
              child: ExcludeSemantics(
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          items[i].done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 24,
                          color: items[i].done ? AppColors.success : AppColors.border,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            items[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyStrong.copyWith(
                              color: items[i].done ? AppColors.textTertiary : AppColors.textPrimary,
                              decoration: items[i].done ? TextDecoration.lineThrough : null,
                              decorationColor: AppColors.textTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text('${items[i].xp} XP',
                            style: AppText.caption.copyWith(
                                fontWeight: FontWeight.w700,
                                color: items[i].done ? AppColors.textTertiary : GameColors.goldDeep)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (missions.allDoneBonusXp > 0 || !missions.allDone) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
              child: Row(children: [
                Icon(missions.allDone ? Icons.celebration_rounded : Icons.casino_outlined,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    missions.allDone
                        ? 'Bonus roll unlocked in Moksha Patam'
                        : 'Finish all ${items.length} for a bonus roll in Moksha Patam',
                    style: AppText.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column on phones; 2 or 4 equal-height columns on wider screens.
class _ShowcaseGrid extends StatelessWidget {
  final List<Widget> children;
  const _ShowcaseGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 840 ? 4 : (box.maxWidth >= 560 ? 2 : 1);
      const gap = AppSpacing.sm;
      if (cols == 1) {
        return Column(children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: gap), children[i]],
        ]);
      }
      return Column(children: [
        for (var r = 0; r < children.length; r += cols) ...[
          if (r > 0) const SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = r; c < r + cols; c++) ...[
                  if (c > r) const SizedBox(width: gap),
                  Expanded(child: c < children.length ? children[c] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
      ]);
    });
  }
}
