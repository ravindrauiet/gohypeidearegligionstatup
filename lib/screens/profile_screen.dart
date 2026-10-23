import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

/// Account & birth-profile overview.
///
/// The backend has no endpoint for changing the account name or email, so
/// those are shown read-only; birth details (which drive the Kundli) are edited
/// through the real Birth Details flow via the sticky bottom button.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, BackendService backendService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to access your Kundli, chats and wallet.'),
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
    if (confirmed != true || !context.mounted) return;
    await backendService.logoutPandit();
    await backendService.logout();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.onboarding, (route) => false);
    }
  }

  static String _formatDate(dynamic raw) {
    final s = raw?.toString() ?? '';
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return s;
    return DateFormat('d MMM yyyy').format(s.contains('T') ? parsed.toLocal() : parsed);
  }

  static String _formatTime(dynamic raw) {
    final s = raw?.toString() ?? '';
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return s;
    final t = DateTime(2000, 1, 1, int.parse(m.group(1)!) % 24, int.parse(m.group(2)!) % 60);
    return DateFormat('h:mm a').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData;
    final dynamic birthRaw = kundli?['birthDetails'];
    final Map birth = birthRaw is Map ? birthRaw : const {};
    final user = backendService.user;

    final String name = (birth['fullName'] ?? user?['fullName'] ?? 'CosmicGuide Seeker').toString().trim();
    final String? accountName = user?['fullName']?.toString();
    final String? email = user?['email']?.toString();
    final String? phone = user?['phone']?.toString();
    final bool isLoggedIn = backendService.isAuthenticated;
    final bool hasChart = backendService.hasBirthDetails;

    String? nonEmpty(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: AppButton(
            label: hasChart ? 'Edit birth details' : 'Add birth details',
            icon: Icons.edit_calendar_rounded,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.birthDetails),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xl),
        children: [
          // Header
          Column(
            children: [
              AppAvatar(name: name, size: 80, color: AppColors.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.headline),
              const SizedBox(height: 4),
              Text(
                nonEmpty(email) ?? (isLoggedIn ? 'Signed in' : 'Guest · not signed in'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body,
              ),
              if (hasChart) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AppBadge(label: 'Lagna ${kundli?['ascendant'] ?? '—'}', color: AppColors.cosmicLight),
                    AppBadge(label: 'Moon ${kundli?['moonSign'] ?? '—'}', color: AppColors.cosmicLight),
                    if (kundli?['nakshatra'] != null)
                      AppBadge(label: '${kundli?['nakshatra']}', color: AppColors.cosmicLight),
                  ],
                ),
              ],
            ],
          ),

          const _SectionLabel('Account'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _InfoRow(icon: Icons.person_outline_rounded, label: 'Name', value: nonEmpty(accountName) ?? '—'),
                const Divider(indent: 52),
                _InfoRow(icon: Icons.alternate_email_rounded, label: 'Email', value: nonEmpty(email) ?? '—'),
                if (nonEmpty(phone) != null) ...[
                  const Divider(indent: 52),
                  _InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: phone!),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, AppSpacing.xs, 4, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Need to change your account email? ', style: AppText.caption),
                InkWell(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.contact),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Contact support',
                        style: AppText.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),

          const _SectionLabel('Birth details'),
          AppCard(
            padding: EdgeInsets.zero,
            child: hasChart || birth.isNotEmpty
                ? Column(
                    children: [
                      _InfoRow(
                          icon: Icons.badge_outlined, label: 'Name on chart', value: nonEmpty(birth['fullName']) ?? '—'),
                      const Divider(indent: 52),
                      _InfoRow(
                          icon: Icons.calendar_today_rounded,
                          label: 'Date of birth',
                          value: nonEmpty(birth['dateOfBirth']) == null ? '—' : _formatDate(birth['dateOfBirth'])),
                      const Divider(indent: 52),
                      _InfoRow(
                          icon: Icons.access_time_rounded,
                          label: 'Time of birth',
                          value: nonEmpty(birth['timeOfBirth']) == null ? '—' : _formatTime(birth['timeOfBirth'])),
                      const Divider(indent: 52),
                      _InfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Place of birth',
                          value: nonEmpty(birth['placeOfBirth']) ?? '—'),
                    ],
                  )
                : const AppStateView(
                    compact: true,
                    icon: Icons.auto_awesome_outlined,
                    title: 'No birth details yet',
                    message: 'Add your date, time and place of birth to generate your Kundli.',
                  ),
          ),

          const _SectionLabel('Shortcuts'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppListRow(
                  icon: Icons.grid_view_rounded,
                  color: AppColors.cosmicLight,
                  title: 'My Kundli chart',
                  subtitle: hasChart ? 'Rasi, Lagna & planetary positions' : 'Add birth details to generate it',
                  onTap: () {
                    if (hasChart) {
                      Navigator.pushNamed(context, AppRoutes.kundliView);
                    } else {
                      showAppSnack(context, 'Add your birth details first to generate your Kundli.');
                      Navigator.pushNamed(context, AppRoutes.birthDetails);
                    }
                  },
                ),
                const Divider(indent: 68),
                AppListRow(
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppColors.success,
                  title: 'Wallet',
                  subtitle: 'Balance ₹${backendService.walletBalance.toStringAsFixed(0)}',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.wallet),
                ),
                const Divider(indent: 68),
                AppListRow(
                  icon: Icons.history_rounded,
                  color: AppColors.info,
                  title: 'Consultations & remedies',
                  subtitle: 'Past sessions and prescribed remedies',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.consultationHistory),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
          AppCard(
            padding: EdgeInsets.zero,
            child: isLoggedIn
                ? AppListRow(
                    icon: Icons.logout_rounded,
                    color: AppColors.danger,
                    title: 'Log out',
                    trailing: const SizedBox.shrink(),
                    onTap: () => _confirmLogout(context, backendService),
                  )
                : AppListRow(
                    icon: Icons.login_rounded,
                    color: AppColors.primary,
                    title: 'Log in',
                    subtitle: 'Sync your Kundli, family & wallet',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.login),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.xl, 4, AppSpacing.xs),
      child: Text(text, style: AppText.subtitle.copyWith(color: AppColors.textSecondary)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.caption),
                  const SizedBox(height: 2),
                  Text(value, style: AppText.bodyStrong),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
