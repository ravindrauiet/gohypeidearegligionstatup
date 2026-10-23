import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../widgets/ui/app_ui.dart';
import 'pandit_chat_screen.dart';
import 'pandit_login_screen.dart';

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
  return fallback;
}

bool _toBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  if (v is num) return v != 0;
  return fallback;
}

String _money(double v) => '₹${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today, 14:05" / "12 Oct, 09:30" for a transaction timestamp; null if unparseable.
String? _shortDate(dynamic raw) {
  final dt = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (dt == null) return null;
  final now = DateTime.now();
  final hm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'Today, $hm';
  return '${dt.day} ${_months[dt.month - 1]}, $hm';
}

class PanditDashboardScreen extends StatefulWidget {
  const PanditDashboardScreen({super.key});

  @override
  State<PanditDashboardScreen> createState() => _PanditDashboardScreenState();
}

class _PanditDashboardScreenState extends State<PanditDashboardScreen> {
  static const Duration _pollInterval = Duration(seconds: 10);

  bool _isOnline = true;
  bool _isTogglingStatus = false;
  bool _isLoading = true;
  bool _isActionBusy = false;
  bool _isFetching = false;
  String? _loadError;

  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _waitingQueue = [];
  Timer? _pollTimer;

  /// Recent payouts credited to this Pandit (null until loaded / on failure).
  List<Map<String, dynamic>>? _payouts;
  bool _payoutsFailed = false;

