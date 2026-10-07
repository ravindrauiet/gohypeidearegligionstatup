import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

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

  Widget _buildMessageState({required IconData icon, required String text, bool showRetry = false}) {
    // Wrapped in a scrollable so pull-to-refresh also works on empty states.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  if (showRetry) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      label: const Text('Retry', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE83D66)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({String label, Color color}) _statusStyle(String? status) {
    switch (status) {
      case 'active':
        return (label: 'In Progress', color: const Color(0xFF2563EB));
      case 'waiting':
        return (label: 'Waiting', color: const Color(0xFFD97706));
      case 'cancelled':
        return (label: 'Cancelled', color: Colors.grey);
      default:
        return (label: 'Completed', color: const Color(0xFF059669));
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFFFF7ED),
                foregroundImage: avatarUrl.startsWith('http') ? NetworkImage(avatarUrl) : null,
                onForegroundImageError: avatarUrl.startsWith('http') ? (_, __) {} : null,
                child: const Icon(Icons.person_rounded, color: Color(0xFFFB9548)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['pandit_name'] ?? 'Pandit').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (item['specialty'] != null)
                      Text(
                        item['specialty'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFFD95D39), fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status.label, style: TextStyle(color: status.color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              if (when.isNotEmpty) Text(when, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (rate > 0) Text('₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}/min', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (durationMins != null)
                Text(
                  '$durationMins min${rate > 0 ? ' · Est. ₹${(durationMins * rate).toStringAsFixed(2)}' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionCard(Map<String, dynamic> p) {
    final rows = <Widget>[];
    void addRow(IconData icon, String label, dynamic value, {bool bold = false}) {
      final text = (value ?? '').toString().trim();
      if (text.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFFFD700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label: $text',
                style: TextStyle(
                  color: bold ? Colors.white : Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ));
    }

    addRow(Icons.diamond_rounded, 'Gemstone', p['gemstone'], bold: true);
    addRow(Icons.self_improvement_rounded, 'Mantra', p['mantra']);
    addRow(Icons.spa_rounded, 'Ritual', p['remedy']);

    final date = _toDate(p['created_at']);
    final byline = [
      if ((p['pandit_name'] ?? '').toString().isNotEmpty) 'Prescribed by ${p['pandit_name']}',
      if (date != null) DateFormat('d MMMM yyyy').format(date),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFD700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('PRESCRIBED VEDIC REMEDY',
                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              ),
            ],
          ),
          ...rows,
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No remedy details recorded.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          if (byline.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(byline, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _buildTab({
    required List<Map<String, dynamic>> items,
    required Widget Function(Map<String, dynamic>) builder,
    required IconData emptyIcon,
    required String emptyText,
  }) {
    return RefreshIndicator(
      color: const Color(0xFFE83D66),
      onRefresh: _loadHistory,
      child: _hasError && items.isEmpty
          ? _buildMessageState(
              icon: Icons.cloud_off_rounded,
              text: 'Could not load your consultation history.\nPlease check your connection.',
              showRetry: true,
            )
          : items.isEmpty
              ? _buildMessageState(icon: emptyIcon, text: emptyText)
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) => builder(items[index]),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
            'Consultations & Remedies',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          bottom: TabBar(
            labelColor: const Color(0xFFE83D66),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFFE83D66),
            tabs: [
              Tab(text: 'Consultations${_isLoading ? '' : ' (${_history.length})'}'),
              Tab(text: 'Remedies${_isLoading ? '' : ' (${_prescriptions.length})'}'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)))
            : TabBarView(
                children: [
                  _buildTab(
                    items: _history,
                    builder: _buildHistoryCard,
                    emptyIcon: Icons.forum_outlined,
                    emptyText: 'No consultations yet.\nConnect with a Pandit from the Chat tab.',
                  ),
                  _buildTab(
                    items: _prescriptions,
                    builder: _buildPrescriptionCard,
                    emptyIcon: Icons.spa_outlined,
                    emptyText: 'No remedies prescribed yet.\nRemedies your Pandit prescribes will appear here.',
                  ),
                ],
              ),
      ),
    );
  }
}
