import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/buddy_service.dart';
import '../rewards/mindset_quiz_screen.dart';
import '../rewards/temple_trip_screen.dart';

/// Links from the buddy feature to screens owned by other features (the
/// mindset quiz and temple trips), kept in one place.
class BuddyLinks {
  BuddyLinks._();

  /// The quiz screen; overridable (e.g. in tests). Null hides quiz CTAs.
  static WidgetBuilder? mindsetQuizBuilder = (_) => const MindsetQuizScreen();

  /// The temple-trip screen for a buddy; null hides the chat action.
  static Widget Function(BuildContext context, int buddyId)? templeTripBuilder =
      (_, id) => TempleTripScreen(buddyId: id);

  static bool get hasMindsetQuiz => mindsetQuizBuilder != null;
  static bool get hasTempleTrip => templeTripBuilder != null;

  /// Opens the 50 mindset questions, then refreshes the buddy status so the
  /// answered count (and match quality) is up to date.
  static Future<void> openMindsetQuiz(BuildContext context) async {
    final b = mindsetQuizBuilder;
    if (b == null) return;
    final service = context.read<BuddyService>();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: b));
    try {
      await service.loadStatus(force: true);
    } catch (_) {}
  }

  static Future<void> openTempleTrip(BuildContext context, int buddyId) async {
    final b = templeTripBuilder;
    if (b == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (ctx) => b(ctx, buddyId)));
  }
}
