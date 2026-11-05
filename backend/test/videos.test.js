// Videos: RSS parser, API item mapping, cache and routes (no network: fetch is stubbed).
const test = require('node:test');
const assert = require('node:assert/strict');
const { install, serve, call } = require('./fake_db');

const fake = install();
const { signToken } = require('../routes/auth');
const videosRouter = require('../routes/videos');
const PLAYLISTS = require('../data/youtube_playlists.json');

const V = videosRouter._internals;

const RSS = `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <link rel="self" href="http://www.youtube.com/feeds/videos.xml?playlist_id=PLtest"/>
 <id>yt:playlist:PLtest</id>
 <yt:playlistId>PLtest</yt:playlistId>
 <title>Tilak Bhajans</title>
 <entry>
  <id>yt:video:AAAAAAAAAAA</id>
  <yt:videoId>AAAAAAAAAAA</yt:videoId>
  <yt:channelId>UC123</yt:channelId>
  <title>Ram &amp; Sita &#8211; Katha &quot;Part 1&quot; &#x1F64F;</title>
  <link rel="alternate" href="https://www.youtube.com/watch?v=AAAAAAAAAAA"/>
  <published>2026-10-01T05:30:00+00:00</published>
  <updated>2026-10-02T05:30:00+00:00</updated>
  <media:group><media:title>Ram &amp; Sita</media:title></media:group>
 </entry>
 <entry>
  <yt:videoId>BBBBBBBBB-_</yt:videoId>
  <title>हनुमान चालीसा | Tilak</title>
  <published>2026-09-01T05:30:00+00:00</published>
 </entry>
 <entry>
  <yt:videoId>CCCCCCCCCCC</yt:videoId>
  <title>Private video</title>
  <published>2026-08-01T05:30:00+00:00</published>
 </entry>
 <entry>
  <yt:videoId>bad id</yt:videoId>
  <title>Broken</title>
 </entry>
 <entry>
  <yt:videoId>AAAAAAAAAAA</yt:videoId>
  <title>Duplicate</title>
 </entry>
</feed>`;

test('decodeXml handles named, numeric and hex entities and CDATA', () => {
  assert.equal(V.decodeXml('a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&#39;'), `a & b <c> "d" 'e'`);
  assert.equal(V.decodeXml('&#2361;&#x0928;'), 'हन');
  assert.equal(V.decodeXml('<![CDATA[x & y]]>'), 'x & y');
  assert.equal(V.decodeXml('&bogus;'), '&bogus;');
  assert.equal(V.decodeXml(null), '');
});

test('parsePlaylistRss extracts entries and skips private, invalid and duplicate videos', () => {
  const vids = V.parsePlaylistRss(RSS);
  assert.equal(vids.length, 2);
  assert.deepEqual(vids[0], {
    videoId: 'AAAAAAAAAAA',
    title: 'Ram & Sita – Katha "Part 1" \u{1F64F}',
    thumbnail: 'https://i.ytimg.com/vi/AAAAAAAAAAA/hqdefault.jpg',
    publishedAt: '2026-10-01T05:30:00+00:00',
  });
  assert.equal(vids[1].videoId, 'BBBBBBBBB-_');
  assert.equal(vids[1].title, 'हनुमान चालीसा | Tilak');
  assert.deepEqual(V.parsePlaylistRss(''), []);
  assert.deepEqual(V.parsePlaylistRss('<feed><title>x</title></feed>'), []);
});

test('mapApiItem maps playlistItems and skips deleted videos', () => {
  const v = V.mapApiItem({ snippet: { title: 'Aarti', publishedAt: '2026-01-02T00:00:00Z', resourceId: { videoId: 'DDDDDDDDDDD' } }, contentDetails: { videoId: 'DDDDDDDDDDD', videoPublishedAt: '2025-12-31T00:00:00Z' } });
  assert.deepEqual(v, { videoId: 'DDDDDDDDDDD', title: 'Aarti', thumbnail: 'https://i.ytimg.com/vi/DDDDDDDDDDD/hqdefault.jpg', publishedAt: '2025-12-31T00:00:00Z' });
  assert.equal(V.mapApiItem({ snippet: { title: 'Deleted video', resourceId: { videoId: 'EEEEEEEEEEE' } } }), null);
  assert.equal(V.mapApiItem({ snippet: { title: 'x' } }), null);
});

