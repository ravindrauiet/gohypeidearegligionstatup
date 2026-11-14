import 'package:cosmicguide/screens/chatbot_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/utils/app_routes.dart';
import 'package:cosmicguide/widgets/cosmic_guide_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chat backend: the first message answers with a generate_kundli action (as /api/chat does
/// once date, time and place are known); generateKundli returns a chart from "the engine".
class FakeChatBackend extends BackendService {
  final List<String> sent = [];
  final List<Map<String, dynamic>> generated = [];
  bool failGenerate = false;
  Map<String, dynamic>? _chart;

  @override
  bool get hasBirthDetails => _chart != null;

  @override
  Future<List<Map<String, dynamic>>> fetchChatHistory({String? astrologerName}) async => [];

  @override
  Future<String?> sendChatMessage(String message, {String? astrologerName, String? specialty, String? field}) async {
    sent.add(message);
    if (sent.length == 1) {
      lastChatAction = {
        'type': 'generate_kundli',
        'birthDetails': {
          'fullName': 'Me',
          'gender': 'Not Specified',
          'dateOfBirth': '2024-09-14',
          'timeOfBirth': '05:35',
          'birthTimeKnown': true,
          'placeOfBirth': 'Chennai, Tamil Nadu',
        },
      };
      return 'Thank you. I have your birth details. I am preparing your Kundli now.';
    }
    lastChatAction = null;
    return 'Your Lagna is Leo, which gives you natural confidence.';
  }

  @override
  Future<Map<String, dynamic>?> generateKundli({
    required String fullName,
    required String gender,
    required String dateOfBirth,
    required String timeOfBirth,
    required String placeOfBirth,
    double? latitude,
    double? longitude,
    String? timezone,
    bool birthTimeKnown = true,
  }) async {
    generated.add({
      'dateOfBirth': dateOfBirth,
      'timeOfBirth': timeOfBirth,
      'placeOfBirth': placeOfBirth,
      'latitude': latitude,
      'longitude': longitude,
      'birthTimeKnown': birthTimeKnown,
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (failGenerate) return null;
    _chart = {
      'ascendant': 'Leo',
      'moonSign': 'Aries',
      'sunSign': 'Virgo',
      'nakshatra': 'Ashwini',
      'nakshatraPada': 2,
      'dashaInfo': {'currentMahadasha': 'Ketu'},
    };
    return _chart;
  }
}

Future<void> pumpChat(WidgetTester tester, FakeChatBackend backend) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ChangeNotifierProvider<BackendService>.value(
    value: backend,
    child: MaterialApp(
      routes: {AppRoutes.kundliView: (_) => const Scaffold(body: Text('KUNDLI VIEW'))},
      home: const ChatbotScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}


void main() {
  testWidgets('birth details typed in chat: loader, real chart card, then a reading', (tester) async {
    final backend = FakeChatBackend();
    await pumpChat(tester, backend);

    await tester.enterText(find.byType(TextField).last, 'Chennai, Tamil Nadu');
    final send = find.byTooltip('Send');
    if (send.evaluate().isNotEmpty) {
      await tester.tap(send.first);
    } else {
      await tester.testTextInput.receiveAction(TextInputAction.send);
    }
    await tester.pump(); // reply arrives
    await tester.pump(const Duration(milliseconds: 50));

    // The CosmicGuide loader covers the chat while the chart is built.
    expect(find.byType(CosmicGuideLoader), findsOneWidget);
    expect(find.text('Preparing your Kundli'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300)); // generateKundli finishes
    await tester.pumpAndSettle();

    // Built by the app pipeline with real coordinates (Chennai from the local city list).
    expect(backend.generated, hasLength(1));
    expect(backend.generated.single['dateOfBirth'], '2024-09-14');
    expect(backend.generated.single['timeOfBirth'], '05:35:00');
    expect(backend.generated.single['latitude'], closeTo(13.08, 0.01));
    expect(backend.generated.single['longitude'], closeTo(80.27, 0.01));

    expect(find.byType(CosmicGuideLoader), findsNothing);
    expect(find.text('Your Kundli is ready'), findsOneWidget);
    expect(find.text('Leo'), findsOneWidget);
    expect(find.text('Ashwini · Pada 2'), findsOneWidget);

    // ...and the astrologer was asked to read the real chart.
    expect(backend.sent.last, 'My Kundli is ready. Please give me my first reading.');

    await tester.tap(find.text('View full Kundli'));
    await tester.pumpAndSettle();
    expect(find.text('KUNDLI VIEW'), findsOneWidget);
  });

  testWidgets('chart generation failure offers the birth-details form, loader goes away', (tester) async {
    final backend = FakeChatBackend()..failGenerate = true;
    await pumpChat(tester, backend);

    await tester.enterText(find.byType(TextField).last, 'Chennai, Tamil Nadu');
    final send = find.byTooltip('Send');
    if (send.evaluate().isNotEmpty) {
      await tester.tap(send.first);
    } else {
      await tester.testTextInput.receiveAction(TextInputAction.send);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(CosmicGuideLoader), findsNothing);
    expect(find.text('Enter birth details'), findsOneWidget);
    expect(backend.sent, hasLength(1)); // no reading requested without a chart
  });
}
