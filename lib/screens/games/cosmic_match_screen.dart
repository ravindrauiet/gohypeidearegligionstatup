import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/game.dart';
import '../../services/backend_service.dart';
import '../../widgets/game_widgets.dart';
import '../../widgets/ui/app_ui.dart';

/// Cosmic Match — your circle of family and friends, ranked by the stars.
class CosmicMatchScreen extends StatefulWidget {
  const CosmicMatchScreen({super.key});

  @override
  State<CosmicMatchScreen> createState() => _CosmicMatchScreenState();
}

const _kViolet = AppColors.cosmicLight;
const _kFamily = AppColors.love;
const _kFriend = AppColors.info;

Color _compatColor(double fraction) {
  if (fraction >= 0.75) return AppColors.success;
  if (fraction >= 0.55) return AppColors.info;
  if (fraction >= 0.4) return AppColors.primary;
  return AppColors.textSecondary;
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

  void _toast(String text) => showAppSnack(context, text);

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
    _toast(name.isEmpty ? 'You\'re connected! Your circle just grew.' : '$name is in your circle now!');
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
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
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
    final action = await showAppSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
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
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        child: GameNoKundli(onCreate: () => Navigator.pushNamed(context, '/birth-details')),
      );
    } else if (_loginRequired && circle == null) {
      body = _LoginState(onLogin: _goLogin);
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: circle != null
                ? _content(circle)
                : [
                    if (_error != null && !_loading)
                      GameError(message: _error!, onRetry: _load, title: 'Couldn\'t load your circle')
                    else
                      const GameSkeleton(blocks: [120, 170, 96, 150, 84, 84], label: 'Gathering your circle'),
                  ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: gameAppBar(title: 'Cosmic Match', subtitle: 'Your circle, ranked by the stars'),
      body: body,
    );
  }

  List<Widget> _content(CosmicCircle c) {
    final guest = c.inviteCode.isEmpty;
    return [
      _youHeader(c.you),
      const SizedBox(height: AppSpacing.sm),
      if (c.members.isEmpty) ...[_emptyCircle(guest), const SizedBox(height: AppSpacing.sm)],
      if (guest) _guestInviteCard() else _inviteCard(c),
      const SizedBox(height: AppSpacing.sm),
      _joinCard(),
      if (c.rankings.isNotEmpty) ...[
        const GameSectionTitle('Who\'s who in your circle'),
        _rankings(c),
      ],
      if (c.members.isNotEmpty) ...[
        GameSectionTitle('Your circle · ${c.members.length}'),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(gradient: AppColors.cosmicGradient, borderRadius: AppRadius.card),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You', style: AppText.caption.copyWith(color: GameColors.gold, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(you.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headline.copyWith(color: Colors.white)),
                if (moon.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(moon, style: AppText.body.copyWith(color: AppColors.textOnDarkMuted)),
                ],
                if (mood.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _DarkChip(icon: Icons.wb_sunny_outlined, text: 'Today: $mood'),
                ],
              ],
            ),
          ),
          if (score != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _ScoreRing(score: score, size: 72),
          ],
        ],
      ),
    );
  }

  Widget _emptyCircle(bool guest) {
    return AppCard(
      key: const Key('circle-empty'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const ExcludeSemantics(child: GameIconTile(icon: Icons.diversity_3_rounded, color: _kViolet, size: 56)),
          const SizedBox(height: AppSpacing.md),
          const Text('Your circle is waiting', textAlign: TextAlign.center, style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Invite one person and instantly see how your stars click: who is your Cosmic Twin, who calms you down, '
            'and who you should never travel without.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: guest ? 'Log in to invite' : 'Invite your first person',
            icon: guest ? Icons.login_rounded : Icons.person_add_alt_1_rounded,
            onPressed: guest ? _goLogin : _share,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Family profiles you add to your Kundli join automatically.',
              textAlign: TextAlign.center, style: AppText.caption),
        ],
      ),
    );
  }

  Widget _inviteCard(CosmicCircle c) {
    return _TitledCard(
      title: 'Invite someone to your circle',
      icon: Icons.person_add_alt_1_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('They enter your code, and you both see how your stars match.', style: AppText.body),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: 'Your invite code: ${c.inviteCode.split('').join(' ')}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(c.inviteCode,
                      key: const Key('circle-code'),
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 4, color: AppColors.textPrimary)),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Copy',
                  icon: Icons.copy_rounded,
                  variant: AppButtonVariant.outline,
                  height: 46,
                  onPressed: _copyCode,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton(label: 'Share', icon: Icons.ios_share_rounded, height: 46, onPressed: _share),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _guestInviteCard() {
    return _TitledCard(
      title: 'Log in to invite friends',
      icon: Icons.lock_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Friends need a way to find you. Log in to get your own invite code.', style: AppText.body),
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'Log in', expand: false, height: 44, onPressed: _goLogin),
        ],
      ),
    );
  }

  Widget _joinCard() {
    return _TitledCard(
      title: 'Have a code?',
      icon: Icons.vpn_key_outlined,
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2),
                  decoration: InputDecoration(
                    labelText: 'Friend\'s code',
                    isDense: true,
                    errorText: _joinError,
                    errorMaxLines: 4,
                    border: OutlineInputBorder(borderRadius: AppRadius.input),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                label: 'Join',
                variant: AppButtonVariant.dark,
                expand: false,
                height: 48,
                loading: _joining,
                onPressed: _join,
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
                padding: EdgeInsets.only(right: i == c.rankings.length - 1 ? 0 : AppSpacing.sm),
                child: SizedBox(width: width, child: _rankingCard(c.rankings[i], c.members.length)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rankingCard(CircleRanking r, int memberCount) {
    final need = math.max(1, r.needMembers - memberCount);
    final Widget inner;
    if (!r.unlocked) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GameIconTile(icon: Icons.lock_rounded, color: AppColors.textTertiary, size: 36),
          const SizedBox(height: AppSpacing.xs),
          Text('Add $need more ${need == 1 ? 'person' : 'people'} to unlock', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            label: 'Invite',
            icon: Icons.person_add_alt_1_rounded,
            variant: AppButtonVariant.outline,
            expand: false,
            height: 44,
            onPressed: _share,
          ),
        ],
      );
    } else if (r.entries.isEmpty) {
      inner = const Text('No one fits this yet. Add more people (with birth details) to crown a winner.',
          style: AppText.caption);
    } else {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < r.entries.length && i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Semantics(
                container: true,
                label: 'Number ${i + 1}: ${r.entries[i].name}, ${r.entries[i].value}. ${r.entries[i].note}',
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RankNumber(rank: i + 1),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(r.entries[i].name,
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                                ),
                                if (r.entries[i].value.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  GamePill(r.entries[i].value,
                                      color: i == 0 ? GameColors.goldDeep : AppColors.textSecondary),
                                ],
                              ],
                            ),
                            if (r.entries[i].note.isNotEmpty)
                              Text(r.entries[i].note,
                                  maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.caption),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: r.unlocked ? AppColors.surface : AppColors.surfaceMuted,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.subtitle.copyWith(color: r.unlocked ? AppColors.textPrimary : AppColors.textSecondary)),
          ),
          const SizedBox(height: AppSpacing.sm),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          key: ValueKey('member-${m.id}'),
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openMember(m),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    _Avatar(name: m.name, color: kindColor, size: 44),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                          if (sub.isNotEmpty)
                            Text(sub,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontStyle: m.hasChart ? FontStyle.normal : FontStyle.italic)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              GamePill(m.isFamily ? 'Family' : 'Friend', color: kindColor),
                              if (m.todayScore != null)
                                GamePill('Today ${m.todayScore}',
                                    color: _scoreColor(m.todayScore!), icon: Icons.wb_sunny_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (c != null) ...[
                      const SizedBox(width: AppSpacing.xs),
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
                                        fontSize: 11, fontWeight: FontWeight.w700, color: _compatColor(c.fraction))),
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

