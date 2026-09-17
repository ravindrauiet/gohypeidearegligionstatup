import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isRecharging = false;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    await backendService.fetchWalletBalance();
  }

  Future<void> _recharge(double amount) async {
    setState(() => _isRecharging = true);
    final backendService = Provider.of<BackendService>(context, listen: false);
    final newBalance = await backendService.rechargeWallet(amount);

    if (mounted) {
      setState(() => _isRecharging = false);
      if (newBalance != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Wallet Recharged Successfully! New Balance: ₹${newBalance.toStringAsFixed(2)}'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final double balance = backendService.walletBalance;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Astro Wallet',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Current Wallet Balance Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF1E1A38).withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('AVAILABLE CONSULTATION BALANCE', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                      Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFFD700), size: 22),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '₹${balance.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text('Valid for Live Pandit Consultations & AI Chart Readings', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. 1-Tap Quick Recharge Options
            const Text(
              '💳 1-TAP WALLET RECHARGE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),

            _buildRechargeCard(
              amount: 100,
              badge: 'STARTER PACK',
              bonusText: '₹100 Added to Wallet',
              badgeColor: Colors.blue,
              onTap: () => _recharge(100),
            ),
            const SizedBox(height: 12),
            _buildRechargeCard(
              amount: 500,
              badge: '+10% BONUS COINS',
              bonusText: 'Get ₹550 Value (₹50 Extra Bonus)',
              badgeColor: const Color(0xFFE83D66),
              isPopular: true,
              onTap: () => _recharge(500),
            ),
            const SizedBox(height: 12),
            _buildRechargeCard(
              amount: 1000,
              badge: '+15% VIP BONUS',
              bonusText: 'Get ₹1,150 Value (₹150 Extra Bonus)',
              badgeColor: const Color(0xFF9C27B0),
              onTap: () => _recharge(1000),
            ),

            const SizedBox(height: 28),

            // 3. Recent Wallet Transactions History
            const Text(
              '📜 RECENT WALLET TRANSACTIONS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildTransactionTile('Initial Sign-up Welcome Bonus', '+₹250.00', 'Credit', const Color(0xFF059669)),
                  const Divider(height: 1),
                  _buildTransactionTile('Live Consultation with Pt. Rishiraj Sharma', '-₹105.00', 'Debit (5 mins)', Colors.black87),
                  const Divider(height: 1),
                  _buildTransactionTile('Wallet Top-up (+10% Bonus)', '+₹550.00', 'Credit', const Color(0xFF059669)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRechargeCard({
    required double amount,
    required String badge,
    required String bonusText,
    required Color badgeColor,
    required VoidCallback onTap,
    bool isPopular = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPopular ? badgeColor : Colors.grey.shade200, width: isPopular ? 2 : 1),
        boxShadow: [
          if (isPopular) BoxShadow(color: badgeColor.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Icons.add_card_rounded, color: badgeColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Recharge ₹${amount.toInt()}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
                        child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(bonusText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _isRecharging ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: badgeColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Add ₹', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(String title, String amount, String sub, Color color) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(amount.startsWith('+') ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: color, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: Text(amount, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
