import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/game_widgets.dart';
import '../../widgets/moksha_board.dart';
import '../../widgets/ui/app_ui.dart';

/// Moksha Patam — the original karma Snakes & Ladders. The dice are rolled on
/// the server; this screen only animates what the server decided.
class MokshaPatamScreen extends StatefulWidget {
  const MokshaPatamScreen({super.key});

  @override
  State<MokshaPatamScreen> createState() => _MokshaPatamScreenState();
}

enum _MsgKind { move, ladder, snake, overshoot, win }

class _RollMessage {
  final _MsgKind kind;
  final IconData icon;
  final String title;
  final String body;
  final String line;
  const _RollMessage(this.kind, this.icon, this.title, this.body, [this.line = '']);

  Color get color {
    switch (kind) {
      case _MsgKind.ladder:
        return MokshaColors.ladder;
      case _MsgKind.snake:
        return MokshaColors.snake;
      case _MsgKind.win:
        return MokshaColors.goldDeep;
      case _MsgKind.overshoot:
        return AppColors.info;
      case _MsgKind.move:
        return AppColors.textPrimary;
    }
  }
}

class _MokshaPatamScreenState extends State<MokshaPatamScreen> with TickerProviderStateMixin {
  late final BackendService _service;
  late final AnimationController _move;
  late final AnimationController _spin;
  final math.Random _rnd = math.Random();
  Timer? _tumble;
  Timer? _clock;

  bool _loading = true;
  bool _noKundli = false;
  String? _error;
  int _loadToken = 0;

  List<MokshaJump> _ladders = const [];
  List<MokshaJump> _snakes = const [];
  List<MokshaPlayer> _players = const [];
  List<MokshaMove> _moves = const [];
  String _activeKey = 'self';

  /// Square each token is drawn on (the server position, except mid-animation).
  final Map<String, int> _shown = {};
  final Map<String, String> _noRollsNotes = {};

  String? _animKey;
  Offset Function(double t)? _path;
  Curve _curve = Curves.linear;
  bool _sparkle = false;

  bool _busy = false;
  bool _tumbling = false;
  int _face = 1;
  _RollMessage? _message;

