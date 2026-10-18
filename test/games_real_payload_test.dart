// Renders the game screens from REAL backend responses captured in
// test/fixtures/game (regenerate them from the backend when the API changes).
// Guards the app <-> backend contract for all four games.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmicguide/models/game.dart';
import 'package:cosmicguide/screens/games/cosmic_match_screen.dart';
import 'package:cosmicguide/screens/games/games_hub_screen.dart';
import 'package:cosmicguide/screens/games/graha_quest_screen.dart';
import 'package:cosmicguide/screens/games/moksha_patam_screen.dart';
import 'package:cosmicguide/screens/games/nakshatra_cards_screen.dart';
import 'package:cosmicguide/widgets/play_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'games_test.dart' show FakeGameBackend, pumpGameScreen, settleGame;

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/game/$name.json').readAsStringSync()) as Map<String, dynamic>;

FakeGameBackend realBackend() => FakeGameBackend()
  ..state = fixture('state')
  ..cards = fixture('cards')
  ..moksha = fixture('moksha')
  ..circle = fixture('circle')
  ..completeResponse = fixture('complete')
  ..collectResponse = fixture('collect')
  ..rollResponse = fixture('roll');

Future<void> scrollAll(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 30; i++) {
    await tester.drag(scrollable, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settleGame(tester, const Duration(milliseconds: 500));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Real game payloads parse', () {
    test('state', () {
      final s = GameState.fromJson(fixture('state'));
      expect(s.planets, hasLength(9));
      expect(s.missions.items, hasLength(3));
      expect(s.missions.items.every((m) => m.title.isNotEmpty && m.why.isNotEmpty && m.xp > 0), isTrue);
      expect(s.player.xpForNext, greaterThan(0));
    });

    test('cards, collect and mission complete', () {
      final album = CardAlbum.fromJson(fixture('cards'));
      expect(album.cards, hasLength(27));
      expect(album.sets, isNotEmpty);
      expect(CollectResult.fromJson(fixture('collect')).collected, isNotEmpty);
      expect(MissionCompleteResult.fromJson(fixture('complete')).xpGained, greaterThan(0));
    });

    test('moksha board and roll', () {
      final board = MokshaBoard.fromJson(fixture('moksha'));
      expect(board.players.length, greaterThanOrEqualTo(2)); // self + family member
      final roll = MokshaRollResult.fromJson(fixture('roll'));
      expect(roll.dice, inInclusiveRange(1, 6));
      expect(roll.to, inInclusiveRange(1, 100));
    });

    test('circle', () {
      final circle = CosmicCircle.fromJson(fixture('circle'));
      expect(circle.inviteCode, isNotEmpty);
      expect(circle.members.length, greaterThanOrEqualTo(3));
      expect(circle.rankings.any((r) => r.unlocked), isTrue);
      expect(circle.rankings.any((r) => !r.unlocked), isTrue);
    });

    test('NO_ROLLS_LEFT carries the next-roll hint', () {
      final body = fixture('no_rolls');
      expect(body['code'], 'NO_ROLLS_LEFT');
      expect(body['nextRollHint'], isA<String>());
    });
  });

  group('Game screens render real payloads at 320x640, 1.3x text', () {
    final screens = <String, Widget>{
      'GamesHubScreen': const GamesHubScreen(),
      'GrahaQuestScreen': const GrahaQuestScreen(),
      'NakshatraCardsScreen': const NakshatraCardsScreen(),
      'MokshaPatamScreen': const MokshaPatamScreen(),
      'CosmicMatchScreen': const CosmicMatchScreen(),
    };
    screens.forEach((name, screen) {
      testWidgets(name, (tester) async {
        await pumpGameScreen(tester, screen, realBackend());
        expect(tester.takeException(), isNull);
        await scrollAll(tester);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Graha Quest shows the real missions and completes one', (tester) async {
      final fake = realBackend();
      final first = GameState.fromJson(fixture('state')).missions.items.first;
      await pumpGameScreen(tester, const GrahaQuestScreen(), fake, disableAnimations: true);
      expect(find.text(first.title), findsOneWidget);
      await tester.ensureVisible(find.text(first.title));
      await tester.tap(find.text(first.title));
      await settleGame(tester, const Duration(seconds: 1));
      expect(fake.completeCalls, [first.id]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cosmic Match shows the invite code and real members', (tester) async {
      final circle = CosmicCircle.fromJson(fixture('circle'));
      await pumpGameScreen(tester, const CosmicMatchScreen(), realBackend());
      expect(find.textContaining(circle.inviteCode), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home PlayStrip', (tester) async {
      await pumpGameScreen(
        tester,
        const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: PlayStrip())),
        realBackend(),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
