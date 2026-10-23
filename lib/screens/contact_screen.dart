import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/ui/app_ui.dart';

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

  /// The phone / WhatsApp number above is a placeholder, so Call and WhatsApp
  /// options are hidden. Set the real number and flip this to `true` to show them.
  static const bool phoneSupportEnabled = false;

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
          label: 'Copy',
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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  String _topic = 'General question';
  bool _sending = false;

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

    setState(() => _sending = true);
    // Messages are sent through the user's email app so they reach support
    // directly; failures fall back to a snackbar with the address.
    await CosmicGuideContact.email(
      context,
      subject: '[CosmicGuide] $_topic',
      body: body.toString(),
    );
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Contact us')),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: AppButton(
            label: 'Send message',
            icon: Icons.send_rounded,
            loading: _sending,
            onPressed: _submitForm,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.lg, AppSpacing.page, AppSpacing.xl),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const Text('How can we help?', style: AppText.headline),
          const SizedBox(height: 6),
          const Text(
            'Questions about your Kundli, a consultation or your wallet? Reach the CosmicGuide team directly.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppListRow(
                  icon: Icons.mail_outline_rounded,
                  color: AppColors.primary,
                  title: 'Email us',
                  subtitle: CosmicGuideContact.supportEmail,
                  onTap: () => CosmicGuideContact.email(context, subject: '[CosmicGuide] Support request'),
                ),
                if (CosmicGuideContact.phoneSupportEnabled) ...[
                  const Divider(indent: 68),
                  AppListRow(
                    icon: Icons.phone_outlined,
                    color: AppColors.info,
                    title: 'Call us',
                    subtitle: CosmicGuideContact.phoneDisplay,
                    onTap: () => CosmicGuideContact.call(context),
                  ),
                  const Divider(indent: 68),
                  AppListRow(
                    icon: Icons.chat_outlined,
                    color: AppColors.success,
                    title: 'WhatsApp',
                    subtitle: 'Chat with support',
                    onTap: () => CosmicGuideContact.whatsapp(context),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Row(
            children: [
              SizedBox(width: 4),
              Icon(Icons.schedule_rounded, size: 14, color: AppColors.textTertiary),
              SizedBox(width: 6),
              Expanded(
                child: Text('Support hours: ${CosmicGuideContact.supportHours}', style: AppText.caption),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const Text('Send us a message', style: AppText.title),
          const SizedBox(height: 4),
          const Text('Your message opens in your email app, ready to send.', style: AppText.caption),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _topic,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Topic', prefixIcon: Icon(Icons.topic_outlined)),
                    items: _topics
                        .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _topic = v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter your name' : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return 'Please enter your email';
                      if (!RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(v)) return 'Please enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                      LengthLimitingTextInputFormatter(16),
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Phone number (optional)', prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _messageController,
                    maxLines: 5,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      hintText: 'Tell us what happened and when',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return 'Please enter your message';
                      if (v.length < 10) return 'Please add a few more details';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
