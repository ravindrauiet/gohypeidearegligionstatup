import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/backend_service.dart';
import '../../services/city_autocomplete_service.dart';

class MoreTab extends StatefulWidget {
  const MoreTab({super.key});

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  bool _isLoadingFamily = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFamilyMembers();
    });
  }

  Future<void> _loadFamilyMembers() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    setState(() => _isLoadingFamily = true);
    await backendService.fetchFamilyKundlis();
    if (mounted) setState(() => _isLoadingFamily = false);
  }

  @override
  Widget build(BuildContext context) {
    final backendService = Provider.of<BackendService>(context);
    final user = backendService.user;
    final name = user?['fullName'] ?? 'ravindra';
    final familyMembers = backendService.familyMembers;
    final selectedFamily = backendService.selectedFamilyMember;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'More & Family Profiles',
          style: TextStyle(
            color: Colors.black,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Primary User Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selectedFamily == null ? const Color(0xFFE83D66) : Colors.grey.shade200,
                  width: selectedFamily == null ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFE83D66).withValues(alpha: 0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Color(0xFFE83D66),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE83D66).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Primary Self',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE83D66)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?['email'] ?? 'AstroAI Primary Account',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (selectedFamily != null)
                    TextButton(
                      onPressed: () => backendService.selectFamilyMember(null),
                      child: const Text('Switch Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  else
                    const Icon(Icons.check_circle_rounded, color: Color(0xFFE83D66), size: 22),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 2. Family & Friends Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('FAMILY & FRIENDS KUNDLIS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                    SizedBox(height: 2),
                    Text('Multiple Profiles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddFamilyDialog(context),
                  icon: const Icon(Icons.add, size: 16, color: Colors.white),
                  label: const Text('Add Member', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Family Members List
            if (_isLoadingFamily)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else if (familyMembers.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.people_outline_rounded, size: 36, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('No Family Kundlis Added Yet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
                    const SizedBox(height: 4),
                    Text('Create Kundlis for your spouse, children, parents, or friends under your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _showAddFamilyDialog(context),
                      child: const Text('+ Add First Family Kundli'),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: familyMembers.length,
                itemBuilder: (context, index) {
                  final member = familyMembers[index];
                  final isSelected = selectedFamily != null && selectedFamily['id'] == member['id'];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                              child: Icon(
                                _getRelationshipIcon(member['relationship']),
                                color: const Color(0xFF6C63FF),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        member['fullName'] ?? 'Family Member',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          member['relationship'] ?? 'Family',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${member['dateOfBirth']} · ${member['placeOfBirth']}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                             Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 IconButton(
                                   icon: Icon(
                                     isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                     color: isSelected ? const Color(0xFF6C63FF) : Colors.grey,
                                   ),
                                   onPressed: () {
                                     if (isSelected) {
                                       backendService.selectFamilyMember(null);
                                     } else {
                                       backendService.selectFamilyMember(member);
                                     }
                                   },
                                 ),
                                 IconButton(
                                   icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                   onPressed: () async {
                                     final confirm = await showDialog<bool>(
                                       context: context,
                                       builder: (ctx) => AlertDialog(
                                         title: const Text('Delete Profile'),
                                         content: Text('Are you sure you want to delete ${member['fullName']}\'s profile?'),
                                         actions: [
                                           TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                           TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                         ],
                                       ),
                                     );
                                     if (confirm == true && member['id'] != null) {
                                       await backendService.deleteFamilyKundli(member['id']);
                                       _loadFamilyMembers();
                                     }
                                   },
                                 ),
                               ],
                             ),
                          ],
                        ),

                        if (member['kundli'] != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCF7F1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Lagna: ${member['kundli']['ascendant'] ?? 'Aries'}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                                Text(
                                  'Moon: ${member['kundli']['moonSign'] ?? 'Taurus'}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD95D39)),
                                ),
                                Text(
                                  'Nakshatra: ${member['kundli']['nakshatra'] ?? 'Rohini'}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF673AB7)),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  backendService.selectFamilyMember(member);
                                  Navigator.pushNamed(context, '/kundli-view');
                                },
                                icon: const Icon(Icons.pie_chart_outline_rounded, size: 14),
                                label: const Text('View Chart', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  backendService.selectFamilyMember(member);
                                  Navigator.pushNamed(context, '/chatbot', arguments: {
                                    'name': 'Family Astro Specialist',
                                    'specialty': '${member['relationship']} Chart Guidance',
                                    'field': 'Family Consultation',
                                    'initialMessage': 'Please provide Kundli astrological guidance for my ${member['relationship']}, ${member['fullName']}.',
                                  });
                                },
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.white),
                                label: const Text('Ask AI Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C63FF),
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 24),

            // 3. Navigation List
            const Text('ACCOUNT OPTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 10),

            _buildMenuItem(
              context,
              icon: Icons.auto_awesome_rounded,
              title: 'Detailed Vedic Kundli Report',
              subtitle: 'Ascendant, Moon Sign, Dasha & Planetary Strength',
              color: const Color(0xFF7C77E6),
              onTap: () => Navigator.pushNamed(context, '/kundli-view'),
            ),

            _buildMenuItem(
              context,
              icon: Icons.edit_calendar_rounded,
              title: 'Edit Primary Birth Details',
              subtitle: 'Update Date, Time, and Place of Birth',
              color: const Color(0xFFFB9548),
              onTap: () => Navigator.pushNamed(context, '/birth-details'),
            ),

            _buildMenuItem(
              context,
              icon: Icons.account_balance_wallet_rounded,
              title: 'Astro Wallet & Bonus',
              subtitle: 'Current Balance: ₹0 (Unlimited AI Pass)',
              color: const Color(0xFF6B1A3A),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Free unlimited AI chat bonus active!')),
                );
              },
            ),

            _buildMenuItem(
              context,
              icon: Icons.chat_rounded,
              title: 'AI Kundli Chat',
              subtitle: '24/7 Personal Astro Assistant',
              color: const Color(0xFFE83D66),
              onTap: () => Navigator.pushNamed(context, '/chatbot'),
            ),

            const SizedBox(height: 20),

            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await backendService.logout();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                label: const Text(
                  'Log Out',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  IconData _getRelationshipIcon(String? relationship) {
    final rel = (relationship ?? '').toLowerCase();
    if (rel.contains('spouse') || rel.contains('wife') || rel.contains('husband')) return Icons.favorite_rounded;
    if (rel.contains('son') || rel.contains('child') || rel.contains('boy')) return Icons.face_rounded;
    if (rel.contains('daughter') || rel.contains('girl')) return Icons.face_3_rounded;
    if (rel.contains('father') || rel.contains('dad')) return Icons.man_rounded;
    if (rel.contains('mother') || rel.contains('mom')) return Icons.woman_rounded;
    if (rel.contains('brother') || rel.contains('sister')) return Icons.people_rounded;
    return Icons.handshake_rounded;
  }

  void _showAddFamilyDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const FamilyBirthDetailsSheet(),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
      ),
    );
  }
}

class FamilyBirthDetailsSheet extends StatefulWidget {
  const FamilyBirthDetailsSheet({super.key});

  @override
  State<FamilyBirthDetailsSheet> createState() => _FamilyBirthDetailsSheetState();
}

class _FamilyBirthDetailsSheetState extends State<FamilyBirthDetailsSheet> {
  int _currentStep = 0; // 0: Relationship, 1: Name & Gender, 2: DOB & TOB, 3: Place of Birth

  String _relationship = 'Spouse';
  final TextEditingController _nameController = TextEditingController();
  String _gender = 'Female';

  DateTime? _selectedDate = DateTime(1998, 8, 15);
  TimeOfDay? _selectedTime = const TimeOfDay(hour: 10, minute: 30);
  bool _dontKnowTime = false;

  final TextEditingController _placeController = TextEditingController(text: 'New Delhi, India');
  List<CitySuggestion> _placeSuggestions = [];
  bool _isSearchingPlace = false;
  Timer? _debounceTimer;
  double? _selectedLatitude;
  double? _selectedLongitude;

  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _relationshipsList = [
    {'label': 'Spouse', 'icon': Icons.favorite_rounded},
    {'label': 'Son', 'icon': Icons.face_rounded},
    {'label': 'Daughter', 'icon': Icons.face_3_rounded},
    {'label': 'Father', 'icon': Icons.man_rounded},
    {'label': 'Mother', 'icon': Icons.woman_rounded},
    {'label': 'Sibling', 'icon': Icons.people_rounded},
    {'label': 'Friend', 'icon': Icons.handshake_rounded},
  ];

  @override
  void initState() {
    super.initState();
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
      initialDate: _selectedDate ?? DateTime(1998, 8, 15),
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
    if (_currentStep == 1 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter family member name')),
      );
      return;
    }

    if (_currentStep == 2 && _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date of birth')),
      );
      return;
    }

    if (_currentStep < 3) {
      setState(() {
        _currentStep++;
      });
    } else {
      _submitFamilyDetails();
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

  Future<void> _submitFamilyDetails() async {
    final name = _nameController.text.trim().isEmpty ? 'Family Member' : _nameController.text.trim();
    final dob = _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : '1998-08-15';
    final tob = _dontKnowTime || _selectedTime == null
        ? '12:00'
        : "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}";
    final place = _placeController.text.trim().isEmpty ? 'New Delhi, India' : _placeController.text.trim();

    setState(() => _isSubmitting = true);

    final backendService = Provider.of<BackendService>(context, listen: false);

    final member = await backendService.addFamilyKundli(
      relationship: _relationship,
      fullName: name,
      gender: _gender,
      dateOfBirth: dob,
      timeOfBirth: tob,
      placeOfBirth: place,
    );

    setState(() => _isSubmitting = false);

    if (mounted) {
      Navigator.pop(context);
      if (member != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved Kundli for ${member['fullName']} (${member['relationship']})!')),
        );
      }
    }
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
      height: MediaQuery.of(context).size.height * 0.90,
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
    double progress = (_currentStep + 1) / 4.0;
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
        return _buildRelationshipStep();
      case 1:
        return _buildNameAndGenderStep();
      case 2:
        return _buildBirthDetailsStep();
      case 3:
        return _buildBirthPlaceStep();
      default:
        return _buildRelationshipStep();
    }
  }

  // Step 0: Relationship Selection
  Widget _buildRelationshipStep() {
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
            child: Icon(Icons.people_outline_rounded, size: 44, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Who is this Kundli for?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select relationship to customize astronomical chart insights',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: _relationshipsList.map((rel) {
            final isSelected = _relationship == rel['label'];
            return GestureDetector(
              onTap: () => setState(() => _relationship = rel['label'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.black.withValues(alpha: 0.1),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      rel['icon'] as IconData,
                      color: isSelected ? Colors.black : Colors.grey.shade700,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        rel['label'] as String,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // Step 1: Name & Gender Input
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
            child: Icon(Icons.person, size: 44, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '${_relationship} Name & Gender',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We calculate exact Lagna, Moon Sign & planetary placements',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Full Name',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'e.g. Ananya Sharma',
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
            'Gender',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildGenderCard('Male', '♂'),
            const SizedBox(width: 10),
            _buildGenderCard('Female', '♀'),
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

  // Step 2: Date & Time of Birth
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
          'Date & Time of Birth',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Accurate date and time determine house divisions and dashas',
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
              "I don't know the exact time of birth",
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
      ],
    );
  }

  // Step 3: Place of Birth Step
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
          'Place of Birth',
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
            hintText: 'e.g. New Delhi, India',
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
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  _currentStep == 3 ? 'Generate AI Kundli Chart' : 'Continue',
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