  @override
  void initState() {
    super.initState();
    final pandit = Provider.of<BackendService>(context, listen: false).currentPandit;
    _isOnline = _toBool(pandit?['is_online'], true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadDashboardData();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _loadDashboardData(silent: true));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  dynamic get _panditId => Provider.of<BackendService>(context, listen: false).currentPandit?['id'];

  /// Loads the active session & waiting queue for the logged-in Pandit.
  /// [silent] is used by background polling: failures keep the last good data.
  Future<void> _loadDashboardData({bool silent = false}) async {
    if (_isFetching) return;
    final backendService = Provider.of<BackendService>(context, listen: false);
    if (!backendService.isPanditLoggedIn) return;

    final panditId = _panditId;
    if (panditId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Your Pandit profile could not be found. Please log in again.';
        });
      }
      return;
    }

    _isFetching = true;
    Map<String, dynamic>? data;
    try {
      data = await backendService.fetchQueueStatus(panditId: panditId);
      // Fresh earnings / minutes on explicit loads (not every background poll).
      if (!silent) {
        await backendService.refreshPanditProfile();
        unawaited(_loadPayouts());
      }
    } catch (_) {
      data = null;
    } finally {
      _isFetching = false;
    }

    if (!mounted) return;

    if (data == null) {
      if (silent) return;
      final hadData = !_isLoading && _loadError == null;
      setState(() {
        _isLoading = false;
        if (!hadData) {
          _loadError = 'Could not load your consultation queue. Check your connection and try again.';
        }
      });
      if (hadData) {
        showAppSnack(context, 'Could not refresh the queue. Showing last known data.', error: true);
      }
      return;
    }

    final active = data['activeSession'];
    final waiting = data['waitingQueue'];
    setState(() {
      _activeSession = active is Map ? Map<String, dynamic>.from(active) : null;
      _waitingQueue = waiting is List
          ? waiting.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      _isLoading = false;
      _loadError = null;
    });
  }

  Future<void> _loadPayouts() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    List<Map<String, dynamic>>? list;
    try {
      list = await backendService.fetchWalletTransactions(asPandit: true);
    } catch (_) {
      list = null;
    }
    if (!mounted) return;
    setState(() {
      _payoutsFailed = list == null;
      if (list != null) {
        _payouts = list.where((t) => t['direction'] == 'credit' && t['type'] != 'recharge').take(5).toList();
      }
    });
  }

  Future<void> _toggleOnlineStatus(bool val) async {
    if (_isTogglingStatus) return;
    final previous = _isOnline;
    setState(() {
      _isOnline = val;
      _isTogglingStatus = true;
    });
    final backendService = Provider.of<BackendService>(context, listen: false);
    bool ok;
    try {
      ok = await backendService.togglePanditStatus(isOnline: val);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _isTogglingStatus = false;
      if (!ok) _isOnline = previous;
    });
    showAppSnack(
      context,
      ok
          ? (val ? 'You are now online and visible to seekers.' : 'You are now offline.')
          : (backendService.lastError ?? 'Could not update your status. Please try again.'),
      error: !ok,
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? AppColors.danger : AppColors.primary,
              minimumSize: const Size(64, 44),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Completes the current active session (if any) and connects the next
  /// waiting seeker. The backend always takes seekers in queue order.
  Future<void> _advanceQueue({required bool endingOnly}) async {
    if (_isActionBusy) return;
    final panditId = _panditId;
    if (panditId == null) return;

    final activeName = (_activeSession?['user_name'] ?? 'the current seeker').toString();
    if (_activeSession != null) {
      final confirmed = await _confirm(
        title: endingOnly ? 'End consultation?' : 'Connect next seeker?',
        message: endingOnly
            ? 'This will mark your session with $activeName as completed.'
                '${_waitingQueue.isNotEmpty ? ' The next seeker in line will be connected automatically.' : ''}'
            : 'This will end your current session with $activeName and connect the next seeker in line.',
        confirmLabel: endingOnly ? 'End session' : 'Connect next',
        destructive: endingOnly,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _isActionBusy = true);
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? res;
    try {
      res = await backendService.nextConsultation(panditId);
    } catch (_) {
      res = null;
    }
    if (!mounted) return;

    if (res == null) {
      setState(() => _isActionBusy = false);
      showAppSnack(context, 'Action failed. Please check your connection and try again.', error: true);
      return;
    }

    await _loadDashboardData();
    if (!mounted) return;
    setState(() => _isActionBusy = false);

    final next = res['activeSession'];
    if (next is Map) {
      final nextSession = Map<String, dynamic>.from(next);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Connected to ${nextSession['user_name'] ?? 'next seeker'}'),
            action: SnackBarAction(
              label: 'Open chat',
              onPressed: () => _openChat(_activeSession ?? nextSession),
            ),
          ),
        );
    } else {
      showAppSnack(context, 'Session completed. You are now available for new seekers.');
    }
  }

  Future<void> _openChat(Map<String, dynamic> session) async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final pandit = backendService.currentPandit;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PanditChatScreen(
          sessionData: {
            ...session,
            if (pandit?['rate_per_min'] != null) 'rate_per_min': pandit!['rate_per_min'],
          },
        ),
      ),
    );
    // Not silent: also refreshes earnings after a session ended in the chat.
    if (mounted) _loadDashboardData();
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: 'Log out?',
      message: 'You will stop receiving consultation requests on this device until you log in again.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    _pollTimer?.cancel();
    final backendService = Provider.of<BackendService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await backendService.logoutPandit();
    messenger.showSnackBar(const SnackBar(content: Text('Logged out of your partner account.')));
    if (navigator.canPop()) navigator.pop();
  }

  void _retryLoad() {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    _loadDashboardData();
  }

  String _waitedLabel(dynamic createdAt) {
    final dt = DateTime.tryParse(createdAt?.toString() ?? '');
    if (dt == null) return 'Waiting in line';
    final mins = DateTime.now().difference(dt.toLocal()).inMinutes;
    if (mins < 1) return 'Joined just now';
    if (mins < 60) return 'Waiting $mins min';
    return 'Waiting ${mins ~/ 60}h ${mins % 60}m';
  }

  String _activeLabel(dynamic startedAt) {
    final dt = DateTime.tryParse(startedAt?.toString() ?? '');
    if (dt == null) return 'Live 1-on-1 chat';
    final mins = DateTime.now().difference(dt.toLocal()).inMinutes;
    if (mins < 1) return 'Started just now';
    if (mins < 60) return 'Started $mins min ago';
    return 'Started ${mins ~/ 60}h ${mins % 60}m ago';
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _buildLoginRequired(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Partner dashboard'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: AppStateView(
            icon: Icons.lock_person_rounded,
            color: AppColors.cosmicLight,
            title: 'Partner login required',
            message: 'This workspace is for verified astrologer partners. '
                'Log in with your partner account to manage live consultations.',
            actionLabel: 'Log in as partner',
            onAction: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const PanditLoginScreen()),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    Widget card(double h) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: SkeletonBox(height: h, radius: AppRadius.lg),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        card(132),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              const Expanded(child: SkeletonBox(height: 76, radius: AppRadius.lg)),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const SkeletonBox(width: 160, height: 18, radius: AppRadius.sm),
        const SizedBox(height: AppSpacing.sm),
        card(120),
        const SizedBox(height: AppSpacing.md),
        const SkeletonBox(width: 140, height: 18, radius: AppRadius.sm),
        const SizedBox(height: AppSpacing.sm),
        card(68),
        card(68),
      ],
    );
  }

  Widget _buildHeader({
    required String name,
    required String specialty,
    required double rate,
    required String avatarUrl,
    required double rating,
    required int reviews,
  }) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                AppAvatar(imageUrl: avatarUrl, name: name, size: 56, online: _isOnline),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                      const SizedBox(height: 2),
                      Text(specialty,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppBadge(label: '${_money(rate)}/min', color: AppColors.textSecondary),
                          if (reviews > 0) RatingBadge(rating.toStringAsFixed(1)),
                          if (reviews > 0) Text('($reviews)', style: AppText.caption),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _AvailabilityRow(
            online: _isOnline,
            busy: _isTogglingStatus,
            onChanged: _toggleOnlineStatus,
          ),
        ],
      ),
    );
  }

  Widget _buildStats({required double earnings, required int minutes}) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.success,
            label: 'Earnings',
            value: '₹${earnings.toStringAsFixed(2)}',
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _StatCard(
            icon: Icons.schedule_rounded,
            color: AppColors.info,
            label: 'Minutes',
            value: '$minutes',
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _StatCard(
            icon: Icons.people_alt_outlined,
            color: AppColors.primary,
            label: 'In queue',
            value: '${_waitingQueue.length}',
          ),
        ),
      ],
    );
  }

  Widget _buildActiveSession() {
    final session = _activeSession;
    if (session == null) {
      return AppCard(
        child: AppStateView(
          compact: true,
          icon: _isOnline ? Icons.mark_chat_read_outlined : Icons.cloud_off_rounded,
          color: _isOnline ? AppColors.success : AppColors.textTertiary,
          title: 'No active session',
          message: _isOnline
              ? 'You are available. New seekers will appear here.'
              : 'You are offline. Go online to receive consultation requests.',
          actionLabel: _isOnline ? null : 'Go online',
          onAction: _isOnline || _isTogglingStatus ? null : () => _toggleOnlineStatus(true),
        ),
      );
    }

    final seekerName = (session['user_name'] ?? 'Seeker').toString();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.45), width: 1.2),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: seekerName, size: 44, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(seekerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                    const SizedBox(height: 2),
                    Text(_activeLabel(session['started_at']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const AppBadge(label: 'LIVE', color: AppColors.success, icon: Icons.circle),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'End',
                  icon: Icons.call_end_rounded,
                  variant: AppButtonVariant.outline,
                  height: 46,
                  loading: _isActionBusy,
                  onPressed: _isActionBusy ? null : () => _advanceQueue(endingOnly: true),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: 'Open chat',
                  icon: Icons.chat_bubble_outline_rounded,
                  height: 46,
                  onPressed: _isActionBusy ? null : () => _openChat(session),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueue() {
    if (_waitingQueue.isEmpty) {
      return const AppCard(
        child: AppStateView(
          compact: true,
          icon: Icons.hourglass_empty_rounded,
          color: AppColors.textTertiary,
          title: 'No seekers waiting',
          message: 'This list refreshes automatically every few seconds.',
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < _waitingQueue.length; index++) ...[
            if (index > 0) const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
            _QueueRow(
              name: (_waitingQueue[index]['user_name'] ?? 'Seeker').toString(),
              position: _toInt(_waitingQueue[index]['queue_position'], index + 1),
              waited: _waitedLabel(_waitingQueue[index]['created_at']),
              isNext: index == 0,
              busy: _isActionBusy,
              onAccept: () => _advanceQueue(endingOnly: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayouts() {
    final payouts = _payouts;
    if (payouts == null) {
      if (_payoutsFailed) {
        return AppCard(
          child: AppStateView.error(
            compact: true,
            title: 'Could not load recent payouts',
            onAction: _loadPayouts,
          ),
        );
      }
      return AppCard(
        child: Column(
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              const Row(
                children: [
                  SkeletonBox(width: 38, height: 38, radius: 10),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: SkeletonBox(height: 14, radius: AppRadius.sm)),
                  SizedBox(width: AppSpacing.lg),
                  SkeletonBox(width: 56, height: 14, radius: AppRadius.sm),
                ],
              ),
            ],
          ],
        ),
      );
    }
    if (payouts.isEmpty) {
      return const AppCard(
        child: AppStateView(
          compact: true,
          icon: Icons.receipt_long_outlined,
          color: AppColors.success,
          title: 'No payouts yet',
          message: 'Completed consultations are credited here.',
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < payouts.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: AppSpacing.md, endIndent: AppSpacing.md),
            _PayoutRow(
              description: (payouts[i]['description'] ?? 'Consultation payout').toString(),
              date: _shortDate(payouts[i]['createdAt'] ?? payouts[i]['created_at']),
              amount: _toDouble(payouts[i]['amount']),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    if (!backendService.isPanditLoggedIn) {
      return _buildLoginRequired(context);
    }

    final Map<String, dynamic> pandit = backendService.currentPandit ?? const {};
    final String name = (pandit['full_name'] ?? 'Pandit Ji').toString();
    final String specialty = (pandit['specialty'] ?? 'Vedic Astrology').toString();
    final double rate = _toDouble(pandit['rate_per_min']);
    final double earnings = _toDouble(pandit['earnings_balance']);
    final int minutes = _toInt(pandit['total_minutes_consulted']);
    final String avatarUrl = (pandit['avatar_url'] ?? '').toString();
    final double rating = _toDouble(pandit['rating']);
    final int reviews = _toInt(pandit['total_reviews']);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Partner dashboard', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading || _isFetching ? null : () => _loadDashboardData(),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out of partner account',
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? _buildSkeleton()
          : _loadError != null
              ? Center(
                  child: SingleChildScrollView(
                    child: AppStateView.error(
                      title: 'Could not load dashboard',
                      message: _loadError,
                      onAction: _retryLoad,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadDashboardData(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
                    children: [
                      _buildHeader(
                        name: name,
                        specialty: specialty,
                        rate: rate,
                        avatarUrl: avatarUrl,
                        rating: rating,
                        reviews: reviews,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _buildStats(earnings: earnings, minutes: minutes),
                      const SectionHeader(
                        title: 'Active consultation',
                        padding: EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
                      ),
                      _buildActiveSession(),
                      SectionHeader(
                        title: 'Incoming requests',
                        subtitle:
                            _waitingQueue.isEmpty ? null : '${_waitingQueue.length} waiting · served in queue order',
                        padding: const EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
                      ),
                      _buildQueue(),
                      SectionHeader(
                        title: 'Recent payouts',
                        subtitle: 'Credits from completed consultations',
                        actionLabel: 'Refresh',
                        onAction: _loadPayouts,
                        padding: const EdgeInsets.fromLTRB(0, AppSpacing.xl, 0, AppSpacing.sm),
                      ),
                      _buildPayouts(),
                    ],
                  ),
                ),
    );
  }
}

// -----------------------------------------------------------------------------
// Private widgets
// -----------------------------------------------------------------------------

class _AvailabilityRow extends StatelessWidget {
  final bool online;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _AvailabilityRow({required this.online, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.success : AppColors.textTertiary;
    return Semantics(
      toggled: online,
      label:
          online ? 'Availability: online. Double tap to go offline' : 'Availability: offline. Double tap to go online',
      excludeSemantics: true,
      button: true,
      child: InkWell(
        onTap: busy ? null : () => onChanged(!online),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          decoration: BoxDecoration(
            color: online ? AppColors.successSoft : AppColors.surfaceMuted,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(online ? 'You are online' : 'You are offline',
                        style: AppText.bodyStrong.copyWith(color: online ? AppColors.success : AppColors.textPrimary)),
                    Text(
                      online ? 'Seekers can find you and join your queue' : 'You are hidden from seekers',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                Switch(
                  value: online,
                  activeTrackColor: AppColors.success,
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatCard({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppText.title.copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final String name;
  final int position;
  final String waited;
  final bool isNext;
  final bool busy;
  final VoidCallback onAccept;

  const _QueueRow({
    required this.name,
    required this.position,
    required this.waited,
    required this.isNext,
    required this.busy,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          AppAvatar(name: name, size: 42, color: isNext ? AppColors.primary : AppColors.cosmicLight),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text('#$position · $waited',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (isNext)
            AppButton(
              label: 'Accept',
              expand: false,
              height: 40,
              loading: busy,
              onPressed: busy ? null : onAccept,
            )
          else
            const AppBadge(label: 'In line', color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  final String description;
  final String? date;
  final double amount;

  const _PayoutRow({required this.description, required this.date, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.south_west_rounded, size: 18, color: AppColors.success),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                if (date != null) Text(date!, style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '+₹${amount.toStringAsFixed(2)}',
            style: AppText.bodyStrong.copyWith(color: AppColors.success),
          ),
        ],
      ),
    );
  }
}
