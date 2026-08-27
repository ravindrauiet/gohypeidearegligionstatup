import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: const Color(0xFF8B0000),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              'Information We Collect',
              [
                'Personal information (name, email, phone number)',
                'Address and location details for puja services',
                'Payment information (processed securely)',
                'Service preferences and booking history',
                'Device information and app usage data',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'How We Use Your Information',
              [
                'To provide puja booking services',
                'To process payments and transactions',
                'To communicate about your bookings',
                'To improve our services and user experience',
                'To send relevant updates and offers (with consent)',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Information Sharing',
              [
                'We do not sell your personal information',
                'Information shared only with service providers',
                'Legal requirements may require disclosure',
                'Your consent is required for marketing communications',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Data Security',
              [
                'Encryption of sensitive data',
                'Secure payment processing',
                'Regular security audits',
                'Limited access to personal information',
                'Compliance with data protection regulations',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Your Rights',
              [
                'Access your personal information',
                'Correct inaccurate data',
                'Request deletion of your data',
                'Opt-out of marketing communications',
                'Data portability',
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              'Contact Us',
              [
                'For privacy-related questions: privacy@pujakaro.com',
                'Data Protection Officer: dpo@pujakaro.com',
                'Phone: +91 98765 43210',
                'Address: [Your Company Address]',
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
                'This privacy policy was last updated on January 1, 2025. We may update this policy from time to time, and we will notify you of any changes.',
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
                  const Icon(Icons.privacy_tip, color: Color(0xFF8B0000), size: 16),
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
