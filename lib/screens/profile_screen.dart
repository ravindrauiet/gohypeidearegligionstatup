import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import 'about_us_screen.dart';
import 'consultation_history_screen.dart';
import 'contact_screen.dart';
import 'faq_screen.dart';
import 'help_screen.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';
import 'wallet_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, BackendService backendService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to access your Kundli, chats and wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Log out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await backendService.logoutPandit();
    await backendService.logout();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (route) => false);
    }
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData;
    final dynamic birthRaw = kundli?['birthDetails'];
    final Map birth = birthRaw is Map ? birthRaw : const {};
    final user = backendService.user;

    final String name = (birth['fullName'] ?? user?['fullName'] ?? 'CosmicGuide Seeker').toString().trim();
    final String? email = user?['email']?.toString();
    final bool isLoggedIn = backendService.isAuthenticated;
    final bool hasChart = backendService.hasBirthDetails;

    final String birthSummary = [
      birth['dateOfBirth'],
      birth['timeOfBirth'],
      birth['placeOfBirth'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Profile & Settings', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // User Avatar Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 5)),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.black,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'C',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email ?? (isLoggedIn ? 'Signed in' : 'Not signed in'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          if (hasChart) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Lagna ${kundli?['ascendant']} · Moon ${kundli?['moonSign'] ?? '—'}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFFB9548), fontWeight: FontWeight.bold),
                            ),
                          ],
                          if (birthSummary.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              birthSummary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _buildGroup([
                _buildListTile(
                  icon: Icons.edit_calendar_rounded,
                  title: hasChart ? 'Update Birth Details' : 'Add Birth Details',
                  subtitle: 'Date, time and place of birth',
                  onTap: () => Navigator.pushNamed(context, '/birth-details'),
                ),
                _buildListTile(
                  icon: Icons.auto_awesome,
                  title: 'My Kundli Chart',
                  subtitle: hasChart ? 'Rasi, Lagna & planetary positions' : 'Add birth details to generate your chart',
                  onTap: () {
                    if (hasChart) {
                      Navigator.pushNamed(context, '/kundli-view');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Add your birth details first to generate your Kundli.')),
                      );
                      Navigator.pushNamed(context, '/birth-details');
                    }
                  },
                ),
                _buildListTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'CosmicGuide AI Astrologer',
                  subtitle: 'Ask questions about your chart',
                  onTap: () => Navigator.pushNamed(context, '/chatbot'),
                ),
              ]),

              const SizedBox(height: 16),

              _buildGroup([
                _buildListTile(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'My Wallet',
                  subtitle: 'Balance ₹${backendService.walletBalance.toStringAsFixed(0)} · Recharge',
                  onTap: () => _push(context, const WalletScreen()),
                ),
                _buildListTile(
                  icon: Icons.history_rounded,
                  title: 'Consultations & Remedies',
                  subtitle: 'Past sessions and prescribed remedies',
                  onTap: () => _push(context, const ConsultationHistoryScreen()),
                ),
              ]),

              const SizedBox(height: 16),

              _buildGroup([
                _buildListTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & Support',
                  subtitle: 'Guides and contact options',
                  onTap: () => _push(context, const HelpScreen()),
                ),
                _buildListTile(
                  icon: Icons.quiz_outlined,
                  title: 'FAQs',
                  subtitle: 'Answers to common questions',
                  onTap: () => _push(context, const FAQScreen()),
                ),
                _buildListTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Contact Us',
                  subtitle: 'Email, phone or WhatsApp',
                  onTap: () => _push(context, const ContactScreen()),
                ),
                _buildListTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About CosmicGuide',
                  subtitle: 'Our mission and values',
                  onTap: () => _push(context, const AboutUsScreen()),
                ),
                _buildListTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'How we handle your data',
                  onTap: () => _push(context, const PrivacyScreen()),
                ),
                _buildListTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  subtitle: 'Rules for using CosmicGuide',
                  onTap: () => _push(context, const TermsScreen()),
                ),
              ]),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: isLoggedIn
                    ? ElevatedButton.icon(
                        onPressed: () => _confirmLogout(context, backendService),
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                        label: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 0,
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                        icon: const Icon(Icons.login_rounded, color: Colors.white),
                        label: const Text('Log in', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> tiles) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(const Divider(height: 1, indent: 20, endIndent: 20));
      children.add(tiles[i]);
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFFFB9548), size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black45),
      ),
    );
  }
}
