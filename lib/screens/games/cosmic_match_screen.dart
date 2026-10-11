import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../widgets/forecast_widgets.dart' show FC, ForecastCard, Pill, ScoreRing, SectionLabel;
import '../../widgets/game_widgets.dart' show ConfettiBurst, GameError, GameNoKundli, GameSkeleton;

/// Cosmic Match — your circle of family and friends, ranked by the stars.
class CosmicMatchScreen extends StatefulWidget {
  const CosmicMatchScreen({super.key});

  @override
  State<CosmicMatchScreen> createState() => _CosmicMatchScreenState();
}

const _kViolet = Color(0xFF6C63FF);
const _kFamily = Color(0xFFDB2777);
const _kFriend = Color(0xFF0891B2);

Color _compatColor(double fraction) {
  if (fraction >= 0.75) return FC.good;
  if (fraction >= 0.55) return FC.blue;
  if (fraction >= 0.4) return FC.accent;
  return _kViolet;
}

String _pretty(String? s) {
  final t = (s ?? '').trim();
  return t.isEmpty ? '' : t[0].toUpperCase() + t.substring(1);
}

/// Forecast mood values (excellent|good|mixed|challenging) in friendly words.
String _moodText(String? mood) {
  switch ((mood ?? '').trim().toLowerCase()) {
    case '':
      return '';
    case 'excellent':
      return 'Excellent';
    case 'good':
      return 'Good';
    case 'mixed':
      return 'Mixed';
    case 'challenging':
      return 'A go-gently day';
    default:
      return _pretty(mood);
  }
}

String _initialOf(String name) => name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

class _CosmicMatchScreenState extends State<CosmicMatchScreen> {
  late final BackendService _service;
  final TextEditingController _code = TextEditingController();

  CosmicCircle? _circle;
  bool _loading = true;
  bool _noKundli = false;
  bool _loginRequired = false;
  String? _error;
  int _loadToken = 0;

