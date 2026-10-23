import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/backend_service.dart';
import '../../services/city_autocomplete_service.dart';
import '../../utils/app_routes.dart';
import '../../widgets/ui/app_ui.dart';

const String _kAppPackageId = 'com.cosmicguide.vedicastro';
const String _kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=$_kAppPackageId';

/// Shown at the bottom of the Account tab. Keep in sync with `version:` in
/// pubspec.yaml (the app does not ship package_info_plus).
const String _kAppVersion = '1.0.0 (2)';

/// Formats a backend date (`yyyy-MM-dd` or a full ISO timestamp from Postgres) for display.
String _formatBirthDate(dynamic raw, {String pattern = 'dd MMM yyyy'}) {
  final parsed = _parseBirthDate(raw);
  if (parsed == null) return raw?.toString() ?? '—';
  return DateFormat(pattern).format(parsed);
}

DateTime? _parseBirthDate(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  // Postgres DATE columns are serialised as UTC midnight timestamps; convert to local
  // so the calendar day matches what the user entered.
  return s.contains('T') ? parsed.toLocal() : parsed;
}

IconData _relationshipIcon(String? relationship) {
  final rel = (relationship ?? '').toLowerCase();
  if (rel.contains('spouse') || rel.contains('wife') || rel.contains('husband') || rel.contains('partner')) {
    return Icons.favorite_rounded;
  }
  if (rel.contains('daughter') || rel.contains('girl')) return Icons.face_3_rounded;
  if (rel.contains('son') || rel.contains('child') || rel.contains('boy')) return Icons.face_rounded;
  if (rel.contains('father') || rel.contains('dad')) return Icons.man_rounded;
  if (rel.contains('mother') || rel.contains('mom')) return Icons.woman_rounded;
  if (rel.contains('brother') || rel.contains('sister') || rel.contains('sibling')) return Icons.people_rounded;
  return Icons.handshake_rounded;
}

class MoreTab extends StatefulWidget {
  static final ValueNotifier<String?> targetSectionNotifier = ValueNotifier<String?>(null);

