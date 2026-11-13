import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const String _projectId = 'zd2pwbff3d';

/// Starts Clarity around the whole app. Use LogLevel.Verbose temporarily to debug setup.
Widget wrapWithClarity(Widget app) => ClarityWidget(
      app: app,
      clarityConfig: ClarityConfig(
        projectId: _projectId,
        logLevel: kReleaseMode ? LogLevel.None : LogLevel.Info,
      ),
    );

/// Hides [child] from session recordings (shown as blocked-out boxes).
Widget clarityPrivate(Widget child) => ClarityMask(child: child);

/// Allows [child] to be recorded inside a private (masked) area.
Widget clarityPublic(Widget child) => ClarityUnmask(child: child);

/// Links recordings to the backend user id (a number, never an email).
void claritySetUserId(String id) {
  try {
    Clarity.setCustomUserId(id);
  } catch (_) {}
}

/// Names the current screen in recordings and heatmaps.
void claritySetScreen(String? name) {
  try {
    Clarity.setCurrentScreenName(name);
  } catch (_) {}
}
