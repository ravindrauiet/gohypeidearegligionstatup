import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/forecast.dart';
import '../services/backend_service.dart';
import '../widgets/forecast_widgets.dart';
import '../widgets/ui/app_ui.dart';
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        titleSpacing: 0,
        title: const Text('Why did this happen?', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Switch profile',
            icon: const Icon(Icons.people_alt_outlined),
            onPressed: () => showKundliProfilePicker(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _noKundli && _day == null
          ? const KundliEmptyState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xxl),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _inputCard(),
                  const SizedBox(height: AppSpacing.md),
                  if (_loading)
                    const ForecastSkeleton()
                  else if (_error != null)
                    ForecastError(message: _error!, onRetry: _explore)
                  else if (_day != null)
                    _results(_day!)
                  else
                    const _HowItWorks(),
                ],
              ),
            ),
    );
  }

  Widget _inputCard() {
    final note = _note.text.trim().toLowerCase();
    return ForecastCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pick a date and ask why', style: AppText.title),
          const SizedBox(height: 4),
          Text(
            'Choose a day that mattered (a new job, a breakup, a loss, a win) and see what your chart was going through.',
            style: AppText.body.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Date', style: AppText.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Semantics(
            button: true,
            label: 'Date: ${FC.date(_date, 'EEEE, d MMMM yyyy')}. Tap to change',
            excludeSemantics: true,
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.input,
                side: const BorderSide(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              child: Text(FC.date(_date, 'MMM'),
                                  style: const TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                            ),
                            FittedBox(
                              child: Text('${_date.day}',
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primaryDark, height: 1.1)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(FC.date(_date, 'EEEE, d MMMM yyyy'),
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                            const Text('Tap to change', style: AppText.caption),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_calendar_rounded, size: 20, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _note,
            maxLines: 2,
            minLines: 1,
            maxLength: 200,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _explore(),
            decoration: const InputDecoration(
              labelText: 'What happened? (optional)',
              hintText: 'e.g. got a new job, breakup, fell ill',
              prefixIcon: Icon(Icons.edit_note_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _examples)
                AppFilterChip(
                  label: e,
                  selected: note == e.toLowerCase(),
                  onTap: () => setState(() => _note.text = e),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Explain this date',
            icon: Icons.auto_awesome_rounded,
            loading: _loading,
            onPressed: _loading ? null : _explore,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.link_rounded, size: 16, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Likely related · ${reasons.first}',
                    style: AppText.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
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
          eyebrow: '${d.weekday.isEmpty ? FC.date(d.date, 'EEEE') : d.weekday}, ${FC.date(d.date, 'd MMMM yyyy')}',
          summary: d.summary,
          aiGenerated: d.meta.isAi,
        ),
        if (_askedNote.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ForecastCard(
            title: 'What you told us',
            icon: Icons.edit_note_rounded,
            iconColor: AppColors.cosmicLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"$_askedNote"', style: AppText.bodyStrong.copyWith(fontStyle: FontStyle.italic)),
                const SizedBox(height: 8),
                if (areas.isEmpty)
                  Text('We could not tell which life area this touches, so everything active that day is shown below.',
                      style: AppText.caption.copyWith(color: AppColors.textSecondary))
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in areas) Pill('Looks like ${LifeArea.label(a)}', color: FC.area(a), icon: FC.areaIcon(a)),
                  ]),
              ],
            ),
          ),
        ],
        for (final a in areas) ...[
          const SizedBox(height: AppSpacing.sm),
          ForecastCard(
            title: 'Why your ${LifeArea.label(a).toLowerCase()} was affected',
            icon: FC.areaIcon(a),
            iconColor: FC.area(a),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: AnimatedBar(value: d.scores[a].score / 100, color: FC.score(d.scores[a].score), height: 6)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text('${d.scores[a].score} · ${d.scores[a].label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: FC.score(d.scores[a].score))),
                    ),
                  ],
                ),
                if (d.scores[a].reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(d.scores[a].reason, style: AppText.body.copyWith(color: AppColors.textPrimary)),
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
          const SectionLabel('Slow planets shaping that time', subtitle: 'The most relevant ones are opened for you'),
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
                  return AspectRow(
                      aspect: a, badge: r.isEmpty ? null : const Pill('Likely related', color: AppColors.primaryDark));
                }),
            ]),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        WhyExpander(
          title: 'More about that day',
          subtitle: 'Your Moon, star and what was in the sky',
          icon: Icons.nightlight_round,
          builder: () => [
            const SectionLabel('Your Moon & star that day'),
            MoonCard(moon: d.moon),
            if (d.events.isNotEmpty) ...[
              const SectionLabel('In the sky that day'),
              ForecastCard(child: Column(children: [for (final e in d.events) EventTile(event: e)])),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: 'Ask the AI astrologer why',
          icon: Icons.auto_awesome_rounded,
          onPressed: () => askAstrologer(context, _question(d), field: 'Why did this happen'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Astrology shows tendencies and timing, not fate. Use it to understand and prepare, not to blame yourself.',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(height: 1.45),
        ),
      ],
    );
  }
}

/// Shown before the first search: three short steps.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return const ForecastCard(
      title: 'How it works',
      icon: Icons.lightbulb_outline_rounded,
      iconColor: AppColors.cosmicLight,
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 6),
      child: Column(
        children: [
          ForecastIconRow(
            icon: Icons.event_rounded,
            color: AppColors.primary,
            title: 'Pick the date',
            detail: 'Any day from your past, or one coming up.',
          ),
          ForecastIconRow(
            icon: Icons.edit_note_rounded,
            color: AppColors.primary,
            title: 'Say what happened',
            detail: 'Optional, but it helps us point at the right life area.',
          ),
          ForecastIconRow(
            icon: Icons.auto_awesome_rounded,
            color: AppColors.primary,
            title: 'See why',
            detail: 'Your dasha, slow planets and Moon that day, explained simply.',
          ),
        ],
      ),
    );
  }
}
