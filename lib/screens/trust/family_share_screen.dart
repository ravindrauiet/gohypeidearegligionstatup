import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/backend_service.dart';
import '../../services/trust_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';
import 'family_notes_screen.dart';

/// Shares text through the system sheet (WhatsApp etc.). Tests replace it.
Future<void> Function(String text, {String? subject}) familyShareText =
    (text, {subject}) async => SharePlus.instance.share(ShareParams(text: text, subject: subject));

/// "Share with family": read-only links for parents and siblings (no login),
/// either for my own profile or, with [matchUserId], for an accepted buddy.
class FamilyShareScreen extends StatefulWidget {
  /// Share this accepted buddy as a match instead of my own profile.
  final int? matchUserId;
  final String? matchName;
  final TrustService? service;

  const FamilyShareScreen({super.key, this.matchUserId, this.matchName, this.service});

  @override
  State<FamilyShareScreen> createState() => _FamilyShareScreenState();
}

class _FamilyShareScreenState extends State<FamilyShareScreen> {
  late final TrustService _service = widget.service ?? TrustService(context.read<BackendService>());
  List<FamilyLink>? _links;
  int _maxActive = 5;
  bool _loading = true;
  String? _error;
  bool _creating = false;
  final Set<int> _busy = {};

  bool get _isMatch => widget.matchUserId != null;
  bool get _loggedIn => context.read<BackendService>().isAuthenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (!_loggedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.familyLinks();
      if (!mounted) return;
      setState(() {
        _links = r.links;
        _maxActive = r.maxActive;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = TrustService.errorText(e);
      });
    }
  }

  String _shareText(FamilyLink l) => l.isMatch
      ? 'Namaste! I would like you to see ${l.matchName ?? 'a match'} on CosmicGuide. '
          'You can also leave me a note there: ${l.url}'
      : 'Namaste! Here is my CosmicGuide profile for the family. You can leave me a note there: ${l.url}';

  Future<void> _share(FamilyLink l) async {
    try {
      await familyShareText(_shareText(l), subject: 'CosmicGuide family link');
    } catch (_) {
      if (mounted) showAppSnack(context, 'Could not open sharing. The link was copied instead.');
      await _copy(l, quiet: true);
    }
  }

  Future<void> _copy(FamilyLink l, {bool quiet = false}) async {
    await Clipboard.setData(ClipboardData(text: l.url));
    if (mounted && !quiet) showAppSnack(context, 'Link copied');
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final link = await _service.createFamilyLink(matchUserId: widget.matchUserId);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _links = [link, ...?_links];
      });
      await _share(link);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      final code = e is TrustException ? e.code : null;
      showAppSnack(
        context,
        switch (code) {
          'LINK_LIMIT' => 'You already have $_maxActive active links. Turn one off below to create another.',
          'NOT_BUDDIES' => 'You can share a match with family once you are buddies.',
          _ => TrustService.errorText(e),
        },
        error: true,
      );
    }
  }

  Future<void> _revoke(FamilyLink l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off this link?'),
        content: const Text('Anyone who has it will no longer be able to open it. Notes already sent stay with you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(l.id));
    try {
      await _service.revokeFamilyLink(l.id);
      if (!mounted) return;
      showAppSnack(context, 'Link turned off');
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, TrustService.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(l.id));
    }
  }

  Widget _intro() {
    final name = widget.matchName ?? 'this match';
    return AppCard(
      gradient: AppColors.cosmicGradient,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.family_restroom_rounded, color: AppColors.gold, size: 32),
        const SizedBox(height: AppSpacing.sm),
        Text(_isMatch ? 'Show $name to your family' : 'Share with family',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25)),
        const SizedBox(height: 6),
        Text(
          _isMatch
              ? 'Send your parents a private link with $name\'s profile and your compatibility score. '
                  'They can leave you a note. No app or login needed.'
              : 'Send your parents or siblings a private link to your profile and biodata. '
                  'They can leave you a note. No app or login needed.',
          style: const TextStyle(color: AppColors.textOnDarkMuted, fontSize: 14, height: 1.45),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          key: const ValueKey('create-family-link'),
          label: _isMatch ? 'Create link for $name' : 'Create family link',
          icon: Icons.link_rounded,
          loading: _creating,
          onPressed: _creating ? null : _create,
        ),
      ]),
    );
  }

  Widget _linkTile(FamilyLink l) {
    final fmt = DateFormat('d MMM yyyy');
    final status = l.active
        ? (l.expiresAt != null ? 'Works until ${fmt.format(l.expiresAt!)}' : 'Active')
        : (l.revokedAt != null ? 'Turned off' : 'Expired');
    final busy = _busy.contains(l.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: ValueKey('family-link-${l.id}'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(l.isMatch ? Icons.favorite_rounded : Icons.person_rounded,
                color: l.active ? AppColors.primary : AppColors.textTertiary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
            ),
            AppBadge(label: l.active ? 'Active' : status, color: l.active ? AppColors.success : AppColors.textTertiary),
          ]),
          const SizedBox(height: 4),
          Text(
            [
              if (l.active) status,
              if (l.notesCount > 0) '${l.notesCount} ${l.notesCount == 1 ? 'note' : 'notes'}',
            ].join(' · ').ifEmpty('No notes yet'),
            style: AppText.caption,
          ),
          if (l.active)
            Wrap(spacing: 4, children: [
              TextButton.icon(
                onPressed: () => _share(l),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share'),
              ),
              TextButton.icon(
                onPressed: () => _copy(l),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => _revoke(l),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Turn off'),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _body() {
    if (!_loggedIn) {
      return Center(
        child: AppStateView(
          icon: Icons.lock_person_rounded,
          title: 'Log in to share with family',
          message: 'Family links are for registered members with a buddy profile.',
          actionLabel: 'Log in',
          onAction: () => Navigator.pushNamed(context, '/login'),
        ),
      );
    }
    final links = _links;
    final children = <Widget>[_intro()];
    if (links == null) {
      if (_loading) {
        children.addAll([
          const SizedBox(height: AppSpacing.md),
          const SkeletonBox(height: 90, radius: AppRadius.lg),
          const SizedBox(height: AppSpacing.sm),
          const SkeletonBox(height: 90, radius: AppRadius.lg),
        ]);
      } else {
        children.add(AppStateView.error(message: _error, onAction: _load, compact: true));
      }
    } else {
      final active = links.where((l) => l.active).length;
      children.add(SectionHeader(
        title: 'Your links',
        subtitle: '$active of $_maxActive active · each works for 30 days',
        padding: const EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
      ));
      if (links.isEmpty) {
        children.add(const AppStateView(
          icon: Icons.link_rounded,
          title: 'No links yet',
          message: 'Create one above and send it on WhatsApp.',
          compact: true,
        ));
      } else {
        children.addAll(links.map(_linkTile));
      }
    }
    children.addAll([
      const SizedBox(height: AppSpacing.sm),
      AppCard(
        padding: EdgeInsets.zero,
        child: AppListRow(
          icon: Icons.mark_chat_read_outlined,
          color: AppColors.primary,
          title: 'Family notes',
          subtitle: 'Messages your family left on your links',
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => FamilyNotesScreen(service: widget.service)))
              .then((_) => _load()),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      const BuddyNote(
        icon: Icons.lock_outline_rounded,
        color: AppColors.success,
        text: 'Family sees name, age, city, bio, badges, biodata and Kundli basics (Moon sign, nakshatra, manglik). '
            'Never your birth date, time or place, phone, email, photos or exact location.',
      ),
    ]);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_isMatch ? 'Share match with family' : 'Share with family')),
      body: _body(),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
