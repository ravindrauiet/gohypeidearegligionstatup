import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../services/backend_service.dart';
import '../widgets/forecast_widgets.dart';
import 'forecast_screen.dart' show AspectRow, MoonCard;
import 'kundli_view_screen.dart' show KundliEmptyState, showKundliProfilePicker;

// ============================================================================
// Life-area relevance (pure helpers, unit tested)
// ============================================================================

const Map<String, List<String>> _areaKeywords = {
  LifeArea.career: [
    'job', 'career', 'promotion', 'promoted', 'work', 'boss', 'office', 'business', 'interview', 'fired',
    'layoff', 'laid off', 'resign', 'startup', 'exam', 'hired', 'contract', 'appraisal', 'transfer', 'project',
  ],
  LifeArea.love: [
    'love', 'marriage', 'married', 'wedding', 'breakup', 'break up', 'broke up', 'divorce', 'partner',
    'girlfriend', 'boyfriend', 'wife', 'husband', 'relationship', 'engaged', 'engagement', 'crush', 'dating',
    'proposal', 'proposed', 'romance', 'cheated',
  ],
  LifeArea.money: [
    'money', 'loss', 'lost', 'debt', 'loan', 'salary', 'profit', 'investment', 'invest', 'stock', 'gain', 'bonus',
    'income', 'expense', 'fraud', 'theft', 'stolen', 'property', 'bought', 'sold', 'lottery', 'finance', 'bankrupt',
  ],
  LifeArea.health: [
    'health', 'ill', 'illness', 'sick', 'surgery', 'hospital', 'accident', 'injury', 'injured', 'disease',
    'fever', 'pain', 'covid', 'operation', 'pregnan', 'baby', 'diagnos', 'fracture',
  ],
  LifeArea.mind: [
    'stress', 'anxiety', 'anxious', 'depress', 'sad', 'panic', 'fear', 'lonely', 'confus', 'overthink',
    'burnout', 'angry', 'anger', 'grief', 'died', 'death', 'passed away', 'mental', 'insomnia', 'worry',
  ],
};

/// Life areas mentioned in a free-text note (simple keyword match).
Set<String> detectLifeAreas(String note) {
  final text = ' ${note.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), ' ')} ';
  final out = <String>{};
  _areaKeywords.forEach((area, words) {
    for (final w in words) {
      // Word-start match so "ill" does not fire on "will" / "still".
      if (RegExp('\\s${RegExp.escape(w)}').hasMatch(text)) {
        out.add(area);
        break;
      }
    }
  });
  return out;
}

const Map<String, Set<String>> _areaPlanets = {
  LifeArea.career: {'Saturn', 'Sun', 'Jupiter', 'Mercury', 'Mars', 'Rahu'},
  LifeArea.love: {'Venus', 'Moon', 'Jupiter', 'Mars', 'Rahu'},
  LifeArea.money: {'Jupiter', 'Venus', 'Mercury', 'Rahu'},
  LifeArea.health: {'Sun', 'Mars', 'Saturn', 'Moon', 'Ketu'},
  LifeArea.mind: {'Moon', 'Mercury', 'Rahu', 'Ketu', 'Saturn'},
};

const Map<String, Set<int>> _areaHouses = {
  LifeArea.career: {10, 6, 2, 11},
  LifeArea.love: {7, 5, 12},
  LifeArea.money: {2, 11, 8},
  LifeArea.health: {1, 6, 8, 12},
  LifeArea.mind: {4, 8, 12, 1},
};

const Map<String, String> _houseTopic = {
  LifeArea.career: 'work and status',
  LifeArea.love: 'partnership and romance',
  LifeArea.money: 'income and savings',
  LifeArea.health: 'body and vitality',
  LifeArea.mind: 'emotional peace',
};

/// Why a planet might plausibly relate to [area] on that date (empty = no link).
List<String> planetRelevance(String planet, int houseFromMoon, String effect, String area, AreaScore score) {
  final reasons = <String>[];
  if (score.reason.toLowerCase().contains(planet.toLowerCase())) {
    reasons.add('Named in your ${LifeArea.label(area).toLowerCase()} reading for that day');
  }
  if (houseFromMoon > 0 && (_areaHouses[area]?.contains(houseFromMoon) ?? false)) {
    reasons.add('${FC.ordinal(houseFromMoon)} from your Moon is a house of ${_houseTopic[area]}');
  }
  if ((_areaPlanets[area]?.contains(planet) ?? false) && effect != Effect.neutral) {
    reasons.add('$planet is a natural significator of ${LifeArea.label(area).toLowerCase()}');
  }
  return reasons;
}

bool dashaRelevant(String lord, String area) => _areaPlanets[area]?.contains(lord) ?? false;

// ============================================================================
// Screen
// ============================================================================