function jsonRes(obj) {
  return { ok: true, status: 200, json: async () => obj, text: async () => JSON.stringify(obj) };
}

test('fetchFromApi paginates the whole playlist and stops at API_MAX_VIDEOS', async () => {
  let calls = 0;
  const fetchImpl = async (url) => {
    calls++;
    const u = new URL(url);
    assert.equal(u.searchParams.get('part'), 'snippet,contentDetails');
    assert.equal(u.searchParams.get('maxResults'), '50');
    const page = Number(u.searchParams.get('pageToken') || 0);
    const items = Array.from({ length: 50 }, (_, i) => {
      const id = `v${String(page * 50 + i).padStart(10, '0')}`;
      return { snippet: { title: `T${page * 50 + i}` }, contentDetails: { videoId: id } };
    });
    return jsonRes({ items, nextPageToken: String(page + 1) });
  };
  const r = await V.fetchFromApi('PLx', 'KEY', fetchImpl);
  assert.ok(V.API_MAX_VIDEOS >= 300);
  assert.equal(calls, V.API_MAX_VIDEOS / 50);
  assert.equal(r.videos.length, V.API_MAX_VIDEOS);
  assert.equal(r.complete, false);
  assert.equal(r.source, 'api');

  const short = await V.fetchFromApi('PLy', 'KEY', async () => jsonRes({ items: [{ snippet: { title: 'A' }, contentDetails: { videoId: 'AAAAAAAAAAA' } }] }));
  assert.equal(short.complete, true);
  assert.equal(short.videos.length, 1);
});

test('cache evicts oldest beyond max size and expires after TTL', () => {
  V.cache.clear();
  for (let i = 0; i < V.CACHE_MAX + 5; i++) V.cacheSet(`k${i}`, i, 1000);
  assert.equal(V.cache.size, V.CACHE_MAX);
  assert.equal(V.cacheGet('k0', 1000), null);
  assert.equal(V.cacheGet(`k${V.CACHE_MAX + 4}`, 1000), V.CACHE_MAX + 4);
  assert.equal(V.cacheGet(`k${V.CACHE_MAX + 4}`, 1000 + V.CACHE_TTL_MS + 1), null);
  V.cache.clear();
});

test('playlist data file is intact', () => {
  assert.equal(PLAYLISTS.length, 180);
  for (const p of PLAYLISTS) assert.ok(p.playlistId && p.title && p.category);
});