Color _scoreColor(int s) {
  if (s >= 75) return AppColors.success;
  if (s >= 60) return AppColors.info;
  if (s >= 42) return AppColors.primary;
  return AppColors.danger;
}

/// White card with a small icon + title header.
class _TitledCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _TitledCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GameIconTile(icon: icon, color: AppColors.textSecondary, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Semantics(header: true, child: Text(title, style: AppText.subtitle))),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DarkChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: GameColors.gold),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ]),
    );
  }
}

class _RankNumber extends StatelessWidget {
  final int rank;
  const _RankNumber({required this.rank});

  @override
  Widget build(BuildContext context) {
    final first = rank == 1;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: first ? GameColors.gold.withValues(alpha: 0.18) : AppColors.surfaceMuted,
        border: Border.all(color: first ? GameColors.gold : AppColors.border),
      ),
      child: Text('$rank',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: first ? GameColors.goldDeep : AppColors.textSecondary)),
    );
  }
}

/// Today's score out of 100 on the dark header.
class _ScoreRing extends StatelessWidget {
  final int score;
  final double size;
  const _ScoreRing({required this.score, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Today\'s score $score out of 100',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _CompatPainter((score / 100).clamp(0.0, 1.0), GameColors.gold, size * 0.06,
                track: Colors.white.withValues(alpha: 0.14)),
            child: Padding(
              padding: EdgeInsets.all(size * 0.18),
              child: FittedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$score',
                        textScaler: TextScaler.noScaling,
                        style:
                            const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                    const Text('today',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: 10, color: AppColors.textOnDarkMuted, height: 1.3)),
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
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
      child: Text(_initialOf(name),
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: color, height: 1)),
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
            painter: _CompatPainter(compat.fraction, color, math.max(2.5, size * 0.07)),
            child: Padding(
              padding: EdgeInsets.all(size * 0.2),
              child: FittedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(parts.first,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color, height: 1)),
                    Text('/${parts.length > 1 ? parts[1] : '36'}',
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textTertiary, height: 1.2)),
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
  final Color? track;
  _CompatPainter(this.fraction, this.color, this.stroke, {this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track ?? color.withValues(alpha: 0.14)
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
  bool shouldRepaint(_CompatPainter old) => old.fraction != fraction || old.color != color || old.track != track;
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
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(title, style: AppText.bodyStrong.copyWith(color: color))),
              ]),
              const SizedBox(height: AppSpacing.xxs),
              Text(text, style: AppText.body),
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
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: AppText.title),
                  Text(who, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (c != null) ...[
          Row(
            children: [
              _CompatRing(compat: c, size: 80),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.label.isEmpty ? 'Your match' : '${c.label} match',
                        style: AppText.title.copyWith(color: _compatColor(c.fraction))),
                    Text('${c.display} points of harmony between your Moons.', style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (c.strongest.isNotEmpty)
            block('Where you two click', c.strongest, AppColors.success, Icons.favorite_border_rounded),
          if (c.weakest.isNotEmpty) block('Where to go gently', c.weakest, AppColors.warning, Icons.spa_outlined),
        ] else
          block(
            'No match yet',
            m.isFamily
                ? '${m.name} hasn\'t added birth details yet. Add their date, time and place of birth to their family profile to see your match.'
                : '${m.name} hasn\'t added birth details yet. Give them a nudge. Your match appears the moment they do.',
            AppColors.textSecondary,
            Icons.hourglass_empty_rounded,
          ),
        if (m.todayScore != null || mood.isNotEmpty)
          block(
            '${m.name}\'s day today',
            [
              if (m.todayScore != null) 'Score ${m.todayScore} out of 100',
              if (mood.isNotEmpty) mood,
            ].join(' · '),
            AppColors.info,
            Icons.wb_sunny_outlined,
          ),
        const SizedBox(height: AppSpacing.xs),
        if (c != null)
          AppButton(
            label: 'Ask an astrologer about us',
            icon: Icons.forum_outlined,
            variant: AppButtonVariant.dark,
            onPressed: () => Navigator.pop(context, 'ask'),
          ),
        if (m.isFriend && m.friendUserId != null)
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.pop(context, 'remove'),
              icon: const Icon(Icons.person_remove_outlined, size: 18),
              label: const Text('Remove from circle'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
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
        child: AppStateView(
          icon: Icons.diversity_3_rounded,
          color: _kViolet,
          title: 'Log in to build your circle',
          message: 'Cosmic Match connects you with family and friends, so it needs to know who you are. '
              'It takes a minute, and your circle is waiting.',
          actionLabel: 'Log in',
          onAction: onLogin,
        ),
      ),
    );
  }
}
