import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend_service.dart';
import '../../services/buddy_service.dart';
import '../../widgets/buddy/buddy_ui.dart';
import '../../widgets/ui/app_ui.dart';
import '../legal/community_guidelines_screen.dart';
import 'buddy_links.dart';

enum _Step { intents, about, interest, bio, languages, location, pledge, done }

const _languages = [
  'Hindi', 'English', 'Bengali', 'Marathi', 'Gujarati', 'Punjabi', 'Tamil', 'Telugu', 'Kannada', //
  'Malayalam', 'Odia', 'Assamese', 'Maithili', 'Bhojpuri', 'Nepali', 'Urdu', 'Sanskrit',
];

const _bioPrompts = [
  'A perfect Sunday for me is…',
  'The temple I keep going back to is…',
  "I'm happiest when…",
  'Something I want to learn this year…',
  'My family would describe me as…',
  'A dream trip on my list…',
];

/// One question per screen: build (or edit) the buddy profile.
/// Pops with `true` once the profile is saved.
class BuddyOnboardingScreen extends StatefulWidget {
  final BuddyProfile? initial;
  const BuddyOnboardingScreen({super.key, this.initial});

  @override
  State<BuddyOnboardingScreen> createState() => _BuddyOnboardingScreenState();
}

class _BuddyOnboardingScreenState extends State<BuddyOnboardingScreen> {
  final Set<String> _intents = {};
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _city = TextEditingController();
  String? _gender;
  String _interestedIn = 'any';
  final Set<String> _langs = {};
  bool _showNearby = false;
  final Set<int> _pledges = {};

