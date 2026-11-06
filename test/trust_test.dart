import 'dart:math';
import 'dart:typed_data';

import 'package:cosmicguide/screens/trust/biodata_edit_screen.dart';
import 'package:cosmicguide/screens/trust/biodata_pdf.dart';
import 'package:cosmicguide/screens/trust/family_notes_screen.dart';
import 'package:cosmicguide/screens/trust/family_share_screen.dart';
import 'package:cosmicguide/screens/trust/phone_verify_sheet.dart';
import 'package:cosmicguide/screens/trust/selfie_picker.dart';
import 'package:cosmicguide/screens/trust/verification_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/buddy_service.dart';
import 'package:cosmicguide/services/trust_service.dart';
import 'package:cosmicguide/theme/app_theme.dart';
import 'package:cosmicguide/widgets/buddy/buddy_candidate_card.dart';
import 'package:cosmicguide/widgets/buddy/trust_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeTrustBackend extends BackendService {
  bool loggedIn = true;
  Map<String, dynamic> verification = {
    'status': 'none',
    'verified': false,
    'phoneVerified': false,
    'phoneAvailable': false,
    'latest': null,
    'submissionsToday': 0,
    'dailyLimit': 3,
  };
  Map<String, dynamic> biodata = {};
  List<Map<String, dynamic>> links = [];
  List<Map<String, dynamic>> notes = [];
  final List<(String, String, Map<String, dynamic>?)> calls = [];
  final Map<String, (BackendException, String?)> failures = {};
  String? _code;
  int _id = 10;

  @override
  String? get lastErrorCode => _code;
  @override
  bool get isAuthenticated => loggedIn;
  @override
  Map<String, dynamic>? get user => loggedIn ? {'id': 1, 'fullName': 'Ravi Kumar'} : null;
  @override
  Map<String, dynamic>? get kundliData => null;

  Map<String, dynamic> _link({String kind = 'self', bool active = true}) {
    final id = ++_id;
    return {
      'id': id,
      'kind': kind,
      'token': 'tok$id',
      'url': 'https://api.example.com/f/tok$id',
      'match': kind == 'match' ? {'userId': 2, 'displayName': 'Priya'} : null,
      'createdAt': DateTime.now().toIso8601String(),
      'expiresAt': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      'revokedAt': active ? null : DateTime.now().toIso8601String(),
      'active': active,
      'notesCount': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add((method, path, body));
    final f = failures['$method $path'];
    _code = f?.$2;
    if (f != null) throw f.$1;
    switch ('$method $path') {
      case 'GET /buddy/verification':
        return verification;
      case 'POST /buddy/verification':
        verification = {
          ...verification,
          'status': 'pending',
          'submissionsToday': (verification['submissionsToday'] as int) + 1,
          'latest': {'id': 1, 'gesture': body!['gesture'], 'status': 'pending', 'createdAt': DateTime.now().toIso8601String()},
        };
        return verification;
      case 'GET /buddy/biodata':
        return {'biodata': biodata};
      case 'PUT /buddy/biodata':
        biodata = Map<String, dynamic>.from(body!['biodata'] as Map);
        return {'biodata': biodata};
      case 'GET /family/links':
        return {'links': links, 'maxActive': 5};
      case 'POST /family/links':
        final l = _link(kind: body?['kind'] == 'match' ? 'match' : 'self');
        links = [l, ...links];
        return {'link': l};
      case 'GET /family/notes':
        return {'notes': notes};
    }
    if (method == 'DELETE' && path.startsWith('/family/links/')) {
      final id = int.parse(path.split('/').last);
      links = [
        for (final l in links) l['id'] == id ? {...l, 'active': false, 'revokedAt': DateTime.now().toIso8601String()} : l
      ];
      return {'link': links.firstWhere((l) => l['id'] == id)};
    }
    if (method == 'DELETE' && path.startsWith('/family/notes/')) {
      final id = int.parse(path.split('/').last);
      notes = notes.where((n) => n['id'] != id).toList();
      return {'ok': true};
    }
    return {'ok': true};
  }
}

class FakePicker implements SelfiePicker {
  Uint8List? next;
  int calls = 0;
  FakePicker(this.next);
  @override
  Future<Uint8List?> takeSelfie() async {
    calls++;
    return next;
  }
}

