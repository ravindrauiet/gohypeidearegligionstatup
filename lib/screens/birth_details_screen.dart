import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/backend_service.dart';
import '../services/city_autocomplete_service.dart';
import '../utils/app_routes.dart';
import '../widgets/ui/app_ui.dart';

class BirthDetailsScreen extends StatefulWidget {
  const BirthDetailsScreen({super.key});

  @override
  State<BirthDetailsScreen> createState() => _BirthDetailsScreenState();
}

class _BirthDetailsScreenState extends State<BirthDetailsScreen> {
  static const int _lastStep = 3;

  // 0: Name, 1: Who You Are, 2: DOB & TOB, 3: Place of Birth
  int _currentStep = 0;

  // Step 0: Name
  final TextEditingController _nameController = TextEditingController();

  // Step 1: Gender
  String _gender = 'Male';

  // Step 2: Date & Time of Birth
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _dontKnowTime = false;

  // Step 3: Place of Birth & Autocomplete
  final TextEditingController _placeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<CitySuggestion> _placeSuggestions = [];
  bool _isSearchingPlace = false;
  Timer? _debounceTimer;
  String _lastPlaceQuery = '';
  int _placeSearchId = 0;

  /// Display name of the place the coordinates below belong to.
  String? _selectedPlaceName;
  double? _selectedLatitude;
  double? _selectedLongitude;

  bool _isSubmitting = false;

  /// Inline validation message for the current step.
  String? _stepError;

  /// True when the last finished place search found nothing.
  bool _noPlaceResults = false;

  @override
  void initState() {
    super.initState();
    _placeController.addListener(_onPlaceTextChanged);

    // Pre-fill the name from the existing Kundli / signed-in account.
    final backend = context.read<BackendService>();
    final birthDetails = backend.kundliData?['birthDetails'];
    final existingName =
        (birthDetails is Map ? birthDetails['fullName']?.toString() : null) ?? backend.user?['fullName']?.toString();
    if (existingName != null && existingName.trim().isNotEmpty) {
      _nameController.text = existingName.trim();
    }
  }

