import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/game_widgets.dart';
import '../../widgets/ui/app_ui.dart';

/// Nakshatra Cards: every day the Moon sits in one of the 27 nakshatras and
/// that card can be collected. Rare cards drop on special sky days; complete
/// rows to claim rewards.
class NakshatraCardsScreen extends StatefulWidget {
  const NakshatraCardsScreen({super.key});

  @override
  State<NakshatraCardsScreen> createState() => _NakshatraCardsScreenState();
}

class _NakshatraCardsScreenState extends State<NakshatraCardsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CardAlbum? _album;
  bool _loading = true;
  bool _noKundli = false;
  String? _error;
  int _token = 0;
  String _loadedDay = '';

  late final AnimationController _flip;

  /// The card being revealed this session (kept so the hero stays put while
  /// the album refreshes underneath).
  CosmicCard? _heroCard;
  bool _collecting = false;
  bool _justCollected = false;
  int _xpGained = 0;
  List<CosmicCard> _bonus = const [];
  int _bonusRevealed = 0;
  final Set<String> _claiming = {};

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static String _arrival(DateTime? d) => d == null ? '' : DateFormat('d MMM').format(d);

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flip.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // New local day = new card on the table.
    if (state == AppLifecycleState.resumed && mounted && _loadedDay.isNotEmpty && _loadedDay != _today()) {
      _resetHero();
      _load();
    }
  }

  void _resetHero() {
    _flip.value = 0;
    _heroCard = null;
    _justCollected = false;
    _xpGained = 0;
    _bonus = const [];
    _bonusRevealed = 0;
  }

  Future<void> _load({bool userRefresh = false}) async {
    final service = Provider.of<BackendService>(context, listen: false);
    final token = ++_token;
    if (_album == null) {
      setState(() {
        _loading = true;
        _error = null;
        _noKundli = false;
      });
    }
    Map<String, dynamic>? raw;
    try {
      raw = await service.fetchGameCards();
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token) return;
    setState(() {
      _loading = false;
      if (raw != null) {
        _album = CardAlbum.fromJson(raw);
        _error = null;
        _noKundli = false;
        _loadedDay = _today();
      } else if (service.lastErrorCode == 'NO_KUNDLI') {
        _album = null;
        _noKundli = true;
      } else if (_album == null) {
        _error = service.lastError ?? 'Could not load your cards. Please try again.';
      } else if (userRefresh) {
        showAppSnack(context, service.lastError ?? 'Could not refresh your cards.', error: true);
      }
    });
  }

  // ------------------------------------------------------------------ collect

  Future<void> _collect() async {
    final album = _album;
    if (album == null || _collecting || !album.today.canCollect || album.today.card.isEmpty) return;
    final service = Provider.of<BackendService>(context, listen: false);
    final reduce = gameReduceMotion(context);

    setState(() {
      _collecting = true;
      _heroCard = album.today.card;
    });
    // Flip right away: the reveal should feel instant; the save runs behind it.
    final flipDone =
        reduce ? Future<void>.sync(() => _flip.value = 1) : _flip.forward(from: 0).orCancel.catchError((_) {});

    Map<String, dynamic>? raw;
    try {
      raw = await service.collectTodayCards();
    } catch (_) {
      raw = null;
    }
    if (!mounted) return;

    if (raw == null) {
      // Could not save: turn the card face-down again.
      if (reduce) {
        _flip.value = 0;
      } else {
        _flip.reverse();
      }
      setState(() {
        _collecting = false;
        _heroCard = null;
      });
      showAppSnack(context, service.lastError ?? 'Could not collect the card. Please try again.', error: true);
      return;
    }

    final result = CollectResult.fromJson(raw);
    await flipDone;
    if (!mounted) return;

    final hero = album.today.card;
    final mainCard =
        result.collected.firstWhere((c) => c.id == hero.id, orElse: () => hero.asCollected(DateTime.now()));
    setState(() {
      _collecting = false;
      _justCollected = true;
      _heroCard = mainCard;
      _xpGained = result.xpGained;
      _bonus = result.collected.where((c) => c.id != hero.id).toList();
      _bonusRevealed = 0;
    });
    ConfettiBurst.show(context, origin: const Alignment(0, -0.35));

    if (result.completedSets.isNotEmpty || result.leveledUp) {
      showAppSnack(
          context,
          result.completedSets.isNotEmpty
              ? 'Set complete! Scroll down to claim your reward.'
              : 'Level up! You reached level ${result.player.level}.');
    }
    await _load(); // album, sets and upcoming now include today's cards
  }

  void _revealBonus() {
    if (_bonusRevealed >= _bonus.length) return;
    setState(() => _bonusRevealed++);
    ConfettiBurst.show(context, particleCount: 24);
  }

  // ------------------------------------------------------------------ claim

  Future<void> _claim(CardSet set) async {
    if (!set.canClaim || _claiming.contains(set.id)) return;
    final service = Provider.of<BackendService>(context, listen: false);
    setState(() => _claiming.add(set.id));

    Map<String, dynamic>? raw;
    try {
      raw = await service.claimCardSet(set.id);
    } catch (_) {
      raw = null;
    }
    if (!mounted) return;

    if (raw == null) {
      final code = service.lastErrorCode;
      setState(() => _claiming.remove(set.id));
      showAppSnack(context, service.lastError ?? 'Could not claim the reward. Please try again.', error: true);
      if (code == 'ALREADY_CLAIMED' || code == 'SET_INCOMPLETE' || code == 'SET_NOT_FOUND') await _load();
      return;
    }

    final result = ClaimResult.fromJson(raw);
    final reward = raw['reward'] is Map ? result.reward : set.reward;
    final album = _album;
    setState(() {
      _claiming.remove(set.id);
      if (album != null) {
        _album = CardAlbum(
          today: album.today,
          cards: album.cards,
          rare: album.rare,
          collectedCount: album.collectedCount,
          total: album.total,
          sets: [for (final s in album.sets) s.id == set.id ? s.asClaimed() : s],
          upcoming: album.upcoming,
        );
      }
    });
    ConfettiBurst.show(context);
    final balance = result.walletBalance;
    final String text;
    if (reward.isWallet) {
      text = balance != null
          ? '${reward.label} claimed! Wallet balance: ₹${balance.toStringAsFixed(balance == balance.roundToDouble() ? 0 : 2)}'
          : '${reward.label} claimed and added to your wallet!';
    } else {
      text = '${reward.label} claimed! You are level ${result.player.level}.';
    }
    showAppSnack(context, text);
  }

  // ------------------------------------------------------------------ sheets

  void _showCard(CosmicCard card) {
    final arrival = card.collected ? null : _album?.arrivalOf(card.id);
    showAppSheet<void>(context, builder: (_) => _CardSheet(card: card, arrival: arrival));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: gameAppBar(title: 'Nakshatra Cards', subtitle: 'Collect all 27 star cards'),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _load(userRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
          children: _content(),
        ),
      ),
    );
  }

  List<Widget> _content() {
    final a = _album;
    if (a == null) {
      if (_noKundli) {
        return [
          GameNoKundli(
            title: 'Your card album is waiting',
            message: 'Add your birth details to find your birth star and start collecting the 27 nakshatra cards.',
            onCreate: () async {
              await Navigator.pushNamed(context, AppRoutes.birthDetails);
              if (mounted) _load();
            },
          ),
        ];
      }
      if (_error != null && !_loading) {
        return [GameError(message: _error!, onRetry: _load)];
      }
      return const [
        GameSkeleton(blocks: [320, 60, 110, 110, 110])
      ];
    }

    CosmicCard? birthStar;
    for (final c in a.cards) {
      if (c.isBirthStar) birthStar = c;
    }
    final claimable = a.sets.where((s) => s.canClaim).length;

    return [
      _hero(a),
      for (var i = 0; i < _bonus.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: _BonusCard(
            card: _bonus[i],
            revealed: i < _bonusRevealed,
            locked: i > _bonusRevealed,
            onReveal: _revealBonus,
            onOpen: () => _showCard(_bonus[i]),
          ),
        ),
      const SizedBox(height: AppSpacing.lg),
      _progress(a),
      if (birthStar != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _birthStarBadge(birthStar),
      ],
      if (a.upcoming.isNotEmpty) ...[
        const GameSectionTitle('Arriving soon'),
        _upcoming(a),
      ],
      GameSectionTitle(
        'Your collection',
        trailing: GamePill('${a.collectedCount}/${a.total}', color: GameColors.ink, fontSize: 12.5),
      ),
      _grid(a),
      if (a.rare.isNotEmpty) ...[
        GameSectionTitle(
          'Rare cards',
          trailing: GamePill('${a.rare.where((c) => c.collected).length}/${a.rare.length}',
              color: GameColors.goldDeep, fontSize: 12.5),
        ),
        _rareShelf(a),
      ],
      if (a.sets.isNotEmpty) ...[
        GameSectionTitle(
          'Sets & rewards',
          trailing: claimable > 0 ? GamePill('$claimable to claim', color: GameColors.good, solid: true) : null,
        ),
        for (final s in a.sets)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _SetRow(set: s, busy: _claiming.contains(s.id), onClaim: () => _claim(s)),
          ),
      ],
    ];
  }

  // ------------------------------------------------------------------ hero

  Widget _hero(CardAlbum a) {
    final today = a.today;
    final card = _heroCard ?? today.card;
    if (card.isEmpty) {
      return const AppCard(
        child: Text('No card on the table right now. Pull down to refresh.', style: AppText.body),
      );
    }
    final faceDown = today.canCollect && !_justCollected && !_collecting && _flip.value == 0;
    final alreadyToday = !today.canCollect && !_justCollected && _heroCard == null;
    final next = a.upcoming.isNotEmpty ? a.upcoming.first : null;

    final String caption;
    if (_justCollected) {
      caption = '${card.name} is yours!';
    } else if (alreadyToday) {
      caption = "You already collected today's card";
    } else {
      caption = "Today's card is waiting";
    }

    return Column(
      children: [
        Text(caption, textAlign: TextAlign.center, style: AppText.title),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          faceDown || _collecting
              ? 'The Moon chose it for you. Tap to turn it over.'
              : (next != null
                  ? 'Come back for ${next.card.name}${next.date != null ? ' on ${_arrival(next.date)}' : ''}.'
                  : 'Come back tomorrow for the next one.'),
          textAlign: TextAlign.center,
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: alreadyToday
                ? CardFace(card: card, onTap: () => _showCard(card))
                : AnimatedBuilder(
                    animation: _flip,
                    builder: (context, _) {
                      final t = Curves.easeInOutCubic.transform(_flip.value);
                      final front = t >= 0.5;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(t * math.pi),
                        child: front
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()..rotateY(math.pi),
                                child: CardFace(card: card, onTap: _justCollected ? () => _showCard(card) : null),
                              )
                            : _CardBack(onTap: _collecting ? null : _collect),
                      );
                    },
                  ),
          ),
        ),
        if (_justCollected && _xpGained > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: GamePill('+$_xpGained XP', color: GameColors.goldDeep, icon: Icons.bolt_rounded, fontSize: 14),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------ sections

  Widget _progress(CardAlbum a) {
    final left = (a.total - a.collectedCount).clamp(0, a.total);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: XpBar(
        progress: a.total == 0 ? 0 : a.collectedCount / a.total,
        color: AppColors.primary,
        label: '${a.collectedCount} of ${a.total} collected',
        trailingLabel: left == 0 ? 'Complete!' : '$left to go',
        semanticLabel: 'Collection: ${a.collectedCount} of ${a.total} cards',
      ),
    );
  }

  Widget _birthStarBadge(CosmicCard card) {
    return GameCard(
      onTap: () => _showCard(card),
      semanticLabel: 'Your birth star is ${card.name}. ${card.collected ? 'Collected' : 'Not collected yet'}.',
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      child: ExcludeSemantics(
        child: Row(
          children: [
            const GameIconTile(icon: Icons.star_rounded, color: GameColors.goldDeep, size: 44),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your birth star', style: AppText.caption),
                  Text('${card.name} ${card.symbol}', style: AppText.subtitle),
                  Text(
                    card.collected ? 'In your album, a special one' : 'A rare card drops when the Moon returns to it',
                    style: AppText.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _upcoming(CardAlbum a) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final u in a.upcoming)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Semantics(
                button: true,
                label: '${u.card.name}. ${u.card.isRare ? 'Arrives' : 'Moon arrives'} ${_arrival(u.date)}',
                child: ExcludeSemantics(
                  child: Material(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: InkWell(
                      onTap: () => _showCard(u.card),
                      customBorder: const StadiumBorder(),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(u.card.symbol, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 8),
                          Text(
                            u.date == null
                                ? u.card.name
                                : '${u.card.name} · ${u.card.isRare ? 'arrives' : 'Moon arrives'} ${_arrival(u.date)}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(CardAlbum a) {
    if (a.cards.isEmpty) {
      return const AppCard(child: Text('Your album is empty for now.', style: AppText.body));
    }
    return LayoutBuilder(builder: (context, c) {
      const gap = AppSpacing.xs;
      final cols = c.maxWidth >= 520 ? 5 : (c.maxWidth >= 380 ? 4 : 3);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < a.cards.length; i++)
            SizedBox(
              width: w.floorToDouble(),
              child: _MiniCard(
                card: a.cards[i],
                number: i + 1,
                arrival: a.cards[i].collected ? null : a.arrivalOf(a.cards[i].id),
                onTap: () => _showCard(a.cards[i]),
              ),
            ),
        ],
      );
    });
  }

  Widget _rareShelf(CardAlbum a) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in a.rare)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: SizedBox(
                  width: 104,
                  child: _MiniCard(card: c, arrival: c.collected ? null : a.arrivalOf(c.id), onTap: () => _showCard(c)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card art
// ---------------------------------------------------------------------------

List<Color> _cardGradient(CosmicCard c) {
  if (c.rarity == CardRarity.legendary) return const [Color(0xFF5A3A12), AppColors.cosmic];
  if (c.isRare) return const [AppColors.cosmicLight, AppColors.cosmic];
  return GameColors.planetGradient(c.ruler);
}

Color _cardEdge(CosmicCard c) =>
    c.rarity == CardRarity.common && !c.isBirthStar ? Colors.white.withValues(alpha: 0.18) : GameColors.gold;

/// Front of a card: deep gradient tinted by the ruler planet, the symbol in a
/// thin ring, name, power line, keywords, ruler and deity.
class CardFace extends StatelessWidget {
  final CosmicCard card;
  final VoidCallback? onTap;
  const CardFace({super.key, required this.card, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = card;
    final colors = _cardGradient(c);
    final meta = [
      if (c.ruler != null) 'Ruler: ${GameColors.glyph(c.ruler)} ${c.ruler}',
      if (c.deity != null) 'Deity: ${c.deity}',
    ];
    final face = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 300),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: _cardEdge(c), width: c.rarity == CardRarity.common ? 1 : 1.5),
        boxShadow: AppShadows.raised,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _StarfieldPainter(seed: c.id.hashCode, opacity: 0.18))),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: _CardTag(
                        c.isBirthStar ? 'Birth star' : CardRarity.label(c.rarity),
                        gold: c.rarity != CardRarity.common || c.isBirthStar,
                      ),
                    ),
                    const Spacer(),
                    if (c.ruler != null)
                      Text(GameColors.glyph(c.ruler),
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(fontSize: 20, color: Colors.white.withValues(alpha: 0.7))),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                  ),
                  child: Text(c.symbol, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 46)),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(c.name,
                    textAlign: TextAlign.center, style: AppText.display.copyWith(color: Colors.white, fontSize: 26)),
                if (c.power.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(c.power,
                      textAlign: TextAlign.center,
                      style: AppText.body.copyWith(color: Colors.white.withValues(alpha: 0.88))),
                ],
                if (c.keywords.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final k in c.keywords.take(4)) _CardTag(k)],
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(meta.join('  ·  '),
                      textAlign: TextAlign.center, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final label = '${c.name} card. ${c.power}';
    if (onTap == null) return Semantics(label: label, child: ExcludeSemantics(child: face));
    return Semantics(
      button: true,
      label: '$label Double tap for details.',
      child: ExcludeSemantics(child: GestureDetector(onTap: onTap, child: face)),
    );
  }
}

class _CardTag extends StatelessWidget {
  final String text;
  final bool gold;
  const _CardTag(this.text, {this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: gold ? GameColors.gold.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: gold ? GameColors.gold.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: gold ? GameColors.gold : Colors.white)),
    );
  }
}

