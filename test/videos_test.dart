import 'dart:convert';
import 'dart:io';

import 'package:cosmicguide/screens/videos/playlist_screen.dart';
import 'package:cosmicguide/screens/videos/videos_screen.dart';
import 'package:cosmicguide/services/backend_service.dart';
import 'package:cosmicguide/services/video_service.dart';
import 'package:cosmicguide/widgets/ui/app_ui.dart';
import 'package:cosmicguide/widgets/videos/video_cards.dart';
import 'package:cosmicguide/widgets/videos/video_home_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real 180-playlist catalogue (long Hindi + English titles).
List<Map<String, dynamic>> _catalogue() {
  final raw = File('backend/data/youtube_playlists.json').readAsStringSync();
  final decoded = jsonDecode(raw);
  final list = decoded is Map ? decoded['playlists'] as List : decoded as List;
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

const _longTitle = 'श्री कृष्ण लीला | A deliberately long video title that keeps going so narrow screens and '
    'large text sizes are exercised without any overflow anywhere | Tilak';

/// How the fake answers `GET /videos/playlists/:id`.
enum DetailMode { list, playerOnly, upstream502, offline }

class FakeBackend extends BackendService {
  bool authed;
  bool failPlaylists;
  bool completeDetails;
  int coinStatus; // 200 = ok, 401 = login required, 500 = server error, 0 = offline
  bool capReached = false;
  bool stringNumbers = false;
  DetailMode detailMode = DetailMode.list;
  final List<String> calls = [];
  final Set<String> serverWatched;

  FakeBackend({
    this.authed = true,
    this.failPlaylists = false,
    this.completeDetails = false,
    this.coinStatus = 200,
    Set<String>? serverWatched,
  }) : serverWatched = serverWatched ?? {'vid0'};

  @override
  bool get isAuthenticated => authed;

  void ping() => notifyListeners();

  @override
  Map<String, dynamic>? get user => authed ? {'id': 7, 'fullName': 'Test'} : null;

  @override
  Future<Map<String, dynamic>> api(String method, String path,
      {Map<String, dynamic>? body, Duration timeout = const Duration(seconds: 15)}) async {
    calls.add('$method $path');
    if (path == '/videos/playlists') {
      if (failPlaylists) throw const BackendException('Server is down', statusCode: 500);
      final list = _catalogue();
      return {
        'categories': list.map((p) => p['category']).toSet().toList(),
        'playlists': list,
      };
    }
    if (path.startsWith('/videos/playlists/')) {
      final id = Uri.decodeComponent(path.substring('/videos/playlists/'.length));
      switch (detailMode) {
        case DetailMode.playerOnly: // new backend, no API key, RSS down
          return {
            'playlistId': id,
            'title': 'Playlist $id',
            'videos': const [],
            'source': 'player',
            'complete': false,
            'playerOnly': true,
            if (authed) 'watched': const [],
          };
        case DetailMode.upstream502: // currently deployed backend
          throw const BackendException('Could not load videos right now. Please try again in a little while.',
              statusCode: 502);
        case DetailMode.offline:
          throw const BackendException('Unable to connect to the server. Please check your internet connection.');
        case DetailMode.list:
          break;
      }
      return {
        'playlistId': id,
        'title': 'Playlist $id',
        'source': completeDetails ? 'api' : 'rss',
        'complete': completeDetails,
        'videos': [
          for (var i = 0; i < 4; i++)
            {
              'videoId': 'vid$i',
              'title': i == 1 ? _longTitle : 'Video number $i | Tilak',
              // Asset-style thumbnails keep network image loading out of
              // widget tests; the UI falls back to the category gradient.
              'thumbnail': 'assets/missing_thumb_$i.jpg',
              'publishedAt': '2026-10-0${i + 1}T10:00:00Z',
            },
        ],
        if (authed) 'watched': serverWatched.toList(),
      };
    }
    if (path == '/coins/video') {
      if (!authed || coinStatus == 401) {
        throw const BackendException('Please log in to earn coins', statusCode: 401);
      }
      if (coinStatus == 500) throw const BackendException('Server problem', statusCode: 500);
      if (coinStatus == 0) throw const BackendException('Unable to connect to the server.');
      if (capReached) return {'awarded': 0, 'balance': 42, 'dailyCapReached': true};
      final id = body?['videoId'] as String;
      final isNew = serverWatched.add(id);
      if (stringNumbers) return {'awarded': isNew ? '1' : '0', 'balance': '42'};
      return {'awarded': isNew ? 1 : 0, 'balance': 42};
    }
    throw BackendException('Unexpected $method $path', statusCode: 404);
  }
}

Widget _app(VideoService service, Widget child, {double textScale = 1.3}) {
  return ChangeNotifierProvider<VideoService>.value(
    value: service,
    child: MaterialApp(
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: w!,
      ),
      home: child,
    ),
  );
}

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 780));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // VideoPlayerScreen hosts a platform WebView, so it is not pumped here.

  group('VideoService', () {
    test('loads the catalogue with categories in rail order', () async {
      final s = VideoService(FakeBackend());
      await s.loadPlaylists();
      expect(s.loaded, isTrue);
      expect(s.playlists.length, 180);
      expect(s.categories.first, 'Episodes / Series');
      expect(s.categories.length, 8);
      expect(VideoCategories.label('Bhajan / Music'), 'Bhajans');
      expect(VideoCategories.label('Lifestyle / Yoga'), 'Yoga');
    });

    test('search matches Hindi and English titles, and category filter', () async {
      final s = VideoService(FakeBackend());
      await s.loadPlaylists();
      expect(s.search('ramayan'), isNotEmpty);
      expect(s.search('रामायण'), isNotEmpty);
      expect(s.search('krishna', category: 'Katha / Stories').every((p) => p.category == 'Katha / Stories'), isTrue);
      expect(s.search('zzzz-not-there'), isEmpty);
    });

    test('featured has 8 playlists led by Ramayan', () async {
      final s = VideoService(FakeBackend());
      await s.loadPlaylists();
      final f = s.featured();
      expect(f.length, 8);
      expect(f.first.title, contains('Ramayan'));
      expect(f.any((p) => p.title.contains('Gayatri')), isTrue);
      expect(f.any((p) => p.category == 'Darshan / Temples'), isTrue);
    });

    test('cleanTitle drops the channel tag', () {
      expect(VideoCategories.cleanTitle('Ramayan Maha Episodes | Complete Series | Tilak'),
          'Ramayan Maha Episodes · Complete Series');
    });

    test('playlist detail is cached and marks server-watched videos', () async {
      final b = FakeBackend();
      final s = VideoService(b);
      final d1 = await s.playlistDetail('PLX');
      final d2 = await s.playlistDetail('PLX');
      expect(identical(d1, d2), isTrue);
      expect(b.calls.where((c) => c == 'GET /videos/playlists/PLX').length, 1);
      expect(s.isWatched('vid0'), isTrue);
      expect(s.isWatched('vid1'), isFalse);
      expect(d1.complete, isFalse);
    });

    test('rewardIfNew pays once, then never calls again', () async {
      final b = FakeBackend(serverWatched: {});
      final s = VideoService(b);
      expect(await s.rewardIfNew('abc', 'Title'), 1);
      expect(s.isWatched('abc'), isTrue);
      expect(s.lastBalance, 42);
      expect(await s.rewardIfNew('abc', 'Title'), 0);
      expect(b.calls.where((c) => c == 'POST /coins/video').length, 1);
      // Persisted locally for the next launch.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('videos_watched_v1:7'), contains('abc'));
      final fresh = VideoService(b);
      expect(await fresh.rewardIfNew('abc', 'Title'), 0);
      expect(b.calls.where((c) => c == 'POST /coins/video').length, 1);
    });

    test('guests and LOGIN_REQUIRED get 0 quietly', () async {
      final guest = FakeBackend(authed: false);
      expect(await VideoService(guest).rewardIfNew('abc', 'T'), 0);
      expect(guest.calls, isEmpty);

      final expired = FakeBackend(coinStatus: 401);
      expect(await VideoService(expired).rewardIfNew('abc', 'T'), 0);
    });

    test('daily cap: video stays unclaimed and no more calls today', () async {
      final b = FakeBackend(serverWatched: {})..capReached = true;
      final s = VideoService(b);
      expect(await s.claimVideoReward('vidAAAAAAAA', 'T'), 0);
      expect(s.isWatched('vidAAAAAAAA'), isFalse); // can still pay tomorrow
      expect(s.dailyCapReached, isTrue);
      expect(s.takeDailyCapNotice(), isTrue);
      expect(s.takeDailyCapNotice(), isFalse); // shown once
      expect(await s.claimVideoReward('vidBBBBBBBB', 'T'), 0);
      expect(b.calls.where((c) => c == 'POST /coins/video').length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('videos_watched_v1:7') ?? const [], isNot(contains('vidAAAAAAAA')));
    });

    test('temporary failures return null (retryable), 4xx returns 0', () async {
      final down = FakeBackend(serverWatched: {}, coinStatus: 500);
      final s = VideoService(down);
      expect(await s.claimVideoReward('abc', 'T'), isNull);
      expect(s.isWatched('abc'), isFalse);
      down.coinStatus = 0; // offline
      expect(await s.claimVideoReward('abc', 'T'), isNull);
      down.coinStatus = 200;
      expect(await s.claimVideoReward('abc', 'T'), 1);
      expect(await VideoService(FakeBackend(coinStatus: 401)).claimVideoReward('x', 'T'), 0);
    });

    test('numbers sent as strings are parsed', () async {
      final b = FakeBackend(serverWatched: {})..stringNumbers = true;
      final s = VideoService(b);
      expect(await s.rewardIfNew('abc', 'T'), 1);
      expect(s.lastBalance, 42);
      final p = VideoPlaylist.fromJson({'no': '12', 'title': 'T', 'category': 'Shorts', 'playlistId': 'PL1'});
      expect(p.no, 12);
      final d = PlaylistDetail.fromJson({
        'videos': [
          {'videoId': 'v1', 'title': null},
          null,
          {'title': 'no id'},
        ],
        'complete': 'false',
      }, 'PLZ');
      expect(d.playlistId, 'PLZ');
      expect(d.videos.single.videoId, 'v1');
      expect(d.complete, isFalse);
    });

    test('switching account drops the previous watched set', () async {
      final b = FakeBackend(serverWatched: {'vid0'});
      final s = VideoService(b);
      await s.playlistDetail('PLX');
      expect(s.isWatched('vid0'), isTrue);
      b.authed = false;
      b.ping();
      expect(s.isWatched('vid0'), isFalse);
      expect(s.cachedDetail('PLX'), isNull);
    });
  });

  group('VideosScreen', () {
    testWidgets('rails, chips, category grid and search at 360px / 1.3x', (tester) async {
      await _phone(tester);
      final s = VideoService(FakeBackend());
      await tester.pumpWidget(_app(s, const VideosScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Bhakti videos'), findsOneWidget);
      expect(find.textContaining('earn 1 coin each'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      // First rail header + chip share the label.
      expect(find.text('Series'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Pick a category from the chips -> grid.
      final shortsChip = find.widgetWithText(AppFilterChip, 'Shorts');
      await tester.scrollUntilVisible(shortsChip, 120,
          scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(shortsChip);
      await tester.pumpAndSettle();
      await tester.tap(shortsChip);
      await tester.pumpAndSettle();
      expect(find.text('12 playlists'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tapping the selected chip again goes back to All; then search.
      await tester.ensureVisible(shortsChip);
      await tester.pumpAndSettle();
      await tester.tap(shortsChip);
      await tester.pumpAndSettle();
      expect(find.text('Series'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'Gayatri');
      await tester.pumpAndSettle();
      expect(find.text('Results'), findsOneWidget);
      expect(find.textContaining('Gayatri Mantra'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No playlists found'), findsOneWidget);
    });

    testWidgets('error state retries', (tester) async {
      await _phone(tester);
      final b = FakeBackend(failPlaylists: true);
      final s = VideoService(b);
      await tester.pumpWidget(_app(s, const VideosScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Could not load videos'), findsOneWidget);

      b.failPlaylists = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load videos'), findsNothing);
      expect(find.text('All'), findsOneWidget);
    });
  });

  group('PlaylistScreen', () {
    testWidgets('shows Play all, watched check, coin chips and the RSS note', (tester) async {
      // Narrow but tall, so the whole (lazy) list is built.
      await tester.binding.setSurfaceSize(const Size(360, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = VideoService(FakeBackend());
      await tester.pumpWidget(_app(
          s, const PlaylistScreen(playlistId: 'PLFPJRCFRDARQOx_u4wFgPS4hxdmbJJnIa', title: 'Ramayan Maha Episodes')));
      await tester.pumpAndSettle();

      expect(find.text('Play all'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget); // vid0 already paid
      expect(find.text('+1'), findsNWidgets(3));
      expect(find.textContaining('Showing the latest 4 videos'), findsOneWidget);
      expect(find.text('Open full playlist on YouTube'), findsOneWidget);
      expect(find.textContaining('3 new'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('complete playlists hide the RSS note', (tester) async {
      await _phone(tester);
      final s = VideoService(FakeBackend(completeDetails: true));
      await tester.pumpWidget(_app(s, const PlaylistScreen(playlistId: 'PLX', title: 'X')));
      await tester.pumpAndSettle();
      expect(find.text('Play all'), findsOneWidget);
      expect(find.textContaining('Showing'), findsNothing);
    });

    testWidgets('320px wide at 1.3x text has no overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = VideoService(FakeBackend());
      await tester.pumpWidget(_app(s, const PlaylistScreen(playlistId: 'PLX', title: _longTitle)));
      await tester.pumpAndSettle();
      expect(find.text('Play all'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('VideoHomeRail', () {
    testWidgets('shows featured playlists and See all', (tester) async {
      await _phone(tester);
      final s = VideoService(FakeBackend());
      var seeAll = 0;
      await tester.pumpWidget(_app(
        s,
        Scaffold(body: ListView(children: [VideoHomeRail(onSeeAll: () => seeAll++)])),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bhakti videos · earn coins'), findsOneWidget);
      expect(find.textContaining('Ramayan Maha Episodes'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('See all'));
      expect(seeAll, 1);

      await tester.tap(find.textContaining('Ramayan Maha Episodes'));
      await tester.pumpAndSettle();
      expect(find.text('Play all'), findsOneWidget);
    });

    testWidgets('player-mode playlists keep the gradient artwork, no errors', (tester) async {
      await _phone(tester);
      final b = FakeBackend()..detailMode = DetailMode.upstream502;
      final s = VideoService(b);
      await tester.pumpWidget(_app(s, Scaffold(body: ListView(children: const [VideoHomeRail()]))));
      await tester.pumpAndSettle();
      expect(find.text('Bhakti videos · earn coins'), findsOneWidget);
      expect(find.byType(VideoFallbackArt), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      expect(s.thumbnailFor(VideoService.featuredPlaylistIds.first), '');
    });
  });

  group('Playlist player mode', () {
    test('playerOnly response -> player-mode detail with no videos', () async {
      final b = FakeBackend()..detailMode = DetailMode.playerOnly;
      final s = VideoService(b);
      final d = await s.playlistDetail('PLP');
      expect(d.playerOnly, isTrue);
      expect(d.usePlayerMode, isTrue);
      expect(d.videos, isEmpty);
      expect(d.source, 'player');
      expect(await s.loadThumbnail('PLP'), ''); // gradient fallback, no broken image
    });

    test('502 UPSTREAM_ERROR (deployed backend) falls back to player mode, cached for a while', () async {
      final b = FakeBackend()..detailMode = DetailMode.upstream502;
      final s = VideoService(b);
      await s.loadPlaylists();
      const id = 'PLFPJRCFRDARQOx_u4wFgPS4hxdmbJJnIa';
      var now = DateTime(2026, 11, 5, 10);
      s.clock = () => now;
      final d = await s.playlistDetail(id);
      expect(d.usePlayerMode, isTrue);
      expect(d.playlistId, id);
      expect(d.title, contains('Ramayan'));
      await s.playlistDetail(id);
      expect(b.calls.where((c) => c == 'GET /videos/playlists/$id').length, 1, reason: 'cached');

      // After the TTL the server is asked again (it may have been redeployed).
      now = now.add(VideoService.playerModeTtl);
      b.detailMode = DetailMode.list;
      final fresh = await s.playlistDetail(id);
      expect(fresh.usePlayerMode, isFalse);
      expect(fresh.videos.length, 4);
      expect(b.calls.where((c) => c == 'GET /videos/playlists/$id').length, 2);
    });

    test('offline still throws (the player could not open either)', () async {
      final b = FakeBackend()..detailMode = DetailMode.offline;
      final s = VideoService(b);
      await expectLater(s.playlistDetail('PLX'), throwsA(isA<BackendException>()));
      expect(s.cachedDetail('PLX'), isNull);
    });

    test('PlaylistDetail.fromJson reads playerOnly', () {
      expect(PlaylistDetail.fromJson({'playerOnly': true, 'videos': []}, 'P').playerOnly, isTrue);
      expect(PlaylistDetail.fromJson({'source': 'player'}, 'P').playerOnly, isTrue);
      final listed = PlaylistDetail.fromJson({
        'videos': [
          {'videoId': 'v1'}
        ]
      }, 'P');
      expect(listed.playerOnly, isFalse);
      expect(listed.usePlayerMode, isFalse);
      expect(const PlaylistDetail.playerOnly('P').usePlayerMode, isTrue);
    });

    for (final mode in [DetailMode.playerOnly, DetailMode.upstream502]) {
      testWidgets('PlaylistScreen shows the Play all videos hero ($mode)', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final s = VideoService(FakeBackend()..detailMode = mode);
        await tester.pumpWidget(_app(s, const PlaylistScreen(playlistId: 'PLX', title: _longTitle)));
        await tester.pumpAndSettle();
        expect(find.text('Play all videos'), findsOneWidget);
        expect(find.textContaining('whole playlist'), findsOneWidget);
        expect(find.textContaining('Earn 1 coin for each new video'), findsOneWidget);
        expect(find.textContaining('Could not'), findsNothing);
        expect(find.textContaining('offline'), findsNothing);
        expect(find.text('Play all'), findsNothing); // list mode hero not shown
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('PlaylistScreen offline -> error state with retry', (tester) async {
      await _phone(tester);
      final b = FakeBackend()..detailMode = DetailMode.offline;
      final s = VideoService(b);
      await tester.pumpWidget(_app(s, const PlaylistScreen(playlistId: 'PLX', title: 'X')));
      await tester.pumpAndSettle();
      expect(find.text('You seem to be offline'), findsOneWidget);
      b.detailMode = DetailMode.list;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Play all'), findsOneWidget);
    });

    test('coins are keyed by the id the player reports, once per video', () async {
      final b = FakeBackend(serverWatched: {'oldVideo001'});
      final s = VideoService(b);
      final claimed = <String>[];
      final t = VideoCoinTracker(s, onClaimed: (id, n) => claimed.add(MapEntry(id, n).toString()));
      // Before the player reports a video nothing is counted.
      expect(t.tick(playing: true), isFalse);

      // Player reports video A (playlist mode metadata); 10 s of real playback.
      t.setVideo('videoAAAAAA', title: 'A');
      for (var i = 0; i < 9; i++) {
        t.tick(playing: true, position: Duration(seconds: i));
      }
      expect(t.playedSeconds, 8); // first sample only sets the baseline
      t.tick(playing: false); // paused: no counting, re-baseline
      t.tick(playing: true, position: const Duration(seconds: 100)); // seek: baseline only
      t.tick(playing: true, position: const Duration(seconds: 101));
      t.tick(playing: true, position: const Duration(seconds: 102));
      expect(t.handled, isTrue);
      await t.pendingClaim;
      expect(t.earned, isTrue);
      expect(s.isWatched('videoAAAAAA'), isTrue);

      // The player moves to B via its own next button: counting restarts for B.
      expect(t.setVideo('videoBBBBBB', title: 'B'), isTrue);
      expect(t.earned, isFalse);
      for (var i = 0; i < 12; i++) {
        t.tick(playing: true); // platform without position updates
      }
      await t.pendingClaim;

      // Back to A (previous): already paid, nothing counted or claimed.
      t.setVideo('videoAAAAAA');
      expect(t.handled, isTrue);
      for (var i = 0; i < 12; i++) {
        t.tick(playing: true);
      }
      // A video paid on an earlier day: one claim call, 0 coins, then watched.
      t.setVideo('oldVideo001');
      for (var i = 0; i < 12; i++) {
        t.tick(playing: true);
      }
      await t.pendingClaim;

      expect(claimed, ['MapEntry(videoAAAAAA: 1)', 'MapEntry(videoBBBBBB: 1)', 'MapEntry(oldVideo001: 0)']);
      final posts = b.calls.where((c) => c == 'POST /coins/video').length;
      expect(posts, 3);
      // Same id reported again (title update) does not reset the counter.
      expect(t.setVideo('oldVideo001', title: 'Old'), isFalse);
      expect(t.title, 'Old');
    });

    test('tracker: guests and daily cap do not count; temporary failure retries', () async {
      final guest = VideoCoinTracker(VideoService(FakeBackend(authed: false)));
      guest.setVideo('videoAAAAAA');
      expect(guest.handled, isTrue);

      final b = FakeBackend(serverWatched: {}, coinStatus: 500);
      final s = VideoService(b);
      var changed = 0;
      final t = VideoCoinTracker(s, onChanged: () => changed++);
      t.setVideo('videoAAAAAA');
      for (var i = 0; i < 10; i++) {
        t.tick(playing: true);
      }
      await t.pendingClaim;
      expect(t.handled, isFalse, reason: 'retry after a little more watching');
      expect(changed, 1);
      b.coinStatus = 200;
      for (var i = 0; i < 5; i++) {
        t.tick(playing: true);
      }
      await t.pendingClaim;
      expect(t.earned, isTrue);

      final capped = FakeBackend(serverWatched: {})..capReached = true;
      final cs = VideoService(capped);
      expect(await cs.claimVideoReward('videoXXXXXX', 'T'), 0);
      final ct = VideoCoinTracker(cs)..setVideo('videoYYYYYY');
      expect(ct.handled, isTrue);
    });
  });
}
