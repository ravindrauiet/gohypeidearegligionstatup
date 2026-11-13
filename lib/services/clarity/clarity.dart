// Microsoft Clarity session analytics (Android/iOS only).
//
// clarity_flutter imports dart:io and has no web implementation, so it is loaded through a
// conditional import: native builds get clarity_native.dart, the web build gets the no-op stub.
export 'clarity_stub.dart' if (dart.library.io) 'clarity_native.dart';
