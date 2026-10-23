import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// Renders Google's sign-in button. Signing in through it is reported on
/// `GoogleSignIn.instance.authenticationEvents`.
Widget buildGoogleWebButton() => gsi.renderButton(
      configuration: gsi.GSIButtonConfiguration(
        type: gsi.GSIButtonType.standard,
        theme: gsi.GSIButtonTheme.outline,
        size: gsi.GSIButtonSize.large,
        text: gsi.GSIButtonText.continueWith,
        shape: gsi.GSIButtonShape.rectangular,
        minimumWidth: 300,
      ),
    );
