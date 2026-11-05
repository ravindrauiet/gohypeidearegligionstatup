import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/buddy_service.dart';

/// Keeps [BuddyService.badgeCount] fresh while [child] (the home screen) is
/// mounted: on start, on every resume, and every
/// [BuddyService.badgeRefreshInterval] while the app is in the foreground.
/// Stops completely in the background. Calls are throttled by the service.
class BuddyBadgeScope extends StatefulWidget {
  final Widget child;

  /// Overridable for tests.
  final Duration interval;

  const BuddyBadgeScope({super.key, required this.child, this.interval = BuddyService.badgeRefreshInterval});

  @override
  State<BuddyBadgeScope> createState() => _BuddyBadgeScopeState();
}

class _BuddyBadgeScopeState extends State<BuddyBadgeScope> with WidgetsBindingObserver {
  late final BuddyService _service;

  @override
  void initState() {
    super.initState();
    _service = context.read<BuddyService>();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame so app start isn't slowed down.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _service.startBadgeUpdates(interval: widget.interval);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _service.startBadgeUpdates(interval: widget.interval);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _service.stopBadgeUpdates();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.stopBadgeUpdates();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
