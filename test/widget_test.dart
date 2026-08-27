import 'package:flutter_test/flutter_test.dart';
import 'package:pujakaro/main.dart';

void main() {
  testWidgets('AstroApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AstroApp());

    // Verify onboarding title exists
    expect(find.text('Welcome to AstroAI'), findsOneWidget);
  });
}