test('videos routes', async (t) => {
  const srv = await serve(videosRouter, '/api/videos');
  const realFetch = global.fetch;
  const savedKey = process.env.YOUTUBE_API_KEY;
  t.after(async () => {
    global.fetch = realFetch;
    if (savedKey === undefined) delete process.env.YOUTUBE_API_KEY; else process.env.YOUTUBE_API_KEY = savedKey;
    await srv.close();
  });
  delete process.env.YOUTUBE_API_KEY;
  const store = fake.reset();
  store.users.set(1, { role: 'user', full_name: 'Asha' });
  store.ledger.push({ id: 1, user_id: 1, amount: 1, reason: 'video', ref: 'BBBBBBBBB-_', note: null, created_at: new Date() });

  const pid = PLAYLISTS[0].playlistId;
  const pid2 = PLAYLISTS[1].playlistId;
  let upstreamCalls = 0;
  // The test server itself is reached through the real fetch; only YouTube is stubbed.
  global.fetch = async (url, opts) => {
    const s = String(url);
    if (s.startsWith('https://www.youtube.com/feeds/videos.xml')) {
      upstreamCalls++;
      if (s.includes(encodeURIComponent(pid2))) return { ok: false, status: 500, text: async () => '' };
      return { ok: true, status: 200, text: async () => RSS };
    }
    return realFetch(url, opts);
  };

  await t.test('GET /playlists', async () => {
    const r = await call(srv.url, 'GET', '/playlists');
    assert.equal(r.status, 200);
    assert.equal(r.body.playlists.length, 180);
    assert.ok(r.body.categories.length > 1);
    assert.ok(r.body.categories.includes(PLAYLISTS[0].category));
    assert.deepEqual(Object.keys(r.body.playlists[0]).sort(), ['category', 'no', 'playlistId', 'title']);
  });

  await t.test('unknown playlist -> 404', async () => {
    const r = await call(srv.url, 'GET', '/playlists/PLnotInTheList123');
    assert.equal(r.status, 404);
  });

  await t.test('RSS fallback, cached, with watched ids when logged in', async () => {
    V.cache.clear();
    const a = await call(srv.url, 'GET', `/playlists/${pid}`);
    assert.equal(a.status, 200);
    assert.equal(a.body.playlistId, pid);
    assert.equal(a.body.title, PLAYLISTS[0].title);
    assert.equal(a.body.source, 'rss');
    assert.equal(a.body.complete, false);
    assert.equal(a.body.videos.length, 2);
    assert.equal(a.body.watched, undefined);
    const b = await call(srv.url, 'GET', `/playlists/${pid}`, { token: signToken({ userId: 1, role: 'user' }) });
    assert.deepEqual(b.body.watched, ['BBBBBBBBB-_']);
    assert.equal(upstreamCalls, 1, 'second call served from cache');
  });

  await t.test('no API key + RSS down -> 200 player mode, cached', async () => {
    V.cache.clear();
    V.failures.clear();
    const before = upstreamCalls;
    const r = await call(srv.url, 'GET', `/playlists/${pid2}`, { token: signToken({ userId: 1, role: 'user' }) });
    assert.equal(r.status, 200);
    assert.equal(r.body.playlistId, pid2);
    assert.equal(r.body.title, PLAYLISTS[1].title);
    assert.deepEqual(r.body.videos, []);
    assert.equal(r.body.source, 'player');
    assert.equal(r.body.playerOnly, true);
    assert.deepEqual(r.body.watched, []);
    const again = await call(srv.url, 'GET', `/playlists/${pid2}`);
    assert.equal(again.body.playerOnly, true);
    assert.equal(upstreamCalls, before + 1, 'player-mode answer cached, RSS not hit again');
  });

  await t.test('lists with videos carry no playerOnly flag', async () => {
    const r = await call(srv.url, 'GET', `/playlists/${pid}`);
    assert.equal(r.body.playerOnly, undefined);
  });

  await t.test('API key set and API + RSS both down -> friendly 502', async () => {
    V.cache.clear();
    V.failures.clear();
    process.env.YOUTUBE_API_KEY = 'KEY';
    const prev = global.fetch;
    global.fetch = async (url, opts) =>
      String(url).startsWith('https://www.googleapis.com')
        ? { ok: false, status: 403, json: async () => ({}) }
        : prev(url, opts);
    try {
      const r = await call(srv.url, 'GET', `/playlists/${pid2}`);
      assert.equal(r.status, 502);
      assert.equal(r.body.code, 'UPSTREAM_ERROR');
      assert.ok(r.body.error);
    } finally {
      global.fetch = prev;
      delete process.env.YOUTUBE_API_KEY;
      V.cache.clear();
      V.failures.clear();
    }
  });
});

test('fetchFromApi keeps earlier pages when a later page fails; first-page failure throws', async () => {
  const page = (n, next) => jsonRes({ items: Array.from({ length: 50 }, (_, i) => ({ snippet: { title: 't' }, contentDetails: { videoId: `p${n}${String(i).padStart(9, '0')}` } })), nextPageToken: next });
  let calls = 0;
  const flaky = async () => (++calls === 1 ? page(1, 'x') : { ok: false, status: 403, json: async () => ({}) });
  const r = await V.fetchFromApi('PLx', 'KEY', flaky);
  assert.equal(r.videos.length, 50);
  assert.equal(r.complete, false);
  await assert.rejects(V.fetchFromApi('PLx', 'KEY', async () => { throw new Error('ECONNRESET'); }));
  await assert.rejects(V.fetchFromApi('PLx', 'KEY', async () => ({ ok: true, status: 200, json: async () => { throw new SyntaxError('bad json'); } })));
});

