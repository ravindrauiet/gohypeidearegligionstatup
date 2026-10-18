// Google's own "Continue with Google" button. On the web, Google Sign-In only
// works through this rendered button; on other platforms it is never shown.
export 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';