  int _index = 0;
  bool _forward = true;
  bool _saving = false;
  bool _locating = false;
  String? _error;
  String? _locationNote;
  bool _saved = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    final backend = context.read<BackendService>();
    if (p != null) {
      _intents.addAll(p.intents);
      _name.text = p.displayName;
      _bio.text = p.bio;
      _city.text = p.city ?? '';
      _gender = p.gender?.toLowerCase();
      _interestedIn = p.interestedIn;
      _langs.addAll(p.languages);
      _showNearby = p.showNearby;
      _pledges.addAll([0, 1, 2]);
    } else {
      final full =
          backend.user?['fullName']?.toString() ?? backend.kundliData?['birthDetails']?['fullName']?.toString() ?? '';
      _name.text = full.trim().split(RegExp(r'\s+')).first;
      final g = backend.user?['gender']?.toString().toLowerCase() ?? '';
      if (g == 'male' || g == 'female') _gender = g;
      _langs.addAll(['Hindi', 'English']);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  List<_Step> get _steps => [
        _Step.intents,
        _Step.about,
        if (_intents.contains(BuddyIntent.lifePartner)) _Step.interest,
        _Step.bio,
        _Step.languages,
        _Step.location,
        _Step.pledge,
        if (!_editing) _Step.done,
      ];

  _Step get _step => _steps[_index.clamp(0, _steps.length - 1)];

  /// Steps that count towards progress (the "done" screen doesn't).
  int get _questionCount => _steps.where((s) => s != _Step.done).length;

  String? _validate(_Step s) => switch (s) {
        _Step.intents => _intents.isEmpty ? 'Pick at least one' : null,
        _Step.about => _name.text.trim().length < 2
            ? 'Please enter the name buddies will see'
            : (_gender == null ? 'Please choose your gender' : null),
        _Step.bio => _bio.text.trim().length < 20 ? 'Write at least a line or two (20+ characters)' : null,
        _Step.languages => _langs.isEmpty ? 'Pick at least one language' : null,
        _Step.location => _city.text.trim().isEmpty ? 'Which city do you live in?' : null,
        _Step.pledge => _pledges.length < 3 ? 'Please agree to all three to continue' : null,
        _ => null,
      };

  Future<void> _next() async {
    final err = _validate(_step);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    FocusScope.of(context).unfocus();
    if (_step == _Step.pledge) {
      await _save();
      return;
    }
    if (_step == _Step.done) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _error = null;
      _forward = true;
      _index++;
    });
  }

  void _back() {
    if (_saving) return;
    if (_index == 0 || _step == _Step.done) {
      Navigator.pop(context, _saved);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _forward = false;
      _index--;
    });
  }

  Future<void> _save() async {
    final service = context.read<BuddyService>();
    setState(() {
      _saving = true;
      _error = null;
    });
    final wantsLife = _intents.contains(BuddyIntent.lifePartner);
    try {
      await service.saveProfile(BuddyProfile(
        displayName: _name.text.trim(),
        bio: _bio.text.trim(),
        intents: BuddyIntent.all.where(_intents.contains).toList(),
        gender: _gender,
        interestedIn: wantsLife ? _interestedIn : 'any',
        city: _city.text.trim(),
        languages: _languages.where(_langs.contains).toList(),
        photoUrl: widget.initial?.photoUrl,
        showNearby: _showNearby,
        isActive: true,
      ));
      _saved = true;
      if (_showNearby) {
        // Permission was already granted when they switched it on.
        await service.updateLocation(city: _city.text.trim());
      }
      if (!mounted) return;
      if (_editing) {
        showAppSnack(context, 'Buddy profile updated');
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _saving = false;
        _forward = true;
        _index = _steps.indexOf(_Step.done);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = BuddyService.errorText(e);
      });
    }
  }

  Future<void> _toggleNearby(bool on) async {
    if (!on) {
      setState(() {
        _showNearby = false;
        _locationNote = null;
      });
      return;
    }
    setState(() => _locating = true);
    final result = await context.read<BuddyService>().ensureLocationPermission();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _showNearby = result == BuddyLocationResult.updated;
      _locationNote = switch (result) {
        BuddyLocationResult.updated => null,
        BuddyLocationResult.serviceDisabled => 'Location is turned off on this device. Turn it on and try again.',
        BuddyLocationResult.deniedForever =>
          'Location permission is blocked. You can allow it in your phone settings, or just keep using your city.',
        _ => "No problem. We'll match you by city instead.",
      };
    });
  }

  // ------------------------------------------------------------------ UI

  Widget _header(IconData icon, String title, String subtitle, {Color color = AppColors.primary}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          decoration:
              BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(title, style: AppText.headline),
        const SizedBox(height: 6),
        Text(subtitle, style: AppText.body),
      ]),
    );
  }

  Widget _choice({
    required String label,
    String? sub,
    required IconData icon,
    Color color = AppColors.primary,
    required bool selected,
    required VoidCallback onTap,
    bool multi = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: sub == null ? label : '$label. $sub',
        onTap: onTap,
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySoft : AppColors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.6 : 1),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: AppRadius.card,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration:
                        BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: AppText.subtitle),
                      if (sub != null) ...[const SizedBox(height: 2), Text(sub, style: AppText.caption)],
                    ]),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    multi
                        ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                        : (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
                    color: selected ? AppColors.primary : AppColors.textTertiary,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intentsStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(Icons.diversity_3_rounded, 'What are you looking for?',
            'Pick everything that feels right. You can change this any time.'),
        for (final i in BuddyIntent.all)
          _choice(
            label: BuddyIntent.label(i),
            sub: BuddyIntent.description(i),
            icon: BuddyIntentStyle.icon(i),
            color: BuddyIntentStyle.color(i),
            selected: _intents.contains(i),
            multi: true,
            onTap: () => setState(() {
              _error = null;
              _intents.contains(i) ? _intents.remove(i) : _intents.add(i);
            }),
          ),
      ]);

  Widget _aboutStep() {
    const genders = [
      ('female', 'Woman', Icons.female_rounded),
      ('male', 'Man', Icons.male_rounded),
      ('other', 'Other', Icons.transgender_rounded)
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(Icons.badge_rounded, 'A little about you', 'Buddies see this name. Your first name is perfect.'),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        maxLength: 40,
        style: AppText.subtitle,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: const InputDecoration(
          labelText: 'Display name',
          hintText: 'e.g. Priya',
          counterText: '',
          prefixIcon: Icon(Icons.person_outline_rounded),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      const Text('I am a', style: AppText.bodyStrong),
      const SizedBox(height: AppSpacing.xs),
      for (final (key, label, icon) in genders)
        _choice(
          label: label,
          icon: icon,
          selected: _gender == key,
          onTap: () => setState(() {
            _gender = key;
            _error = null;
          }),
        ),
    ]);
  }

  Widget _interestStep() {
    const opts = [
      ('female', 'Women', Icons.female_rounded),
      ('male', 'Men', Icons.male_rounded),
      ('any', 'Everyone', Icons.favorite_rounded)
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(Icons.favorite_rounded, 'For a life partner, you would like to meet…',
          'Only used for life-partner matches. Friends, travel and satsang are open to everyone.',
          color: AppColors.love),
      for (final (key, label, icon) in opts)
        _choice(
          label: label,
          icon: icon,
          color: AppColors.love,
          selected: _interestedIn == key,
          onTap: () {
            setState(() => _interestedIn = key);
            Future.delayed(const Duration(milliseconds: 220), () {
              if (mounted && _step == _Step.interest) _next();
            });
          },
        ),
    ]);
  }

  Widget _bioStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(Icons.edit_note_rounded, 'Say something real',
            'A few honest lines get far more replies than a long list. Tap an idea to start.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in _bioPrompts)
            ActionChip(
              label: Text(p),
              avatar: const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
              onPressed: () {
                final cur = _bio.text.trimRight();
                final next = cur.isEmpty ? '$p ' : '$cur\n$p ';
                if (next.length > 500) return;
                setState(() {
                  _bio.text = next;
                  _bio.selection = TextSelection.collapsed(offset: next.length);
                  _error = null;
                });
              },
            ),
        ]),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _bio,
          maxLength: 500,
          minLines: 4,
          maxLines: 7,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _error = null),
          decoration: const InputDecoration(
            hintText: 'I love early morning aarti, long walks and good chai…',
            alignLabelWithHint: true,
          ),
        ),
        const BuddyNote(
          icon: Icons.shield_outlined,
          text: "Please don't add your phone number, address or social handles here.",
          color: AppColors.warning,
        ),
      ]);

  Widget _languagesStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(
            Icons.translate_rounded, 'Which languages do you speak?', 'So you can find people you can really talk to.'),
        Wrap(spacing: 8, runSpacing: 10, children: [
          for (final l in _languages)
            AppFilterChip(
              label: l,
              selected: _langs.contains(l),
              icon: _langs.contains(l) ? Icons.check_rounded : null,
              onTap: () => setState(() {
                _error = null;
                _langs.contains(l) ? _langs.remove(l) : _langs.add(l);
              }),
            ),
        ]),
      ]);

  Widget _locationStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(Icons.near_me_rounded, 'Where are you based?', 'Your city is shown on your profile.',
            color: const Color(0xFF0E9F8A)),
        TextField(
          controller: _city,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          style: AppText.subtitle,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: const InputDecoration(
            labelText: 'City',
            hintText: 'e.g. Varanasi',
            counterText: '',
            prefixIcon: Icon(Icons.location_city_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          color: _showNearby ? AppColors.primarySoft : AppColors.surface,
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, 6, 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showNearby,
            onChanged: _locating ? null : _toggleNearby,
            title: const Text('Show buddies near me', style: AppText.bodyStrong),
            subtitle: Text(
                _locating ? 'Asking for permission…' : 'Get a gentle heads-up when a great match is close by.',
                style: AppText.caption),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_locationNote != null) ...[
          BuddyNote(icon: Icons.info_outline_rounded, text: _locationNote!, color: AppColors.warning),
          const SizedBox(height: AppSpacing.sm),
        ],
        const BuddyNote(
          icon: Icons.lock_outline_rounded,
          text: 'Approximate only. We round your location to about 1 km and only ever show "~3 km away". '
              'Your exact location is never stored or shown to anyone.',
        ),
      ]);

  Widget _pledgeStep() {
    const items = [
      (Icons.cake_outlined, 'I am 18 or older', 'Buddies is only for adults.'),
      (Icons.volunteer_activism_outlined, 'I will be kind and respectful', 'No pressure, no rudeness, no spam.'),
      (
        Icons.flag_outlined,
        'I will report anything that feels wrong',
        'Never share money, OTPs or bank details. Meet in public places.'
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(
          Icons.verified_user_rounded, 'Our safety promise', 'CosmicGuide buddies is a respectful space. Please agree:',
          color: AppColors.success),
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AppCard(
            color: _pledges.contains(i) ? AppColors.successSoft : AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: CheckboxListTile(
              value: _pledges.contains(i),
              activeColor: AppColors.success,
              controlAffinity: ListTileControlAffinity.trailing,
              secondary: Icon(items[i].$1, color: AppColors.success),
              title: Text(items[i].$2, style: AppText.bodyStrong),
              subtitle: Text(items[i].$3, style: AppText.caption),
              onChanged: (v) => setState(() {
                _error = null;
                v == true ? _pledges.add(i) : _pledges.remove(i);
              }),
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TermsLink(
          label: 'Read the community guidelines',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CommunityGuidelinesScreen(initialSection: GuidelinesSection.buddy))),
        ),
      ),
    ]);
  }

  Widget _doneStep() {
    final status = context.watch<BuddyService>().status;
    final answered = status?.quizAnswered ?? 0;
    final remaining = ((status?.quizTotal ?? 50) - answered).clamp(0, 50);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: AppSpacing.xl),
      Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: AppShadows.glow(AppColors.primary),
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 46),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      const Text('Your buddy profile is live', textAlign: TextAlign.center, style: AppText.headline),
      const SizedBox(height: 6),
      const Text('We have started looking for people who truly fit you.',
          textAlign: TextAlign.center, style: AppText.body),
      const SizedBox(height: AppSpacing.xl),
      if (remaining > 0)
        AppCard(
          gradient: AppColors.cosmicGradient,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.psychology_rounded, color: AppColors.gold),
              SizedBox(width: 8),
              Expanded(
                child: Text('One more thing',
                    style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: AppSpacing.xs),
            Text(
              answered == 0
                  ? 'Answer the 50 mindset questions to get much better matches and earn up to 2,500 coins'
                  : 'Answer the remaining $remaining mindset questions for much better matches and up to ${remaining * 50} more coins',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.35),
            ),
            if (BuddyLinks.hasMindsetQuiz) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: answered == 0 ? 'Start the questions' : 'Continue the questions',
                icon: Icons.arrow_forward_rounded,
                onPressed: () async {
                  await BuddyLinks.openMindsetQuiz(context);
                },
              ),
            ],
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final step = _step;
    final isDone = step == _Step.done;
    final body = switch (step) {
      _Step.intents => _intentsStep(),
      _Step.about => _aboutStep(),
      _Step.interest => _interestStep(),
      _Step.bio => _bioStep(),
      _Step.languages => _languagesStep(),
      _Step.location => _locationStep(),
      _Step.pledge => _pledgeStep(),
      _Step.done => _doneStep(),
    };
    final progress = isDone ? 1.0 : (_index + 1) / _questionCount;
    final buttonLabel = switch (step) {
      _Step.pledge => _editing ? 'Save changes' : 'Create my profile',
      _Step.done => 'Start discovering',
      _ => 'Next',
    };

    return PopScope(
      // After saving, system back must go through _back() so the caller gets
      // `true` and refreshes (a plain pop would return null).
      canPop: _index == 0 && !isDone && !_saving && !_saved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(children: [
                IconButton(
                  tooltip: _index == 0 || isDone ? 'Close' : 'Back',
                  icon: Icon(_index == 0 || isDone ? Icons.close_rounded : Icons.arrow_back_rounded),
                  onPressed: _saving ? null : _back,
                ),
                Expanded(
                  child: Column(children: [
                    Text(
                      isDone
                          ? 'All set'
                          : '${_editing ? 'Edit profile' : 'Buddy profile'} · Step ${_index + 1} of $_questionCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 6),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
                      builder: (context, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: v,
                          minHeight: 4,
                          backgroundColor: AppColors.surfaceMuted,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 48),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
                child: AnimatedSwitcher(
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(step);
                    final dx = incoming == _forward ? 0.08 : -0.08;
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, if (current != null) current],
                  ),
                  child: KeyedSubtree(key: ValueKey(step), child: body),
                ),
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
                child:
                    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration:
                          BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(child: Text(_error!, style: AppText.body.copyWith(color: AppColors.danger))),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  AppButton(
                    label: buttonLabel,
                    icon: step == _Step.pledge ? Icons.check_rounded : null,
                    loading: _saving,
                    variant: isDone && BuddyLinks.hasMindsetQuiz ? AppButtonVariant.outline : AppButtonVariant.primary,
                    onPressed: _saving ? null : _next,
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
