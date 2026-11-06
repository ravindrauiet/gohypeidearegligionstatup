import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../../services/trust_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';
import 'biodata_pdf.dart';
import 'verification_screen.dart' show syncBuddyTrust;

/// Shares the generated PDF (WhatsApp etc.). Tests replace it.
Future<void> Function(Uint8List bytes, String fileName) biodataPdfShare = (bytes, name) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
    fileNameOverrides: [name],
    subject: 'Biodata',
  ));
};

/// "Biodata details": optional life-partner details in one grouped form,
/// plus "Download biodata" (an A4 PDF made on the device).
class BiodataEditScreen extends StatefulWidget {
  final TrustService? service;
  const BiodataEditScreen({super.key, this.service});

  @override
  State<BiodataEditScreen> createState() => _BiodataEditScreenState();
}

class _BiodataEditScreenState extends State<BiodataEditScreen> {
  late final TrustService _service = widget.service ?? TrustService(context.read<BackendService>());
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {
    for (final k in ['heightCm', ...BiodataOptions.maxLength.keys]) k: TextEditingController(),
  };
  String? _income;
  String? _diet;
  bool _loading = true;
  String? _error;
  String? _errorCode;
  bool _saving = false;
  bool _dirty = false;

  bool get _loggedIn => context.read<BackendService>().isAuthenticated;

  @override
  void initState() {
    super.initState();
    for (final c in _c.values) {
      c.addListener(_markDirty);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && !_loading) setState(() => _dirty = true);
  }

  void _fill(Biodata b) {
    final m = b.toJson();
    for (final e in _c.entries) {
      e.value.text = m[e.key]?.toString() ?? '';
    }
    _income = b.incomeRange;
    _diet = b.diet;
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
      _errorCode = null;
    });
    try {
      final b = await _service.loadBiodata();
      if (!mounted) return;
      _fill(b);
      setState(() {
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = TrustService.errorText(e);
        _errorCode = e is TrustException ? e.code : null;
      });
    }
  }

  String? _t(String k) {
    final s = _c[k]!.text.trim();
    return s.isEmpty ? null : s;
  }

  Biodata get _current => Biodata(
        heightCm: int.tryParse(_c['heightCm']!.text.trim()),
        education: _t('education'),
        profession: _t('profession'),
        incomeRange: _income,
        diet: _diet,
        community: _t('community'),
        gotra: _t('gotra'),
        fatherOccupation: _t('fatherOccupation'),
        motherOccupation: _t('motherOccupation'),
        siblings: _t('siblings'),
        aboutFamily: _t('aboutFamily'),
        partnerExpectations: _t('partnerExpectations'),
      );

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final saved = await _service.saveBiodata(_current);
      if (!mounted) return;
      _fill(saved);
      setState(() {
        _saving = false;
        _dirty = false;
      });
      syncBuddyTrust(context, biodata: saved);
      showAppSnack(context, 'Biodata saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, TrustService.errorText(e), error: true);
    }
  }

  Future<void> _download() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final backend = context.read<BackendService>();
    BuddyStatus? st;
    try {
      st = context.read<BuddyService>().status;
    } catch (_) {}
    final p = st?.profile;
    await showAppSheet<void>(
      context,
      builder: (_) => BiodataDownloadSheet(
        biodata: _current,
        name: p?.displayName ?? '${backend.user?['fullName'] ?? 'Biodata'}',
        age: st?.age,
        gender: p?.gender,
        city: p?.city,
        languages: p?.languages ?? const [],
        kundli: backend.kundliData,
      ),
    );
  }

  // -------------------------------------------------------------------- UI

  Widget _group(String title, IconData icon, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppText.subtitle)),
            ]),
            const SizedBox(height: AppSpacing.xs),
            ...children,
          ]),
        ),
      );

  Widget _text(String key, String label, {String? hint, int lines = 1, TextInputAction? action}) {
    final max = BiodataOptions.maxLength[key]!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: TextFormField(
        key: ValueKey('biodata-$key'),
        controller: _c[key],
        maxLength: max,
        maxLines: lines,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: lines > 1 ? TextInputAction.newline : (action ?? TextInputAction.next),
        decoration: InputDecoration(labelText: label, hintText: hint, counterText: lines > 1 ? null : ''),
        validator: (v) => (v ?? '').trim().length > max ? 'At most $max characters' : null,
      ),
    );
  }

  Widget _buildForm() {
    final h = int.tryParse(_c['heightCm']!.text.trim());
    return Form(
      key: _form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const BuddyNote(
            icon: Icons.info_outline_rounded,
            text: 'Everything here is optional. Accepted buddies and family links see it; '
                'Discover cards only show your education and profession.',
          ),
          const SizedBox(height: AppSpacing.md),
          _group('Personal', Icons.person_outline_rounded, [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: TextFormField(
                key: const ValueKey('biodata-heightCm'),
                controller: _c['heightCm'],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Height (cm)',
                  helperText: h != null && h >= BiodataOptions.heightMin && h <= BiodataOptions.heightMax
                      ? BiodataOptions.heightLabel(h)
                      : 'e.g. 165',
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null;
                  final n = int.tryParse(s);
                  if (n == null || n < BiodataOptions.heightMin || n > BiodataOptions.heightMax) {
                    return 'Between ${BiodataOptions.heightMin} and ${BiodataOptions.heightMax} cm';
                  }
                  return null;
                },
              ),
            ),
            _text('education', 'Education', hint: 'e.g. B.Tech, MBA'),
            _text('profession', 'Profession', hint: 'e.g. Software engineer'),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: DropdownButtonFormField<String>(
                key: const ValueKey('biodata-income'),
                initialValue: _income,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Annual income'),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('Not shown')),
                  for (final e in BiodataOptions.incomeRanges.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _income = v;
                  _dirty = true;
                }),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Diet', style: AppText.caption),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in BiodataOptions.diets.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _diet == e.key,
                  onSelected: (sel) => setState(() {
                    _diet = sel ? e.key : null;
                    _dirty = true;
                  }),
                ),
            ]),
            _text('community', 'Religion / community'),
            _text('gotra', 'Gotra'),
          ]),
          _group('Family', Icons.family_restroom_rounded, [
            _text('fatherOccupation', "Father's occupation"),
            _text('motherOccupation', "Mother's occupation"),
            _text('siblings', 'Siblings', hint: 'e.g. 1 elder brother (married)'),
            _text('aboutFamily', 'About the family', lines: 4),
          ]),
          _group('Partner expectations', Icons.favorite_border_rounded, [
            _text('partnerExpectations', 'What are you looking for?', lines: 4),
          ]),
          AppButton(
            key: const ValueKey('save-biodata'),
            label: 'Save biodata',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('download-biodata'),
            label: 'Download biodata (PDF)',
            icon: Icons.picture_as_pdf_outlined,
            variant: AppButtonVariant.outline,
            onPressed: _download,
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
          title: 'Log in to add your biodata',
          actionLabel: 'Log in',
          onAction: () => Navigator.pushNamed(context, '/login'),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      if (_errorCode == 'NO_PROFILE') {
        return const Center(
          child: AppStateView(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Create your buddy profile first',
            message: 'Biodata is part of your buddy profile. Set it up in Find your buddy.',
          ),
        );
      }
      return Center(child: AppStateView.error(message: _error, onAction: _load));
    }
    return _buildForm();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your biodata changes are not saved yet.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Biodata details')),
        body: _body(),
      ),
    );
  }
}