/// "Why did this happen?" — pick any date, describe what happened, and see the
/// dasha, slow transits, aspects and tara that were active.
/// Route arguments (optional): `{date: DateTime|'YYYY-MM-DD', note: String, familyId: int}`.
class DateExplorerScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialNote;
  final int? familyId;
  const DateExplorerScreen({super.key, this.initialDate, this.initialNote, this.familyId});

  factory DateExplorerScreen.fromArgs(Object? args) {
    if (args is! Map) return const DateExplorerScreen();
    final d = args['date'];
    return DateExplorerScreen(
      initialDate: d is DateTime ? dateOnly(d) : fDate(d),
      initialNote: fStrOrNull(args['note']),
      familyId: fIntOrNull(args['familyId']),
    );
  }

  @override
  State<DateExplorerScreen> createState() => _DateExplorerScreenState();
}

class _DateExplorerScreenState extends State<DateExplorerScreen> {
  static const _examples = ['Got a new job', 'Breakup', 'Money loss', 'Fell ill', 'Anxious phase', 'Got married'];

  late final BackendService _service;
  late final TextEditingController _note = TextEditingController(text: widget.initialNote ?? '');
  late DateTime _date = widget.initialDate ?? dateOnly(DateTime.now());
  int? _familyId;
  int? _observedSelection;