  void _onPlaceTextChanged() {
    final query = _placeController.text.trim();
    // The listener also fires on cursor/selection changes; ignore those.
    if (query == _lastPlaceQuery) return;
    _lastPlaceQuery = query;
    _noPlaceResults = false;
    if (query.isNotEmpty) _stepError = null;

    // Typing after picking a suggestion invalidates its coordinates.
    if (_selectedPlaceName != null && query != _selectedPlaceName) {
      _selectedPlaceName = null;
      _selectedLatitude = null;
      _selectedLongitude = null;
    }

    _debounceTimer?.cancel();
    if (query.isEmpty) {
      _placeSearchId++;
      setState(() {
        _placeSuggestions = [];
        _isSearchingPlace = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final searchId = ++_placeSearchId;
      setState(() => _isSearchingPlace = true);
      List<CitySuggestion> suggestions = [];
      try {
        suggestions = await CityAutocompleteService.fetchCitySuggestions(query);
      } catch (e) {
        debugPrint('Place search failed: $e');
      }
      // Drop stale responses that finished after a newer search started.
      if (!mounted || searchId != _placeSearchId) return;
      setState(() {
        _placeSuggestions = suggestions;
        _noPlaceResults = suggestions.isEmpty;
        _isSearchingPlace = false;
      });
      if (suggestions.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  void _selectSuggestion(CitySuggestion suggestion) {
    _debounceTimer?.cancel();
    _placeSearchId++;
    _lastPlaceQuery = suggestion.fullDisplayName;
    _placeController.value = TextEditingValue(
      text: suggestion.fullDisplayName,
      selection: TextSelection.collapsed(offset: suggestion.fullDisplayName.length),
    );

    setState(() {
      _selectedPlaceName = suggestion.fullDisplayName;
      _selectedLatitude = suggestion.latitude;
      _selectedLongitude = suggestion.longitude;
      _placeSuggestions = [];
      _isSearchingPlace = false;
    });

    FocusScope.of(context).unfocus();
  }

  void _clearPlace() {
    _debounceTimer?.cancel();
    _placeSearchId++;
    _placeController.clear();
    setState(() {
      _placeSuggestions = [];
      _isSearchingPlace = false;
    });
  }

  ThemeData _pickerTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: AppColors.surface,
      ),
    );
  }

  Future<void> _selectDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select date of birth',
      builder: (context, child) => Theme(data: _pickerTheme(context), child: child!),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _stepError = null;
      });
    }
  }

  Future<void> _selectTime() async {
    FocusScope.of(context).unfocus();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 10, minute: 30),
      helpText: 'Select time of birth',
      builder: (context, child) => Theme(data: _pickerTheme(context), child: child!),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
        _dontKnowTime = false;
        _stepError = null;
      });
    }
  }

  void _showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, action: action),
      );
  }

  /// Shows a validation message inline, under the field it is about.
  void _showFieldError(String message) => setState(() => _stepError = message);

  void _clearFieldError() {
    if (_stepError != null) setState(() => _stepError = null);
  }

  void _nextStep() {
    if (_isSubmitting) return;
    if (_currentStep == 0 && _nameController.text.trim().isEmpty) {
      _showFieldError('Please enter your name');
      return;
    }

    if (_currentStep == 2) {
      if (_selectedDate == null) {
        _showFieldError('Please select your date of birth');
        return;
      }
      if (_selectedTime == null && !_dontKnowTime) {
        _showFieldError("Please select your birth time, or tick \"Don't Know\"");
        return;
      }
    }

    if (_currentStep == _lastStep && _placeController.text.trim().isEmpty) {
      _showFieldError('Please enter your place of birth');
      return;
    }

    FocusScope.of(context).unfocus();
    if (_currentStep < _lastStep) {
      setState(() {
        _stepError = null;
        _currentStep++;
      });
    } else {
      _submitAllDetails();
    }
  }

  void _previousStep() {
    if (_isSubmitting) return;
    if (_currentStep > 0) {
      FocusScope.of(context).unfocus();
      setState(() {
        _stepError = null;
        _currentStep--;
      });
    } else {
      Navigator.maybePop(context);
    }
  }

  /// Local suggestions have no coordinates, and free-typed text has none
  /// either. Look the place up so the chart is not silently cast for Delhi
  /// (the backend's default when lat/long are missing).
  Future<void> _resolveCoordinatesIfNeeded(String place) async {
    if (_selectedLatitude != null && _selectedLongitude != null) return;
    try {
      final results = await CityAutocompleteService.fetchCitySuggestions(place);
      for (final s in results) {
        if (s.latitude != null && s.longitude != null) {
          _selectedLatitude = s.latitude;
          _selectedLongitude = s.longitude;
          _selectedPlaceName = place;
          return;
        }
      }
    } catch (e) {
      debugPrint('Coordinate lookup failed: $e');
    }
  }

  Future<void> _submitAllDetails() async {
    final name = _nameController.text.trim();
    final dob = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final tob = _dontKnowTime || _selectedTime == null
        ? '12:00:00'
        : "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00";
    final place = _placeController.text.trim();

    setState(() {
      _isSubmitting = true;
      _placeSuggestions = [];
    });

    final backendService = context.read<BackendService>();

    await _resolveCoordinatesIfNeeded(place);
    if (!mounted) return;
    if (_selectedLatitude == null || _selectedLongitude == null) {
      setState(() => _isSubmitting = false);
      _showMessage(
          'We couldn\'t locate "$place". Pick a place from the suggestions and check your internet connection.');
      return;
    }

    // The birth timezone is derived server-side from the place's coordinates
    // (never from this device's timezone), so no timezone is sent here.
    Map<String, dynamic>? kundli;
    try {
      kundli = await backendService.generateKundli(
        fullName: name,
        gender: _gender,
        dateOfBirth: dob,
        timeOfBirth: tob,
        placeOfBirth: place,
        latitude: _selectedLatitude,
        longitude: _selectedLongitude,
        birthTimeKnown: !_dontKnowTime,
      );
    } catch (e) {
      debugPrint('Kundli generation failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
    });

    if (kundli == null) {
      // generateKundli returns null on failure; the reason is in lastError.
      _showMessage(
        backendService.lastError ?? 'Could not generate your Kundli. Please try again.',
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            if (mounted && !_isSubmitting) _submitAllDetails();
          },
        ),
      );
      return;
    }

    // Fresh dashboard; nothing from the entry flow should remain on the stack.
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _placeController.removeListener(_onPlaceTextChanged);
    _nameController.dispose();
    _placeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  Widget build(BuildContext context) {
    final showCta = _currentStep != _lastStep || _placeSuggestions.isEmpty;
    return PopScope(
      // System back walks back through the wizard steps first.
      canPop: _currentStep == 0 && !_isSubmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _previousStep();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeaderProgress(),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: _buildCurrentStepView(),
                    ),
                  ),
                ),
              ),
              // Sticky CTA (hidden while the place suggestions need the room).
              if (showCta) _buildBottomActionButton() else SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }

  /// Back arrow, "Step x of 4" and a slim progress bar.
  Widget _buildHeaderProgress() {
    final progress = (_currentStep + 1) / (_lastStep + 1);
    final canGoBack = _currentStep > 0 || Navigator.canPop(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.page, 0),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: canGoBack
                      ? IconButton(
                          tooltip: 'Back',
                          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                          onPressed: _isSubmitting ? null : _previousStep,
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Step ${_currentStep + 1} of ${_lastStep + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                color: AppColors.primary,
                backgroundColor: AppColors.border,
                semanticsLabel: 'Step ${_currentStep + 1} of ${_lastStep + 1}',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildNameStep();
      case 1:
        return _buildWhoYouAreStep();
      case 2:
        return _buildBirthDetailsStep();
      case 3:
        return _buildBirthPlaceStep();
      default:
        return _buildNameStep();
    }
  }

  /// Icon tile, title and one helpful line at the top of each step.
  Widget _stepHeader({required IconData icon, required String title, String? subtitle, bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Text(title, style: compact ? AppText.title : AppText.headline),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: AppText.body),
        ],
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
      ],
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(text, style: AppText.bodyStrong),
      );

  /// Inline error for fields that are not text inputs.
  Widget _inlineError() {
    if (_stepError == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _stepError!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.danger, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Step 0: Name
  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          icon: Icons.person_outline_rounded,
          title: 'Enter your Name',
          subtitle: 'We use this to calculate your Sun & other placements.',
        ),
        _fieldLabel('Your Name'),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => _nextStep(),
          onChanged: (_) => _clearFieldError(),
          style: AppText.bodyStrong.copyWith(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'e.g. Ravindra Sharma',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            errorText: _stepError,
            errorMaxLines: 2,
          ),
        ),
      ],
    );
  }

  // Step 1: Who You Are
  Widget _buildWhoYouAreStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          icon: Icons.badge_outlined,
          title: 'Who You Are',
          subtitle: 'This helps us get your reading right for you',
        ),
        _fieldLabel('Your Gender'),
        Row(
          children: [
            _buildGenderCard('Male', Icons.male_rounded),
            const SizedBox(width: AppSpacing.xs),
            _buildGenderCard('Female', Icons.female_rounded),
            const SizedBox(width: AppSpacing.xs),
            _buildGenderCard('Other', Icons.transgender_rounded),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderCard(String label, IconData icon) {
    final isSelected = _gender == label;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: isSelected ? AppColors.primarySoft : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 1.6 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _gender = label),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: 4),
              child: Column(
                children: [
                  Icon(icon, size: 26, color: isSelected ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Step 2: Date & Time of Birth
  Widget _buildBirthDetailsStep() {
    final dateStr = _selectedDate != null ? DateFormat('dd MMM yyyy').format(_selectedDate!) : 'DD / MM / YYYY';
    final timeStr =
        _selectedTime != null ? MaterialLocalizations.of(context).formatTimeOfDay(_selectedTime!) : 'HH : MM';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          icon: Icons.event_outlined,
          title: 'Enter your birth details',
          subtitle: 'Your exact date and time decide your Ascendant, Moon sign & Nakshatra.',
        ),
        AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _fieldLabel('Date of birth'),
              _buildPickerField(
                icon: Icons.calendar_today_rounded,
                label: dateStr,
                hasValue: _selectedDate != null,
                semanticLabel: 'Date of birth',
                onTap: _selectDate,
              ),
              const SizedBox(height: AppSpacing.md),
              _fieldLabel('Time of birth'),
              _buildPickerField(
                icon: Icons.schedule_rounded,
                label: _dontKnowTime ? "Don't know (using 12:00 noon)" : timeStr,
                hasValue: _selectedTime != null || _dontKnowTime,
                semanticLabel: 'Time of birth',
                onTap: _selectTime,
              ),
              CheckboxListTile(
                value: _dontKnowTime,
                onChanged: _isSubmitting
                    ? null
                    : (val) {
                        setState(() {
                          _dontKnowTime = val ?? false;
                          if (_dontKnowTime) {
                            _selectedTime = null;
                            _stepError = null;
                          }
                        });
                      },
                activeColor: AppColors.primary,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text("I don't know my birth time", style: AppText.bodyStrong),
                subtitle: _dontKnowTime
                    ? const Text(
                        'We will use 12:00 noon. Your Ascendant and house placements may be less accurate.',
                        style: AppText.caption,
                      )
                    : null,
              ),
            ],
          ),
        ),
        _inlineError(),
      ],
    );
  }

  Widget _buildPickerField({
    required IconData icon,
    required String label,
    required bool hasValue,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: '$semanticLabel: ${hasValue ? label : 'not set'}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.input,
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _isSubmitting ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 15),
            child: Row(
              children: [
                Icon(icon, color: hasValue ? AppColors.primary : AppColors.textTertiary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: hasValue ? AppColors.textPrimary : AppColors.textTertiary,
                      fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more_rounded, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Step 3: Birth place with live autocomplete (India, Nepal & Sri Lanka)
  Widget _buildBirthPlaceStep() {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hasSuggestions = _placeSuggestions.isNotEmpty;
    final confirmed = _selectedLatitude != null && _selectedPlaceName != null && !hasSuggestions;
    final noResults =
        _noPlaceResults && !_isSearchingPlace && !hasSuggestions && _placeController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader(
          icon: Icons.location_on_outlined,
          title: 'Enter your birth place',
          subtitle: isKeyboardOpen && hasSuggestions
              ? null
              : 'Small differences can change your Rising sign. India, Nepal & Sri Lanka supported.',
          compact: isKeyboardOpen,
        ),
        _fieldLabel('Place of birth'),
        TextField(
          controller: _placeController,
          enabled: !_isSubmitting,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.addressCity],
          onSubmitted: (_) {
            if (_placeSuggestions.isNotEmpty) {
              _selectSuggestion(_placeSuggestions.first);
            }
          },
          style: AppText.bodyStrong.copyWith(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Type city (e.g. Delhi, Kathmandu, Colombo)',
            prefixIcon: const Icon(Icons.search_rounded),
            errorText: _stepError,
            errorMaxLines: 2,
            suffixIcon: _isSearchingPlace
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : (_placeController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
                        tooltip: 'Clear',
                        onPressed: _clearPlace,
                      )
                    : null),
          ),
        ),
        if (hasSuggestions) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: _placeSuggestions.length,
                separatorBuilder: (context, index) => const Divider(indent: 64),
                itemBuilder: (context, index) => _suggestionRow(_placeSuggestions[index]),
              ),
            ),
          ),
        ],
        if (confirmed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Location found',
                    style: AppText.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        if (noResults)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textTertiary),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No matching places yet. Check the spelling, or try the nearest bigger town.',
                    style: AppText.caption,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _suggestionRow(CitySuggestion suggestion) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectSuggestion(suggestion),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                  child: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        suggestion.cityName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong,
                      ),
                      Text(
                        suggestion.fullDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.north_west_rounded, size: 16, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Sticky bottom CTA.
  Widget _buildBottomActionButton() {
    final isLast = _currentStep == _lastStep;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppButton(
                label: isLast ? 'Generate my Kundli' : 'Next',
                icon: isLast ? Icons.auto_awesome_rounded : null,
                loading: _isSubmitting,
                onPressed: _isSubmitting ? null : _nextStep,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
