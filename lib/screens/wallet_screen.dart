import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

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
        title: Text('Add ${_rupees(amount)}?'),
        content: Text(
          bonus > 0
              ? 'You will also get ${_rupees(bonus)} bonus, so ${_rupees(amount + bonus)} in total will be added to your wallet.'
              : '${_rupees(amount)} will be added to your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Add money'),
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
      showAppSnack(context, 'Money added. New balance: ₹${newBalance.toStringAsFixed(2)}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backendService.lastError ?? 'Recharge failed. No amount was added. Please try again.'),
          action: SnackBarAction(label: 'Retry', onPressed: () => _recharge(amount)),
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
      child: SingleChildScrollView(
        child: AppStateView(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Log in to use your wallet',
          message: 'Your wallet balance is linked to your CosmicGuide account.',
          actionLabel: 'Log in',
          onAction: () => Navigator.pushNamed(context, AppRoutes.login),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final double balance = backendService.walletBalance;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Wallet'),
        actions: [
          if (_hasWallet(backendService))
            IconButton(
              tooltip: 'Consultation history',
              icon: const Icon(Icons.history_rounded),
              onPressed: () => Navigator.pushNamed(context, AppRoutes.consultationHistory),
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _isRecharging
              ? const LinearProgressIndicator(minHeight: 2)
              : const Divider(height: 2, thickness: 1, color: AppColors.border),
        ),
      ),
      body: !_hasWallet(backendService)
          ? _buildLoginRequired()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
                children: [
                  _buildBalanceCard(balance),
                  const SectionHeader(
                    title: 'Add money',
                    subtitle: 'Bonus credit on ₹500 and above',
                    padding: EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildRechargeTile(amount: 100)),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: _buildRechargeTile(amount: 500, isPopular: true)),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: _buildRechargeTile(amount: 1000)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildCustomAmountCard(),
                  const SectionHeader(
                    title: 'Transactions',
                    padding: EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
                  ),
                  _buildTransactions(),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard(double balance) {
    Widget value;
    if (_isLoadingBalance) {
      value = Container(
        width: 160,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      );
    } else if (_balanceError != null) {
      value = Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.textOnDarkMuted, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              _balanceError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textOnDark, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _loadBalance,
            style: TextButton.styleFrom(foregroundColor: AppColors.gold, minimumSize: const Size(44, 44)),
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      value = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '₹${balance.toStringAsFixed(2)}',
          style: const TextStyle(
            color: AppColors.textOnDark,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.cosmicGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Available balance', style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 13)),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.gold, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: value)),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Used for live pandit chats. AI astrologer chats are free.',
            style: TextStyle(color: AppColors.textOnDarkMuted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildRechargeTile({required double amount, bool isPopular = false}) {
    final bonus = _bonusFor(amount);
    final enabled = !_isRecharging;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Add ${_rupees(amount)}${bonus > 0 ? ', get ${_rupees(bonus)} bonus' : ''}',
      excludeSemantics: true,
      child: Material(
        color: isPopular ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: isPopular ? AppColors.primary : AppColors.border, width: isPopular ? 1.4 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => _recharge(amount) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
            child: Column(
              children: [
                SizedBox(
                  height: 20,
                  child: isPopular
                      ? const FittedBox(child: AppBadge(label: 'Popular', color: Colors.white, background: AppColors.primary))
                      : null,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_rupees(amount), style: AppText.title.copyWith(fontSize: 20)),
                ),
                const SizedBox(height: 2),
                Text(
                  bonus > 0 ? '+${_rupees(bonus)} bonus' : 'No bonus',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: bonus > 0 ? AppColors.success : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: enabled ? AppColors.primary : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAmountCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Other amount', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.sm),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                label: 'Add',
                expand: false,
                height: 48,
                onPressed: _isRecharging ? null : _submitCustomAmount,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Min ${_rupees(_minRecharge)} · 10% bonus on ₹500+ · 15% bonus on ₹1000+',
            style: AppText.caption,
          ),
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
      return const Column(
        children: [
          SkeletonBox(height: 60, radius: AppRadius.md),
          SizedBox(height: AppSpacing.xs),
          SkeletonBox(height: 60, radius: AppRadius.md),
          SizedBox(height: AppSpacing.xs),
          SkeletonBox(height: 60, radius: AppRadius.md),
        ],
      );
    }
    if (_transactionsError != null && _transactions.isEmpty) {
      return AppCard(
        padding: EdgeInsets.zero,
        child: AppStateView.error(
          title: 'Could not load transactions',
          message: _transactionsError,
          compact: true,
          onAction: _loadTransactions,
        ),
      );
    }
    if (_transactions.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.zero,
        child: AppStateView(
          icon: Icons.receipt_long_outlined,
          title: 'No transactions yet',
          message: 'Your recharges and consultation charges will be listed here.',
          compact: true,
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < _transactions.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
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
    final color = isCredit ? AppColors.success : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCredit ? AppColors.successSoft : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              isCredit ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: isCredit ? AppColors.success : AppColors.textSecondary,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(_txDate(tx['createdAt']), style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${isCredit ? '+' : '−'}₹${amount.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
