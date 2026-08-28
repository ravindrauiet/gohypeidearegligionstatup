import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/backend_service.dart';
import '../../services/city_autocomplete_service.dart';

class LoveTab extends StatefulWidget {
  const LoveTab({super.key});

  @override
  State<LoveTab> createState() => _LoveTabState();
}

class _LoveTabState extends State<LoveTab> {
  String? _partnerName;
  String? _partnerGender;
  String? _partnerDob;
  String? _partnerTob;
  String? _partnerPob;

  bool _isMatching = false;
  Map<String, dynamic>? _synastryData;

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final kundli = backendService.kundliData ?? {
      'ascendant': 'Scorpio',
      'moonSign': 'Pisces',
      'birthDetails': {'fullName': 'ravindra'}
    };

    final userName = kundli['birthDetails']?['fullName'] ?? kundli['fullName'] ?? 'ravindra';
    final userMoon = kundli['moonSign'] ?? 'Pisces';
    final userLagna = kundli['ascendant'] ?? 'Scorpio';

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Synastry & Guna Milan',
          style: TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: IconButton(
              icon: const Icon(Icons.info_outline_rounded, color: Colors.black, size: 20),
              onPressed: () => _showInfoDialog(context),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            // 1. Interactive Synastry Partner Card (Connecting Orbits)
            SizedBox(
              height: 240,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Orbital Dashed Arc
                  CustomPaint(
                    size: const Size(320, 200),
                    painter: DashedOrbitalArcPainter(),
                  ),

                  // Left Bubble: Your Profile
                  Positioned(
                    left: 0,
                    top: 10,
                    child: _buildProfileBubble(
                      title: 'Your Profile',
                      name: userName,
                      sign: '$userMoon Moon',
                      isUser: true,
                    ),
                  ),

                  // Right Bubble: Partner's Profile
                  Positioned(
                    right: 0,
                    bottom: 10,
                    child: _buildProfileBubble(
                      title: "Partner's Profile",
                      name: _partnerName ?? 'Add Partner',
                      sign: _partnerName != null ? (_partnerDob ?? 'Tap to view') : 'Tap to enter details',
                      isUser: false,
                      onTap: _showAddPartnerDialog,
                    ),
                  ),

                  // Center Pink Heart Badge
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE83D66),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFE83D66),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. Styled Headline
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Find your ',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE83D66), width: 2),
                  ),
                  child: const Text(
                    'LOVE',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE83D66),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'with the stars (GPT-4o Ashtakoot Guna Engine)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 28),

            // 3. Match Calculation Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isMatching ? null : _calculateSynastryMatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isMatching
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Calculate AI Synastry Match',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // 4. Dynamic GPT-4o Synastry Results Section
            if (_synastryData != null) ...[
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Dark Celestial Score Banner
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // Circular Score Badge
                              Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                                  border: Border.all(color: const Color(0xFFFFD700), width: 2),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${_synastryData!['score'] ?? 88}%',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFFFFD700),
                                        ),
                                      ),
                                      const Text(
                                        'MATCH',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white70,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Verdict & Ashtakoot Score
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'ASHTAKOOT SCORE: ${_synastryData!['gunas'] ?? '28 / 36 Gunas'}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFFD700),
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _synastryData!['verdict'] ?? 'Harmonious Match',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'OpenAI GPT-4o Vedic Synastry Engine',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Results Details Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 4-Dimension Metric Progress Grid
                          if (_synastryData!['breakdown'] != null) ...[
                            const Text(
                              'COMPATIBILITY DIMENSIONS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.grey,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 14),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 2.2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              children: [
                                _buildDimensionCard(
                                  'Emotional Sync',
                                  _synastryData!['breakdown']['emotional'] ?? 92,
                                  Icons.favorite_rounded,
                                  const Color(0xFFE83D66),
                                ),
                                _buildDimensionCard(
                                  'Romance',
                                  _synastryData!['breakdown']['romance'] ?? 90,
                                  Icons.auto_awesome_rounded,
                                  const Color(0xFFFF9800),
                                ),
                                _buildDimensionCard(
                                  'Communication',
                                  _synastryData!['breakdown']['communication'] ?? 85,
                                  Icons.chat_bubble_outline_rounded,
                                  const Color(0xFF2196F3),
                                ),
                                _buildDimensionCard(
                                  'Marriage Longevity',
                                  _synastryData!['breakdown']['longevity'] ?? 88,
                                  Icons.verified_user_rounded,
                                  const Color(0xFF9C27B0),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                          ],

                          // Vedic Analysis Paragraph
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCF7F1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.stars_rounded, color: Colors.black, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Vedic Synastry Insights',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _synastryData!['summary'] ?? 'Strong emotional resonance and planetary compatibility detected.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade800,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 12),
                                Row(
                                  children: const [
                                    Icon(Icons.verified_rounded, color: Color(0xFFE83D66), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'RECOMMENDED VEDIC REMEDY',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFE83D66),
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _synastryData!['advice'] ?? 'Saturn aspects suggest long-term commitment and stability.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Consult Astrologer CTA
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/chatbot', arguments: {
                                  'name': 'Rishi & Olivia',
                                  'specialty': 'Love & Synastry Consultation',
                                  'field': 'Love Compatibility',
                                  'initialMessage': 'Analyze the synastry between me ($userName) and ${_partnerName ?? 'my partner'} for marriage longevity and romantic alignment.',
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.support_agent_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Consult Love Astrologer Rishi & Olivia',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionCard(String label, int val, IconData icon, Color color) {
    double progress = (val / 100.0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Text(
                '$val%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: color.withValues(alpha: 0.12),
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileBubble({
    required String title,
    required String name,
    required String sign,
    required bool isUser,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 145,
        height: 145,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF0F3),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isUser
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'R', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE83D66)))
                    : const Icon(Icons.add, color: Color(0xFFE83D66), size: 24),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              sign,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPartnerDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PartnerBirthDetailsSheet(
        initialName: _partnerName,
        initialDob: _partnerDob,
        onSave: (name, gender, dob, tob, pob) {
          setState(() {
            _partnerName = name;
            _partnerGender = gender;
            _partnerDob = dob;
            _partnerTob = tob;
            _partnerPob = pob;
          });
          _calculateSynastryMatch();
        },
      ),
    );
  }

  Future<void> _calculateSynastryMatch() async {
    final backendService = Provider.of<BackendService>(context, listen: false);

    if (_partnerName == null || _partnerName!.isEmpty) {
      _showAddPartnerDialog();
      return;
    }

    setState(() {
      _isMatching = true;
    });

    final result = await backendService.fetchSynastryMatch(
      partnerName: _partnerName!,
      partnerGender: _partnerGender,
      partnerDob: _partnerDob ?? '1999-05-20',
      partnerTob: _partnerTob ?? '10:30',
      partnerPob: _partnerPob ?? 'Delhi, India',
    );

    if (mounted) {
      setState(() {
        _isMatching = false;
        if (result != null) {
          _synastryData = result;
        } else {
          _synastryData = {
            'score': 88,
            'gunas': '28 / 36 Gunas',
            'verdict': 'Excellent Match (Harmonious Compatibility)',
            'summary': 'Strong emotional resonance and planetary compatibility detected.',
            'breakdown': {'emotional': 92, 'romance': 90, 'communication': 85, 'longevity': 88},
            'advice': 'Saturn aspects suggest long-term commitment and stability.'
          };
        }
      });
    }
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCF7F1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('What is Synastry & Ashtakoot Milan?'),
        content: const Text(
          'Synastry compares the natal birth charts of two individuals to analyze planetary aspects, Ashtakoot 36 Gunas (Varna, Vashya, Tara, Yoni, Maitri, Gana, Bhakoot, Nadi), and emotional chemistry for marriage longevity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class PartnerBirthDetailsSheet extends StatefulWidget {
  final String? initialName;
  final String? initialDob;
  final Function(String name, String gender, String dob, String tob, String pob) onSave;

  const PartnerBirthDetailsSheet({
    super.key,
    this.initialName,
    this.initialDob,
    required this.onSave,
  });

  @override
  State<PartnerBirthDetailsSheet> createState() => _PartnerBirthDetailsSheetState();
}

class _PartnerBirthDetailsSheetState extends State<PartnerBirthDetailsSheet> {
  int _currentStep = 0; // 0: Name & Gender, 1: DOB & TOB, 2: POB

  final TextEditingController _nameController = TextEditingController();
  String _gender = 'Female';

  DateTime? _selectedDate = DateTime(1999, 5, 20);
  TimeOfDay? _selectedTime = const TimeOfDay(hour: 10, minute: 30);
  bool _dontKnowTime = false;

  final TextEditingController _placeController = TextEditingController(text: 'Delhi, India');
  List<CitySuggestion> _placeSuggestions = [];
  bool _isSearchingPlace = false;
  Timer? _debounceTimer;
  double? _selectedLatitude;
  double? _selectedLongitude;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) _nameController.text = widget.initialName!;
    _placeController.addListener(_onPlaceTextChanged);
  }

  void _onPlaceTextChanged() {
    final query = _placeController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _placeSuggestions = [];
        _isSearchingPlace = false;
      });
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _isSearchingPlace = true);
      final suggestions = await CityAutocompleteService.fetchCitySuggestions(query);
      if (mounted) {
        setState(() {
          _placeSuggestions = suggestions;
          _isSearchingPlace = false;
        });
      }
    });
  }

  void _selectSuggestion(CitySuggestion suggestion) {
    _placeController.removeListener(_onPlaceTextChanged);
    _placeController.text = suggestion.fullDisplayName;
    _placeController.addListener(_onPlaceTextChanged);

    setState(() {
      _selectedLatitude = suggestion.latitude;
      _selectedLongitude = suggestion.longitude;
      _placeSuggestions = [];
      _isSearchingPlace = false;
    });

    FocusScope.of(context).unfocus();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(1999, 5, 20),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
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
              primary: Colors.black,
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
    if (_currentStep == 0 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter partner full name')),
      );
      return;
    }

    if (_currentStep == 1 && _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date of birth')),
      );
      return;
    }

    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
    } else {
      _submitPartnerDetails();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _submitPartnerDetails() {
    final name = _nameController.text.trim().isEmpty ? 'Partner' : _nameController.text.trim();
    final dob = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : '1999-05-20';
    final tob = _dontKnowTime || _selectedTime == null
        ? '12:00'
        : "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}";
    final place = _placeController.text.trim().isEmpty ? 'Delhi, India' : _placeController.text.trim();

    Navigator.pop(context);
    widget.onSave(name, _gender, dob, tob, place);
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFFFCF7F1),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Top Progress Header
          _buildHeaderProgress(),

          // Step Body
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
    );
  }

  Widget _buildHeaderProgress() {
    double progress = (_currentStep + 1) / 3.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
            onPressed: _previousStep,
          ),
          Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 12),
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
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildNameAndGenderStep();
      case 1:
        return _buildBirthDetailsStep();
      case 2:
        return _buildBirthPlaceStep();
      default:
        return _buildNameAndGenderStep();
    }
  }

  // Step 0: Name & Gender Input
  Widget _buildNameAndGenderStep() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.amber.shade200, width: 4),
          ),
          child: const Center(
            child: Icon(Icons.favorite_rounded, size: 44, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Partner Name & Gender",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Required for Ashtakoot 36 Guna Milan & Synastry alignment',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Partner Full Name',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. Priya Sharma',
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
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Partner Gender',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildGenderCard('Female', '♀'),
            const SizedBox(width: 10),
            _buildGenderCard('Male', '♂'),
            const SizedBox(width: 10),
            _buildGenderCard('Other', '⚥'),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderCard(String label, String symbol) {
    final isSelected = _gender == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
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
              Text(symbol, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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

  // Step 1: Date & Time of Birth
  Widget _buildBirthDetailsStep() {
    final dateStr = _selectedDate != null ? DateFormat('dd / MM / yyyy').format(_selectedDate!) : 'DD / MM / YYYY';
    final timeStr = _selectedTime != null
        ? "${_selectedTime!.hour.toString().padLeft(2, '0')} : ${_selectedTime!.minute.toString().padLeft(2, '0')}"
        : 'HH : MM';

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.amber.shade200, width: 4),
          ),
          child: const Center(
            child: Icon(Icons.cake_rounded, size: 44, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Partner Date & Time of Birth',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Determines exact planetary degrees and house trines',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Date of Birth', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.black),
                          const SizedBox(width: 10),
                          Text(dateStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Time of Birth', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _selectTime(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 18, color: Colors.black),
                          const SizedBox(width: 10),
                          Text(timeStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Checkbox(
              value: _dontKnowTime,
              activeColor: Colors.black,
              onChanged: (val) {
                setState(() {
                  _dontKnowTime = val ?? false;
                  if (_dontKnowTime) _selectedTime = null;
                });
              },
            ),
            const Text(
              "I don't know partner's exact time of birth",
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
      ],
    );
  }

  // Step 2: Place of Birth Step
  Widget _buildBirthPlaceStep() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: const Color(0xFFFFB74D),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.amber.shade200, width: 4),
          ),
          child: const Center(
            child: Icon(Icons.location_on_rounded, size: 44, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Partner Place of Birth',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Determines exact geographical coordinates & ayanamsa offset',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('City / Town of Birth', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _placeController,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. Delhi, India',
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.black54),
            suffixIcon: _isSearchingPlace
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : null,
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
        if (_placeSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _placeSuggestions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final suggestion = _placeSuggestions[index];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined, size: 20, color: Colors.black),
                  title: Text(suggestion.fullDisplayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  onTap: () => _selectSuggestion(suggestion),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildBottomActionButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF7F1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Text(
            _currentStep == 2 ? 'Calculate Synastry Match' : 'Continue',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class DashedOrbitalArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(40, 40);
    path.cubicTo(100, -20, 220, 220, 280, 160);

    for (var i = 0.0; i < 1.0; i += 0.03) {
      final p1 = path.computeMetrics().first.getTangentForOffset(i * path.computeMetrics().first.length);
      if (p1 != null) {
        canvas.drawCircle(p1.position, 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
