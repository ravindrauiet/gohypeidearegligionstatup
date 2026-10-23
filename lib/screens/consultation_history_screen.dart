import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';
import '../widgets/ui/app_ui.dart';

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

DateTime? _toDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String _formatDate(dynamic v) {
  final d = _toDate(v);
  return d == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(d);
}

class ConsultationHistoryScreen extends StatefulWidget {
  const ConsultationHistoryScreen({super.key});

  @override
  State<ConsultationHistoryScreen> createState() => _ConsultationHistoryScreenState();
}

class _ConsultationHistoryScreenState extends State<ConsultationHistoryScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _prescriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadHistory();
    });
  }

  List<Map<String, dynamic>> _asMapList(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  Future<void> _loadHistory() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    Map<String, dynamic>? data;
    try {
      data = await backendService.fetchConsultationHistory();
    } catch (_) {
      data = null;
    }

    if (!mounted) return;
    setState(() {
      if (data != null) {
        _history = _asMapList(data['history']);
        _prescriptions = _asMapList(data['prescriptions']);
        _hasError = false;
      } else {
        _hasError = true;
      }
      _isLoading = false;
    });
    if (data == null && (_history.isNotEmpty || _prescriptions.isNotEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not refresh history. Showing last loaded data.')),
      );
    }
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _loadHistory();
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    String? message,
    bool showRetry = false,
  }) {
    // Wrapped in a scrollable so pull-to-refresh also works on empty states.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: showRetry
                ? AppStateView.error(title: title, message: message, onAction: _retry)
                : AppStateView(icon: icon, title: title, message: message),
          ),
        ),
      ),
    );
  }

  ({String label, Color color}) _statusStyle(String? status) {
    switch (status) {
      case 'active':
        return (label: 'In progress', color: AppColors.info);
      case 'waiting':
        return (label: 'Waiting', color: AppColors.warning);
      case 'cancelled':
        return (label: 'Cancelled', color: AppColors.textTertiary);
      default:
        return (label: 'Completed', color: AppColors.success);
    }
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final status = _statusStyle(item['status']?.toString());
    final rate = _toDouble(item['rate_per_min']);
    final start = _toDate(item['started_at']);
    final end = _toDate(item['ended_at']);
    final int? durationMins = (start != null && end != null && end.isAfter(start))
        ? (end.difference(start).inSeconds / 60).ceil()
        : null;
    final avatarUrl = (item['avatar_url'] ?? '').toString();
    final when = _formatDate(item['started_at'] ?? item['created_at']);
    final name = (item['pandit_name'] ?? 'Pandit').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(imageUrl: avatarUrl.startsWith('http') ? avatarUrl : null, name: name, size: 44),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                      if (item['specialty'] != null)
                        Text(
                          item['specialty'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppBadge(label: status.label, color: status.color),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (when.isNotEmpty) Text(when, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
                      if (rate > 0)
                        Text('₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}/min', style: AppText.caption),
                    ],
                  ),
                ),
                if (durationMins != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$durationMins min', style: AppText.bodyStrong),
                      if (rate > 0)
                        Text('Est. ₹${(durationMins * rate).toStringAsFixed(2)}', style: AppText.caption),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrescriptionCard(Map<String, dynamic> p) {
    final rows = <Widget>[];
    void addRow(IconData icon, String label, dynamic value) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.caption),
                  const SizedBox(height: 1),
                  Text(text, style: AppText.bodyStrong),
                ],
              ),
            ),
          ],
        ),
      ));
    }

    addRow(Icons.diamond_outlined, 'Gemstone', p['gemstone']);
    addRow(Icons.self_improvement_rounded, 'Mantra', p['mantra']);
    addRow(Icons.spa_outlined, 'Ritual', p['remedy']);

    final date = _toDate(p['created_at']);
    final byline = [
      if ((p['pandit_name'] ?? '').toString().isNotEmpty) 'Prescribed by ${p['pandit_name']}',
      if (date != null) DateFormat('d MMMM yyyy').format(date),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.gold, size: 20),
                const SizedBox(width: AppSpacing.xs),
                const Expanded(child: Text('Prescribed remedy', style: AppText.subtitle)),
                if (date != null) Text(DateFormat('d MMM').format(date), style: AppText.caption),
              ],
            ),
            ...rows,
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xs),
                child: Text('No remedy details recorded.', style: AppText.body),
              ),
            if (byline.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(byline, style: AppText.caption),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTab({
    required List<Map<String, dynamic>> items,
    required Widget Function(Map<String, dynamic>) builder,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyText,
  }) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadHistory,
      child: _hasError && items.isEmpty
          ? _buildMessageState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load your history',
              message: 'Please check your connection and try again.',
              showRetry: true,
            )
          : items.isEmpty
              ? _buildMessageState(icon: emptyIcon, title: emptyTitle, message: emptyText)
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.page),
                  itemCount: items.length,
                  itemBuilder: (context, index) => builder(items[index]),
                ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.page),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, __) => const SkeletonBox(height: 112, radius: AppRadius.lg),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text('Consultations & remedies', overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Consultations${_isLoading ? '' : ' (${_history.length})'}'),
              Tab(text: 'Remedies${_isLoading ? '' : ' (${_prescriptions.length})'}'),
            ],
          ),
        ),
        body: _isLoading
            ? _buildSkeleton()
            : TabBarView(
                children: [
                  _buildTab(
                    items: _history,
                    builder: _buildHistoryCard,
                    emptyIcon: Icons.forum_outlined,
                    emptyTitle: 'No consultations yet',
                    emptyText: 'Live pandit chats you take from the Ask Astro tab will appear here.',
                  ),
                  _buildTab(
                    items: _prescriptions,
                    builder: _buildPrescriptionCard,
                    emptyIcon: Icons.spa_outlined,
                    emptyTitle: 'No remedies yet',
                    emptyText: 'Remedies your pandit prescribes during a session will be saved here.',
                  ),
                ],
              ),
      ),
    );
  }
}
