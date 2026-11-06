import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/trust_service.dart';
import '../../widgets/ui/app_ui.dart';

/// Notes family members left on my family links (push type `family_note`).
class FamilyNotesScreen extends StatefulWidget {
  final TrustService? service;
  const FamilyNotesScreen({super.key, this.service});

  @override
  State<FamilyNotesScreen> createState() => _FamilyNotesScreenState();
}

class _FamilyNotesScreenState extends State<FamilyNotesScreen> {
  late final TrustService _service = widget.service ?? TrustService(context.read<BackendService>());
  List<FamilyNote>? _notes;
  bool _loading = true;
  String? _error;

  bool get _loggedIn => context.read<BackendService>().isAuthenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (!_loggedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final n = await _service.familyNotes();
      if (!mounted) return;
      setState(() {
        _notes = n;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = TrustService.errorText(e);
      });
    }
  }

  Future<void> _delete(FamilyNote n) async {
    final before = _notes;
    setState(() => _notes = _notes?.where((x) => x.id != n.id).toList());
    try {
      await _service.deleteFamilyNote(n.id);
      if (mounted) showAppSnack(context, 'Note deleted');
    } catch (e) {
      if (!mounted) return;
      setState(() => _notes = before);
      showAppSnack(context, TrustService.errorText(e), error: true);
    }
  }

  static IconData _icon(String relation) => switch (relation) {
        'Mother' => Icons.face_3_rounded,
        'Father' => Icons.face_6_rounded,
        'Sibling' => Icons.people_rounded,
        _ => Icons.person_rounded,
      };

  Widget _tile(FamilyNote n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: ValueKey('family-note-${n.id}'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, 4, AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primarySoft,
              child: Icon(_icon(n.relation), color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n.name} · ${n.relation}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subtitle),
                Text(
                  [
                    if (n.about != null) 'About ${n.about}',
                    if (n.createdAt != null) DateFormat('d MMM, h:mm a').format(n.createdAt!),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textTertiary),
              onPressed: () => _delete(n),
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text(n.message, style: AppText.body.copyWith(color: AppColors.textPrimary)),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (!_loggedIn) {
      return Center(
        child: AppStateView(
          icon: Icons.lock_person_rounded,
          title: 'Log in to see family notes',
          actionLabel: 'Log in',
          onAction: () => Navigator.pushNamed(context, '/login'),
        ),
      );
    }
    final notes = _notes;
    if (notes == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(child: AppStateView.error(message: _error, onAction: _load));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: notes.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
              AppStateView(
                icon: Icons.mark_chat_unread_outlined,
                title: 'No notes yet',
                message: 'When your family opens a link you shared and leaves a note, it shows up here.',
              ),
            ])
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
              children: notes.map(_tile).toList(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Family notes')),
      body: _body(),
    );
  }
}
