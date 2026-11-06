import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notification_service.dart';
import '../../widgets/ui/app_ui.dart';

/// Notification settings: master switch, per-category toggles and the daily
/// horoscope time. Stored locally; buddy / messages / trips / rewards /
/// announcements are also synced to the server (they gate push sends).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationService>().refreshPermission();
    });
  }

  String _timeLabel(NotificationPrefs p) {
    final (h, m) = NotificationSchedule.horoscopeSlot(p);
    return MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay(hour: h, minute: m));
  }

  Future<void> _pickTime(NotificationService s) async {
    final (h, m) = NotificationSchedule.horoscopeSlot(s.prefs);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      helpText: 'Daily horoscope time (10 AM – 12 PM)',
    );
    if (picked == null || !mounted) return;
    // Morning reminders stay between 10:00 and 12:00 IST.
    final mins = (picked.hour * 60 + picked.minute).clamp(10 * 60, 12 * 60);
    await s.updatePrefs(s.prefs.copyWith(horoscopeHour: mins ~/ 60, horoscopeMinute: mins % 60));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<NotificationService>();
    final p = s.prefs;
    final registered = s.registered;
    final on = p.master;

    void set(NotificationPrefs next) => s.updatePrefs(next);

    Widget toggle({
      required Key key,
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
      bool enabled = true,
    }) {
      final active = on && enabled;
      return SwitchListTile(
        key: key,
        value: value && active,
        onChanged: active ? onChanged : null,
        secondary: Icon(icon, color: active ? AppColors.primary : AppColors.textTertiary),
        title: Text(title, style: AppText.bodyStrong),
        subtitle: Text(subtitle, style: AppText.caption.copyWith(color: AppColors.textSecondary)),
        activeThumbColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      );
    }

    Widget group(String title, List<Widget> children, {String? footer}) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xxs, bottom: AppSpacing.xs),
              child: Text(title.toUpperCase(), style: AppText.overline),
            ),
            AppCard(padding: EdgeInsets.zero, child: Column(children: children)),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xxs, AppSpacing.xs, AppSpacing.xxs, 0),
                child: Text(footer, style: AppText.caption),
              ),
          ]),
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.xxl),
        children: [
          if (s.permissionGranted == false) _PermissionBanner(onTurnOn: s.turnOnFromSettings),
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              key: const Key('notif_master'),
              value: on,
              onChanged: (v) => set(p.copyWith(master: v)),
              secondary: Icon(on ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                  color: on ? AppColors.primary : AppColors.textTertiary),
              title: const Text('Allow notifications', style: AppText.bodyStrong),
              subtitle: Text(
                  on ? 'You will get the alerts you choose below' : 'All CosmicGuide notifications are paused',
                  style: AppText.caption.copyWith(color: AppColors.textSecondary)),
              activeThumbColor: AppColors.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
          ),
          group('Reminders', [
            toggle(
              key: const Key('notif_horoscope'),
              icon: Icons.wb_sunny_outlined,
              title: 'Daily horoscope',
              subtitle: 'Your personal guidance every morning',
              value: p.horoscope,
              onChanged: (v) => set(p.copyWith(horoscope: v)),
            ),
            ListTile(
              key: const Key('notif_horoscope_time'),
              enabled: on && p.horoscope,
              leading: const SizedBox(width: 24),
              title: const Text('Delivery time', style: AppText.body),
              trailing: Text(_timeLabel(p),
                  style: AppText.bodyStrong
                      .copyWith(color: on && p.horoscope ? AppColors.primary : AppColors.textTertiary)),
              onTap: on && p.horoscope ? () => _pickTime(s) : null,
            ),
            toggle(
              key: const Key('notif_checkin'),
              icon: Icons.toll_outlined,
              title: 'Check-in reminders',
              subtitle: registered ? 'Evening reminder to keep your coin streak' : 'Log in to earn daily coins',
              value: p.checkin,
              enabled: registered,
              onChanged: (v) => set(p.copyWith(checkin: v)),
            ),
            toggle(
              key: const Key('notif_festivals'),
              icon: Icons.celebration_outlined,
              title: 'Festivals & vrat days',
              subtitle: 'The evening before and the morning of',
              value: p.festivals,
              onChanged: (v) => set(p.copyWith(festivals: v)),
            ),
            toggle(
              key: const Key('notif_nudges'),
              icon: Icons.auto_awesome_outlined,
              title: 'Gentle nudges',
              subtitle: 'Weekly mindset questions and a hello when you have been away',
              value: p.nudges,
              onChanged: (v) => set(p.copyWith(nudges: v)),
            ),
          ]),
          group(
            'Buddies & updates',
            [
              toggle(
                key: const Key('notif_buddy'),
                icon: Icons.person_add_alt_outlined,
                title: 'Buddy requests',
                subtitle: 'New requests and accepted connections',
                value: p.buddy,
                enabled: registered,
                onChanged: (v) => set(p.copyWith(buddy: v)),
              ),
              toggle(
                key: const Key('notif_messages'),
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Messages',
                subtitle: 'When a buddy sends you a message',
                value: p.messages,
                enabled: registered,
                onChanged: (v) => set(p.copyWith(messages: v)),
              ),
              toggle(
                key: const Key('notif_trips'),
                icon: Icons.temple_hindu_outlined,
                title: 'Trip updates',
                subtitle: 'Status changes for your temple trips',
                value: p.trips,
                enabled: registered,
                onChanged: (v) => set(p.copyWith(trips: v)),
              ),
              toggle(
                key: const Key('notif_announcements'),
                icon: Icons.campaign_outlined,
                title: 'Announcements',
                subtitle: 'News and offers from CosmicGuide',
                value: p.announcements,
                enabled: registered,
                onChanged: (v) => set(p.copyWith(announcements: v)),
              ),
            ],
            footer: registered ? null : 'Log in to get buddy, message, trip and announcement alerts.',
          ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final Future<void> Function() onTurnOn;
  const _PermissionBanner({required this.onTurnOn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        key: const Key('notif_permission_banner'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warningSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.notifications_off_rounded, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Notifications are off', style: AppText.bodyStrong),
              SizedBox(height: 2),
              Text('Allow them in your phone settings to get reminders.', style: AppText.caption),
            ]),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: onTurnOn, child: const Text('Turn on')),
        ]),
      ),
    );
  }
}