test('loadPlaylist: API -> RSS fallback, short TTL for empty lists, failures cached briefly', async () => {
  V.cache.clear();
  V.failures.clear();
  let t0 = 1_000_000;
  const now = () => t0;
  let rssCalls = 0;
  let down = false;
  const fetchImpl = async (url) => {
    if (String(url).startsWith('https://www.googleapis.com')) return { ok: false, status: 403, json: async () => ({}) };
    rssCalls++;
    if (down) throw new Error('ETIMEDOUT');
    return { ok: true, status: 200, text: async () => '<feed></feed>' };
  };
  const a = await V.loadPlaylist('PLempty', { apiKey: 'KEY', fetchImpl, now });
  assert.equal(a.source, 'rss');
  assert.deepEqual(a.videos, []);
  t0 += V.EMPTY_TTL_MS - 1;
  await V.loadPlaylist('PLempty', { apiKey: 'KEY', fetchImpl, now });
  assert.equal(rssCalls, 1, 'empty list cached for a short while');
  t0 += 2;
  down = true;
  // With an API key, API + RSS both failing is a real outage: reject (route answers 502).
  await assert.rejects(V.loadPlaylist('PLempty', { apiKey: 'KEY', fetchImpl, now }));
  assert.equal(rssCalls, 2, 'refetched after the short TTL');
  await assert.rejects(V.loadPlaylist('PLempty', { apiKey: 'KEY', fetchImpl, now }));
  assert.equal(rssCalls, 2, 'recent failure answered without calling YouTube again');
  t0 += V.FAILURE_TTL_MS + 1;
  down = false;
  await V.loadPlaylist('PLempty', { apiKey: '', fetchImpl, now });
  assert.equal(rssCalls, 3);
  assert.equal(V.failures.has('PLempty'), false);
  V.cache.clear();
  V.failures.clear();
});

test('loadPlaylist without an API key: RSS failure -> player mode, cached ~30 min', async () => {
  V.cache.clear();
  V.failures.clear();
  let t0 = 5_000_000;
  const now = () => t0;
  let rssCalls = 0;
  let apiCalls = 0;
  let rssOk = false;
  const fetchImpl = async (url) => {
    if (String(url).startsWith('https://www.googleapis.com')) { apiCalls++; return { ok: false, status: 403, json: async () => ({}) }; }
    rssCalls++;
    return rssOk ? { ok: true, status: 200, text: async () => RSS } : { ok: false, status: 404, text: async () => '' };
  };
  const a = await V.loadPlaylist('PLgone', { apiKey: '', fetchImpl, now });
  assert.deepEqual(a, { videos: [], source: 'player', complete: false, playerOnly: true });
  assert.equal(V.failures.has('PLgone'), false, 'player mode is an answer, not a failure');
  t0 += V.PLAYER_TTL_MS - 1;
  await V.loadPlaylist('PLgone', { apiKey: '', fetchImpl, now });
  assert.equal(rssCalls, 1, 'player-mode answer cached, RSS not hammered');
  t0 += 2;
  rssOk = true;
  const b = await V.loadPlaylist('PLgone', { apiKey: '', fetchImpl, now });
  assert.equal(rssCalls, 2, 'RSS retried after the player TTL');
  assert.equal(b.source, 'rss');
  assert.equal(b.videos.length, 2);
  assert.equal(apiCalls, 0, 'no API calls without a key');
  assert.ok(V.PLAYER_TTL_MS >= 20 * 60 * 1000 && V.PLAYER_TTL_MS <= 60 * 60 * 1000);
  V.cache.clear();
  V.failures.clear();
});
