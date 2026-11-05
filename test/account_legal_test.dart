import 'dart:convert';

import 'package:cosmicguide/screens/legal/community_guidelines_screen.dart';
import 'package:cosmicguide/screens/tabs/more_tab.dart' show DeleteAccountDialog;
import 'package:cosmicguide/services/backend_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget home) => MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: c!,
      ),
      home: home,
    );

Future<void> _narrow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('BackendService.deleteAccount', () {
    setUp(() => SharedPreferences.setMockInitialValues({
          'auth_token': 'tok',
          'user_data': '{"id":7}',
          'kundli_data': '{"ascendant":"Leo"}',
          'videos_watched_v1:7': ['abc'],
          'daily_checkin_prompted_day': '2026-11-05',
          'onboarding_seen': true,
        }));

    test('sends DELETE with confirm and clears the session and user caches', () async {
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/me')) {
          return http.Response(jsonEncode({'user': {'id': 7}, 'kundli': {'ascendant': 'Leo'}}), 200);
        }
        expect(r.method, 'DELETE');
        expect(r.url.path, endsWith('/auth/account'));
        expect(r.headers['Authorization'], 'Bearer tok');
        expect(jsonDecode(r.body), {'confirm': 'DELETE'});
        return http.Response(jsonEncode({'success': true}), 200);
      });
      await http.runWithClient(() async {
        final b = BackendService();
        await b.ready;
        expect(b.isAuthenticated, isTrue);
        expect(await b.deleteAccount(), isTrue);
        expect(b.isAuthenticated, isFalse);
        expect(b.user, isNull);
        expect(b.kundliData, isNull);
      }, () => client);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('kundli_data'), isNull);
      expect(prefs.getStringList('videos_watched_v1:7'), isNull);
      expect(prefs.getString('daily_checkin_prompted_day'), isNull);
      expect(prefs.getBool('onboarding_seen'), isTrue); // app flag kept
    });

    test('failure keeps the session; pandit accounts get a friendly message', () async {
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/me')) {
          return http.Response(jsonEncode({'user': {'id': 7}, 'kundli': {'ascendant': 'Leo'}}), 200);
        }
        return http.Response(jsonEncode({'error': 'Pandit accounts are closed by support', 'code': 'PANDIT_ACCOUNT'}), 409);
      });
      await http.runWithClient(() async {
        final b = BackendService();
        await b.ready;
        expect(await b.deleteAccount(), isFalse);
        expect(b.isAuthenticated, isTrue);
        expect(b.lastError, 'Please contact support to close a pandit account.');
      }, () => client);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), 'tok');
    });
  });

  group('DeleteAccountDialog', () {
    testWidgets('needs DELETE typed, shows errors, pops true on success', (tester) async {
      await _narrow(tester);
      var calls = 0;
      var succeed = false;
      bool? result;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => DeleteAccountDialog(
                    onDelete: () async {
                      calls++;
                      return succeed;
                    },
                    errorText: () => 'Server said no',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.textContaining('buddies, requests and chats'), findsOneWidget);
      expect(tester.takeException(), isNull);

      TextButton deleteButton() => tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete account'));
      expect(deleteButton().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'delete me');
      await tester.pump();
      expect(deleteButton().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      expect(deleteButton().onPressed, isNotNull);

      await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Server said no'), findsOneWidget);
      expect(result, isNull); // still open

      succeed = true;
      await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(result, isTrue);
      expect(find.text('Delete your account?'), findsNothing);
    });
  });

  group('CommunityGuidelinesScreen', () {
    testWidgets('renders every section at 320px / 1.3x', (tester) async {
      await _narrow(tester);
      await tester.pumpWidget(_app(const CommunityGuidelinesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Buddy community guidelines'), findsOneWidget);
      expect(find.text('Never ask for money'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('No cash value'), 300, scrollable: find.byType(Scrollable).last);
      await tester.scrollUntilVisible(find.text('Rejected requests are refunded'), 300, scrollable: find.byType(Scrollable).last);
      expect(tester.takeException(), isNull);
    });

    testWidgets('initialSection jumps to that section; chips scroll', (tester) async {
      await _narrow(tester);
      await tester.pumpWidget(_app(const CommunityGuidelinesScreen(initialSection: GuidelinesSection.trip)));
      await tester.pumpAndSettle();
      expect(find.text('Temple trip terms'), findsOneWidget);
      final y = tester.getTopLeft(find.text('Temple trip terms')).dy;
      expect(y, lessThan(700));
      await tester.tap(find.text('Coins'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Coins terms')).dy, lessThan(300));
      expect(tester.takeException(), isNull);
    });
  });
}
