/// Shared form validators for the auth & onboarding flow.
class Validators {
  Validators._();

  static final RegExp _emailRegExp =
      RegExp(r"^[\w.!#$%&'*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$");

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your full name';
    if (v.length < 2) return 'Name is too short';
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your email address';
    if (!_emailRegExp.hasMatch(v)) return 'Please enter a valid email address';
    return null;
  }

  /// [isNew] enforces the minimum length only when creating a password, so
  /// existing users with older/shorter passwords can still sign in.
  static String? password(String? value, {bool isNew = false}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please enter your password';
    if (isNew && v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }
}
