import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../widgets/forecast_widgets.dart' show FC, ForecastCard, Pill, SectionLabel;
import '../../widgets/game_widgets.dart' show ConfettiBurst, GameError, GameNoKundli, GameSkeleton;
import '../../widgets/moksha_board.dart';

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
  final String emoji;
  final String title;
  final String body;
  final String line;
  const _RollMessage(this.kind, this.emoji, this.title, this.body, [this.line = '']);

  Color get color {
    switch (kind) {
      case _MsgKind.ladder:
        return MokshaColors.ladder;
      case _MsgKind.snake:
        return MokshaColors.snake;
      case _MsgKind.win:
        return MokshaColors.goldDeep;
      case _MsgKind.overshoot:
        return FC.violet;
      case _MsgKind.move:
        return FC.blue;
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
    _buzz(HapticFeedback.selectionClick);
    setState(() {
      _activeKey = p.profileKey;
      _message = null;
    });
  }

  // --------------------------------------------------------------------------
  // Roll flow
  // --------------------------------------------------------------------------

  void _buzz(Future<void> Function() feedback) {
    feedback().catchError((Object _) {});
  }

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
    _buzz(HapticFeedback.mediumImpact);

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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg ?? 'The dice slipped away. Please try again.')));
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
    _buzz(HapticFeedback.lightImpact);

    if (!reduce) {
      // A beat to read the dice before the token moves.
      final start = MokshaGeometry.unitCenter(from);
      if (!await _animate(key, (_) => start, const Duration(milliseconds: 320))) return;
      for (var s = from; s < landed; s++) {
        final a = MokshaGeometry.unitCenter(s);
        final b = MokshaGeometry.unitCenter(s + 1);
        if (!await _animate(key, (t) => MokshaGeometry.hop(a, b, t), const Duration(milliseconds: 170))) return;
        _shown[key] = s + 1;
        _buzz(HapticFeedback.selectionClick);
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
        _buzz(climbing ? HapticFeedback.mediumImpact : HapticFeedback.heavyImpact);
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
      _buzz(HapticFeedback.heavyImpact);
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
      return _RollMessage(_MsgKind.win, '🕉', 'Moksha!',
          '$subject rolled a ${r.dice} and reached square 100. The journey begins again from square 1.');
    }
    if (r.overshoot) {
      final need = MokshaGeometry.goal - r.from;
      return _RollMessage(_MsgKind.overshoot, '🎯', 'So close!',
          '$subject rolled a ${r.dice}, but Moksha needs exactly $need. ${you ? 'You stay' : '${who.name} stays'} on ${r.from} — the next roll could be the one.');
    }
    if (ev != null && rest != landed) {
      if (rest > landed) {
        return _RollMessage(_MsgKind.ladder, '🪜', 'Ladder! ${ev.name}',
            '$subject rolled a ${r.dice} and climbed from $landed to $rest.', ev.line);
      }
      return _RollMessage(
          _MsgKind.snake,
          '🐍',
          'A little slip: ${ev.name}',
          '$subject rolled a ${r.dice} and slid from $landed to $rest. Every sage slipped here once — the next ladder is waiting.',
          ev.line);
    }
    return _RollMessage(
        _MsgKind.move, '🎲', '$subject rolled a ${r.dice}', 'Hopped from ${r.from} to $landed. Onward!');
  }

  // --------------------------------------------------------------------------
  // Sheets
  // --------------------------------------------------------------------------

  Future<void> _sheet(List<Widget> Function(BuildContext) children) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(ladder ? '🪜' : '🐍', style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(j.name.isEmpty ? (ladder ? 'A ladder' : 'A snake') : j.name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
                Text('${ladder ? 'Ladder · climbs' : 'Snake · slides'} from ${j.from} to ${j.to}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (j.line.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(j.line, style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade900)),
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
    _buzz(HapticFeedback.selectionClick);
    _sheet((_) => [
          Text('Square $square', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (square == MokshaGeometry.goal)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                  '🕉 Moksha — freedom, the end of the journey. Land here with an exact roll to win, then begin again a little wiser.',
                  style: TextStyle(fontSize: 14, height: 1.45)),
            ),
          if (square == 1)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child:
                  Text('Where every journey begins. One roll at a time.', style: TextStyle(fontSize: 14, height: 1.45)),
            ),
          for (final j in hits) _jumpTile(j),
        ]);
  }

  void _howToPlay() {
    Widget step(String emoji, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 18))),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45))),
            ],
          ),
        );
    _sheet((_) => [
          const Text('How to play', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'Moksha Patam is the ancient Indian game of karma — the great-grandparent of Snakes & Ladders. '
            'Good deeds lift you, slips pull you back, and everyone gets home in the end.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 14),
          step('🎲', 'Tap the dice. Your token hops that many squares.'),
          step('🪜', 'Land at the foot of a ladder — a virtue — and climb straight up.'),
          step('🐍', 'Land on a snake\'s head — a slip — and slide down its tail. No drama, just roll again.'),
          step('🕉', 'Reach square 100 with an exact roll to win Moksha, a rare card and a pile of XP.'),
          step('⭐',
              'You get 1 roll a day, +1 when the Moon is kind to your birth star, +1 for finishing all 3 missions.'),
          step('👨‍👩‍👧', 'Your family plays on the same board. Tap a name to roll for them.'),
          if (_ladders.isNotEmpty) ...[
            const SectionLabel('Ladders on this board'),
            for (final l in _ladders) _jumpTile(l),
          ],
          if (_snakes.isNotEmpty) ...[
            const SectionLabel('Snakes on this board'),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: GameNoKundli(onCreate: () => Navigator.pushNamed(context, '/birth-details')),
      );
    } else {
      body = RefreshIndicator(
        color: MokshaColors.maroon,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
      backgroundColor: FC.bg,
      appBar: AppBar(
        backgroundColor: FC.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Moksha Patam',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 18)),
            Text('The game of karma',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'How to play',
            icon: const Icon(Icons.help_outline_rounded, color: Colors.black),
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
      const SizedBox(height: 12),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedBuilder(animation: _move, builder: (context, _) => _board()),
        ),
      ),
      const SizedBox(height: 12),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: _message == null
            ? const SizedBox(width: double.infinity)
            : Padding(padding: const EdgeInsets.only(bottom: 12), child: _messageCard(_message!)),
      ),
      if (active.rollsLeft > 0 || _busy) _rollButton(active) else _noRollsCard(active),
      const SectionLabel('Players'),
      for (final p in _players) _playerTile(p),
      const SizedBox(height: 6),
      _moreRollsCard(active),
      if (_moves.isNotEmpty) ...[
        const SectionLabel('Recent moves'),
        ForecastCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
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
    final color = luck.chandrashtama ? const Color(0xFF4F46E5) : (bonus ? FC.good : const Color(0xFFB45309));
    final line = luck.line.isNotEmpty
        ? luck.line
        : (luck.tara.isNotEmpty ? '${luck.tara} Tara today' : 'The sky is quiet today — a calm day to play.');
    return Semantics(
      container: true,
      label: 'Today\'s luck for ${p.isYou ? 'you' : p.name}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(luck.chandrashtama ? Icons.nightlight_round : Icons.auto_awesome, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line, style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w700)),
                  if (bonus)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Pill('Lucky star day · +1 roll', color: FC.good, icon: Icons.casino_rounded),
                    )
                  else if (luck.chandrashtama)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('A gentle day: no bonus roll from the stars, so play it easy.',
                          style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade700)),
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: m.color.withValues(alpha: 0.45), width: 1.4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Text(m.emoji, style: const TextStyle(fontSize: 26))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: m.color)),
                  if (m.line.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(m.line,
                          style: const TextStyle(
                              fontSize: 13.5, height: 1.4, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 3),
                  Text(m.body, style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade800)),
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
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF9A3412), MokshaColors.maroon], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(color: MokshaColors.maroon.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: _busy ? null : _roll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _spin,
                      builder: (context, _) =>
                          MokshaDice(value: _face, size: 56, angle: _tumbling ? _spin.value * 2 * math.pi : 0),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text('${_rollsText(p.rollsLeft)} today',
                              style: const TextStyle(
                                  color: Color(0xFFFFE2B8), fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ],
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
    return ForecastCard(
      key: const Key('moksha-no-rolls'),
      color: const Color(0xFFFFFBF5),
      borderColor: MokshaColors.gold.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Opacity(opacity: 0.55, child: MokshaDice(value: _face, size: 40)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('The dice are resting', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            note.isNotEmpty
                ? note
                : '${p.isYou ? 'You\'ve' : '${p.name} has'} used every roll for today. Come back tomorrow — the board remembers exactly where you stand.',
            style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 10),
          Pill('New rolls in ${_untilMidnight()}', color: MokshaColors.maroon, icon: Icons.schedule_rounded),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Come back tomorrow — the board remembers exactly where you stand.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade700)),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final o in others)
                  OutlinedButton.icon(
                    onPressed: () => _select(o),
                    icon: const Icon(Icons.casino_rounded, size: 16),
                    label: Text('Roll for ${o.isYou ? 'yourself' : o.name}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MokshaColors.maroon,
                      side: const BorderSide(color: MokshaColors.maroon),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${p.isYou ? 'You' : p.name}, $sub${p.wins > 0 ? ', ${p.wins} wins' : ''}',
        hint: selected ? null : 'Tap to play as ${p.isYou ? 'yourself' : p.name}',
        child: Material(
          key: ValueKey('moksha-player-${p.profileKey}'),
          color: selected ? color.withValues(alpha: 0.1) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: selected ? color : Colors.black.withValues(alpha: 0.07), width: selected ? 1.6 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _busy ? null : () => _select(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    MokshaTokenDot(label: _initial(p), color: color, size: 32, active: selected),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.isYou ? '${p.name} (you)' : p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          Text(sub, style: TextStyle(fontSize: 12, height: 1.3, color: Colors.grey.shade700)),
                        ],
                      ),
                    ),
                    if (p.wins > 0) ...[
                      const SizedBox(width: 6),
                      Pill('🕉 ${p.wins}', color: MokshaColors.goldDeep),
                    ],
                    if (selected) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle_rounded, size: 20, color: color),
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
    Widget row(String emoji, String text, {Widget? action}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 18))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade900)),
                    if (action != null) action,
                  ],
                ),
              ),
            ],
          ),
        );
    return ForecastCard(
      title: 'Want more rolls?',
      icon: Icons.casino_rounded,
      iconColor: MokshaColors.maroon,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        children: [
          row('🎲', 'Everyone gets 1 free roll every day.'),
          row('⭐', 'Lucky star days: when the Moon is kind to your birth star, you get +1 roll.'),
          row(
            '✅',
            'Finish all 3 of today\'s missions for +1 roll.',
            action: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/games/quest'),
                icon: const Icon(Icons.flag_rounded, size: 16),
                label: const Text('Go to today\'s missions'),
                style: TextButton.styleFrom(
                  foregroundColor: MokshaColors.maroon,
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
    final String emoji;
    if (ev.contains('moksha')) {
      emoji = '🕉';
    } else if (ev.startsWith('ladder')) {
      emoji = '🪜';
    } else if (ev.startsWith('snake')) {
      emoji = '🐍';
    } else if (ev.isNotEmpty && m.to == m.from) {
      emoji = '🎯';
    } else if (ev.isNotEmpty) {
      emoji = m.to > m.from ? '🪜' : '🐍';
    } else {
      emoji = '🎲';
    }
    final name = m.name.isEmpty ? 'Player' : m.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 15))),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: m.dice > 0 ? ' rolled ${m.dice}: ' : ': '),
                TextSpan(text: '${m.from} → ${m.to}'),
                if ((m.event ?? '').isNotEmpty)
                  TextSpan(text: ' · ${m.event}', style: TextStyle(color: Colors.grey.shade700)),
              ]),
              style: const TextStyle(fontSize: 12.5, height: 1.35, color: Colors.black),
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
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFF7D6), Color(0xFFFFE08A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: MokshaColors.gold, width: 2),
            ),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const ExcludeSemantics(child: Text('🕉', style: TextStyle(fontSize: 56, height: 1.1))),
                        const SizedBox(height: 6),
                        Semantics(
                          header: true,
                          child: const Text('Moksha!',
                              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: MokshaColors.maroon)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${isYou ? 'You' : name} climbed every ladder, outlasted every snake and reached square 100.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, height: 1.45, color: MokshaColors.ink),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (xp > 0) Pill('+$xp XP', color: FC.good, icon: Icons.bolt_rounded, solid: true),
                            Pill(wins == 1 ? 'First Moksha' : 'Moksha × $wins',
                                color: MokshaColors.maroon, solid: true),
                          ],
                        ),
                        if (card != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: MokshaColors.gold),
                            ),
                            child: Row(
                              children: [
                                ExcludeSemantics(child: Text(card.symbol, style: const TextStyle(fontSize: 28))),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Rare card unlocked',
                                          style: TextStyle(
                                              fontSize: 11, fontWeight: FontWeight.w800, color: MokshaColors.goldDeep)),
                                      Text(card.name,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                                      if (card.power.isNotEmpty)
                                        Text(card.power,
                                            style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade800)),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MokshaColors.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Begin a new journey', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          const Positioned.fill(child: ConfettiBurst(particleCount: 90, origin: Alignment(0, -0.5))),
        ],
      ),
    );
  }
}
