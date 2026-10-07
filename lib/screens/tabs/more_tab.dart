import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/backend_service.dart';
import '../../services/city_autocomplete_service.dart';
import '../pandit_registration_screen.dart';
import '../pandit_dashboard_screen.dart';
import '../pandit_login_screen.dart';
import '../wallet_screen.dart';
import '../consultation_history_screen.dart';
import '../gemstone_remedy_screen.dart';
import '../panchang_screen.dart';
import '../blog_screen.dart';
import '../faq_screen.dart';
import '../help_screen.dart';
import '../privacy_screen.dart';
import '../terms_screen.dart';
import '../about_us_screen.dart';
import '../contact_screen.dart';

const String _kAppPackageId = 'com.cosmicguide.ai';
const String _kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=$_kAppPackageId';

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

class MoreTab extends StatefulWidget {
  const MoreTab({super.key});

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  bool _isLoadingFamily = false;
  final Set<String> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFamilyMembers();
      if (mounted) Provider.of<BackendService>(context, listen: false).fetchWalletBalance();
    });
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
      _showSnack(backendService.lastError ?? 'Could not refresh family profiles.', color: Colors.redAccent);
    }
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
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
    const message = 'I use CosmicGuide for Vedic Kundli, Guna Milan & live astrologer guidance. Try it: $_kPlayStoreUrl';
    final ok = await _launch(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'));
    if (ok) return;
    await Clipboard.setData(const ClipboardData(text: message));
    _showSnack('Share link copied to clipboard');
  }

  Future<void> _rateApp() async {
    var ok = await _launch(Uri.parse('market://details?id=$_kAppPackageId'));
    if (!ok) ok = await _launch(Uri.parse(_kPlayStoreUrl));
    if (!ok) _showSnack('Could not open the app store. Please try again later.');
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your Kundli and family profiles.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final id = int.tryParse(member['id']?.toString() ?? '');
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Profile'),
        content: Text('Are you sure you want to delete ${member['fullName'] ?? 'this'}\'s profile?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
      _showSnack(backendService.lastError ?? 'Could not delete profile. Please try again.', color: Colors.redAccent);
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
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'More & Family Profiles',
          style: TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadFamilyMembers(),
            backendService.fetchWalletBalance(),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Primary User Header Card
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pushNamed(context, '/profile'),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selectedFamily == null ? const Color(0xFFE83D66) : Colors.grey.shade200,
                        width: selectedFamily == null ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFFE83D66).withValues(alpha: 0.15),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: Color(0xFFE83D66),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE83D66).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Primary Self',
                                      style:
                                          TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE83D66)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?['email']?.toString() ?? 'Tap to view profile',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        if (selectedFamily != null)
                          TextButton(
                            onPressed: () => backendService.selectFamilyMember(null),
                            child: const Text('Use Self', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        else
                          const Icon(Icons.check_circle_rounded, color: Color(0xFFE83D66), size: 22),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Pandit & Astrologer Marketplace Section Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF1E1A38).withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 22),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('ASTROLOGER & PANDIT PORTAL',
                              style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Consult Live & Inspect Seeker Kundlis',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Register as an expert astrologer or switch to your live consultation workspace.',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _push(const PanditRegistrationScreen()),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFFD700)),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const FittedBox(
                              child: Text('Register as Pandit',
                                  style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _push(backendService.isPanditLoggedIn
                                ? const PanditDashboardScreen()
                                : const PanditLoginScreen()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE83D66),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const FittedBox(
                              child: Text('Pandit Dashboard',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Wallet & Consultation Tools Section
              const Text(
                'SERVICING & CONSULTATION TOOLS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildToolTile(
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF059669),
                      title: 'My Wallet',
                      subtitle: 'Balance: ₹${backendService.walletBalance.toStringAsFixed(0)}',
                      subtitleColor: const Color(0xFF059669),
                      onTap: () => _push(const WalletScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildToolTile(
                      icon: Icons.history_rounded,
                      color: const Color(0xFFE83D66),
                      title: 'Consult History',
                      subtitle: 'Past chats & remedies',
                      subtitleColor: Colors.grey,
                      onTap: () => _push(const ConsultationHistoryScreen()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // AI Gemstone & Remedy Recommendation Tool Banner
              Material(
                color: const Color(0xFF9C27B0).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _push(const GemstoneRemedyScreen()),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF9C27B0).withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(color: Color(0xFF9C27B0), shape: BoxShape.circle),
                          child: const Icon(Icons.diamond_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('AI Gemstone & Remedy Finder Tool',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF7B1FA2))),
                              SizedBox(height: 2),
                              Text('Discover optimal gemstones & mantras for your current Dasha',
                                  style: TextStyle(fontSize: 11, color: Colors.black87)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF7B1FA2), size: 14),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 2. Family & Friends Section Header
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FAMILY & FRIENDS KUNDLIS',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                        SizedBox(height: 2),
                        Text('Multiple Profiles',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                  if (isLoggedIn)
                    ElevatedButton.icon(
                      onPressed: () => _showFamilySheet(),
                      icon: const Icon(Icons.add, size: 16, color: Colors.white),
                      label: const Text('Add',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Family Members List
              if (!isLoggedIn)
                _buildFamilyEmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Log in to save family Kundlis',
                  message: 'Family profiles are stored securely with your account.',
                  buttonLabel: 'Log In',
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (r) => false),
                )
              else if (_isLoadingFamily && familyMembers.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              else if (familyMembers.isEmpty)
                _buildFamilyEmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No Family Kundlis Added Yet',
                  message: 'Create Kundlis for your spouse, children, parents, or friends under your account.',
                  buttonLabel: '+ Add First Family Kundli',
                  onPressed: () => _showFamilySheet(),
                  secondaryLabel: 'Refresh',
                  onSecondary: _loadFamilyMembers,
                )
              else
                ...familyMembers.map((member) => _buildFamilyMemberCard(member, selectedFamily, backendService)),

              const SizedBox(height: 24),

              // 3. Navigation List
              const Text('ACCOUNT & KUNDLI',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 10),

              _buildMenuItem(
                icon: Icons.person_rounded,
                title: 'My Profile & Settings',
                subtitle: 'Account details and preferences',
                color: const Color(0xFF3F51B5),
                onTap: () => Navigator.pushNamed(context, '/profile'),
              ),
              _buildMenuItem(
                icon: Icons.auto_awesome_rounded,
                title: 'Detailed Vedic Kundli Report',
                subtitle: 'Ascendant, Moon Sign, Dasha & Planetary Strength',
                color: const Color(0xFF7C77E6),
                onTap: () {
                  backendService.selectFamilyMember(null);
                  Navigator.pushNamed(context, '/kundli-view');
                },
              ),
              _buildMenuItem(
                icon: Icons.edit_calendar_rounded,
                title: 'Edit Primary Birth Details',
                subtitle: 'Update Date, Time, and Place of Birth',
                color: const Color(0xFFFB9548),
                onTap: () => Navigator.pushNamed(context, '/birth-details'),
              ),
              _buildMenuItem(
                icon: Icons.wb_sunny_rounded,
                title: 'Daily Panchang & Muhurat',
                subtitle: 'Tithi, Nakshatra, Rahu Kaal & auspicious timings',
                color: const Color(0xFFD97706),
                onTap: () => _push(const PanchangScreen()),
              ),
              _buildMenuItem(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Astro Wallet & Recharge',
                subtitle: 'Current Balance: ₹${backendService.walletBalance.toStringAsFixed(0)}',
                color: const Color(0xFF6B1A3A),
                onTap: () => _push(const WalletScreen()),
              ),
              _buildMenuItem(
                icon: Icons.chat_rounded,
                title: 'AI Kundli Chat',
                subtitle: '24/7 Personal Astro Assistant',
                color: const Color(0xFFE83D66),
                onTap: () => Navigator.pushNamed(context, '/chatbot'),
              ),

              const SizedBox(height: 12),
              const Text('LEARN & SUPPORT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 10),

              _buildMenuItem(
                icon: Icons.menu_book_rounded,
                title: 'Astrology Blog',
                subtitle: 'Articles on Vedic astrology & remedies',
                color: const Color(0xFF00897B),
                onTap: () => _push(const BlogScreen()),
              ),
              _buildMenuItem(
                icon: Icons.quiz_rounded,
                title: 'FAQs',
                subtitle: 'Answers to common questions',
                color: const Color(0xFF5C6BC0),
                onTap: () => _push(const FAQScreen()),
              ),
              _buildMenuItem(
                icon: Icons.support_agent_rounded,
                title: 'Help & Support',
                subtitle: 'Guides and troubleshooting',
                color: const Color(0xFF0288D1),
                onTap: () => _push(const HelpScreen()),
              ),
              _buildMenuItem(
                icon: Icons.mail_outline_rounded,
                title: 'Contact Us',
                subtitle: 'Reach our support team',
                color: const Color(0xFF7B1FA2),
                onTap: () => _push(const ContactScreen()),
              ),
              _buildMenuItem(
                icon: Icons.share_rounded,
                title: 'Share CosmicGuide',
                subtitle: 'Invite friends & family',
                color: const Color(0xFF2E7D32),
                onTap: _shareApp,
              ),
              _buildMenuItem(
                icon: Icons.star_rate_rounded,
                title: 'Rate the App',
                subtitle: 'Tell us how we are doing',
                color: const Color(0xFFFFA000),
                onTap: _rateApp,
              ),
              _buildMenuItem(
                icon: Icons.info_outline_rounded,
                title: 'About Us',
                subtitle: 'Our mission and team',
                color: const Color(0xFF546E7A),
                onTap: () => _push(const AboutUsScreen()),
              ),
              _buildMenuItem(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                subtitle: 'How we protect your data',
                color: const Color(0xFF455A64),
                onTap: () => _push(const PrivacyScreen()),
              ),
              _buildMenuItem(
                icon: Icons.gavel_rounded,
                title: 'Terms & Conditions',
                subtitle: 'Terms of service',
                color: const Color(0xFF37474F),
                onTap: () => _push(const TermsScreen()),
              ),

              const SizedBox(height: 20),

              // Logout Button
              if (isLoggedIn)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _confirmLogout,
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Color subtitleColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 22),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 12),
                ],
              ),
              const SizedBox(height: 10),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: subtitleColor, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFamilyEmptyState({
    required IconData icon,
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Colors.grey),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
              if (secondaryLabel != null && onSecondary != null)
                TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                child: Icon(
                  _getRelationshipIcon(relationship),
                  color: const Color(0xFF6C63FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        relationship,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [_formatBirthDate(member['dateOfBirth']), if (place.isNotEmpty) place].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isSelected ? 'Active profile' : 'Set as active profile',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? const Color(0xFF6C63FF) : Colors.grey,
                ),
                onPressed: () => backendService.selectFamilyMember(isSelected ? null : member),
              ),
              if (isDeleting)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.black54),
                  onSelected: (value) {
                    if (value == 'edit') _showFamilySheet(existingMember: member);
                    if (value == 'delete') _deleteMember(member);
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit details'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        title: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (kundli != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCF7F1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Lagna: ${kundli['ascendant'] ?? '—'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      'Moon: ${kundli['moonSign'] ?? '—'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD95D39)),
                    ),
                    Text(
                      'Nakshatra: ${kundli['nakshatra'] ?? '—'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF673AB7)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      backendService.selectFamilyMember(member);
                      Navigator.pushNamed(context, '/kundli-view');
                    },
                    icon: const Icon(Icons.pie_chart_outline_rounded, size: 14),
                    label: const Text('View Chart', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      backendService.selectFamilyMember(member);
                      Navigator.pushNamed(context, '/chatbot', arguments: {
                        'name': 'Family Astro Specialist',
                        'specialty': '$relationship Chart Guidance',
                        'field': 'Family Consultation',
                        'initialMessage': _familyChatPrompt(member),
                      });
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.white),
                    label: const Text('Ask AI Chat',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

  IconData _getRelationshipIcon(String? relationship) {
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

  Future<void> _showFamilySheet({Map<String, dynamic>? existingMember}) async {
    final saved = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FamilyBirthDetailsSheet(existingMember: existingMember),
    );
    if (saved != null && mounted) {
      _showSnack(
        '${existingMember != null ? 'Updated' : 'Saved'} Kundli for ${saved['fullName']} (${saved['relationship']})!',
        color: const Color(0xFF059669),
      );
    }
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
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

  ThemeData _pickerTheme() => ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          surface: Color(0xFFFCF7F1),
        ),
      );

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) => Theme(data: _pickerTheme(), child: child!),
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
      builder: (context, child) => Theme(data: _pickerTheme(), child: child!),
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
      child: Container(
        height: (media.size.height - media.viewInsets.bottom) * 0.92,
        decoration: const BoxDecoration(
          color: Color(0xFFFCF7F1),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildHeaderProgress(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: _buildCurrentStepView(),
              ),
            ),
            if (_errorText != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorText!, style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13)),
                    ),
                  ],
                ),
              ),
            _buildBottomActionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderProgress() {
    double progress = (_currentStep + 1) / 4.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: _currentStep == 0 ? 'Close' : 'Back',
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
            onPressed: _isSubmitting ? null : _previousStep,
          ),
          Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.black.withValues(alpha: 0.08),
                  color: Colors.black,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: Colors.black, size: 22),
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

  Widget _buildStepHeader(IconData icon, String title, String subtitle) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.amber.shade200, width: 4),
          ),
          child: Center(child: Icon(icon, size: 40, color: Colors.white)),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, {Widget? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.black, width: 1.5),
      ),
    );
  }

  // Step 0: Relationship Selection
  Widget _buildRelationshipStep() {
    return Column(
      children: [
        _buildStepHeader(
          Icons.people_outline_rounded,
          _isEditing ? 'Edit Kundli Profile' : 'Who is this Kundli for?',
          'Select relationship to customize astronomical chart insights',
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: _relationshipsList.map((rel) {
            final label = rel['label'] as String;
            final isSelected = _relationship == label;
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _relationship = label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? Colors.black : Colors.black.withValues(alpha: 0.1),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        rel['icon'] as IconData,
                        color: isSelected ? Colors.black : Colors.grey.shade700,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
      children: [
        _buildStepHeader(
          Icons.person,
          '$_relationship Name & Gender',
          'We calculate exact Lagna, Moon Sign & planetary placements',
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Full Name',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: 60,
          onChanged: (_) {
            if (_errorText != null) setState(() => _errorText = null);
          },
          onSubmitted: (_) => _nextStep(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: _inputDecoration('e.g. Ananya Sharma').copyWith(counterText: ''),
        ),
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Gender',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildGenderCard('Male', '♂'),
            const SizedBox(width: 10),
            _buildGenderCard('Female', '♀'),
            const SizedBox(width: 10),
            _buildGenderCard('Other', '⚥'),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderCard(String label, String symbol) {
    final isSelected = _gender == label;
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _gender = label),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.black : Colors.black.withValues(alpha: 0.1),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              children: [
                Text(symbol, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickerField({
    required String label,
    required IconData icon,
    required String value,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 8),
        Material(
          color: enabled ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: enabled ? Colors.black : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: enabled ? Colors.black : Colors.grey,
                      ),
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

  // Step 2: Date & Time of Birth
  Widget _buildBirthDetailsStep() {
    final dateStr = _selectedDate != null ? DateFormat('dd MMM yyyy').format(_selectedDate!) : 'Select date';
    final timeStr = _dontKnowTime
        ? 'Unknown'
        : (_selectedTime != null ? _selectedTime!.format(context) : 'Select time');

    return Column(
      children: [
        _buildStepHeader(
          Icons.cake_rounded,
          'Date & Time of Birth',
          'Accurate date and time determine house divisions and dashas',
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPickerField(
                label: 'Date of Birth',
                icon: Icons.calendar_today_rounded,
                value: dateStr,
                enabled: true,
                onTap: () => _selectDate(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPickerField(
                label: 'Time of Birth',
                icon: Icons.access_time_rounded,
                value: timeStr,
                enabled: !_dontKnowTime,
                onTap: () => _selectTime(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _dontKnowTime,
          activeColor: Colors.black,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            "I don't know the exact time of birth",
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          subtitle: _dontKnowTime
              ? const Text('12:00 noon will be used. Lagna & houses may be approximate.',
                  style: TextStyle(fontSize: 12))
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
      children: [
        _buildStepHeader(
          Icons.location_on_rounded,
          'Place of Birth',
          'Determines exact geographical coordinates & ayanamsa offset',
        ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('City / Town of Birth',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _placeController,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: _inputDecoration(
            'e.g. New Delhi, India',
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.black54),
            suffixIcon: _isSearchingPlace
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
                  )
                : (_selectedLatitude != null
                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF059669))
                    : null),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _selectedLatitude != null && _selectedLongitude != null
                ? 'Coordinates: ${_selectedLatitude!.toStringAsFixed(4)}, ${_selectedLongitude!.toStringAsFixed(4)}'
                : 'Pick a suggestion for precise coordinates',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        if (_placeSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _placeSuggestions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final suggestion = _placeSuggestions[index];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(Icons.location_on_outlined, size: 20, color: Colors.black),
                    title: Text(suggestion.fullDisplayName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      color: const Color(0xFFFCF7F1),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            disabledBackgroundColor: Colors.black54,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  _currentStep == 3 ? (_isEditing ? 'Save Changes' : 'Generate AI Kundli Chart') : 'Continue',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