  bool _joining = false;
  String? _joinError;
  bool _joinNeedsLogin = false;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _service = Provider.of<BackendService>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Data
  // --------------------------------------------------------------------------

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await _service.fetchCircle();
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _loadToken) return;
    setState(() {
      _loading = false;
      if (raw != null) {
        _circle = CosmicCircle.fromJson(raw);
        _noKundli = false;
        _loginRequired = false;
      } else {
        final code = _service.lastErrorCode;
        _noKundli = code == 'NO_KUNDLI';
        _loginRequired = code == 'LOGIN_REQUIRED';
        _error = _service.lastError ?? 'Could not load your circle. Please try again.';
      }
    });
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _goLogin() => Navigator.pushNamed(context, '/login');

  Future<bool> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  String _shareText(CosmicCircle c) => c.shareText.isNotEmpty
      ? c.shareText
      : 'Join my cosmic circle on CosmicGuide and see how our stars match! Use my code ${c.inviteCode}';

  Future<void> _copyCode() async {
    final c = _circle;
    if (c == null || c.inviteCode.isEmpty) return;
    final ok = await _copy(c.inviteCode);
    if (!mounted) return;
    _toast(ok ? 'Code copied. Send it to someone you like!' : 'Could not copy. Your code is ${c.inviteCode}');
  }

  Future<void> _share() async {
    final c = _circle;
    if (c == null) return;
    if (c.inviteCode.isEmpty) {
      _goLogin();
      return;
    }
    final text = _shareText(c);
    var launched = false;
    try {
      launched = await launchUrl(Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}'),
              mode: LaunchMode.externalApplication)
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (_) {
      launched = false;
    }
    if (launched || !mounted) return;
    final ok = await _copy(text);
    if (!mounted) return;
    _toast(ok ? 'Invite copied. Paste it into any chat!' : 'Share this code with a friend: ${c.inviteCode}');
  }

  Future<void> _join() async {
    if (_joining) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() {
        _joinError = 'Type the code your friend sent you.';
        _joinNeedsLogin = false;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _joining = true;
      _joinError = null;
      _joinNeedsLogin = false;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await _service.joinCircle(code);
    } catch (_) {
      raw = null;
    }
    if (!mounted) return;
    if (raw == null) {
      final errCode = _service.lastErrorCode;
      setState(() {
        _joining = false;
        _joinNeedsLogin = errCode == 'LOGIN_REQUIRED';
        _joinError = _joinMessage(errCode, _service.lastError);
      });
      return;
    }
    final result = JoinCircleResult.fromJson(raw);
    final hasCircle = raw['circle'] is Map;
    setState(() {
      _joining = false;
      _code.clear();
      if (hasCircle) _circle = result.circle;
    });
    final name = result.member?.name ?? '';
    ConfettiBurst.show(context);
    _toast(name.isEmpty ? '🎉 You\'re connected! Your circle just grew.' : '🎉 $name is in your circle now!');
    if (!hasCircle) _load();
  }

  String _joinMessage(String? code, String? fallback) {
    switch (code) {
      case 'INVALID_CODE':
        return 'Hmm, that code doesn\'t match anyone. Check it and try again.';
      case 'OWN_CODE':
        return 'That\'s your own code! Send it to a friend instead.';
      case 'ALREADY_FRIENDS':
        return 'You two are already in each other\'s circle.';
      case 'BAD_CODE':
        return 'That doesn\'t look like a code. Check it and try again.';
      case 'CIRCLE_FULL':
        return 'That circle is full right now (30 people is the limit).';
      case 'LOGIN_REQUIRED':
        return 'Log in to add friends to your circle.';
      default:
        return fallback ?? 'Could not join the circle. Please try again.';
    }
  }

  Future<void> _remove(CircleMember m) async {
    final id = m.friendUserId;
    if (_removing || id == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.name}?'),
        content:
            Text('${m.name} will leave your circle and you will leave theirs. You can always reconnect with a code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: FC.bad),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _removing = true);
    Map<String, dynamic>? raw;
    try {
      raw = await _service.removeCircleFriend(id);
    } catch (_) {
      raw = null;
    }
    if (!mounted) return;
    setState(() {
      _removing = false;
      if (raw != null && raw['circle'] is Map) _circle = CosmicCircle.fromJson(raw['circle']);
    });
    if (raw == null) {
      _toast(_service.lastError ?? 'Could not remove this friend. Please try again.');
      return;
    }
    _toast('${m.name} was removed from your circle.');
    if (raw['circle'] is! Map) _load();
  }

  void _askAbout(CircleMember m) {
    final you = _circle?.you ?? const CircleYou();
    final c = m.compatibility;
    final rel =
        m.isFamily ? ((m.relationship ?? '').isNotEmpty ? 'my ${m.relationship}' : 'my family member') : 'my friend';
    final parts = <String>[
      'Tell me about my compatibility with $rel ${m.name}.',
      if (c != null) 'Our Ashtakoota match is ${c.display}${c.label.isNotEmpty ? ' (${c.label})' : ''}.',
      if (c != null && c.strongest.isNotEmpty) 'Strongest: ${c.strongest}.',
      if (c != null && c.weakest.isNotEmpty) 'Weakest: ${c.weakest}.',
      if ((you.moonSign ?? '').isNotEmpty)
        'My Moon is in ${you.moonSign}${(you.nakshatra ?? '').isNotEmpty ? ' (${you.nakshatra})' : ''}.',
      if ((m.moonSign ?? '').isNotEmpty)
        'Their Moon is in ${m.moonSign}${(m.nakshatra ?? '').isNotEmpty ? ' (${m.nakshatra})' : ''}.',
      'How do we bring out the best in each other?',
    ];
    Navigator.pushNamed(context, '/chatbot', arguments: {
      'name': 'Cosmic Match Guide',
      'specialty': 'Compatibility & relationships',
      'field': 'Compatibility',
      'initialMessage': parts.join(' '),
    });
  }

  Future<void> _openMember(CircleMember m) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _MemberDetail(member: m),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'ask') _askAbout(m);
    if (action == 'remove') await _remove(m);
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final circle = _circle;
    Widget body;
    if (_noKundli && circle == null) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: GameNoKundli(onCreate: () => Navigator.pushNamed(context, '/birth-details')),
      );
    } else if (_loginRequired && circle == null) {
      body = _LoginState(onLogin: _goLogin);
    } else {
      body = RefreshIndicator(
        color: _kViolet,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: circle != null
                ? _content(circle)
                : [
                    if (_error != null && !_loading)
                      GameError(message: _error!, onRetry: _load, title: 'Your circle slipped behind a cloud')
                    else
                      const GameSkeleton(blocks: [120, 170, 96, 150, 84, 84], label: 'Gathering your circle'),
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
            const Text('Cosmic Match',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 18)),
            Text('Your circle, ranked by the stars',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
      body: body,
    );
  }

  List<Widget> _content(CosmicCircle c) {
    final guest = c.inviteCode.isEmpty;
    return [
      _youHeader(c.you),
      const SizedBox(height: 14),
      if (c.members.isEmpty) ...[_emptyCircle(guest), const SizedBox(height: 14)],
      if (guest) _guestInviteCard() else _inviteCard(c),
      const SizedBox(height: 14),
      _joinCard(),
      if (c.rankings.isNotEmpty) ...[
        const SectionLabel('Who\'s who in your circle'),
        _rankings(c),
      ],
      if (c.members.isNotEmpty) ...[
        SectionLabel('Your circle · ${c.members.length}'),
        for (final m in c.members) _memberTile(m),
      ],
    ];
  }

  Widget _youHeader(CircleYou you) {
    final moon = [
      if ((you.moonSign ?? '').isNotEmpty) 'Moon in ${you.moonSign}',
      if ((you.nakshatra ?? '').isNotEmpty) you.nakshatra!,
    ].join(' · ');
    final mood = _moodText(you.mood);
    final score = you.todayScore;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [FC.heroA, FC.heroB], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: FC.heroA.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOU',
                    style: TextStyle(
                        color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(you.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
                if (moon.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(moon, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                ],
                if (mood.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Pill('Today: $mood', color: const Color(0xFF7DD3FC), icon: Icons.brightness_5_rounded),
                ],
              ],
            ),
          ),
          if (score != null) ...[
            const SizedBox(width: 12),
            ScoreRing(score: score, size: 76, color: FC.moodOnDark(you.mood ?? ''), caption: 'today'),
          ],
        ],
      ),
    );
  }

  Widget _emptyCircle(bool guest) {
    return Container(
      key: const Key('circle-empty'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFF3EEFF), Color(0xFFFFEEF5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kViolet.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          const ExcludeSemantics(child: Text('🌌', style: TextStyle(fontSize: 44, height: 1.1))),
          const SizedBox(height: 8),
          const Text('Your circle is waiting',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Invite one person and instantly see how your stars click: who is your Cosmic Twin, who calms you down, '
            'and who you should never travel without.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: guest ? _goLogin : _share,
            icon: Icon(guest ? Icons.login_rounded : Icons.person_add_alt_1_rounded, size: 18),
            label: Text(guest ? 'Log in to invite' : 'Invite your first person'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kViolet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Family profiles you add to your Kundli join automatically.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _inviteCard(CosmicCircle c) {
    return ForecastCard(
      title: 'Invite someone to your circle',
      icon: Icons.card_giftcard_rounded,
      iconColor: _kViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('They enter your code, and you both see how your stars match.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          Semantics(
            label: 'Your invite code: ${c.inviteCode.split('').join(' ')}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: _kViolet.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kViolet.withValues(alpha: 0.35), width: 1.4),
              ),
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(c.inviteCode,
                      key: const Key('circle-code'),
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 5, color: Color(0xFF3B2F9E))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black26),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Share', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1FA855),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _guestInviteCard() {
    return ForecastCard(
      title: 'Log in to invite friends',
      icon: Icons.lock_outline_rounded,
      iconColor: _kViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Friends need a way to find you. Log in to get your own invite code.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _goLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kViolet,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Log in'),
          ),
        ],
      ),
    );
  }

  Widget _joinCard() {
    return ForecastCard(
      title: 'Have a code?',
      icon: Icons.vpn_key_rounded,
      iconColor: FC.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('circle-code-input'),
                  controller: _code,
                  enabled: !_joining,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    LengthLimitingTextInputFormatter(24),
                  ],
                  onChanged: (_) {
                    if (_joinError != null) {
                      setState(() {
                        _joinError = null;
                        _joinNeedsLogin = false;
                      });
                    }
                  },
                  onSubmitted: (_) => _join(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2),
                  decoration: InputDecoration(
                    labelText: 'Friend\'s code',
                    isDense: true,
                    errorText: _joinError,
                    errorMaxLines: 4,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _joining ? null : _join,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _joining
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Join'),
              ),
            ],
          ),
          if (_joinNeedsLogin)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _goLogin, child: const Text('Log in')),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Rankings
  // --------------------------------------------------------------------------

  Widget _rankings(CosmicCircle c) {
    final width = math.min(250.0, MediaQuery.of(context).size.width * 0.74);
    return SingleChildScrollView(
      key: const Key('circle-rankings'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < c.rankings.length; i++)
              Padding(
                padding: EdgeInsets.only(right: i == c.rankings.length - 1 ? 0 : 12),
                child: SizedBox(width: width, child: _rankingCard(c.rankings[i], c.members.length)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rankingCard(CircleRanking r, int memberCount) {
    const medals = ['🥇', '🥈', '🥉'];
    final need = math.max(1, r.needMembers - memberCount);
    final Widget inner;
    if (!r.unlocked) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), shape: BoxShape.circle),
            child: Icon(Icons.lock_rounded, size: 20, color: Colors.grey.shade700, semanticLabel: 'Locked'),
          ),
          const SizedBox(height: 10),
          Text('Add $need more ${need == 1 ? 'person' : 'people'} to unlock',
              style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: const Text('Invite'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kViolet,
              side: const BorderSide(color: _kViolet),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      );
    } else if (r.entries.isEmpty) {
      inner = Text('No one fits this yet. Add more people (with birth details) to crown a winner.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade700));
    } else {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < r.entries.length && i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                container: true,
                label: 'Number ${i + 1}: ${r.entries[i].name}, ${r.entries[i].value}. ${r.entries[i].note}',
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(medals[i], style: TextStyle(fontSize: i == 0 ? 22 : 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(r.entries[i].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: i == 0 ? 15 : 14, fontWeight: FontWeight.w800)),
                                ),
                                if (r.entries[i].value.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Pill(r.entries[i].value, color: i == 0 ? const Color(0xFFB45309) : FC.neutral),
                                ],
                              ],
                            ),
                            if (r.entries[i].note.isNotEmpty)
                              Text(r.entries[i].note,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      key: ValueKey('ranking-${r.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: r.unlocked ? Colors.white : const Color(0xFFF4F1EC),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: r.unlocked ? FC.accent.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child:
                    Opacity(opacity: r.unlocked ? 1 : 0.5, child: Text(r.emoji, style: const TextStyle(fontSize: 24))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: r.unlocked ? Colors.black : Colors.grey.shade700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          inner,
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Members
  // --------------------------------------------------------------------------

  Widget _memberTile(CircleMember m) {
    final c = m.hasChart ? m.compatibility : null;
    final kindColor = m.isFamily ? _kFamily : _kFriend;
    final moon = [
      if ((m.moonSign ?? '').isNotEmpty) 'Moon in ${m.moonSign}',
      if ((m.nakshatra ?? '').isNotEmpty) m.nakshatra!,
    ].join(' · ');
    final sub = m.hasChart ? moon : 'Hasn\'t added birth details';
    final label = [
      m.name,
      m.isFamily ? 'Family' : 'Friend',
      if (c != null) 'compatibility ${c.display}${c.label.isNotEmpty ? ', ${c.label}' : ''}',
      if (m.todayScore != null) 'today\'s score ${m.todayScore}',
      if (!m.hasChart) 'hasn\'t added birth details',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          key: ValueKey('member-${m.id}'),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.07)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openMember(m),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    _Avatar(name: m.name, color: kindColor, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          if (sub.isNotEmpty)
                            Text(sub,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    fontStyle: m.hasChart ? FontStyle.normal : FontStyle.italic,
                                    color: Colors.grey.shade700)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Pill(m.isFamily ? 'Family' : 'Friend', color: kindColor),
                              if (m.todayScore != null)
                                Pill('Today ${m.todayScore}',
                                    color: FC.score(m.todayScore!), icon: Icons.wb_sunny_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (c != null) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 62,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CompatRing(compat: c, size: 50),
                            if (c.label.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(c.label,
                                    maxLines: 1,
                                    style: TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w800, color: _compatColor(c.fraction))),
                              ),
                            ],
                          ],
                        ),
                      ),
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
}

// ============================================================================
// Pieces
// ============================================================================

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const _Avatar({required this.name, required this.color, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: [Color.lerp(color, Colors.white, 0.35)!, color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: Text(_initialOf(name),
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontSize: size * 0.44, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
    );
  }
}

/// Compatibility ring: score out of 36 (Ashtakoota gunas).
class _CompatRing extends StatelessWidget {
  final Compatibility compat;
  final double size;
  const _CompatRing({required this.compat, this.size = 50});

  @override
  Widget build(BuildContext context) {
    final color = _compatColor(compat.fraction);
    final parts = compat.display.split('/');
    return Semantics(
      label: 'Compatibility ${compat.display}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _CompatPainter(compat.fraction, color, size * 0.1),
            child: Padding(
              padding: EdgeInsets.all(size * 0.2),
              child: FittedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(parts.first,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color, height: 1)),
                    Text('/${parts.length > 1 ? parts[1] : '36'}',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade600, height: 1.2)),
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

class _CompatPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final double stroke;
  _CompatPainter(this.fraction, this.color, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    if (fraction <= 0) return;
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(_CompatPainter old) => old.fraction != fraction || old.color != color;
}

/// Bottom-sheet content. Pops with `'ask'` or `'remove'` when an action is chosen.
class _MemberDetail extends StatelessWidget {
  final CircleMember member;
  const _MemberDetail({required this.member});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final c = m.hasChart ? m.compatibility : null;
    final kindColor = m.isFamily ? _kFamily : _kFriend;
    final who = [
      m.isFamily ? 'Family' : 'Friend',
      if ((m.relationship ?? '').isNotEmpty) _pretty(m.relationship),
      if ((m.moonSign ?? '').isNotEmpty) 'Moon in ${m.moonSign}',
      if ((m.nakshatra ?? '').isNotEmpty) m.nakshatra!,
    ].join(' · ');
    final mood = _moodText(m.mood);

    Widget block(String title, String text, Color color, IconData icon) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color))),
              ]),
              const SizedBox(height: 4),
              Text(text, style: TextStyle(fontSize: 13.5, height: 1.45, color: Colors.grey.shade900)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Avatar(name: m.name, color: kindColor, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  Text(who, style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.grey.shade700)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (c != null) ...[
          Row(
            children: [
              _CompatRing(compat: c, size: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.label.isEmpty ? 'Your match' : '${c.label} match',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _compatColor(c.fraction))),
                    Text('${c.display} points of harmony between your Moons.',
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (c.strongest.isNotEmpty) block('Where you two click', c.strongest, FC.good, Icons.favorite_rounded),
          if (c.weakest.isNotEmpty) block('Where to go gently', c.weakest, const Color(0xFFB45309), Icons.spa_rounded),
        ] else
          block(
            'No match yet',
            m.isFamily
                ? '${m.name} hasn\'t added birth details yet. Add their date, time and place of birth to their family profile to see your match.'
                : '${m.name} hasn\'t added birth details yet. Give them a nudge. Your match appears the moment they do.',
            _kViolet,
            Icons.hourglass_empty_rounded,
          ),
        if (m.todayScore != null || mood.isNotEmpty)
          block(
            '${m.name}\'s day today',
            [
              if (m.todayScore != null) 'Score ${m.todayScore} out of 100',
              if (mood.isNotEmpty) mood,
            ].join(' · '),
            FC.blue,
            Icons.wb_sunny_rounded,
          ),
        const SizedBox(height: 4),
        if (c != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'ask'),
              icon: const Icon(Icons.forum_rounded, size: 18),
              label: const Text('Ask an astrologer about us'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        if (m.isFriend && m.friendUserId != null)
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.pop(context, 'remove'),
              icon: const Icon(Icons.person_remove_alt_1_rounded, size: 18),
              label: const Text('Remove from circle'),
              style: TextButton.styleFrom(foregroundColor: FC.bad),
            ),
          ),
      ],
    );
  }
}

class _LoginState extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoginState({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: _kViolet.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.diversity_3_rounded, color: _kViolet, size: 40),
            ),
            const SizedBox(height: 18),
            const Text('Log in to build your circle',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Cosmic Match connects you with family and friends, so it needs to know who you are. '
              'It takes a minute, and your circle is waiting.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Log in'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kViolet,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
