import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/notifications/notification_inbox_screen.dart';
import '../../services/notification_inbox_service.dart';
import '../ui/app_ui.dart';

/// Bell button with a red unread badge for the Home hero header. Opens
/// [NotificationInboxScreen]; refreshes the unread count on mount, on app
/// resume and when coming back from the inbox. Renders nothing when no
/// [NotificationInboxService] is provided.
class NotificationBell extends StatefulWidget {
  /// Translucent style for dark (cosmic) headers.
  final bool onDark;

  /// Overrides the default tap (push the inbox).
  final VoidCallback? onTap;

  const NotificationBell({super.key, this.onDark = true, this.onTap});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with WidgetsBindingObserver {
  NotificationInboxService? _read() {
    try {
      return Provider.of<NotificationInboxService>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_read()?.refreshUnread());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) unawaited(_read()?.refreshUnread());
  }

  Future<void> _open() async {
    if (widget.onTap != null) return widget.onTap!();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationInboxScreen()));
    if (mounted) unawaited(_read()?.refreshUnread(force: true));
  }

  @override
  Widget build(BuildContext context) {
    NotificationInboxService? svc;
    try {
      svc = Provider.of<NotificationInboxService>(context);
    } on ProviderNotFoundException {
      svc = null;
    }
    if (svc == null) return const SizedBox.shrink();
    final count = svc.signedIn ? svc.unread : 0;
    return NotificationBellButton(count: count, onDark: widget.onDark, onTap: _open);
  }
}

/// Stateless visual part of [NotificationBell] (bell + badge, 48dp target).
class NotificationBellButton extends StatelessWidget {
  final int count;
  final bool onDark;
  final VoidCallback onTap;

  const NotificationBellButton({super.key, required this.count, required this.onTap, this.onDark = true});

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    final fg = onDark ? Colors.white : AppColors.textPrimary;
    return Semantics(
      button: true,
      label: has ? 'Notifications, $count unread' : 'Notifications',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: SizedBox(
          width: 44,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: onDark ? Colors.white.withValues(alpha: 0.12) : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: onDark ? Colors.white.withValues(alpha: 0.28) : AppColors.border),
                ),
                child: Icon(has ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                    color: fg, size: 22),
              ),
              if (has)
                Positioned(
                  top: 2,
                  right: -4,
                  child: MediaQuery.withNoTextScaling(
                    child: Container(
                      key: const ValueKey('notification-badge'),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: onDark ? AppColors.cosmic : Colors.white, width: 1.5),
                      ),
                      child: Text(
                        inboxBadgeText(count),
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 10, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
