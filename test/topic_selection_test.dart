import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmicguide/screens/topic_selection_screen.dart';
import 'package:cosmicguide/utils/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _newInterests = [
  'Find a life partner',
  'Business partner',
  'Friends & community',
  'Travel buddy',
  'Satsang',
  'Bhajans & videos',
  'Games & rewards',
];

const _astroTopics = [
  'My Vedic Kundli',
  'Love & marriage matching',
  "How's my day today",
  "Today's Panchang & Moon",
  'My planet weather',
];

Future<void> pumpTopics(WidgetTester tester, {Size size = const Size(320, 568), double textScale = 1.3}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      routes: {
        '/': (_) => const TopicSelectionScreen(),
        AppRoutes.birthDetails: (_) => const Scaffold(body: Text('BIRTH STUB')),
        AppRoutes.home: (_) => const Scaffold(body: Text('HOME STUB')),
      },
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTopic(WidgetTester tester, String title) async {
  if (find.text(title).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pump();
}

void main() {
  test('keeps the old astro ids and adds the new interests, all unique', () {
    final ids = TopicSelectionScreen.topicIds;
    expect(TopicSelectionScreen.prefsKey, 'interest_topics');
    expect(ids, containsAll(['kundli', 'love', 'day', 'panchang', 'transits']));
    expect(
      ids,
      containsAll(['life_partner', 'business_partner', 'friends', 'travel', 'satsang', 'bhajans', 'games']),
    );
    expect(ids.toSet().length, ids.length);
    expect(TopicSelectionScreen.defaultSelection, {'kundli'});
  });

  for (final size in const [Size(320, 568), Size(412, 915)]) {
    testWidgets('every interest card lays out at ${size.width.toInt()}px and 1.3x text', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpTopics(tester, size: size);
      for (final title in [..._newInterests, ..._astroTopics]) {
        await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull, reason: title);
      }
      expect(find.text('1 selected'), findsOneWidget);
    });
  }

  testWidgets('saves picked ids in display order under interest_topics', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpTopics(tester);
    await _tapTopic(tester, 'Find a life partner');
    await _tapTopic(tester, 'Satsang');
    await _tapTopic(tester, 'Games & rewards');
    expect(find.text('4 selected'), findsOneWidget);

    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();
    expect(find.text('BIRTH STUB'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('interest_topics'), ['life_partner', 'satsang', 'games', 'kundli']);
  });

  testWidgets('needs at least one pick to proceed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpTopics(tester);
    await _tapTopic(tester, 'My Vedic Kundli');
    expect(find.text('Select at least one'), findsOneWidget);
    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();
    expect(find.text('BIRTH STUB'), findsNothing);

    await _tapTopic(tester, 'My planet weather');
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('Skip goes home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpTopics(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('HOME STUB'), findsOneWidget);
  });

  testWidgets('cards announce their selected state', (tester) async {
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    await pumpTopics(tester, size: const Size(412, 915), textScale: 1.0);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Find a life partner')),
      matchesSemantics(
        label: 'Find a life partner',
        hint: 'Matches from your real Kundli and 50 mindset questions, not just photos.',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
