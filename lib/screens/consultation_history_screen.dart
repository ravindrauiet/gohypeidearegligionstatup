import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backend_service.dart';

class ConsultationHistoryScreen extends StatefulWidget {
  const ConsultationHistoryScreen({super.key});

  @override
  State<ConsultationHistoryScreen> createState() => _ConsultationHistoryScreenState();
}

class _ConsultationHistoryScreenState extends State<ConsultationHistoryScreen> {
  bool _isLoading = true;
  List _history = [];
  List _prescriptions = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final backendService = Provider.of<BackendService>(context, listen: false);
    final data = await backendService.fetchConsultationHistory();

    if (mounted) {
      setState(() {
        if (data != null) {
          _history = data['history'] ?? [];
          _prescriptions = data['prescriptions'] ?? [];
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFFCF7F1),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFCF7F1),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Consultation History & Remedies',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          bottom: const TabBar(
            labelColor: Color(0xFFE83D66),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFFE83D66),
            tabs: [
              Tab(text: 'Past Consultations'),
              Tab(text: 'Prescribed Remedies'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE83D66)))
            : TabBarView(
                children: [
                  // Tab 1: Past Consultations
                  ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _history.isEmpty ? 1 : _history.length,
                    itemBuilder: (context, index) {
                      if (_history.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('No past consultations found yet.', style: TextStyle(color: Colors.grey)),
                          ),
                        );
                      }

                      final item = _history[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundImage: NetworkImage(item['avatar_url'] ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80'),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['pandit_name'] ?? 'Pt. Rishiraj Sharma',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      Text(
                                        item['specialty'] ?? 'Vedic Kundli Advisor',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFFD95D39), fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text('Completed', style: TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Rate: ₹${item['rate_per_min'] ?? 21}/min', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const Text('Total Billed: ₹105.00', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Tab 2: Prescribed Remedies Cards
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E1A38), Color(0xFF2E2452)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFFFD700)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Row(
                              children: [
                                Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD700), size: 20),
                                SizedBox(width: 8),
                                Text('PRESCRIBED VEDIC REMEDY CARD', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                              ],
                            ),
                            SizedBox(height: 12),
                            Text('💎 Gemstone: Yellow Sapphire (Pukhraj) 5.25 Ratti in Gold Ring', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            SizedBox(height: 6),
                            Text('🕉️ Mantra: Om Gram Greem Groum Sah Gurave Namah (108x daily)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            SizedBox(height: 6),
                            Text('🌿 Ritual: Offer Yellow Flowers & Chana Dal on Thursday mornings', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            SizedBox(height: 10),
                            Text('Prescribed by Pt. Rishiraj Sharma · 15 August 2026', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
