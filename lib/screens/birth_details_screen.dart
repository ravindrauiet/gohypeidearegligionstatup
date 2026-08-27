import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/backend_service.dart';

class BirthDetailsScreen extends StatefulWidget {
  const BirthDetailsScreen({super.key});

  @override
  State<BirthDetailsScreen> createState() => _BirthDetailsScreenState();
}

class _BirthDetailsScreenState extends State<BirthDetailsScreen> {
  int _currentStep = 0; // 0: Topics, 1: Name, 2: Who You Are, 3: DOB & TOB, 4: Place of Birth

  // Step 0: Selected Topics
  final List<String> _selectedTopics = ['Explore my birth chart'];

  // Step 1: Name
  final TextEditingController _nameController = TextEditingController();

  // Step 2: Gender & Relationship Status
  String _gender = 'Male';
  String _relationshipStatus = 'Single';

  // Step 3: Date & Time of Birth
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _dontKnowTime = false;

  // Step 4: Place of Birth
  final TextEditingController _placeController = TextEditingController();

  bool _isSubmitting = false;

  final List<Map<String, String>> _topicsList = [
    {
      'title': 'Explore my birth chart',
      'subtitle': 'Learn your unique qualities from planetary positions at birth.',
      'icon': '🔮',
    },
    {
      'title': 'Love compatibility',
      'subtitle': 'See how your synastry charts work in your romantic relationship.',
      'icon': '💑',
    },
    {
      'title': "How's my day today",
      'subtitle': "Find out how planetary movements impact your day's energies.",
      'icon': '🌅',
    },
    {
      'title': "Today's moon calendar",
      'subtitle': 'See the current moon phase and its effects on your life.',
      'icon': '🌙',
    },
    {
      'title': 'My transits today',
      'subtitle': 'Know how current planetary movements influence your life path.',
      'icon': '🪐',
    },
  ];

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(1998, 7, 15),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFEE5A78),
              onPrimary: Colors.white,
              surface: Color(0xFFFCF7F1),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 10, minute: 30),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFEE5A78),
              onPrimary: Colors.white,
              surface: Color(0xFFFCF7F1),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _dontKnowTime = false;
      });
    }
  }

  void _nextStep() {
    if (_currentStep == 1 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    if (_currentStep == 3 && _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth')),
      );
      return;
    }

    if (_currentStep < 4) {
      setState(() {
        _currentStep++;
      });
    } else {
      _submitAllDetails();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _submitAllDetails() async {
    final name = _nameController.text.trim().isEmpty ? 'Ravindra' : _nameController.text.trim();
    final dob = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : '1998-07-15';
    final tob = _dontKnowTime || _selectedTime == null
        ? '12:00:00'
        : "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}:00";
    final place = _placeController.text.trim().isEmpty ? 'New Delhi, India' : _placeController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    final backendService = Provider.of<BackendService>(context, listen: false);

    await backendService.generateKundli(
      fullName: name,
      gender: _gender,
      dateOfBirth: dob,
      timeOfBirth: tob,
      placeOfBirth: place,
    );

    setState(() {
      _isSubmitting = false;
    });

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1), // Warm cream background matching UI screenshots
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Progress Bar
            _buildHeaderProgress(),

            // Wizard Step Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: _buildCurrentStepView(),
              ),
            ),

            // Bottom Action Button
            _buildBottomActionButton(),
          ],
        ),
      ),
    );
  }

  // Progress Bar & Back Arrow Header
  Widget _buildHeaderProgress() {
    double progress = (_currentStep + 1) / 5.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              if (_currentStep > 0)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
                  onPressed: _previousStep,
                )
              else
                const SizedBox(width: 48),
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
        ],
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildTopicsStep();
      case 1:
        return _buildNameStep();
      case 2:
        return _buildWhoYouAreStep();
      case 3:
        return _buildBirthDetailsStep();
      case 4:
        return _buildBirthPlaceStep();
      default:
        return _buildTopicsStep();
    }
  }

  // Step 0: Choose Topics
  Widget _buildTopicsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Choose a topic to explore your astrological insights',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 24),
        ..._topicsList.map((topic) {
          final isSelected = _selectedTopics.contains(topic['title']);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _selectedTopics.remove(topic['title']);
                } else {
                  _selectedTopics.add(topic['title']!);
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.black.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.06),
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF7F1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        topic['icon']!,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              topic['title']!,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF00C853),
                                size: 22,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          topic['subtitle']!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
            child: const Text(
              'Skip to dashboard',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 14,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Step 1: Name Input
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
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. ravindra',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
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

  // Step 2: Who You Are (Gender & Relationship Status)
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

        // Your Gender Section
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Your Gender',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
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

        // Your Relationship Status Section
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Your relationship status',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
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
          children: ['Single', 'Married', 'In a relationship', 'Divorced'].map((status) {
            final isSelected = _relationshipStatus == status;
            return GestureDetector(
              onTap: () => setState(() => _relationshipStatus = status),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.black.withValues(alpha: 0.1),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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
              color: isSelected ? Colors.black : Colors.black.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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

  // Step 3: Date & Time of Birth
  Widget _buildBirthDetailsStep() {
    final dateStr = _selectedDate != null ? DateFormat('dd / MM / yyyy').format(_selectedDate!) : 'DD / MM / YYYY';
    final timeStr = _selectedTime != null
        ? "${_selectedTime!.hour.toString().padLeft(2, '0')} : ${_selectedTime!.minute.toString().padLeft(2, '0')}"
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
          'Enter your birth Details',
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
        const SizedBox(height: 28),

        // Date of Birth
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Date Of Birth',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _selectDate(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Colors.black87, size: 22),
                const SizedBox(width: 14),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 16,
                    color: _selectedDate != null ? Colors.black : Colors.grey.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Time of Birth
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Time of birth',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _selectTime(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_rounded, color: Colors.black87, size: 22),
                const SizedBox(width: 14),
                Text(
                  _dontKnowTime ? 'Don\'t Know' : timeStr,
                  style: TextStyle(
                    fontSize: 16,
                    color: (_selectedTime != null || _dontKnowTime) ? Colors.black : Colors.grey.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Checkbox: Don't know
        const SizedBox(height: 10),
        Row(
          children: [
            Checkbox(
              value: _dontKnowTime,
              activeColor: Colors.black,
              onChanged: (val) {
                setState(() {
                  _dontKnowTime = val ?? false;
                });
              },
            ),
            const Text(
              'Don\'t Know',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black),
            ),
          ],
        ),
      ],
    );
  }

  // Step 4: Enter your birth place (Matching user image media_1787849045895.jpg)
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

        // Place of Birth Input Box
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Place of birth',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _placeController,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Select your birth place',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500),
            filled: true,
            fillColor: Colors.white,
            prefixIcon: const Icon(Icons.location_on, color: Colors.black, size: 22),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.black, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // Bottom Action Button
  Widget _buildBottomActionButton() {
    final isStep0 = _currentStep == 0;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: isStep0 ? Colors.black : const Color(0xFFEE5A78), // Pink matching UI screenshots
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isStep0 ? 'Proceed' : (_currentStep == 4 ? 'Next' : 'Next'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (isStep0) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
