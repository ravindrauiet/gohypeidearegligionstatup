import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/backend_service.dart';

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final user = backendService.user;
    final name = user?['fullName'] ?? 'ravindra';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'More Options',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            // User Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFE83D66).withOpacity(0.15),
                    child: Text(
                      name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFE83D66),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?['email'] ?? 'AstroAI Seeker',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.black),
                    onPressed: () => Navigator.pushNamed(context, '/birth-details'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Navigation List
            _buildMenuItem(
              context,
              icon: Icons.auto_awesome_rounded,
              title: 'Detailed Vedic Kundli Report',
              subtitle: 'Ascendant, Moon Sign, Dasha & Planetary Strength',
              color: const Color(0xFF7C77E6),
              onTap: () => Navigator.pushNamed(context, '/kundli-view'),
            ),

            _buildMenuItem(
              context,
              icon: Icons.edit_calendar_rounded,
              title: 'Edit Birth Details',
              subtitle: 'Update Date, Time, and Place of Birth',
              color: const Color(0xFFFB9548),
              onTap: () => Navigator.pushNamed(context, '/birth-details'),
            ),

            _buildMenuItem(
              context,
              icon: Icons.account_balance_wallet_rounded,
              title: 'Astro Wallet & Bonus',
              subtitle: 'Current Balance: ₹0',
              color: const Color(0xFF6B1A3A),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Free chat bonus activated!')),
                );
              },
            ),

            _buildMenuItem(
              context,
              icon: Icons.chat_rounded,
              title: 'AI Kundli Chat',
              subtitle: '24/7 Personal Astro Assistant',
              color: const Color(0xFFE83D66),
              onTap: () => Navigator.pushNamed(context, '/chatbot'),
            ),

            const SizedBox(height: 20),

            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await backendService.logout();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
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
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
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
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
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
    );
  }
}
