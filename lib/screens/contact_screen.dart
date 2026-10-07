import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Single source of truth for CosmicGuide support contact details.
/// Used by Contact, Help, Privacy and Terms screens.
class CosmicGuideContact {
  CosmicGuideContact._();

  static const String appName = 'CosmicGuide';
  static const String supportEmail = 'support@cosmicguide.app';
  static const String privacyEmail = 'privacy@cosmicguide.app';
  static const String phoneDisplay = '+91 98765 43210';
  static const String phoneE164 = '+919876543210';
  static const String whatsappNumber = '919876543210';
  static const String supportHours = '9:00 AM – 8:00 PM IST, all days';

  static Future<void> email(BuildContext context, {String? to, String? subject, String? body}) {
    final address = to ?? supportEmail;
    final query = <String, String>{
      if (subject != null) 'subject': subject,
      if (body != null) 'body': body,
    };
    final uri = Uri(
      scheme: 'mailto',
      path: address,
      // Encode manually: Uri's queryParameters uses '+' for spaces, which
      // many mail apps show literally.
      query: query.isEmpty
          ? null
          : query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&'),
    );
    return _launch(context, uri, fallbackLabel: 'email address', fallbackValue: address);
  }

  static Future<void> call(BuildContext context) {
    return _launch(context, Uri(scheme: 'tel', path: phoneE164), fallbackLabel: 'phone number', fallbackValue: phoneDisplay);
  }

  static Future<void> whatsapp(BuildContext context, {String message = 'Namaste CosmicGuide team, I need help with '}) {
    final uri = Uri.parse('https://wa.me/$whatsappNumber?text=${Uri.encodeComponent(message)}');
    return _launch(context, uri, fallbackLabel: 'WhatsApp number', fallbackValue: phoneDisplay);
  }

  static Future<void> _launch(
    BuildContext context,
    Uri uri, {
    required String fallbackLabel,
    required String fallbackValue,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (launched || messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not open an app for this. Our $fallbackLabel is $fallbackValue'),
        action: SnackBarAction(
          label: 'COPY',
          onPressed: () => Clipboard.setData(ClipboardData(text: fallbackValue)),
        ),
      ),
    );
  }
}

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  static const Color _accent = Color(0xFFFB9548);
  static const Color _text = Color(0xFF5F4B32);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  String _topic = 'General question';

  static const List<String> _topics = [
    'General question',
    'Kundli / birth chart',
    'Live Pandit consultation',
    'Wallet & payments',
    'Account & privacy',
    'Feedback',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = _phoneController.text.trim();
    final body = StringBuffer()
      ..writeln(_messageController.text.trim())
      ..writeln()
      ..writeln('---')
      ..writeln('Name: ${_nameController.text.trim()}')
      ..writeln('Email: ${_emailController.text.trim()}');
    if (phone.isNotEmpty) body.writeln('Phone: $phone');

    // Messages are sent through the user's email app so they reach support
    // directly; failures fall back to a snackbar with the address.
    await CosmicGuideContact.email(
      context,
      subject: '[CosmicGuide] $_topic',
      body: body.toString(),
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _accent),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFCF7F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          tooltip: 'Back',
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Contact Us', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Get in Touch',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 8),
              const Text(
                'Questions about your Kundli, a consultation or your wallet? The CosmicGuide team is happy to help.',
                style: TextStyle(fontSize: 15, color: _text, height: 1.5),
              ),
              const SizedBox(height: 20),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _accent.withValues(alpha: 0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildContactAction(
                      icon: Icons.email_rounded,
                      title: 'Email',
                      content: CosmicGuideContact.supportEmail,
                      onTap: () => CosmicGuideContact.email(context, subject: '[CosmicGuide] Support request'),
                    ),
                    const Divider(height: 1),
                    _buildContactAction(
                      icon: Icons.phone_rounded,
                      title: 'Phone',
                      content: CosmicGuideContact.phoneDisplay,
                      onTap: () => CosmicGuideContact.call(context),
                    ),
                    const Divider(height: 1),
                    _buildContactAction(
                      icon: Icons.chat_rounded,
                      title: 'WhatsApp',
                      content: 'Chat with support',
                      onTap: () => CosmicGuideContact.whatsapp(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 14, color: Colors.grey),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Support hours: ${CosmicGuideContact.supportHours}',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              const Text(
                'Send us a Message',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your message opens in your email app, ready to send.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _topic,
                      isExpanded: true,
                      decoration: _decoration('Topic', Icons.topic_outlined),
                      items: _topics.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _topic = v);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Full Name', Icons.person_outline),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter your name' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _decoration('Email', Icons.alternate_email),
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'Please enter your email';
                        if (!RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(v)) return 'Please enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')), LengthLimitingTextInputFormatter(16)],
                      decoration: _decoration('Phone Number (Optional)', Icons.phone_outlined),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _messageController,
                      maxLines: 5,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _decoration('Message', Icons.message_outlined).copyWith(alignLabelWithHint: true),
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'Please enter your message';
                        if (v.length < 10) return 'Please add a few more details';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _submitForm,
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        label: const Text('Send Message', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactAction({
    required IconData icon,
    required String title,
    required String content,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: _accent.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: _accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black)),
                    const SizedBox(height: 2),
                    Text(content, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _text)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