  const MoreTab({super.key});

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  final GlobalKey _familySectionKey = GlobalKey();
  bool _isLoadingFamily = false;
  final Set<String> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    MoreTab.targetSectionNotifier.addListener(_checkTargetSection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFamilyMembers();
      if (mounted) Provider.of<BackendService>(context, listen: false).fetchWalletBalance();
      _checkTargetSection();
    });
  }

  @override
  void dispose() {
    MoreTab.targetSectionNotifier.removeListener(_checkTargetSection);
    super.dispose();
  }

  void _checkTargetSection() {
    if (MoreTab.targetSectionNotifier.value == 'family') {
      MoreTab.targetSectionNotifier.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _familySectionKey.currentContext;
        if (ctx == null) return;
        final reduceMotion = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
        Scrollable.ensureVisible(
          ctx,
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  Future<void> _loadFamilyMembers() async {
    if (!mounted) return;
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (!backendService.isAuthenticated) return;
    setState(() => _isLoadingFamily = true);
    List<Map<String, dynamic>>? list;
    try {
      list = await backendService.fetchFamilyKundlis();
    } catch (e) {
      debugPrint('Family load failed: $e');
    }
    if (!mounted) return;
    setState(() => _isLoadingFamily = false);
    if (list == null) {
      _showSnack(backendService.lastError ?? 'Could not refresh family profiles.', error: true);
    }
  }

  void _go(String route, {Object? arguments}) {
    Navigator.pushNamed(context, route, arguments: arguments);
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    showAppSnack(context, message, error: error);
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('launchUrl failed for $uri: $e');
      return false;
    }
  }

  Future<void> _shareApp() async {
    const message =
        'I use CosmicGuide for Vedic Kundli, Guna Milan & live astrologer guidance. Try it: $_kPlayStoreUrl';
    final ok = await _launch(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'));
    if (ok) return;
    await Clipboard.setData(const ClipboardData(text: message));
    _showSnack('Share link copied to clipboard');
  }

  Future<void> _rateApp() async {
    var ok = await _launch(Uri.parse('market://details?id=$_kAppPackageId'));
    if (!ok) ok = await _launch(Uri.parse(_kPlayStoreUrl));
    if (!ok) _showSnack('Could not open the app store. Please try again later.', error: true);
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your Kundli and family profiles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final backendService = Provider.of<BackendService>(context, listen: false);
    backendService.selectFamilyMember(null);
    try {
      if (backendService.isPanditLoggedIn) await backendService.logoutPandit();
      await backendService.logout();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final id = int.tryParse(member['id']?.toString() ?? '');
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('${member['fullName'] ?? 'This'}\'s profile and saved Kundli will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deletingIds.add(id.toString()));
    bool ok = false;
    try {
      ok = await backendService.deleteFamilyKundli(id);
    } catch (e) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _deletingIds.remove(id.toString()));

    if (ok) {
      final selected = backendService.selectedFamilyMember;
      if (selected != null && selected['id']?.toString() == id.toString()) {
        backendService.selectFamilyMember(null);
      }
      _showSnack('Deleted ${member['fullName'] ?? 'profile'}');
    } else {
      _showSnack(backendService.lastError ?? 'Could not delete profile. Please try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final user = backendService.user;
    final String name = (user?['fullName']?.toString().trim().isNotEmpty ?? false)
        ? user!['fullName'].toString()
        : (backendService.kundliData?['birthDetails']?['fullName']?.toString() ?? 'Seeker');
    final familyMembers = backendService.familyMembers;
    final selectedFamily = backendService.selectedFamilyMember;
    final isLoggedIn = backendService.isAuthenticated;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('My account'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await Future.wait([
            _loadFamilyMembers(),
            backendService.fetchWalletBalance(),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProfileHeader(backendService, name, user, selectedFamily, isLoggedIn),
              const SizedBox(height: AppSpacing.sm),
              _buildStatsRow(backendService),

              // Family & friends
              Padding(
                key: _familySectionKey,
                padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Family & friends', style: AppText.title),
                          SizedBox(height: 2),
                          Text('Save Kundlis for the people you care about', style: AppText.caption),
                        ],
                      ),
                    ),
                    if (isLoggedIn && familyMembers.isNotEmpty)
                      AppButton(
                        label: 'Add',
                        icon: Icons.add_rounded,
                        variant: AppButtonVariant.secondary,
                        expand: false,
                        height: 40,
                        onPressed: () => _showFamilySheet(),
                      ),
                  ],
                ),
              ),
              if (!isLoggedIn)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: AppStateView(
                    compact: true,
                    icon: Icons.lock_outline_rounded,
                    title: 'Log in to save family Kundlis',
                    message: 'Family profiles are stored securely with your account.',
                    actionLabel: 'Log in',
                    onAction: () => Navigator.of(context, rootNavigator: true)
                        .pushNamedAndRemoveUntil(AppRoutes.login, (r) => false),
                  ),
                )
              else if (_isLoadingFamily && familyMembers.isEmpty)
                const Column(children: [
                  SkeletonBox(height: 132, radius: AppRadius.lg),
                  SizedBox(height: AppSpacing.sm),
                  SkeletonBox(height: 132, radius: AppRadius.lg),
                ])
              else if (familyMembers.isEmpty)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: AppStateView(
                    compact: true,
                    icon: Icons.people_outline_rounded,
                    title: 'No family profiles yet',
                    message: 'Add Kundlis for your spouse, children, parents or friends. Pull down to refresh.',
                    actionLabel: 'Add family member',
                    onAction: () => _showFamilySheet(),
                  ),
                )
              else
                ...familyMembers.map((member) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _buildFamilyMemberCard(member, selectedFamily, backendService),
                    )),

              _group('My Kundli', [
                AppListRow(
                  icon: Icons.auto_awesome_rounded,
                  color: AppColors.cosmicLight,
                  title: 'Detailed Kundli report',
                  subtitle: 'Ascendant, Moon sign, Dasha & planet strength',
                  onTap: () {
                    backendService.selectFamilyMember(null);
                    _go(AppRoutes.kundliView);
                  },
                ),
                AppListRow(
                  icon: Icons.edit_calendar_rounded,
                  color: AppColors.cosmicLight,
                  title: 'Edit birth details',
                  subtitle: 'Date, time and place of birth',
                  onTap: () => _go(AppRoutes.birthDetails),
                ),
                AppListRow(
                  icon: Icons.insights_rounded,
                  color: AppColors.cosmicLight,
                  title: 'My personal forecast',
                  subtitle: 'Daily, weekly & monthly guidance',
                  onTap: () => _go(AppRoutes.forecast),
                ),
                AppListRow(
                  icon: Icons.timeline_rounded,
                  color: AppColors.cosmicLight,
                  title: 'Life timeline',
                  subtitle: 'Sade Sati, dashas & major transits',
                  onTap: () => _go(AppRoutes.lifeTimeline),
                ),
                AppListRow(
                  icon: Icons.manage_search_rounded,
                  color: AppColors.cosmicLight,
                  title: 'Why did this happen?',
                  subtitle: 'What your chart was going through on any date',
                  onTap: () => _go(AppRoutes.dateExplorer),
                ),
                AppListRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  color: AppColors.cosmicLight,
                  title: 'AI astrologer chat',
                  subtitle: 'Ask anything about your chart, 24/7',
                  onTap: () => _go(AppRoutes.chatbot),
                ),
              ]),

              _group('Explore', [
                AppListRow(
                  icon: Icons.wb_sunny_outlined,
                  color: AppColors.primary,
                  title: 'Panchang & muhurat',
                  subtitle: 'Tithi, Nakshatra, Rahu Kaal & good timings',
                  onTap: () => _go(AppRoutes.panchang),
                ),
                AppListRow(
                  icon: Icons.diamond_outlined,
                  color: AppColors.primary,
                  title: 'Gemstone & remedy finder',
                  subtitle: 'Gemstones and mantras for your current Dasha',
                  onTap: () => _go(AppRoutes.gemstoneRemedy),
                ),
                AppListRow(
                  icon: Icons.sports_esports_outlined,
                  color: AppColors.primary,
                  title: 'Cosmic games',
                  subtitle: 'Daily missions, Nakshatra cards & more',
                  onTap: () => _go(AppRoutes.games),
                ),
                AppListRow(
                  icon: Icons.menu_book_outlined,
                  color: AppColors.primary,
                  title: 'Astrology blog',
                  subtitle: 'Articles on Vedic astrology & remedies',
                  onTap: () => _go(AppRoutes.blog),
                ),
              ]),

              _group('Support', [
                AppListRow(
                  icon: Icons.support_agent_rounded,
                  title: 'Help & support',
                  subtitle: 'Guides and troubleshooting',
                  onTap: () => _go(AppRoutes.help),
                ),
                AppListRow(
                  icon: Icons.quiz_outlined,
                  title: 'FAQs',
                  subtitle: 'Answers to common questions',
                  onTap: () => _go(AppRoutes.faq),
                ),
                AppListRow(
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact us',
                  subtitle: 'Write to our support team',
                  onTap: () => _go(AppRoutes.contact),
                ),
                AppListRow(
                  icon: Icons.share_outlined,
                  title: 'Share CosmicGuide',
                  subtitle: 'Invite friends & family',
                  onTap: _shareApp,
                ),
                AppListRow(
                  icon: Icons.star_outline_rounded,
                  title: 'Rate the app',
                  subtitle: 'Tell us how we are doing',
                  onTap: _rateApp,
                ),
              ]),

              _group('Legal', [
                AppListRow(
                  icon: Icons.info_outline_rounded,
                  title: 'About us',
                  onTap: () => _go(AppRoutes.about),
                ),
                AppListRow(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () => _go(AppRoutes.privacy),
                ),
                AppListRow(
                  icon: Icons.gavel_rounded,
                  title: 'Terms of service',
                  onTap: () => _go(AppRoutes.terms),
                ),
              ]),

              const SizedBox(height: AppSpacing.xl),
              _buildPanditCard(backendService),

              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: EdgeInsets.zero,
                child: isLoggedIn
                    ? AppListRow(
                        icon: Icons.logout_rounded,
                        color: AppColors.danger,
                        title: 'Log out',
                        trailing: const SizedBox.shrink(),
                        onTap: _confirmLogout,
                      )
                    : AppListRow(
                        icon: Icons.login_rounded,
                        color: AppColors.primary,
                        title: 'Log in',
                        subtitle: 'Sync your Kundli, family & wallet',
                        onTap: () => Navigator.of(context, rootNavigator: true)
                            .pushNamedAndRemoveUntil(AppRoutes.login, (r) => false),
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('CosmicGuide · Version $_kAppVersion', textAlign: TextAlign.center, style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(
    BackendService backendService,
    String name,
    Map<String, dynamic>? user,
    Map<String, dynamic>? selectedFamily,
    bool isLoggedIn,
  ) {
    final kundli = backendService.kundliData;
    final email = user?['email']?.toString();
    final phone = user?['phone']?.toString();
    final contact = [
      if (email != null && email.trim().isNotEmpty) email,
      if (phone != null && phone.trim().isNotEmpty) phone,
    ].join(' · ');
    final chartLine = backendService.hasBirthDetails
        ? 'Lagna ${kundli?['ascendant'] ?? '—'} · Moon ${kundli?['moonSign'] ?? '—'}'
        : null;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                AppAvatar(name: name, size: 56, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                      const SizedBox(height: 2),
                      Text(
                        contact.isNotEmpty ? contact : (isLoggedIn ? 'Signed in' : 'Guest · not signed in'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body,
                      ),
                      if (chartLine != null) ...[
                        const SizedBox(height: 2),
                        Text(chartLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(color: AppColors.cosmicLight)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: _headerAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit profile',
                  onTap: () => _go(AppRoutes.profile),
                ),
              ),
              Container(width: 1, height: 28, color: AppColors.divider),
              Expanded(
                child: _headerAction(
                  icon: Icons.grid_view_rounded,
                  label: 'My Kundli',
                  onTap: () {
                    backendService.selectFamilyMember(null);
                    _go(backendService.hasBirthDetails ? AppRoutes.kundliView : AppRoutes.birthDetails);
                  },
                ),
              ),
            ],
          ),
          if (selectedFamily != null) ...[
            const Divider(),
            Container(
              color: AppColors.infoSoft,
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.xs, 6),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.info),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Viewing ${selectedFamily['fullName'] ?? 'a family'}\'s chart',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => backendService.selectFamilyMember(null),
                    child: const Text('Use mine'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerAction({required IconData icon, required String label, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(BackendService backendService) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.account_balance_wallet_outlined,
              color: AppColors.success,
              value: '₹${backendService.walletBalance.toStringAsFixed(0)}',
              label: 'Wallet balance',
              onTap: () => _go(AppRoutes.wallet),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _StatCard(
              icon: Icons.history_rounded,
              color: AppColors.info,
              value: 'Consultations',
              label: 'History & remedies',
              onTap: () => _go(AppRoutes.consultationHistory),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String label, List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const Divider(indent: 68));
      children.add(rows[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, AppSpacing.xl, 4, AppSpacing.xs),
          child: Text(label, style: AppText.subtitle.copyWith(color: AppColors.textSecondary)),
        ),
        AppCard(padding: EdgeInsets.zero, child: Column(children: children)),
      ],
    );
  }

  Widget _buildPanditCard(BackendService backendService) {
    final loggedIn = backendService.isPanditLoggedIn;
    return AppCard(
      gradient: AppColors.cosmicGradient,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.workspace_premium_outlined, color: AppColors.gold, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loggedIn ? 'Pandit workspace' : 'Are you an astrologer?',
                        style: AppText.subtitle.copyWith(color: AppColors.textOnDark)),
                    const SizedBox(height: 2),
                    Text(
                      loggedIn
                          ? 'Go online, manage your queue and consult seekers.'
                          : 'Join CosmicGuide as a pandit and consult seekers live.',
                      style: AppText.caption.copyWith(color: AppColors.textOnDarkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (loggedIn)
            AppButton(
              label: 'Open pandit dashboard',
              height: 44,
              onPressed: () => _go(AppRoutes.panditDashboard),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Join as pandit',
                    height: 44,
                    onPressed: () => _go(AppRoutes.panditRegistration),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _OnDarkButton(
                    label: 'Pandit login',
                    onPressed: () => _go(AppRoutes.panditLogin),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFamilyMemberCard(
    Map<String, dynamic> member,
    Map<String, dynamic>? selectedFamily,
    BackendService backendService,
  ) {
    final memberId = member['id']?.toString();
    final isSelected = selectedFamily != null && selectedFamily['id']?.toString() == memberId;
    final isDeleting = memberId != null && _deletingIds.contains(memberId);
    final kundli = member['kundli'] is Map ? member['kundli'] as Map : null;
    final relationship = member['relationship']?.toString() ?? 'Family';
    final fullName = member['fullName']?.toString() ?? 'Family Member';
    final place = member['placeOfBirth']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.cosmicLight.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(_relationshipIcon(relationship), color: AppColors.cosmicLight, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          const AppBadge(label: 'Active', color: AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [relationship, _formatBirthDate(member['dateOfBirth']), if (place.isNotEmpty) place].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (isDeleting)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'More options for $fullName',
                  icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                  onSelected: (value) {
                    if (value == 'select') backendService.selectFamilyMember(isSelected ? null : member);
                    if (value == 'edit') _showFamilySheet(existingMember: member);
                    if (value == 'delete') _deleteMember(member);
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'select',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(isSelected ? Icons.person_outline_rounded : Icons.check_circle_outline_rounded),
                        title: Text(isSelected ? 'Use my own chart' : 'Set as active profile'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit details'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                        title: Text('Delete', style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (kundli != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chartPill('Lagna', kundli['ascendant']),
                  _chartPill('Moon', kundli['moonSign']),
                  _chartPill('Nakshatra', kundli['nakshatra']),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'View chart',
                    icon: Icons.pie_chart_outline_rounded,
                    variant: AppButtonVariant.outline,
                    height: 44,
                    onPressed: () {
                      backendService.selectFamilyMember(member);
                      _go(AppRoutes.kundliView);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AppButton(
                    label: 'Ask AI',
                    icon: Icons.chat_bubble_outline_rounded,
                    variant: AppButtonVariant.secondary,
                    height: 44,
                    onPressed: () {
                      backendService.selectFamilyMember(member);
                      _go(AppRoutes.chatbot, arguments: {
                        'name': 'Family Astro Specialist',
                        'specialty': '$relationship Chart Guidance',
                        'field': 'Family Consultation',
                        'initialMessage': _familyChatPrompt(member),
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartPill(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$label ', style: const TextStyle(color: AppColors.textTertiary)),
          TextSpan(text: value?.toString() ?? '—', style: const TextStyle(color: AppColors.textPrimary)),
        ]),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// The chat backend only loads the account holder's own chart, so include the
  /// family member's birth data and key placements in the question itself.
  String _familyChatPrompt(Map<String, dynamic> member) {
    final k = member['kundli'] is Map ? member['kundli'] as Map : const {};
    final parts = <String>[
      'Please provide Vedic Kundli guidance for my ${member['relationship'] ?? 'family member'}, ${member['fullName'] ?? ''}',
      'born ${_formatBirthDate(member['dateOfBirth'], pattern: 'yyyy-MM-dd')} at ${member['timeOfBirth'] ?? 'unknown time'} in ${member['placeOfBirth'] ?? 'India'}',
      if (k['ascendant'] != null) 'Lagna ${k['ascendant']}',
      if (k['moonSign'] != null) 'Moon in ${k['moonSign']}',
      if (k['nakshatra'] != null) '${k['nakshatra']} Nakshatra',
    ];
    return '${parts.join(', ')}.';
  }

  Future<void> _showFamilySheet({Map<String, dynamic>? existingMember}) async {
    final saved = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FamilyBirthDetailsSheet(existingMember: existingMember),
    );
    if (saved != null && mounted) {
      _showSnack(
          '${existingMember != null ? 'Updated' : 'Saved'} Kundli for ${saved['fullName']} (${saved['relationship']})');
    }
  }
}

/// Compact tappable stat tile used in the wallet / consultations row.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback onTap;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
          ],
        ),
      ),
    );
  }
}

/// Secondary button styled for the dark cosmic pandit card.
class _OnDarkButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _OnDarkButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.button,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.button.copyWith(color: AppColors.textOnDark)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FamilyBirthDetailsSheet extends StatefulWidget {
  /// When provided the sheet edits this member (prefilled) instead of adding a new one.
  final Map<String, dynamic>? existingMember;

  const FamilyBirthDetailsSheet({super.key, this.existingMember});

  @override
  State<FamilyBirthDetailsSheet> createState() => _FamilyBirthDetailsSheetState();
}

class _FamilyBirthDetailsSheetState extends State<FamilyBirthDetailsSheet> {
  int _currentStep = 0; // 0: Relationship, 1: Name & Gender, 2: DOB & TOB, 3: Place of Birth

  String _relationship = 'Spouse';
  final TextEditingController _nameController = TextEditingController();
  String _gender = 'Female';

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _dontKnowTime = false;

  final TextEditingController _placeController = TextEditingController();
  List<CitySuggestion> _placeSuggestions = [];
  bool _isSearchingPlace = false;
  Timer? _debounceTimer;
  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedPlaceName;

  bool _isSubmitting = false;
  String? _errorText;

  static const List<Map<String, dynamic>> _relationshipsList = [
    {'label': 'Spouse', 'icon': Icons.favorite_rounded},
    {'label': 'Son', 'icon': Icons.face_rounded},
    {'label': 'Daughter', 'icon': Icons.face_3_rounded},
    {'label': 'Father', 'icon': Icons.man_rounded},
    {'label': 'Mother', 'icon': Icons.woman_rounded},
    {'label': 'Sibling', 'icon': Icons.people_rounded},
    {'label': 'Friend', 'icon': Icons.handshake_rounded},
    {'label': 'Partner', 'icon': Icons.favorite_border_rounded},
  ];

  static const List<(String, IconData)> _genders = [
    ('Male', Icons.male_rounded),
    ('Female', Icons.female_rounded),
    ('Other', Icons.transgender_rounded),
  ];

  bool get _isEditing => widget.existingMember != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existingMember;
    if (m != null) {
      _relationship = m['relationship']?.toString() ?? _relationship;
      _nameController.text = m['fullName']?.toString() ?? '';
      final g = m['gender']?.toString();
      if (g == 'Male' || g == 'Female' || g == 'Other') _gender = g!;
      _selectedDate = _parseBirthDate(m['dateOfBirth']);
      final tob = m['timeOfBirth']?.toString() ?? '';
      final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(tob);
      if (match != null) {
        _selectedTime = TimeOfDay(hour: int.parse(match.group(1)!) % 24, minute: int.parse(match.group(2)!) % 60);
      }
      _placeController.text = m['placeOfBirth']?.toString() ?? '';
      _selectedPlaceName = _placeController.text;
      final k = m['kundli'];
      final kMap = k is Map ? k : const {};
      _selectedLatitude = double.tryParse((m['latitude'] ?? kMap['latitude'])?.toString() ?? '');
      _selectedLongitude = double.tryParse((m['longitude'] ?? kMap['longitude'])?.toString() ?? '');
    }
    _placeController.addListener(_onPlaceTextChanged);
  }

  void _onPlaceTextChanged() {
    final query = _placeController.text.trim();
    // Typing a different place invalidates previously selected coordinates.
    if (_selectedPlaceName != null && _placeController.text != _selectedPlaceName) {
      _selectedPlaceName = null;
      _selectedLatitude = null;
      _selectedLongitude = null;
    }
    _debounceTimer?.cancel();
    if (query.length < 2) {
      if (_placeSuggestions.isNotEmpty || _isSearchingPlace) {
        setState(() {
          _placeSuggestions = [];
          _isSearchingPlace = false;
        });
      }
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isSearchingPlace = true);
      List<CitySuggestion> suggestions = const [];
      try {
        suggestions = await CityAutocompleteService.fetchCitySuggestions(query);
      } catch (e) {
        debugPrint('City search failed: $e');
      }
      if (!mounted || _placeController.text.trim() != query) return;
      setState(() {
        _placeSuggestions = suggestions;
        _isSearchingPlace = false;
      });
    });
  }

  void _selectSuggestion(CitySuggestion suggestion) {
    _debounceTimer?.cancel();
    _placeController.removeListener(_onPlaceTextChanged);
    _placeController.text = suggestion.fullDisplayName;
    _placeController.addListener(_onPlaceTextChanged);

    setState(() {
      _selectedPlaceName = suggestion.fullDisplayName;
      _selectedLatitude = suggestion.latitude;
      _selectedLongitude = suggestion.longitude;
      _placeSuggestions = [];
      _isSearchingPlace = false;
      _errorText = null;
    });

    FocusScope.of(context).unfocus();
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _errorText = null;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
        _dontKnowTime = false;
        _errorText = null;
      });
    }
  }

  void _setError(String message) {
    setState(() => _errorText = message);
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();
    if (_currentStep == 1 && _nameController.text.trim().length < 2) {
      _setError('Please enter the family member\'s full name');
      return;
    }
    if (_currentStep == 2) {
      if (_selectedDate == null) {
        _setError('Please select date of birth');
        return;
      }
      if (_selectedTime == null && !_dontKnowTime) {
        _setError('Please select time of birth, or tick "I don\'t know the exact time"');
        return;
      }
    }
    if (_currentStep == 3 && _placeController.text.trim().isEmpty) {
      _setError('Please enter place of birth');
      return;
    }

    if (_currentStep < 3) {
      setState(() {
        _errorText = null;
        _currentStep++;
      });
    } else {
      _submitFamilyDetails();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _errorText = null;
        _currentStep--;
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submitFamilyDetails() async {
    if (_isSubmitting) return;
    final name = _nameController.text.trim();
    final dob = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final tob = _dontKnowTime || _selectedTime == null
        ? '12:00'
        : "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}";
    final place = _placeController.text.trim();
    final hasCoords = _selectedLatitude != null && _selectedLongitude != null;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final backendService = Provider.of<BackendService>(context, listen: false);
    final old = widget.existingMember;
    final oldId = int.tryParse(old?['id']?.toString() ?? '');
    Map<String, dynamic>? member;
    try {
      // The birth timezone is derived server-side from the coordinates.
      if (oldId != null) {
        member = await backendService.updateFamilyKundli(
          oldId,
          relationship: _relationship,
          fullName: name,
          gender: _gender,
          dateOfBirth: dob,
          timeOfBirth: tob,
          placeOfBirth: place,
          latitude: hasCoords ? _selectedLatitude : null,
          longitude: hasCoords ? _selectedLongitude : null,
          birthTimeKnown: !_dontKnowTime,
        );
        final selected = backendService.selectedFamilyMember;
        if (member != null && selected != null && selected['id']?.toString() == oldId.toString()) {
          backendService.selectFamilyMember(member);
        }
      } else {
        member = await backendService.addFamilyKundli(
          relationship: _relationship,
          fullName: name,
          gender: _gender,
          dateOfBirth: dob,
          timeOfBirth: tob,
          placeOfBirth: place,
          latitude: hasCoords ? _selectedLatitude : null,
          longitude: hasCoords ? _selectedLongitude : null,
          birthTimeKnown: !_dontKnowTime,
        );
      }
    } catch (e) {
      debugPrint('Save family member failed: $e');
      member = null;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (member != null) {
      Navigator.pop(context, member);
    } else if (!backendService.isAuthenticated && !backendService.isGuestSession) {
      _setError('Please log in to save family profiles.');
    } else {
      _setError(backendService.lastError ?? 'Could not save this profile. Please check your connection and try again.');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _placeController.removeListener(_onPlaceTextChanged);
    _nameController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      // A Material (not a coloured Container) so ListTile ink renders correctly.
      child: Material(
        color: AppColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: (media.size.height - media.viewInsets.bottom) * 0.92,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              _buildHeaderProgress(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.md),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _buildCurrentStepView(),
                ),
              ),
              if (_errorText != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(_errorText!, style: AppText.body.copyWith(color: AppColors.danger)),
                      ),
                    ],
                  ),
                ),
              _buildBottomActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderProgress() {
    final progress = (_currentStep + 1) / 4.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: _currentStep == 0 ? 'Close' : 'Back',
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: _isSubmitting ? null : _previousStep,
          ),
          Expanded(
            child: Column(
              children: [
                Text('Step ${_currentStep + 1} of 4', style: AppText.caption),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceMuted,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 1:
        return _buildNameAndGenderStep();
      case 2:
        return _buildBirthDetailsStep();
      case 3:
        return _buildBirthPlaceStep();
      default:
        return _buildRelationshipStep();
    }
  }

  Widget _buildStepHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.headline),
          const SizedBox(height: 6),
          Text(subtitle, style: AppText.body),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text, style: AppText.bodyStrong),
      );

  Widget _selectableTile({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
  }) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }

  // Step 0: Relationship Selection
  Widget _buildRelationshipStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          _isEditing ? 'Edit Kundli profile' : 'Who is this Kundli for?',
          'Choose the relationship so readings are framed for them.',
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.6,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          children: _relationshipsList.map((rel) {
            final label = rel['label'] as String;
            final isSelected = _relationship == label;
            return _selectableTile(
              selected: isSelected,
              onTap: () => setState(() => _relationship = label),
              child: Row(
                children: [
                  Icon(rel['icon'] as IconData,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Step 1: Name & Gender Input
  Widget _buildNameAndGenderStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Name & gender',
          'Used to personalise the chart and readings for your ${_relationship.toLowerCase()}.',
        ),
        _fieldLabel('Full name'),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: 60,
          onChanged: (_) {
            if (_errorText != null) setState(() => _errorText = null);
          },
          onSubmitted: (_) => _nextStep(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'e.g. Ananya Sharma',
            prefixIcon: Icon(Icons.person_outline_rounded),
            counterText: '',
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _fieldLabel('Gender'),
        Row(
          children: [
            for (var i = 0; i < _genders.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(child: _buildGenderCard(_genders[i].$1, _genders[i].$2)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildGenderCard(String label, IconData icon) {
    final isSelected = _gender == label;
    return _selectableTile(
      selected: isSelected,
      onTap: () => setState(() => _gender = label),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: 4),
      child: Column(
        children: [
          Icon(icon, size: 22, color: isSelected ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerField({
    required String label,
    required IconData icon,
    required String value,
    required bool enabled,
    required bool hasValue,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        Semantics(
          button: true,
          enabled: enabled,
          label: '$label: $value',
          excludeSemantics: true,
          child: Material(
            color: enabled ? AppColors.surface : AppColors.surfaceMuted,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.input,
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 15),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: enabled ? AppColors.primary : AppColors.textTertiary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                          color: enabled && hasValue ? AppColors.textPrimary : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Step 2: Date & Time of Birth
  Widget _buildBirthDetailsStep() {
    final dateStr = _selectedDate != null ? DateFormat('dd MMM yyyy').format(_selectedDate!) : 'Select date';
    final timeStr =
        _dontKnowTime ? 'Unknown' : (_selectedTime != null ? _selectedTime!.format(context) : 'Select time');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Date & time of birth',
          'An accurate time sets the Lagna, houses and Dasha periods.',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPickerField(
                label: 'Date of birth',
                icon: Icons.calendar_today_rounded,
                value: dateStr,
                enabled: true,
                hasValue: _selectedDate != null,
                onTap: () => _selectDate(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildPickerField(
                label: 'Time of birth',
                icon: Icons.access_time_rounded,
                value: timeStr,
                enabled: !_dontKnowTime,
                hasValue: _selectedTime != null || _dontKnowTime,
                onTap: () => _selectTime(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          value: _dontKnowTime,
          activeColor: AppColors.primary,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text("I don't know the exact time of birth", style: AppText.bodyStrong),
          subtitle: _dontKnowTime
              ? const Text('12:00 noon will be used. Lagna & houses may be approximate.', style: AppText.caption)
              : null,
          onChanged: (val) {
            setState(() {
              _dontKnowTime = val ?? false;
              _errorText = null;
            });
          },
        ),
      ],
    );
  }

  // Step 3: Place of Birth Step
  Widget _buildBirthPlaceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Place of birth',
          'Pick the city from the list so we can use exact coordinates.',
        ),
        _fieldLabel('City / town of birth'),
        TextField(
          controller: _placeController,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. Delhi, Kathmandu, Colombo',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _isSearchingPlace
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : (_selectedLatitude != null ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : null),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _selectedLatitude != null && _selectedLongitude != null
              ? 'Coordinates: ${_selectedLatitude!.toStringAsFixed(4)}, ${_selectedLongitude!.toStringAsFixed(4)}'
              : 'Pick a suggestion for precise coordinates',
          style: AppText.caption,
        ),
        if (_placeSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _placeSuggestions.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final suggestion = _placeSuggestions[index];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.location_on_outlined, size: 20),
                    title: Text(suggestion.fullDisplayName, style: AppText.bodyStrong),
                    onTap: () => _selectSuggestion(suggestion),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBottomActionButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: AppButton(
        label: _currentStep == 3 ? (_isEditing ? 'Save changes' : 'Create Kundli') : 'Continue',
        loading: _isSubmitting,
        onPressed: _isSubmitting ? null : _nextStep,
      ),
    );
  }
}