  DayForecast? _day;
  Set<String> _areas = {};
  String _askedNote = '';
  bool _loading = false;
  String? _error;
  bool _noKundli = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _service = Provider.of<BackendService>(context, listen: false);
    _observedSelection = activeFamilyId(_service);
    _familyId = widget.familyId ?? _observedSelection;
    _service.addListener(_onServiceChanged);
    if (widget.initialDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _explore();
      });
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _note.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    final id = activeFamilyId(_service);
    if (id == _observedSelection || !mounted) return;
    _observedSelection = id;
    setState(() {
      _familyId = id;
      _day = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'When did it happen?',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = dateOnly(picked));
  }

  Future<void> _explore() async {
    FocusScope.of(context).unfocus();
    final token = ++_token;
    final note = _note.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      _noKundli = false;
    });
    Map<String, dynamic>? raw;
    try {
      raw = await _service.fetchDayForecast(date: _date, familyId: _familyId);
    } catch (_) {
      raw = null;
    }
    if (!mounted || token != _token) return;
    DayForecast? parsed;
    if (raw != null) {
      try {
        parsed = DayForecast.fromJson(raw, fallbackDate: _date);
      } catch (_) {}
    }
    setState(() {
      _loading = false;
      if (parsed != null) {
        _day = parsed;
        _askedNote = note;
        _areas = detectLifeAreas(note);
      } else {
        _day = null;
        _noKundli = _service.lastErrorCode == 'NO_KUNDLI';
        _error = _service.lastError ?? 'Could not read this date. Please try again.';
      }
    });
  }

  String _question(DayForecast d) {
    final p = d.meta.profile;
    final who = p.isFamily && p.name.isNotEmpty ? 'This is about my ${p.relationship ?? 'family member'} ${p.name}. ' : '';
    final slow = d.transits
        .where((t) => t.isSlow)
        .map((t) => '${t.planet} in ${t.sign}${t.retrograde ? ' (R)' : ''}, ${FC.ordinal(t.houseFromMoon)} from Moon')
        .join('; ');
    final aspects = d.aspects.map((a) => '${a.transitPlanet} ${a.aspect} natal ${a.natalPlanet}').join('; ');
    return '$who${_askedNote.isNotEmpty ? 'On ${FC.date(d.date, 'd MMMM yyyy')} this happened: "$_askedNote". ' : 'I want to understand ${FC.date(d.date, 'd MMMM yyyy')}. '}'
        '${d.dasha.isEmpty ? '' : 'My dasha was ${d.dasha.chain}. '}'
        '${slow.isNotEmpty ? 'Slow transits: $slow. ' : ''}'
        '${aspects.isNotEmpty ? 'Aspects to my chart: $aspects. ' : ''}'
        'Moon was in ${d.moon.sign} (${d.moon.nakshatra}), ${d.moon.taraBala.name} Tara'
        '${d.moon.chandrashtama ? ', Chandrashtama' : ''}. '
        'Astrologically, why did this happen and what was it teaching me?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FC.bg,
      appBar: AppBar(
        backgroundColor: FC.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: const Text('Why did this happen?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Switch profile',
            icon: const Icon(Icons.people_alt_outlined, color: Colors.black),
            onPressed: () => showKundliProfilePicker(context),
          ),
        ],
      ),
      body: _noKundli && _day == null
          ? const KundliEmptyState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _inputCard(),
                  const SizedBox(height: 16),
                  if (_loading)
                    const ForecastSkeleton()
                  else if (_error != null)
                    ForecastError(message: _error!, onRetry: _explore)
                  else if (_day != null)
                    _results(_day!),
                ],
              ),
            ),
    );
  }

  Widget _inputCard() {
    return ForecastCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Decode a moment of your life',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.black)),
          const SizedBox(height: 4),
          Text(
            'Pick a date that mattered — a new job, a breakup, a loss, a win — and see what your chart was going through.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: 'Date: ${FC.date(_date, 'EEEE, d MMMM yyyy')}. Tap to change',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickDate,
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: FC.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_rounded, color: FC.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            Text(FC.date(_date, 'EEEE, d MMMM yyyy'),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_calendar_rounded, size: 18, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            minLines: 1,
            maxLength: 200,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _explore(),
            decoration: InputDecoration(
              labelText: 'What happened? (optional)',
              hintText: 'e.g. got a new job, breakup, fell ill',
              filled: true,
              fillColor: FC.bg,
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _examples)
                ActionChip(
                  label: Text(e),
                  onPressed: () => setState(() => _note.text = e),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
                  labelStyle: const TextStyle(fontSize: 12, color: Colors.black87),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _explore,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Explain this date'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _relevanceTag(List<String> reasons) {
    return Semantics(
      label: 'Likely related: ${reasons.join('. ')}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(color: FC.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.link_rounded, size: 15, color: Color(0xFFB45309)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Likely related · ${reasons.first}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7C2D12))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(DayForecast d) {
    final areas = _areas.toList()..sort((a, b) => LifeArea.all.indexOf(a).compareTo(LifeArea.all.indexOf(b)));
    List<String> reasonsFor(String planet, int house, String effect) => [
          for (final a in areas) ...planetRelevance(planet, house, effect, a, d.scores[a]),
        ];

    final slow = d.transits.where((t) => t.isSlow).toList();
    final ranked = [
      for (final t in slow) MapEntry(t, reasonsFor(t.planet, t.houseFromMoon, t.effect)),
    ]..sort((a, b) => b.value.length.compareTo(a.value.length));
    final dashaReasons = [
      for (final a in areas)
        for (final lord in d.dasha.lords)
          if (dashaRelevant(lord, a)) '$lord period colours ${LifeArea.label(a).toLowerCase()} matters',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.meta.accuracyNote != null) AccuracyBanner(d.meta.accuracyNote!),
        ForecastHero(
          eyebrow: '${d.weekday}, ${FC.date(d.date, 'd MMMM yyyy')}',
          summary: d.summary,
          aiGenerated: d.meta.isAi,
        ),
        if (_askedNote.isNotEmpty) ...[
          const SizedBox(height: 14),
          ForecastCard(
            title: 'What you told us',
            icon: Icons.edit_note_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"$_askedNote"', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                if (areas.isEmpty)
                  Text('We could not tell which life area this touches, so everything active that day is shown below.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700))
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in areas) Pill('Looks like ${LifeArea.label(a)}', color: FC.area(a), icon: FC.areaIcon(a)),
                  ]),
              ],
            ),
          ),
        ],
        for (final a in areas) ...[
          const SizedBox(height: 14),
          ForecastCard(
            title: 'Why your ${LifeArea.label(a).toLowerCase()} was affected',
            icon: FC.areaIcon(a),
            iconColor: FC.area(a),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: AnimatedBar(value: d.scores[a].score / 100, color: FC.area(a))),
                    const SizedBox(width: 10),
                    Text('${d.scores[a].score} · ${d.scores[a].label}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: FC.score(d.scores[a].score))),
                  ],
                ),
                if (d.scores[a].reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(d.scores[a].reason, style: TextStyle(fontSize: 13, height: 1.45, color: Colors.grey.shade900)),
                ],
              ],
            ),
          ),
        ],
        if (!d.dasha.isEmpty) ...[
          const SectionLabel('Your dasha at that time'),
          if (dashaReasons.isNotEmpty) _relevanceTag(dashaReasons),
          DashaCard(dasha: d.dasha),
        ],
        if (ranked.isNotEmpty) ...[
          const SectionLabel('Slow planets shaping that time'),
          for (final e in ranked) ...[
            if (e.value.isNotEmpty) _relevanceTag(e.value),
            TransitCard(transit: e.key, profile: d.meta.profile, initiallyExpanded: e.value.isNotEmpty),
          ],
        ],
        if (d.aspects.isNotEmpty) ...[
          const SectionLabel('Planets touching your birth chart'),
          ForecastCard(
            child: Column(children: [
              for (final a in d.aspects)
                Builder(builder: (context) {
                  final r = reasonsFor(a.transitPlanet, 0, a.effect);
                  return AspectRow(aspect: a, badge: r.isEmpty ? null : const Pill('Likely related', color: FC.accent));
                }),
            ]),
          ),
        ],
        const SectionLabel('Your Moon & star that day'),
        MoonCard(moon: d.moon),
        if (d.events.isNotEmpty) ...[
          const SectionLabel('In the sky that day'),
          ForecastCard(child: Column(children: [for (final e in d.events) EventTile(event: e)])),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => askAstrologer(context, _question(d), field: 'Why did this happen'),
            icon: const Icon(Icons.forum_rounded, size: 18),
            label: const Text('Ask the AI astrologer why', maxLines: 1, overflow: TextOverflow.ellipsis),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Astrology shows tendencies and timing, not fate. Use it to understand and prepare, not to blame yourself.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.4),
        ),
      ],
    );
  }
}
