import 'package:flutter/widgets.dart';

/// Web / unsupported platforms: Clarity is not available, everything passes through.
Widget wrapWithClarity(Widget app) => app;

/// Hides [child] from session recordings.
Widget clarityPrivate(Widget child) => child;

/// Allows [child] to be recorded inside a private (masked) area.
Widget clarityPublic(Widget child) => child;

void claritySetUserId(String id) {}

void claritySetScreen(String? name) {}