/// Face-down card with a slow sheen: "tap to reveal".
class _CardBack extends StatelessWidget {
  final VoidCallback? onTap;
  const _CardBack({this.onTap});

  @override
  Widget build(BuildContext context) {
    final back = GameShimmer(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        width: double.infinity,
        height: 320,
        decoration: BoxDecoration(
          gradient: AppColors.cosmicGradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: GameColors.gold.withValues(alpha: 0.7), width: 1.5),
          boxShadow: AppShadows.raised,
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _StarfieldPainter(seed: 27, opacity: 0.5))),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: GameColors.gold.withValues(alpha: 0.25)),
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: GameColors.gold, width: 1.5),
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                      child: const Icon(Icons.nightlight_round, size: 36, color: GameColors.gold),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Tap to reveal',
                        textAlign: TextAlign.center, style: AppText.title.copyWith(color: Colors.white)),
                    const SizedBox(height: AppSpacing.xxs),
                    Text("today's nakshatra card",
                        textAlign: TextAlign.center, style: AppText.body.copyWith(color: AppColors.textOnDarkMuted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: "Today's card, face down. Double tap to reveal and collect it.",
      child: ExcludeSemantics(child: GestureDetector(onTap: onTap, child: back)),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  final int seed;
  final double opacity;
  const _StarfieldPainter({required this.seed, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint();
    for (var i = 0; i < 40; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      paint.color = Colors.white.withValues(alpha: opacity * (0.3 + rnd.nextDouble() * 0.7));
      canvas.drawCircle(o, 0.5 + rnd.nextDouble() * 1.1, paint);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => old.seed != seed || old.opacity != opacity;
}

/// Extra rare card won today: face-down until tapped, revealed one at a time.
class _BonusCard extends StatelessWidget {
  final CosmicCard card;
  final bool revealed;
  final bool locked;
  final VoidCallback onReveal;
  final VoidCallback onOpen;
  const _BonusCard({
    required this.card,
    required this.revealed,
    required this.locked,
    required this.onReveal,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (!revealed) {
      final child = GameCard(
        onTap: locked ? null : onReveal,
        semanticLabel: 'Bonus rare card. Double tap to reveal.',
        gradient: GameColors.night,
        borderColor: GameColors.gold.withValues(alpha: 0.6),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ExcludeSemantics(
          child: Row(
            children: [
              const GameIconTile(icon: Icons.redeem_rounded, color: GameColors.gold, size: 44, onDark: true),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Bonus rare card!', style: AppText.subtitle.copyWith(color: Colors.white)),
                    Text(locked ? 'Reveal the one above first' : 'Tap to reveal it',
                        style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: GameColors.gold),
            ],
          ),
        ),
      );
      return locked ? Opacity(opacity: 0.55, child: child) : GameShimmer(child: child);
    }
    final tile = GameCard(
      onTap: onOpen,
      semanticLabel: 'Rare card revealed: ${card.name}. Double tap for details.',
      gradient: _cardGradient(card),
      borderColor: GameColors.gold.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Text(card.symbol, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CardTag(CardRarity.label(card.rarity), gold: true),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(card.name, style: AppText.subtitle.copyWith(color: Colors.white)),
                  if (card.power.isNotEmpty)
                    Text(card.power, style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (gameReduceMotion(context)) return tile;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
      ),
      child: tile,
    );
  }
}

/// Album tile: collected cards in their colours, missing ones as quiet grey
/// tiles with the date the Moon reaches them (when known).
class _MiniCard extends StatelessWidget {
  final CosmicCard card;
  final int? number;
  final DateTime? arrival;
  final VoidCallback onTap;
  const _MiniCard({required this.card, required this.onTap, this.number, this.arrival});

  @override
  Widget build(BuildContext context) {
    final c = card;
    final got = c.collected;
    final when = arrival == null ? '' : DateFormat('d MMM').format(arrival!);
    final fg = got ? Colors.white : AppColors.textSecondary;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

    final String label;
    if (got) {
      label = '${c.name}, collected${c.isBirthStar ? ', your birth star' : ''}';
    } else if (when.isNotEmpty) {
      label = '${c.name}, not collected. ${c.isRare ? 'Arrives' : 'Moon arrives'} $when';
    } else {
      label = '${c.name}, not collected yet';
    }

    final radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(
                color: got ? null : AppColors.surface,
                gradient: got
                    ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _cardGradient(c))
                    : null,
                borderRadius: radius,
                border: Border.all(
                  color: c.isBirthStar || (got && c.rarity != CardRarity.common)
                      ? GameColors.gold
                      : (got ? Colors.transparent : AppColors.border),
                  width: c.isBirthStar ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (number != null)
                          Text('$number',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w700, color: fg.withValues(alpha: 0.7))),
                        const Spacer(),
                        if (c.isBirthStar)
                          const Icon(Icons.star_rounded, size: 12, color: GameColors.gold)
                        else if (!got)
                          const Icon(Icons.lock_outline_rounded, size: 11, color: AppColors.textTertiary),
                      ],
                    ),
                    Opacity(
                      opacity: got ? 1 : 0.3,
                      child: ColorFiltered(
                        colorFilter: got
                            ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                            : const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
                        child: Text(c.symbol, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        textScaler: scaler,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: got ? Colors.white : AppColors.textPrimary)),
                    Text(
                      got ? 'Collected' : (when.isNotEmpty ? when : 'Not yet'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      textScaler: scaler,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: got
                            ? AppColors.textOnDarkMuted
                            : (when.isNotEmpty ? AppColors.primaryDark : AppColors.textTertiary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final CardSet set;
  final bool busy;
  final VoidCallback onClaim;
  const _SetRow({required this.set, required this.busy, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final s = set;
    final color = s.claimed ? AppColors.textTertiary : (s.complete ? GameColors.good : AppColors.primary);
    return GameCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      borderColor: s.canClaim ? GameColors.good.withValues(alpha: 0.5) : null,
      glow: s.canClaim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.name, style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          XpBar(
            progress: s.progress,
            color: color,
            label: '${s.collected}/${s.size} cards',
            semanticLabel: '${s.name}: ${s.collected} of ${s.size} cards',
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              GamePill(
                'Reward: ${s.reward.label}',
                color: s.reward.isWallet ? GameColors.good : GameColors.goldDeep,
                icon: s.reward.isWallet ? Icons.account_balance_wallet_rounded : Icons.bolt_rounded,
                fontSize: 12,
              ),
              if (s.claimed)
                const GamePill('Claimed', color: GameColors.muted, icon: Icons.check_rounded, fontSize: 12)
              else if (s.complete)
                Semantics(
                  button: true,
                  label: 'Claim ${s.reward.label} for ${s.name}',
                  child: ExcludeSemantics(
                    child: AppButton(
                      label: 'Claim',
                      icon: Icons.redeem_rounded,
                      expand: false,
                      height: 44,
                      loading: busy,
                      onPressed: onClaim,
                    ),
                  ),
                )
              else
                Text('${s.size - s.collected} more to unlock', style: AppText.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardSheet extends StatelessWidget {
  final CosmicCard card;
  final DateTime? arrival;
  const _CardSheet({required this.card, this.arrival});

  @override
  Widget build(BuildContext context) {
    final c = card;
    final String note;
    if (c.collected) {
      note =
          c.collectedOn != null ? 'Collected on ${DateFormat('d MMM yyyy').format(c.collectedOn!)}' : 'In your album';
    } else if (arrival != null) {
      note =
          '${c.isRare ? 'Arrives' : 'Moon arrives'} ${DateFormat('d MMM').format(arrival!)} — open the app that day to collect it.';
    } else if (c.isRare && c.how != null) {
      note = c.how!;
    } else if (c.isRare && c.date != null) {
      note = 'Arrives ${DateFormat('d MMM yyyy').format(c.date!)} — open the app that day to collect it.';
    } else if (c.isRare) {
      note = 'A rare card. It drops on a special sky day, so keep playing.';
    } else {
      note = 'Not collected yet. The Moon visits every nakshatra about once a month.';
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: c.collected
                    ? CardFace(card: c)
                    : Opacity(
                        opacity: 0.75,
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.matrix(<double>[
                            0.2126, 0.7152, 0.0722, 0, 0, //
                            0.2126, 0.7152, 0.0722, 0, 0, //
                            0.2126, 0.7152, 0.0722, 0, 0, //
                            0, 0, 0, 1, 0,
                          ]),
                          child: CardFace(card: c),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(c.collected ? Icons.check_circle_rounded : Icons.nightlight_round,
                        size: 16, color: c.collected ? GameColors.good : AppColors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text(note, textAlign: TextAlign.center, style: AppText.bodyStrong)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
