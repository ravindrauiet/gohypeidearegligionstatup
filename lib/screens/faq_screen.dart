import 'package:flutter/material.dart';

class FAQScreen extends StatefulWidget {
  const FAQScreen({Key? key}) : super(key: key);

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  final List<FAQItem> _faqItems = [
    FAQItem(
      question: 'How do I book a puja?',
      answer: 'To book a puja, simply browse our catalog, select your preferred puja, choose a date and time, fill in your details, and complete the payment. You\'ll receive a confirmation email with all the details.',
    ),
    FAQItem(
      question: 'What payment methods do you accept?',
      answer: 'We accept all major credit/debit cards, UPI payments, net banking, and digital wallets. All payments are processed securely through our payment gateway.',
    ),
    FAQItem(
      question: 'Can I cancel or reschedule my booking?',
      answer: 'Yes, you can cancel or reschedule your booking up to 24 hours before the scheduled time. Cancellation policies and refund amounts vary depending on the service type.',
    ),
    FAQItem(
      question: 'Are your pujaris qualified and experienced?',
      answer: 'Absolutely! All our pujaris are certified, experienced, and follow traditional practices. They undergo regular training and quality checks to ensure the highest standards.',
    ),
    FAQItem(
      question: 'What if I\'m not satisfied with the service?',
      answer: 'Customer satisfaction is our priority. If you\'re not satisfied, please contact us within 24 hours of the service completion. We\'ll address your concerns and provide appropriate solutions.',
    ),
    FAQItem(
      question: 'Do you provide puja materials?',
      answer: 'Yes, we offer a complete range of puja materials and items through our shop. You can purchase everything you need for your puja in one place.',
    ),
    FAQItem(
      question: 'How far in advance should I book?',
      answer: 'We recommend booking at least 3-5 days in advance, especially for popular dates and festivals. However, we can accommodate last-minute bookings based on availability.',
    ),
    FAQItem(
      question: 'Do you provide astrology services?',
      answer: 'Yes, we offer comprehensive astrology services including birth chart analysis, daily horoscopes, and personalized consultations with experienced astrologers.',
    ),
    FAQItem(
      question: 'What areas do you serve?',
      answer: 'We currently serve major cities across India. Please check our service area coverage or contact us to confirm availability in your location.',
    ),
    FAQItem(
      question: 'How can I track my order?',
      answer: 'Once your booking is confirmed, you\'ll receive tracking details via email and SMS. You can also track your order status through our app or website.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Frequently Asked Questions'),
        backgroundColor: const Color(0xFF8B0000),
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _faqItems.length,
        itemBuilder: (context, index) {
          return _buildFAQItem(_faqItems[index]);
        },
      ),
    );
  }

  Widget _buildFAQItem(FAQItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        title: Text(
          item.question,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8B0000),
          ),
        ),
        iconColor: const Color(0xFF8B0000),
        collapsedIconColor: const Color(0xFF8B0000),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              item.answer,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FAQItem {
  final String question;
  final String answer;

  FAQItem({
    required this.question,
    required this.answer,
  });
}
