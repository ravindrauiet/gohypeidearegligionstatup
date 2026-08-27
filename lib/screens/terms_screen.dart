import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: const Color(0xFF8B0000),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              'Acceptance of Terms',
              [
                'By using PujaKaro app, you agree to these terms',
                'These terms apply to all users of the service',
                'We may modify these terms at any time',
                'Continued use constitutes acceptance of changes',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Service Description',
              [
                'PujaKaro provides puja booking services',
                'We connect users with qualified pujaris',
                'Services include various types of pujas',
                'We also offer astrology and consultation services',
                'Product sales for puja materials and items',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'User Responsibilities',
              [
                'Provide accurate and complete information',
                'Maintain the security of your account',
                'Comply with all applicable laws',
                'Respect the rights of other users',
                'Report any suspicious activities',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Booking and Cancellation',
              [
                'Bookings are confirmed upon payment',
                'Cancellation policy varies by service type',
                'Refunds processed according to our policy',
                'Rescheduling may be possible with advance notice',
                'No-shows may result in charges',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Payment Terms',
              [
                'All prices are in Indian Rupees (INR)',
                'Payment required at time of booking',
                'We accept major credit/debit cards and UPI',
                'Secure payment processing guaranteed',
                'Taxes and fees included in displayed prices',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Limitation of Liability',
              [
                'We are not liable for indirect damages',
                'Maximum liability limited to service amount',
                'Force majeure events excluded',
                'Third-party service provider issues',
                'User responsibility for personal safety',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Intellectual Property',
              [
                'App content and design are our property',
                'User-generated content remains user property',
                'No unauthorized copying or distribution',
                'Trademarks and logos protected',
                'Respect for third-party intellectual property',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Governing Law',
              [
                'These terms governed by Indian law',
                'Disputes resolved in Indian courts',
                'Arbitration may be required for certain disputes',
                'Jurisdiction in [Your City], India',
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'These terms of service were last updated on January 1, 2025. For questions about these terms, please contact us at legal@pujakaro.com',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<String> items) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8B0000),
              ),
            ),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.description, color: Color(0xFF8B0000), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