  @override
  void initState() {
    super.initState();
    _service = Provider.of<BackendService>(context, listen: false);
    // Created eagerly: dispose() must never be the first thing to touch them.
    _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 170));
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_busy && (_active?.rollsLeft ?? 1) <= 0) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _tumble?.cancel();
    _clock?.cancel();
    _move.dispose();
    _spin.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Data
  // --------------------------------------------------------------------------

  MokshaPlayer? get _active {
    for (final p in _players) {
      if (p.profileKey == _activeKey) return p;
    }
    return _players.isEmpty ? null : _players.first;
  }

  int _indexOf(String key) => math.max(0, _players.indexWhere((p) => p.profileKey == key));

  Future<void> _load() async {
    if (_busy) return;
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
      _noKundli = false;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await _service.fetchMokshaBoard();
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _loadToken) return;
    final board = raw == null ? null : MokshaBoard.fromJson(raw);
    setState(() {
      _loading = false;
      if (board != null && board.players.isNotEmpty) {
        _ladders = board.ladders.where((l) => l.isLadder).toList();
        _snakes = board.snakes.where((l) => !l.isLadder).toList();
        _moves = board.lastMoves;
        _applyPlayers(board.players);
      } else {
        _noKundli = raw == null && _service.lastErrorCode == 'NO_KUNDLI';
        _error = (raw == null ? _service.lastError : null) ?? 'Could not load the board. Please try again.';
      }
    });
  }

  /// Server truth: positions and rolls always come from the latest response.
  void _applyPlayers(List<MokshaPlayer> players) {
    // "You" first so your token keeps the same colour.
    _players = [...players.where((p) => p.isYou), ...players.where((p) => !p.isYou)];
    _shown
      ..clear()
      ..addEntries(_players.map((p) => MapEntry(p.profileKey, p.position)));
    if (!_players.any((p) => p.profileKey == _activeKey)) _activeKey = _players.first.profileKey;
    _noRollsNotes.removeWhere((key, _) => _players.any((p) => p.profileKey == key && p.rollsLeft > 0));
  }

  void _select(MokshaPlayer p) {
    if (_busy || p.profileKey == _activeKey) return;
    setState(() {
      _activeKey = p.profileKey;
      _message = null;
    });
  }

  // --------------------------------------------------------------------------
  // Roll flow
  // --------------------------------------------------------------------------

  void _startTumble() {
    _tumbling = true;
    _spin.repeat();
    _tumble?.cancel();
    _tumble = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (mounted) setState(() => _face = 1 + _rnd.nextInt(6));
    });
  }

  void _stopTumble() {
    _tumble?.cancel();
    _tumble = null;
    _tumbling = false;
    _spin
      ..stop()
      ..value = 0;
  }

  Future<bool> _animate(String key, Offset Function(double) path, Duration duration,
      {Curve curve = Curves.linear, bool sparkle = false}) async {
    setState(() {
      _animKey = key;
      _path = path;
      _curve = curve;
      _sparkle = sparkle;
    });
    _move.duration = duration;
    try {
      await _move.forward(from: 0).orCancel;
    } on TickerCanceled {
      return false;
    }
    return mounted;
  }

  Future<void> _roll() async {
    final p = _active;
    if (_busy || _loading || p == null || p.rollsLeft <= 0) return;
    final reduce = MediaQuery.of(context).disableAnimations;
    final key = p.profileKey;
    setState(() {
      _busy = true;
      _message = null;
      if (!reduce) _startTumble();
    });

    final suspense = reduce ? Future<void>.value() : Future<void>.delayed(const Duration(milliseconds: 650));
    Map<String, dynamic>? raw;
    try {
      raw = await _service.rollMokshaDice(profileKey: key);
    } catch (_) {
      raw = null;
    }
    await suspense;
    if (!mounted) return;
    _stopTumble();

    if (raw == null) {
      _rollFailed(key);
      return;
    }
    await _play(MokshaRollResult.fromJson(raw), p, reduce);
  }

  void _rollFailed(String key) {
    final code = _service.lastErrorCode;
    final msg = _service.lastError;
    // The server says when and how the next roll arrives.
    final hint = _service.lastErrorData?['nextRollHint'];
    setState(() {
      _busy = false;
      if (code == 'NO_ROLLS_LEFT') {
        _noRollsNotes[key] = hint is String && hint.trim().isNotEmpty ? hint.trim() : (msg ?? '');
        _players = [
          for (final p in _players)
            if (p.profileKey == key)
              MokshaPlayer(
                profileKey: p.profileKey,
                name: p.name,
                relationship: p.relationship,
                position: p.position,
                wins: p.wins,
                rollsLeft: 0,
                isYou: p.isYou,
                luck: p.luck,
              )
            else
              p,
        ];
      } else if (code == 'NO_KUNDLI') {
        _noKundli = true;
        _players = const [];
      }
    });
    if (code == 'NO_ROLLS_LEFT' || code == 'NO_KUNDLI') return;
    showAppSnack(context, msg ?? 'The dice slipped away. Please try again.', error: true);
    if (code == 'PLAYER_NOT_FOUND') _load();
  }

  Future<void> _play(MokshaRollResult r, MokshaPlayer who, bool reduce) async {
    final key = who.profileKey;
    final from = r.from;
    final landed = r.overshoot ? from : math.max(from, r.landed);
    final ev = r.event;
    // After Moksha the server sends the token back to 1; the celebration happens on 100.
    final rest = r.won ? MokshaGeometry.goal : r.to;

    setState(() {
      _face = r.dice;
      _shown[key] = from;
    });

    if (!reduce) {
      // A beat to read the dice before the token moves.
      final start = MokshaGeometry.unitCenter(from);
      if (!await _animate(key, (_) => start, const Duration(milliseconds: 320))) return;
      for (var s = from; s < landed; s++) {
        final a = MokshaGeometry.unitCenter(s);
        final b = MokshaGeometry.unitCenter(s + 1);
        if (!await _animate(key, (t) => MokshaGeometry.hop(a, b, t), const Duration(milliseconds: 170))) return;
        _shown[key] = s + 1;
      }
    }
    if (!mounted) return;

    final message = _messageFor(r, who, landed, rest);
    setState(() {
      _animKey = null;
      _shown[key] = landed;
      _message = message;
    });

    if (rest != landed) {
      if (!reduce) {
        final a = MokshaGeometry.unitCenter(landed);
        final b = MokshaGeometry.unitCenter(rest);
        final climbing = rest > landed;
        final ok = climbing
            ? await _animate(key, (t) => Offset.lerp(a, b, t)!, const Duration(milliseconds: 900),
                curve: Curves.easeInOutCubic, sparkle: true)
            : await _animate(key, (t) => MokshaGeometry.snakePoint(a, b, t, cell: 1 / MokshaGeometry.side),
                const Duration(milliseconds: 1100),
                curve: Curves.easeInOut);
        if (!ok) return;
      }
      setState(() {
        _animKey = null;
        _sparkle = false;
        _shown[key] = rest;
      });
    }

    if (!mounted) return;
    if (r.won) {
      await showDialog<void>(
        context: context,
        builder: (_) => _MokshaWinDialog(name: who.name, isYou: who.isYou, reward: r.reward, wins: who.wins + 1),
      );
      if (!mounted) return;
    }

    setState(() {
      _animKey = null;
      _sparkle = false;
      if (r.players.isNotEmpty) {
        _applyPlayers(r.players);
      } else {
        _applyPlayers([
          for (final p in _players)
            if (p.profileKey == key)
              MokshaPlayer(
                profileKey: p.profileKey,
                name: p.name,
                relationship: p.relationship,
                position: r.won ? 1 : r.to,
                wins: p.wins + (r.won ? 1 : 0),
                rollsLeft: r.rollsLeft,
                isYou: p.isYou,
                luck: p.luck,
              )
            else
              p,
        ]);
      }
      _moves = [
        MokshaMove(
          profileKey: key,
          name: who.name,
          dice: r.dice,
          from: from,
          to: r.won ? MokshaGeometry.goal : r.to,
          // Same display strings the server uses in lastMoves.
          event: r.won
              ? 'Moksha!'
              : (r.overshoot
                  ? 'Needs an exact roll'
                  : (ev == null ? null : '${ev.isLadder ? 'Ladder' : 'Snake'}: ${ev.name}')),
          at: DateTime.now(),
        ),
        ..._moves,
      ].take(10).toList();
      _busy = false;
    });
  }

  _RollMessage _messageFor(MokshaRollResult r, MokshaPlayer who, int landed, int rest) {
    final you = who.isYou;
    final subject = you ? 'You' : who.name;
    final ev = r.event;
    if (r.won) {
      return _RollMessage(_MsgKind.win, Icons.self_improvement_rounded, 'Moksha!',
          '$subject rolled a ${r.dice} and reached square 100. The journey begins again from square 1.');
    }
    if (r.overshoot) {
      final need = MokshaGeometry.goal - r.from;
      return _RollMessage(_MsgKind.overshoot, Icons.gps_fixed_rounded, 'So close!',
          '$subject rolled a ${r.dice}, but Moksha needs exactly $need. ${you ? 'You stay' : '${who.name} stays'} on ${r.from} — the next roll could be the one.');
    }
    if (ev != null && rest != landed) {
      if (rest > landed) {
        return _RollMessage(_MsgKind.ladder, Icons.trending_up_rounded, 'Ladder! ${ev.name}',
            '$subject rolled a ${r.dice} and climbed from $landed to $rest.', ev.line);
      }
      return _RollMessage(
          _MsgKind.snake,
          Icons.trending_down_rounded,
          'A little slip: ${ev.name}',
          '$subject rolled a ${r.dice} and slid from $landed to $rest. Every sage slipped here once — the next ladder is waiting.',
          ev.line);
    }
    return _RollMessage(_MsgKind.move, Icons.casino_rounded, '$subject rolled a ${r.dice}',
        'Hopped from ${r.from} to $landed. Onward!');
  }

  // --------------------------------------------------------------------------
  // Sheets
  // --------------------------------------------------------------------------

  Future<void> _sheet(List<Widget> Function(BuildContext) children) {
    return showAppSheet<void>(
      context,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children(ctx),
            ),
          ),
        ),
      ),
    );
  }

  Widget _jumpTile(MokshaJump j) {
    final ladder = j.isLadder;
    final color = ladder ? MokshaColors.ladder : MokshaColors.snake;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: GameIconTile(
                icon: ladder ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: color, size: 36),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(j.name.isEmpty ? (ladder ? 'A ladder' : 'A snake') : j.name, style: AppText.subtitle),
                Text('${ladder ? 'Ladder · climbs' : 'Snake · slides'} from ${j.from} to ${j.to}',
                    style: AppText.caption.copyWith(color: color)),
                if (j.line.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(j.line, style: AppText.body),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onSquareTap(int square) {
    final hits = [
      ..._ladders.where((l) => l.from == square || l.to == square),
      ..._snakes.where((l) => l.from == square || l.to == square),
    ];
    if (hits.isEmpty && square != MokshaGeometry.goal && square != 1) return;
    _sheet((_) => [
          Text('Square $square', style: AppText.title),
          const SizedBox(height: AppSpacing.sm),
          if (square == MokshaGeometry.goal)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                  'Moksha: freedom, the end of the journey. Land here with an exact roll to win, then begin again a little wiser.',
                  style: AppText.body),
            ),
          if (square == 1)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text('Where every journey begins. One roll at a time.', style: AppText.body),
            ),
          for (final j in hits) _jumpTile(j),
        ]);
  }

  void _howToPlay() {
    Widget step(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: GameIconTile(icon: icon, color: AppColors.textSecondary, size: 32)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(text, style: AppText.body.copyWith(color: AppColors.textPrimary)),
                ),
              ),
            ],
          ),
        );
    _sheet((_) => [
          const Text('How to play', style: AppText.headline),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Moksha Patam is the ancient Indian game of karma, the great-grandparent of Snakes & Ladders. '
            'Good deeds lift you, slips pull you back, and everyone gets home in the end.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.md),
          step(Icons.casino_outlined, 'Tap the dice. Your token hops that many squares.'),
          step(Icons.trending_up_rounded, 'Land at the foot of a ladder (a virtue) and climb straight up.'),
          step(Icons.trending_down_rounded,
              'Land on a snake\'s head (a slip) and slide down its tail. No drama, just roll again.'),
          step(Icons.flag_rounded, 'Reach square 100 with an exact roll to win Moksha, a rare card and a pile of XP.'),
          step(Icons.today_rounded,
              'You get 1 roll a day, +1 when the Moon is kind to your birth star, +1 for finishing all 3 missions.'),
          step(Icons.groups_rounded, 'Your family plays on the same board. Tap a name to roll for them.'),
          if (_ladders.isNotEmpty) ...[
            const GameSectionTitle('Ladders on this board'),
            for (final l in _ladders) _jumpTile(l),
          ],
          if (_snakes.isNotEmpty) ...[
            const GameSectionTitle('Snakes on this board'),
            for (final s in _snakes) _jumpTile(s),
          ],
        ]);
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_noKundli && _players.isEmpty) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        child: GameNoKundli(onCreate: () => Navigator.pushNamed(context, AppRoutes.birthDetails)),
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _players.isNotEmpty
                ? _content()
                : [
                    if (_error != null && !_loading)
                      GameError(message: _error!, onRetry: _load)
                    else
                      const GameSkeleton(blocks: [56, 288, 84, 60, 60], label: 'Setting up the board'),
                  ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: gameAppBar(
        title: 'Moksha Patam',
        subtitle: 'The game of karma',
        actions: [
          IconButton(
            tooltip: 'How to play',
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: _howToPlay,
          ),
        ],
      ),
      body: body,
    );
  }

  List<Widget> _content() {
    final active = _active!;
    return [
      _luckBanner(active),
      const SizedBox(height: AppSpacing.sm),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedBuilder(animation: _move, builder: (context, _) => _board()),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: _message == null
            ? const SizedBox(width: double.infinity)
            : Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _messageCard(_message!)),
      ),
      if (active.rollsLeft > 0 || _busy) _rollButton(active) else _noRollsCard(active),
      const GameSectionTitle('Players'),
      for (final p in _players) _playerTile(p),
      const SizedBox(height: AppSpacing.xs),
      _moreRollsCard(active),
      if (_moves.isNotEmpty) ...[
        const GameSectionTitle('Recent moves'),
        AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxs),
          child: Column(children: [for (final m in _moves) _moveRow(m)]),
        ),
      ],
    ];
  }

  String _initial(MokshaPlayer p) => p.name.trim().isEmpty ? '?' : p.name.trim().characters.first.toUpperCase();

  Widget _board() {
    final groups = <int, int>{};
    final seen = <int, int>{};
    for (final p in _players) {
      if (p.profileKey == _animKey) continue;
      final sq = _shown[p.profileKey] ?? p.position;
      groups[sq] = (groups[sq] ?? 0) + 1;
    }
    Offset? sparkleAt;
    final tokens = <MokshaToken>[];
    for (var i = 0; i < _players.length; i++) {
      final p = _players[i];
      Offset c;
      final path = _path;
      if (p.profileKey == _animKey && path != null) {
        c = path(_curve.transform(_move.value));
        if (_sparkle) sparkleAt = c;
      } else {
        final sq = _shown[p.profileKey] ?? p.position;
        final n = groups[sq] ?? 1;
        final k = seen[sq] ?? 0;
        seen[sq] = k + 1;
        c = MokshaGeometry.unitCenter(sq) + Offset((k - (n - 1) / 2) * 0.03, n > 1 ? (k.isEven ? -0.008 : 0.008) : 0);
      }
      tokens.add(MokshaToken(
        id: p.profileKey,
        label: _initial(p),
        color: MokshaColors.token(i),
        center: c,
        active: p.profileKey == _activeKey,
      ));
    }
    final where =
        _players.map((p) => '${p.isYou ? 'You' : p.name} on square ${_shown[p.profileKey] ?? p.position}').join(', ');
    return MokshaBoardView(
      ladders: _ladders,
      snakes: _snakes,
      tokens: tokens,
      sparkleAt: sparkleAt,
      sparkleT: _move.value,
      onSquareTap: _busy ? null : _onSquareTap,
      semanticLabel: 'Moksha Patam board, 100 squares. $where.',
    );
  }

  Widget _luckBanner(MokshaPlayer p) {
    final luck = p.luck;
    final bonus = luck.favorable && !luck.chandrashtama;
    final color = luck.chandrashtama ? AppColors.info : (bonus ? AppColors.success : AppColors.warning);
    final line = luck.line.isNotEmpty
        ? luck.line
        : (luck.tara.isNotEmpty ? '${luck.tara} Tara today' : 'The sky is quiet today, a calm day to play.');
    return Semantics(
      container: true,
      label: 'Today\'s luck for ${p.isYou ? 'you' : p.name}',
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GameIconTile(
                icon: luck.chandrashtama ? Icons.nightlight_round : Icons.auto_awesome_rounded, color: color, size: 36),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line, style: AppText.bodyStrong),
                  if (bonus)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xxs),
                      child: GamePill('Lucky star day · +1 roll', color: AppColors.success, icon: Icons.casino_rounded),
                    )
                  else if (luck.chandrashtama)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child:
                          Text('A gentle day: no bonus roll from the stars, so play it easy.', style: AppText.caption),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(_RollMessage m) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('moksha-message'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.card,
          border: Border.all(color: m.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: GameIconTile(icon: m.icon, color: m.color, size: 40)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, style: AppText.subtitle.copyWith(color: m.color)),
                  if (m.line.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(m.line, style: AppText.bodyStrong.copyWith(fontStyle: FontStyle.italic)),
                    ),
                  const SizedBox(height: 2),
                  Text(m.body, style: AppText.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _rollsText(int n) => n <= 0 ? 'No rolls left' : (n == 1 ? '1 roll left' : '$n rolls left');

  Widget _rollButton(MokshaPlayer p) {
    final title = _busy ? (_tumbling ? 'Rolling…' : 'Moving…') : (p.isYou ? 'Roll the dice' : 'Roll for ${p.name}');
    return Semantics(
      button: true,
      enabled: !_busy,
      label: '$title. ${_rollsText(p.rollsLeft)} today',
      child: Material(
        key: const Key('moksha-roll'),
        color: AppColors.cosmic,
        borderRadius: AppRadius.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : _roll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) =>
                        MokshaDice(value: _face, size: 52, angle: _tumbling ? _spin.value * 2 * math.pi : 0),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title.copyWith(color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('${_rollsText(p.rollsLeft)} today',
                            style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textOnDarkMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _untilMidnight() {
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${math.max(1, m)}m';
  }

  Widget _noRollsCard(MokshaPlayer p) {
    final note = _noRollsNotes[p.profileKey] ?? '';
    final others = _players.where((o) => o.profileKey != p.profileKey && o.rollsLeft > 0).toList();
    return AppCard(
      key: const Key('moksha-no-rolls'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Opacity(opacity: 0.5, child: MokshaDice(value: _face, size: 36)),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('The dice are resting', style: AppText.title)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            note.isNotEmpty
                ? note
                : '${p.isYou ? 'You\'ve' : '${p.name} has'} used every roll for today. Come back tomorrow — the board remembers exactly where you stand.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          GamePill('New rolls in ${_untilMidnight()}', color: AppColors.textSecondary, icon: Icons.schedule_rounded),
          if (note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('Come back tomorrow — the board remembers exactly where you stand.', style: AppText.caption),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final o in others)
                  AppButton(
                    label: 'Roll for ${o.isYou ? 'yourself' : o.name}',
                    icon: Icons.casino_outlined,
                    variant: AppButtonVariant.outline,
                    expand: false,
                    height: 44,
                    onPressed: () => _select(o),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _playerTile(MokshaPlayer p) {
    final selected = p.profileKey == _activeKey;
    final color = MokshaColors.token(_indexOf(p.profileKey));
    final square = _shown[p.profileKey] ?? p.position;
    final sub = [
      if (!p.isYou && (p.relationship ?? '').isNotEmpty) p.relationship!,
      'Square $square',
      _rollsText(p.rollsLeft),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${p.isYou ? 'You' : p.name}, $sub${p.wins > 0 ? ', ${p.wins} wins' : ''}',
        hint: selected ? null : 'Tap to play as ${p.isYou ? 'yourself' : p.name}',
        child: Material(
          key: ValueKey('moksha-player-${p.profileKey}'),
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: selected ? AppColors.textPrimary : AppColors.border, width: selected ? 1.4 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _busy ? null : () => _select(p),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    MokshaTokenDot(label: _initial(p), color: color, size: 32),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.isYou ? '${p.name} (you)' : p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                          Text(sub, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    if (p.wins > 0) ...[
                      const SizedBox(width: 6),
                      GamePill('${p.wins}', color: MokshaColors.goldDeep, icon: Icons.emoji_events_rounded),
                    ],
                    if (selected) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.textPrimary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _moreRollsCard(MokshaPlayer active) {
    Widget row(IconData icon, String text, {Widget? action}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: AppText.body.copyWith(color: AppColors.textPrimary)),
                    if (action != null) action,
                  ],
                ),
              ),
            ],
          ),
        );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Want more rolls?', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.sm),
          row(Icons.today_rounded, 'Everyone gets 1 free roll every day.'),
          row(Icons.auto_awesome_rounded,
              'Lucky star days: when the Moon is kind to your birth star, you get +1 roll.'),
          row(
            Icons.task_alt_rounded,
            'Finish all 3 of today\'s missions for +1 roll.',
            action: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.gamesQuest),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Go to today\'s missions'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moveRow(MokshaMove m) {
    // `event` is a display string from the server ("Ladder: Generosity", "Snake: Ego", "Moksha!", ...).
    final ev = (m.event ?? '').toLowerCase();
    final IconData icon;
    final Color color;
    if (ev.contains('moksha')) {
      icon = Icons.self_improvement_rounded;
      color = MokshaColors.goldDeep;
    } else if (ev.startsWith('ladder')) {
      icon = Icons.trending_up_rounded;
      color = MokshaColors.ladder;
    } else if (ev.startsWith('snake')) {
      icon = Icons.trending_down_rounded;
      color = MokshaColors.snake;
    } else if (ev.isNotEmpty && m.to == m.from) {
      icon = Icons.gps_fixed_rounded;
      color = AppColors.info;
    } else if (ev.isNotEmpty) {
      final up = m.to > m.from;
      icon = up ? Icons.trending_up_rounded : Icons.trending_down_rounded;
      color = up ? MokshaColors.ladder : MokshaColors.snake;
    } else {
      icon = Icons.casino_outlined;
      color = AppColors.textTertiary;
    }
    final name = m.name.isEmpty ? 'Player' : m.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(child: Icon(icon, size: 16, color: color)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: m.dice > 0 ? ' rolled ${m.dice}: ' : ': '),
                TextSpan(text: '${m.from} → ${m.to}'),
                if ((m.event ?? '').isNotEmpty)
                  TextSpan(text: ' · ${m.event}', style: const TextStyle(color: AppColors.textSecondary)),
              ]),
              style: AppText.body.copyWith(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Win celebration
// ============================================================================

class _MokshaWinDialog extends StatelessWidget {
  final String name;
  final bool isYou;
  final MokshaReward? reward;
  final int wins;
  const _MokshaWinDialog({required this.name, required this.isYou, required this.reward, required this.wins});

  @override
  Widget build(BuildContext context) {
    final card = reward?.card;
    final xp = reward?.xp ?? 0;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Container(
                            width: 72,
                            height: 72,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: MokshaColors.gold.withValues(alpha: 0.14),
                              border: Border.all(color: MokshaColors.gold, width: 1.5),
                            ),
                            child: const Text('ॐ',
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(fontSize: 34, height: 1.1, color: MokshaColors.goldDeep)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Semantics(header: true, child: const Text('Moksha!', style: AppText.display)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${isYou ? 'You' : name} climbed every ladder, outlasted every snake and reached square 100.',
                          textAlign: TextAlign.center,
                          style: AppText.body,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (xp > 0)
                              GamePill('+$xp XP', color: AppColors.success, icon: Icons.bolt_rounded, fontSize: 12.5),
                            GamePill(wins == 1 ? 'First Moksha' : 'Moksha × $wins',
                                color: MokshaColors.goldDeep, icon: Icons.emoji_events_rounded, fontSize: 12.5),
                          ],
                        ),
                        if (card != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Row(
                              children: [
                                ExcludeSemantics(child: Text(card.symbol, style: const TextStyle(fontSize: 28))),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Rare card unlocked',
                                          style: AppText.caption.copyWith(color: MokshaColors.goldDeep)),
                                      Text(card.name, style: AppText.subtitle),
                                      if (card.power.isNotEmpty) Text(card.power, style: AppText.caption),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppButton(label: 'Begin a new journey', onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          const Positioned.fill(child: ConfettiBurst(particleCount: 40, origin: Alignment(0, -0.5))),
        ],
      ),
    );
  }
}
