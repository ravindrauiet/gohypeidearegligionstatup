import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

/// Mirrors the bonus slabs applied by `POST /pandit/wallet/recharge`.
double _bonusFor(double amount) {
  if (amount >= 1000) return amount * 0.15;
  if (amount >= 500) return amount * 0.10;
  return 0;
}

String _rupees(double v) => '₹${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const double _minRecharge = 50;
  static const double _maxRecharge = 50000;

  bool _isLoadingBalance = true;
  String? _balanceError;
  bool _isRecharging = false;

  bool _isLoadingTransactions = true;
  String? _transactionsError;
  List<Map<String, dynamic>> _transactions = [];
  final TextEditingController _customAmountController = TextEditingController();
  String? _customAmountError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAll();
    });
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    super.dispose();
  }

  /// Guests (anonymous sessions) also have a server-side wallet.
  bool _hasWallet(BackendService s) => s.isAuthenticated || s.isGuestSession;

  Future<void> _loadAll() => Future.wait([_loadBalance(), _loadTransactions()]);

  Future<void> _loadBalance() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (!_hasWallet(backendService)) {
      setState(() => _isLoadingBalance = false);
      return;
    }
    setState(() {
      _isLoadingBalance = true;
      _balanceError = null;
    });
    double? balance;
    try {
      balance = await backendService.fetchWalletBalance();
    } catch (_) {
      balance = null;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingBalance = false;
      _balanceError = balance == null ? (backendService.lastError ?? 'Could not load your balance.') : null;
    });
  }

  Future<void> _loadTransactions() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (!_hasWallet(backendService)) {
      setState(() => _isLoadingTransactions = false);
      return;
    }
    setState(() {
      _isLoadingTransactions = true;
      _transactionsError = null;
    });
    List<Map<String, dynamic>>? list;
    try {
      list = await backendService.fetchWalletTransactions();
    } catch (_) {
      list = null;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingTransactions = false;
      if (list != null) {
        _transactions = list;
      } else {
        _transactionsError = backendService.lastError ?? 'Could not load transactions.';
      }
    });
  }

  Future<void> _recharge(double amount) async {
    if (_isRecharging) return;
    final bonus = _bonusFor(amount);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Recharge'),
        content: Text(
          bonus > 0
              ? 'Add ${_rupees(amount)} to your wallet?\nYou will receive ${_rupees(bonus)} bonus (total ${_rupees(amount + bonus)}).'
              : 'Add ${_rupees(amount)} to your wallet?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            child: const Text('Recharge', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRecharging = true);
    final backendService = Provider.of<BackendService>(context, listen: false);
    double? newBalance;
    try {
      newBalance = await backendService.rechargeWallet(amount);
    } catch (_) {
      newBalance = null;
    }

    if (!mounted) return;
    setState(() => _isRecharging = false);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (newBalance != null) {
      _customAmountController.clear();
      setState(() => _balanceError = null);
      _loadTransactions();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wallet recharged! New balance: ₹${newBalance.toStringAsFixed(2)}'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Recharge failed. No amount was added. Please try again.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: () => _recharge(amount)),
        ),
      );
    }
  }

  void _submitCustomAmount() {
    FocusScope.of(context).unfocus();
    final amount = double.tryParse(_customAmountController.text.trim());
    String? error;
    if (amount == null) {
      error = 'Enter an amount';
    } else if (amount < _minRecharge) {
      error = 'Minimum recharge is ${_rupees(_minRecharge)}';
    } else if (amount > _maxRecharge) {
      error = 'Maximum recharge is ${_rupees(_maxRecharge)}';
    }
    setState(() => _customAmountError = error);
    if (error == null) _recharge(amount!);
  }

  Widget _buildLoginRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Log in to use your wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Your wallet balance is linked to your CosmicGuide account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              child: const Text('Log in'),
            ),
          ],
        ),
      ),
    );
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
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'My Wallet',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: !_hasWallet(backendService)
          ? _buildLoginRequired()
          : RefreshIndicator(
              color: const Color(0xFFE83D66),
              onRefresh: _loadAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. Current Wallet Balance Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
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
                        const Row(
                          children: [
                            Expanded(
                              child: Text('AVAILABLE BALANCE',
                                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                            ),
                            Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFFD700), size: 22),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          child: _isLoadingBalance
                              ? const Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  ),
                                )
                              : _balanceError != null
                                  ? Row(
                                      children: [
                                        const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _balanceError!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontSize: 12),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _loadBalance,
                                          child: const Text('Retry', style: TextStyle(color: Color(0xFFFFD700))),
                                        ),
                                      ],
                                    )
                                  : FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '₹${balance.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                        ),
                        const SizedBox(height: 4),
                        const Text('Use for live Pandit consultations', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'QUICK RECHARGE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12),

                  _buildRechargeCard(amount: 100, badge: 'STARTER', badgeColor: Colors.blue),
                  const SizedBox(height: 12),
                  _buildRechargeCard(amount: 500, badge: '+10% BONUS', badgeColor: const Color(0xFFE83D66), isPopular: true),
                  const SizedBox(height: 12),
                  _buildRechargeCard(amount: 1000, badge: '+15% BONUS', badgeColor: const Color(0xFF9C27B0)),

                  const SizedBox(height: 20),

                  // Custom amount
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Custom amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customAmountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textInputAction: TextInputAction.done,
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,5}(\.\d{0,2})?'))],
                                onSubmitted: (_) => _submitCustomAmount(),
                                onChanged: (_) {
                                  if (_customAmountError != null) setState(() => _customAmountError = null);
                                },
                                decoration: InputDecoration(
                                  prefixText: '₹ ',
                                  hintText: 'e.g. 250',
                                  errorText: _customAmountError,
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFFFCF7F1),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _isRecharging ? null : _submitCustomAmount,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Get 10% bonus on ₹500+ and 15% bonus on ₹1000+.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  const Text(
                    'TRANSACTIONS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 12),
                  _buildTransactions(),
                  if (_isRecharging) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(color: Color(0xFF059669)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _transactionsPlaceholder({required IconData icon, required String text, Widget? action}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.grey.shade400, size: 36),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }

  String _txDate(dynamic raw) {
    final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (dt == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _buildTransactions() {
    if (_isLoadingTransactions && _transactions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: Color(0xFFE83D66))),
      );
    }
    if (_transactionsError != null && _transactions.isEmpty) {
      return _transactionsPlaceholder(
        icon: Icons.cloud_off_rounded,
        text: _transactionsError!,
        action: TextButton(onPressed: _loadTransactions, child: const Text('Retry')),
      );
    }
    if (_transactions.isEmpty) {
      return _transactionsPlaceholder(
        icon: Icons.receipt_long_rounded,
        text: 'No transactions yet. Your recharges and consultation charges will be listed here.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _transactions.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _buildTransactionTile(_transactions[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final isCredit = tx['direction']?.toString() == 'credit';
    final amountRaw = tx['amount'];
    final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse(amountRaw?.toString() ?? '') ?? 0;
    final type = tx['type']?.toString() ?? '';
    final rawDescription = tx['description']?.toString().trim() ?? '';
    final description = rawDescription.isNotEmpty
        ? rawDescription
        : (type == 'recharge' ? 'Wallet recharge' : 'Consultation charge');
    final color = isCredit ? const Color(0xFF059669) : const Color(0xFFE53935);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(isCredit ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 2),
                Text(_txDate(tx['createdAt']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildRechargeCard({
    required double amount,
    required String badge,
    required Color badgeColor,
    bool isPopular = false,
  }) {
    final bonus = _bonusFor(amount);
    final bonusText = bonus > 0
        ? 'Get ${_rupees(amount + bonus)} value (${_rupees(bonus)} extra)'
        : '${_rupees(amount)} added to wallet';

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
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Icons.add_card_rounded, color: badgeColor, size: 22),
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
                      Text(_rupees(amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
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
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isRecharging ? null : () => _recharge(amount),
              style: ElevatedButton.styleFrom(
                backgroundColor: badgeColor,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
