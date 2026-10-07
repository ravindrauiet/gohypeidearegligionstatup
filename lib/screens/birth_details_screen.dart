import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/backend_service.dart';
import '../services/city_autocomplete_service.dart';
import '../utils/app_routes.dart';

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

  // Step 1: Gender & Relationship Status
  String _gender = 'Male';
  String _relationshipStatus = 'Single';

  // Step 2: Date & Time of Birth
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _dontKnowTime = false;

  // Step 3: Place of Birth & Autocomplete
  final TextEditingController _placeController = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    _placeController.addListener(_onPlaceTextChanged);

    // Pre-fill the name from the existing Kundli / signed-in account.
    final backend = context.read<BackendService>();
    final birthDetails = backend.kundliData?['birthDetails'];
    final existingName =
        (birthDetails is Map ? birthDetails['fullName']?.toString() : null) ??
            backend.user?['fullName']?.toString();
    if (existingName != null && existingName.trim().isNotEmpty) {
      _nameController.text = existingName.trim();
    }
  }

  void _onPlaceTextChanged() {
    final query = _placeController.text.trim();
    // The listener also fires on cursor/selection changes; ignore those.
    if (query == _lastPlaceQuery) return;
    _lastPlaceQuery = query;

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
        _isSearchingPlace = false;
      });
    });
  }

  void _selectSuggestion(CitySuggestion suggestion) {
    _debounceTimer?.cancel();
    _placeSearchId++;
    _lastPlaceQuery = suggestion.fullDisplayName;
    _placeController.value = TextEditingValue(
      text: suggestion.fullDisplayName,
      selection:
          TextSelection.collapsed(offset: suggestion.fullDisplayName.length),
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
        primary: const Color(0xFFEE5A78),
        onPrimary: Colors.white,
        surface: const Color(0xFFFCF7F1),
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
      builder: (context, child) =>
          Theme(data: _pickerTheme(context), child: child!),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    FocusScope.of(context).unfocus();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 10, minute: 30),
      helpText: 'Select time of birth',
      builder: (context, child) =>
          Theme(data: _pickerTheme(context), child: child!),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
        _dontKnowTime = false;
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

  void _nextStep() {
    if (_isSubmitting) return;
    if (_currentStep == 0 && _nameController.text.trim().isEmpty) {
      _showMessage('Please enter your name');
      return;
    }

    if (_currentStep == 2) {
      if (_selectedDate == null) {
        _showMessage('Please select your date of birth');
        return;
      }
      if (_selectedTime == null && !_dontKnowTime) {
        _showMessage("Please select your birth time, or tick \"Don't Know\"");
        return;
      }
    }

    if (_currentStep == _lastStep && _placeController.text.trim().isEmpty) {
      _showMessage('Please enter your place of birth');
      return;
    }

    FocusScope.of(context).unfocus();
    if (_currentStep < _lastStep) {
      setState(() {
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
    Navigator.pushNamedAndRemoveUntil(
        context, AppRoutes.home, (route) => false);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _placeController.removeListener(_onPlaceTextChanged);
    _nameController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // System back walks back through the wizard steps first.
      canPop: _currentStep == 0 && !_isSubmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _previousStep();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFCF7F1),
        body: SafeArea(
          child: Column(
            children: [
              // Top Navigation & Progress Bar
              _buildHeaderProgress(),

              // Wizard Step Body
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _buildCurrentStepView(),
                ),
              ),

              // Bottom Action Button
              _buildBottomActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  // Progress Bar & Back Arrow Header
  Widget _buildHeaderProgress() {
    final progress = (_currentStep + 1) / (_lastStep + 1);
    final canGoBack = _currentStep > 0 || Navigator.canPop(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: canGoBack
                ? IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.black, size: 20),
                    onPressed: _isSubmitting ? null : _previousStep,
                  )
                : null,
          ),
          Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.black.withValues(alpha: 0.08),
                  color: Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
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

  // Step 0: Name Input
  Widget _buildNameStep() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.amber.shade200, width: 4),
          ),
          child: const Center(
            child: Icon(Icons.person, size: 48, color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Enter your Name',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We use this to calculate your Sun & other placements.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 36),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Your Name',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => _nextStep(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. Ravindra Sharma',
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // Step 1: Who You Are (Gender & Relationship Status)
  Widget _buildWhoYouAreStep() {
    return Column(
      children: [
        const SizedBox(height: 12),
        const Text(
          '💖',
          style: TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 16),
        const Text(
          'Who You Are',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This helps us get your reading right for you',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Your Gender',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildGenderCard('Male', '♂'),
            const SizedBox(width: 10),
            _buildGenderCard('Female', '♀'),
            const SizedBox(width: 10),
            _buildGenderCard('Other', '⚥'),
          ],
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Your relationship status',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.8,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: ['Single', 'Married', 'In a relationship', 'Divorced']
              .map((status) {
            final isSelected = _relationshipStatus == status;
            return GestureDetector(
              onTap: () => setState(() => _relationshipStatus = status),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? Colors.black
                        : Colors.black.withValues(alpha: 0.1),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildGenderCard(String label, String icon) {
    final isSelected = _gender == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? Colors.black
                  : Colors.black.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Text(icon,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 2: Date & Time of Birth
  Widget _buildBirthDetailsStep() {
    final dateStr = _selectedDate != null
        ? DateFormat('dd MMM yyyy').format(_selectedDate!)
        : 'DD / MM / YYYY';
    final timeStr = _selectedTime != null
        ? MaterialLocalizations.of(context).formatTimeOfDay(_selectedTime!)
        : 'HH : MM';

    return Column(
      children: [
        const SizedBox(height: 12),
        const Text(
          '🎂',
          style: TextStyle(fontSize: 48),
        ),
        const SizedBox(height: 16),
        const Text(
          'Enter your birth details',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your exact date and time decide your Ascendant, Moon sign & Nakshatra.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Date of birth',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 10),
        _buildPickerField(
          icon: Icons.calendar_month_rounded,
          label: dateStr,
          hasValue: _selectedDate != null,
          onTap: _selectDate,
        ),
        const SizedBox(height: 20),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Time of birth',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 10),
        _buildPickerField(
          icon: Icons.access_time_rounded,
          label: _dontKnowTime ? "Don't know (using 12:00 noon)" : timeStr,
          hasValue: _selectedTime != null || _dontKnowTime,
          onTap: _selectTime,
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            value: _dontKnowTime,
            onChanged: (val) {
              setState(() {
                _dontKnowTime = val ?? false;
                if (_dontKnowTime) _selectedTime = null;
              });
            },
            activeColor: Colors.black,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              "I don't know my birth time",
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black),
            ),
            subtitle: _dontKnowTime
                ? Text(
                    'We will use 12:00 noon. Your Ascendant and house placements may be less accurate.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildPickerField({
    required IconData icon,
    required String label,
    required bool hasValue,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _isSubmitting ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.black87, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: hasValue ? Colors.black : Colors.grey.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  // Step 3: Enter your birth place with Live 5-City Autocomplete Suggestions
  Widget _buildBirthPlaceStep() {
    return Column(
      children: [
        const SizedBox(height: 12),
        const Text(
          '📍',
          style: TextStyle(fontSize: 52),
        ),
        const SizedBox(height: 16),
        const Text(
          'Enter your birth place',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Small differences can change your Rising sign. Use the most accurate info you have.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 36),

        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Place of birth',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 10),

        // Text Field for Place Input
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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Type city or state (e.g. Delhi, Mumbai)',
            hintStyle: TextStyle(
                color: Colors.grey.shade400, fontWeight: FontWeight.w500),
            filled: true,
            fillColor: Colors.white,
            prefixIcon:
                const Icon(Icons.location_on, color: Colors.black, size: 22),
            suffixIcon: _isSearchingPlace
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    ),
                  )
                : (_placeController.text.isNotEmpty
                    ? IconButton(
                        icon:
                            const Icon(Icons.clear_rounded, color: Colors.grey),
                        tooltip: 'Clear',
                        onPressed: _clearPlace,
                      )
                    : null),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide:
                  BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide:
                  BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.black, width: 1.5),
            ),
          ),
        ),

        // Live 5-City & State Autocomplete Suggestions Overlay Box
        if (_placeSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _placeSuggestions.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final suggestion = _placeSuggestions[index];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_city_rounded,
                        color: Color(0xFFEE5A78), size: 22),
                    title: Text(
                      suggestion.cityName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black),
                    ),
                    subtitle: Text(
                      suggestion.fullDisplayName,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.north_west_rounded,
                        size: 16, color: Colors.grey),
                    onTap: () => _selectSuggestion(suggestion),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // Bottom Action Button
  Widget _buildBottomActionButton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEE5A78),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  _currentStep == 3 ? 'Generate Kundli Chart' : 'Next',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