class FakePhone implements PhoneVerifier {
  @override
  final bool available;
  FakePhone(this.available);
  @override
  Future<PhoneCodeResult> sendCode(String e164) async => const PhoneCodeResult(verificationId: 'vid');
  @override
  Future<String> confirm(String verificationId, String code) async => 'id-token-123456789012345';
}

Future<void> pumpTrust(WidgetTester tester, FakeTrustBackend backend, Widget child,
    {double width = 360, double textScale = 1.3}) async {
  tester.view.physicalSize = Size(width * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<BackendService>.value(value: backend),
      ChangeNotifierProvider(create: (c) => BuddyService(c.read<BackendService>())),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: w!,
      ),
      routes: {'/login': (_) => const Scaffold(body: Text('LOGIN SCREEN'))},
      home: KeyedSubtree(key: UniqueKey(), child: child),
    ),
  ));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Map<String, dynamic> candidateJson({bool verified = false, bool phone = false}) => {
      'userId': 7,
      'displayName': 'Priya Sharma',
      'age': 27,
      'city': 'Varanasi',
      'distanceKm': 4,
      'intents': ['friend', 'life_partner'],
      'bio': 'Aarti and long walks.',
      'score': 82,
      'breakdown': {'kundli': 74, 'mindset': 88, 'distance': 96},
      'highlights': ['You agree on 31 of 38 shared questions', 'Both Moons in water signs'],
      'verified': verified,
      'phoneVerified': phone,
      'education': 'MBA',
      'profession': 'Banker',
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    familyShareText = (text, {subject}) async {};
    biodataPdfShare = (bytes, name) async {};
  });

  group('models', () {
    test('candidate + profile parse trust fields; profile toJson never sends them', () {
      final c = BuddyCandidate.tryParse({
        ...candidateJson(verified: true, phone: true),
        'biodata': {'heightCm': 170, 'diet': 'veg', 'gotra': 'Kashyap', 'incomeRange': 'bogus'},
      })!;
      expect(c.verified, isTrue);
      expect(c.phoneVerified, isTrue);
      expect(c.careerLine, 'MBA · Banker');
      expect(c.biodata!.heightCm, 170);
      expect(c.biodata!.incomeRange, isNull);
      expect(c.biodata!.personalRows.map((r) => r.$1), containsAll(['Height', 'Diet', 'Gotra']));
      final p = BuddyProfile.fromJson({'displayName': 'R', 'intents': ['friend'], 'verified': true, 'biodata': {'education': 'BA'}});
      expect(p.verified, isTrue);
      expect(p.biodata.education, 'BA');
      expect(p.toJson().containsKey('verified'), isFalse);
      expect(p.toJson().containsKey('biodata'), isFalse);
      expect(p.copyWith(isActive: false).verified, isTrue);
      expect(BiodataOptions.heightLabel(170), "170 cm (5' 7\")");
    });

    test('verification state + family link parsing', () {
      final s = VerificationState.fromJson({'status': 'rejected', 'latest': {'id': 3, 'gesture': 'Thumbs up', 'status': 'rejected', 'reason': 'Blurry'}, 'submissionsToday': 1});
      expect(s.status, VerificationStatus.rejected);
      expect(s.canSubmit, isTrue);
      expect(s.latest!.reason, 'Blurry');
      expect(VerificationState.fromJson({'verified': true}).verified, isTrue);
      expect(VerificationState.fromJson({'status': 'none', 'submissionsToday': 3, 'dailyLimit': 3}).canSubmit, isFalse);
      final l = FamilyLink.tryParse({'id': 1, 'kind': 'match', 'url': 'https://x/f/abc', 'match': {'userId': 2, 'displayName': 'Priya'}, 'active': true})!;
      expect(l.title, 'Match: Priya');
      expect(TrustGestures.all, contains(TrustGestures.random(Random(1))));
    });
  });

  group('badges', () {
    testWidgets('candidate card shows the blue check only for verified people', (tester) async {
      Future<void> card(Map<String, dynamic> j) => pumpTrust(
            tester,
            FakeTrustBackend(),
            Scaffold(
              body: SingleChildScrollView(
                child: BuddyCandidateCard(
                    candidate: BuddyCandidate.tryParse(j)!, onOpen: () {}, onSkip: () {}, onConnect: () {}),
              ),
            ),
            width: 320,
          );
      await card(candidateJson(verified: true, phone: true));
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('Phone verified'), findsOneWidget);
      expect(find.text('MBA · Banker'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await card(candidateJson());
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      expect(find.text('Phone verified'), findsNothing);
    });

    testWidgets('mini tile and name row render the compact badge', (tester) async {
      await pumpTrust(
        tester,
        FakeTrustBackend(),
        Scaffold(
          body: Column(children: [
            BuddyMiniTile(candidate: BuddyCandidate.tryParse(candidateJson(verified: true))!, onTap: () {}),
            const SizedBox(width: 150, child: BuddyNameWithBadge(text: 'A very very long display name', verified: true)),
            const VerifiedBadge(),
          ]),
        ),
      );
      expect(find.byIcon(Icons.verified_rounded), findsNWidgets(3));
      expect(find.text('Verified'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('verification flow', () {
    testWidgets('none -> gesture -> selfie -> send -> pending', (tester) async {
      final backend = FakeTrustBackend();
      final picker = FakePicker(Uint8List.fromList(List.filled(2048, 1)));
      await pumpTrust(tester, backend,
          VerificationScreen(picker: picker, phoneVerifier: FakePhone(false), random: Random(3)), width: 320);
      expect(find.text('Show people you are real'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-card')), findsNothing, reason: 'no Firebase: phone option hidden');
      await tapKey(tester, 'start-verification');
      final gesture = tester.widget<Text>(find.byKey(const ValueKey('gesture-text'))).data!;
      expect(TrustGestures.all, contains(gesture));
      await tapKey(tester, 'take-selfie');
      expect(picker.calls, 1);
      expect(find.byKey(const ValueKey('send-selfie')), findsOneWidget);
      await tapKey(tester, 'send-selfie');
      final post = backend.calls.firstWhere((c) => c.$1 == 'POST');
      expect(post.$3!['gesture'], gesture);
      expect((post.$3!['imageBase64'] as String).isNotEmpty, isTrue);
      expect(find.byKey(const ValueKey('pending-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('start-verification')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a photo over 400 KB is refused on the device', (tester) async {
      final backend = FakeTrustBackend();
      final picker = FakePicker(Uint8List(maxSelfieBytes + 1));
      await pumpTrust(tester, backend, VerificationScreen(picker: picker, phoneVerifier: FakePhone(false)));
      await tapKey(tester, 'start-verification');
      await tapKey(tester, 'take-selfie');
      expect(find.textContaining('too large'), findsOneWidget);
      expect(find.byKey(const ValueKey('send-selfie')), findsNothing);
      expect(backend.calls.where((c) => c.$1 == 'POST'), isEmpty);
    });

    testWidgets('rejected shows the reason and allows a retry; verified and phone states', (tester) async {
      final backend = FakeTrustBackend()
        ..verification = {
          'status': 'rejected',
          'phoneAvailable': true,
          'latest': {'id': 1, 'gesture': 'Thumbs up', 'status': 'rejected', 'reason': 'Face not visible'},
          'submissionsToday': 1,
          'dailyLimit': 3,
        };
      await pumpTrust(tester, backend, VerificationScreen(picker: FakePicker(null), phoneVerifier: FakePhone(true)),
          width: 320);
      expect(find.byKey(const ValueKey('rejected-card')), findsOneWidget);
      expect(find.text('Face not visible'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const ValueKey('verify-phone')), findsOneWidget);
      expect(tester.takeException(), isNull);

      backend.verification = {'status': 'verified', 'verified': true, 'phoneVerified': true, 'phoneAvailable': true};
      await pumpTrust(tester, backend, VerificationScreen(picker: FakePicker(null), phoneVerifier: FakePhone(true)));
      expect(find.byKey(const ValueKey('verified-card')), findsOneWidget);
      expect(find.text('Phone verified'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-verification')), findsNothing);
    });

    testWidgets('daily limit, guest and no-profile states', (tester) async {
      final backend = FakeTrustBackend()..verification = {'status': 'none', 'submissionsToday': 3, 'dailyLimit': 3};
      await pumpTrust(tester, backend, VerificationScreen(picker: FakePicker(null), phoneVerifier: FakePhone(false)));
      expect(find.textContaining('3 selfies a day'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-verification')), findsNothing);

      final guest = FakeTrustBackend()..loggedIn = false;
      await pumpTrust(tester, guest, VerificationScreen(picker: FakePicker(null), phoneVerifier: FakePhone(false)));
      expect(find.text('Log in to get verified'), findsOneWidget);
      expect(guest.calls, isEmpty);

      final noProfile = FakeTrustBackend()
        ..failures['GET /buddy/verification'] = (const BackendException('Set up', statusCode: 409), 'NO_PROFILE');
      await pumpTrust(tester, noProfile, VerificationScreen(picker: FakePicker(null), phoneVerifier: FakePhone(false)));
      expect(find.text('Create your buddy profile first'), findsOneWidget);
    });
  });

  group('family', () {
    testWidgets('links list: create shares the url, revoke turns it off', (tester) async {
      final backend = FakeTrustBackend();
      final shared = <String>[];
      familyShareText = (text, {subject}) async => shared.add(text);
      await pumpTrust(tester, backend, const FamilyShareScreen(), width: 320);
      expect(find.text('No links yet'), findsOneWidget);
      await tapKey(tester, 'create-family-link');
      expect(shared.single, contains('https://api.example.com/f/tok11'));
      expect(find.text('My profile'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      await tester.ensureVisible(find.text('Turn off'));
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Turn off').last);
      await tester.pumpAndSettle();
      expect(backend.calls.any((c) => c.$1 == 'DELETE' && c.$2 == '/family/links/11'), isTrue);
      expect(find.text('Turned off'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('match share posts the buddy id; limit error is friendly', (tester) async {
      final backend = FakeTrustBackend();
      await pumpTrust(tester, backend, const FamilyShareScreen(matchUserId: 2, matchName: 'Priya'));
      expect(find.text('Show Priya to your family'), findsOneWidget);
      await tapKey(tester, 'create-family-link');
      final post = backend.calls.firstWhere((c) => c.$1 == 'POST');
      expect(post.$3, {'kind': 'match', 'matchUserId': 2});
      expect(find.text('Match: Priya'), findsOneWidget);

      backend.failures['POST /family/links'] = (const BackendException('limit', statusCode: 409), 'LINK_LIMIT');
      await tapKey(tester, 'create-family-link');
      expect(find.textContaining('5 active links'), findsOneWidget);
    });

    testWidgets('family notes: list and delete; empty state', (tester) async {
      final backend = FakeTrustBackend()
        ..notes = [
          {'id': 5, 'linkId': 1, 'name': 'Sunita', 'relation': 'Mother', 'message': 'She seems lovely', 'createdAt': '2026-11-05T10:00:00Z'},
          {'id': 6, 'linkId': 2, 'name': 'Ramesh', 'relation': 'Father', 'message': 'Call me', 'about': 'Priya'},
        ];
      await pumpTrust(tester, backend, const FamilyNotesScreen(), width: 320);
      expect(find.text('Sunita · Mother'), findsOneWidget);
      expect(find.textContaining('About Priya'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete note').first);
      await tester.pumpAndSettle();
      expect(find.text('Sunita · Mother'), findsNothing);
      expect(backend.calls.any((c) => c.$1 == 'DELETE' && c.$2 == '/family/notes/5'), isTrue);
      backend.notes = [];
      await pumpTrust(tester, backend, const FamilyNotesScreen());
      expect(find.text('No notes yet'), findsOneWidget);
    });
  });

  group('biodata', () {
    for (final width in [320.0, 412.0]) {
      testWidgets('form at ${width.toInt()}px / 1.3x: fills, validates and saves', (tester) async {
        final backend = FakeTrustBackend()..biodata = {'education': 'B.Com', 'diet': 'jain'};
        await pumpTrust(tester, backend, const BiodataEditScreen(), width: width);
        expect(tester.takeException(), isNull);
        expect(find.text('B.Com'), findsOneWidget);

        await tester.enterText(find.byKey(const ValueKey('biodata-heightCm')), '90');
        await tapKey(tester, 'save-biodata');
        expect(find.textContaining('Between 120 and 230'), findsOneWidget);
        expect(backend.calls.where((c) => c.$1 == 'PUT'), isEmpty);

        await tester.enterText(find.byKey(const ValueKey('biodata-heightCm')), '170');
        await tester.enterText(find.byKey(const ValueKey('biodata-profession')), 'Chartered accountant');
        await tester.enterText(find.byKey(const ValueKey('biodata-gotra')), 'Kashyap');
        await tester.pumpAndSettle();
        await tapKey(tester, 'save-biodata');
        final put = backend.calls.lastWhere((c) => c.$1 == 'PUT');
        expect(put.$3!['biodata'],
            {'heightCm': 170, 'education': 'B.Com', 'profession': 'Chartered accountant', 'diet': 'jain', 'gotra': 'Kashyap'});
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('download sheet builds a PDF and shares it; contact stays on the device', (tester) async {
      final shared = <(int, String)>[];
      biodataPdfShare = (bytes, name) async => shared.add((bytes.length, name));
      final backend = FakeTrustBackend()..biodata = {'education': 'MBA'};
      await pumpTrust(tester, backend, const BiodataEditScreen(), width: 320);
      await tapKey(tester, 'download-biodata');
      expect(find.text('Include birth details'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('include-birth'))).value, isTrue);
      await tester.enterText(find.byKey(const ValueKey('biodata-contact')), 'Father: 9800000000');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('make-pdf')));
        for (var i = 0; i < 50 && shared.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));
      expect(shared.single.$1, greaterThan(1000));
      expect(shared.single.$2, endsWith('.pdf'));
      expect(backend.calls.any((c) => '${c.$3}'.contains('9800000000')), isFalse, reason: 'contact is never sent');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BiodataDownloadSheet.contactPrefKey), 'Father: 9800000000');
    });
  });

  group('pdf', () {
    test('buildBiodataPdf returns a non-empty PDF, with and without birth details', () async {
      const b = Biodata(
        heightCm: 165,
        education: 'M.Sc',
        profession: 'Teacher',
        incomeRange: '6_10l',
        diet: 'veg',
        gotra: 'Bharadwaj',
        fatherOccupation: 'Retired',
        siblings: '1 younger sister',
        aboutFamily: 'Simple, warm family from Lucknow. ✨',
        partnerExpectations: 'Kind, family oriented — and loves travel.',
      );
      final full = await buildBiodataPdf(const BiodataPdfData(
        name: 'Asha Rao',
        gender: 'Female',
        age: 31,
        city: 'Delhi',
        languages: ['Hindi', 'English'],
        biodata: b,
        moonSign: 'Cancer',
        lagna: 'Leo',
        nakshatra: 'Pushya',
        manglik: true,
        birthDate: '1995-03-10',
        birthTime: '05:45',
        birthPlace: 'Varanasi',
        contact: 'Mother: 98xxxxxx10',
      ));
      expect(full.length, greaterThan(1000));
      expect(String.fromCharCodes(full.take(5)), '%PDF-');
      final minimal = await buildBiodataPdf(const BiodataPdfData(name: 'नाम', includeBirthDetails: false));
      expect(String.fromCharCodes(minimal.take(5)), '%PDF-');
    });

    test('pdfSafe maps symbols and drops unsupported characters; kundli basics', () {
      expect(pdfSafe('₹10–20 lakh · ok ✨'), 'Rs 10-20 lakh - ok');
      final k = BiodataPdfData.kundliBasics({
        'moonSign': 'Cancer',
        'ascendant': 'Leo',
        'nakshatra': 'Pushya',
        'planetaryPositions': [
          {'name': 'Mars', 'house': 7}
        ],
        'birthDetails': {'dateOfBirth': '1995-03-10T00:00:00.000Z', 'timeOfBirth': '05:45:00', 'placeOfBirth': 'Varanasi'},
      });
      expect(k.manglik, isTrue);
      expect(k.date, '1995-03-10');
      expect(k.time, '05:45');
      expect(BiodataPdfData.kundliBasics(null).moonSign, isNull);
    });
  });
}