/// Options for the PDF: include birth details (default on) and an optional
/// contact line that is kept only on this device.
class BiodataDownloadSheet extends StatefulWidget {
  final Biodata biodata;
  final String name;
  final int? age;
  final String? gender;
  final String? city;
  final List<String> languages;
  final Map<String, dynamic>? kundli;

  const BiodataDownloadSheet({
    super.key,
    required this.biodata,
    required this.name,
    this.age,
    this.gender,
    this.city,
    this.languages = const [],
    this.kundli,
  });

  static const contactPrefKey = 'biodata_pdf_contact';

  @override
  State<BiodataDownloadSheet> createState() => _BiodataDownloadSheetState();
}

class _BiodataDownloadSheetState extends State<BiodataDownloadSheet> {
  bool _birth = true;
  final _contact = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(BiodataDownloadSheet.contactPrefKey);
      if (mounted && v != null && _contact.text.isEmpty) _contact.text = v;
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final contact = _contact.text.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      contact.isEmpty
          ? await prefs.remove(BiodataDownloadSheet.contactPrefKey)
          : await prefs.setString(BiodataDownloadSheet.contactPrefKey, contact);
    } catch (_) {}
    try {
      final k = BiodataPdfData.kundliBasics(widget.kundli);
      final g = widget.gender;
      final bytes = await buildBiodataPdf(BiodataPdfData(
        name: widget.name,
        gender: g == null ? null : '${g[0].toUpperCase()}${g.substring(1)}',
        age: widget.age,
        city: widget.city,
        languages: widget.languages,
        biodata: widget.biodata,
        moonSign: k.moonSign,
        lagna: k.lagna,
        nakshatra: k.nakshatra,
        manglik: k.manglik,
        includeBirthDetails: _birth,
        birthDate: k.date,
        birthTime: k.time,
        birthPlace: k.place,
        contact: contact.isEmpty ? null : contact,
      ));
      final safe = widget.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
      await biodataPdfShare(bytes, 'Biodata_${safe.isEmpty ? 'CosmicGuide' : safe}.pdf');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not create the PDF. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Download biodata', style: AppText.title),
        const SizedBox(height: 4),
        const Text('A clean A4 PDF made on your phone. Share it on WhatsApp or print it.', style: AppText.body),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          key: const ValueKey('include-birth'),
          contentPadding: EdgeInsets.zero,
          value: _birth,
          onChanged: (v) => setState(() => _birth = v),
          title: const Text('Include birth details', style: AppText.bodyStrong),
          subtitle: const Text('Date, time and place of birth (only in this PDF)'),
        ),
        TextField(
          key: const ValueKey('biodata-contact'),
          controller: _contact,
          maxLength: 80,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: 'Contact for biodata (optional)',
            hintText: 'e.g. Father: 98xxxxxx10',
            helperText: 'Printed only in the PDF. Never sent to CosmicGuide.',
          ),
        ),
        if (_error != null) Text(_error!, style: AppText.body.copyWith(color: AppColors.danger)),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const ValueKey('make-pdf'),
          label: 'Create and share PDF',
          icon: Icons.picture_as_pdf_rounded,
          loading: _busy,
          onPressed: _busy ? null : _go,
        ),
      ]),
    );
  }
}
