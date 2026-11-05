// Devotional video library (/api/videos), built on the curated Tilak playlists in
// data/youtube_playlists.json. Uses the YouTube Data API v3 when YOUTUBE_API_KEY is set,
// otherwise the public playlist RSS feed (latest ~15 videos). Results are cached in memory.
// Without an API key, when the RSS feed fails (YouTube now answers 404 for playlist feeds),
// the detail route answers 200 in "player mode" ({ videos: [], source: 'player',
// playerOnly: true }) and the app plays the whole playlist by id in the YouTube player.
const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');
const PLAYLISTS = require('../data/youtube_playlists.json');

const CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const EMPTY_TTL_MS = 10 * 60 * 1000; // an empty list is often a YouTube hiccup (consent page, new playlist)
const FAILURE_TTL_MS = 60 * 1000; // while YouTube is down, answer 502 fast instead of waiting on it again
const PLAYER_TTL_MS = 30 * 60 * 1000; // no API key + RSS down: keep answering "player mode" without re-hitting RSS
const CACHE_MAX = 200;
const FETCH_TIMEOUT_MS = 8000;
// Whole playlists: 20 pages x 50 (1 quota unit per page). Longer ones are returned with complete:false.
const API_MAX_VIDEOS = 1000;
const SKIP_TITLES = new Set(['Private video', 'Deleted video']);
const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;

const PLAYLIST_BY_ID = new Map(PLAYLISTS.map((p) => [p.playlistId, p]));
const CATEGORIES = [...new Set(PLAYLISTS.map((p) => p.category).filter(Boolean))];

const thumbnailFor = (videoId) => `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`;

// ---------------------------------------------------------------------------
// XML / RSS parsing (no dependencies; YouTube's Atom feed is simple and stable)
// ---------------------------------------------------------------------------
function decodeXml(s) {
  if (s === undefined || s === null) return '';
  let out = String(s);
  const cdata = out.match(/^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/);
  if (cdata) return cdata[1];
  out = out.replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/g, (m, ent) => {
    if (ent[0] === '#') {
      const code = ent[1] === 'x' || ent[1] === 'X' ? parseInt(ent.slice(2), 16) : parseInt(ent.slice(1), 10);
      try { return Number.isFinite(code) ? String.fromCodePoint(code) : m; } catch (_) { return m; }
    }
    return { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" }[ent];
  });
  return out;
}

function tag(xml, name) {
  const re = new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`);
  const m = xml.match(re);
  return m ? decodeXml(m[1]).trim() : null;
}

function parsePlaylistRss(xml) {
  const videos = [];
  const seen = new Set();
  const re = /<entry(?:\s[^>]*)?>([\s\S]*?)<\/entry>/g;
  let m;
  while ((m = re.exec(String(xml || ''))) !== null) {
    const entry = m[1];
    const videoId = tag(entry, 'yt:videoId');
    if (!videoId || !VIDEO_ID_RE.test(videoId) || seen.has(videoId)) continue;
    const title = tag(entry, 'title') || tag(entry, 'media:title') || '';
    if (SKIP_TITLES.has(title)) continue;
    seen.add(videoId);
    videos.push({ videoId, title, thumbnail: thumbnailFor(videoId), publishedAt: tag(entry, 'published') });
  }
  return videos;
}

// Maps one playlistItems.list item to our shape (null when it should be skipped).
function mapApiItem(item) {
  const sn = (item && item.snippet) || {};
  const cd = (item && item.contentDetails) || {};
  const videoId = cd.videoId || (sn.resourceId && sn.resourceId.videoId);
  const title = sn.title || '';
  if (!videoId || !VIDEO_ID_RE.test(videoId) || SKIP_TITLES.has(title)) return null;
  return { videoId, title, thumbnail: thumbnailFor(videoId), publishedAt: cd.videoPublishedAt || sn.publishedAt || null };
}

// ---------------------------------------------------------------------------
// Upstream fetchers
// ---------------------------------------------------------------------------
class UpstreamError extends Error {}

async function fetchWithTimeout(url, fetchImpl) {
  let res;
  try {
    res = await fetchImpl(url, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS), headers: { 'Accept-Language': 'en' } });
  } catch (err) {
    throw new UpstreamError(`fetch failed: ${err && err.message}`);
  }
  if (!res.ok) throw new UpstreamError(`upstream HTTP ${res.status}`);
  return res;
}

async function fetchFromApi(playlistId, apiKey, fetchImpl = fetch) {
  const videos = [];
  const seen = new Set();
  let pageToken = '';
  let complete = false;
  for (let page = 0; page < Math.ceil(API_MAX_VIDEOS / 50); page++) {
    const qs = new URLSearchParams({ part: 'snippet,contentDetails', maxResults: '50', playlistId, key: apiKey });
    if (pageToken) qs.set('pageToken', pageToken);
    let data;
    try {
      const res = await fetchWithTimeout(`https://www.googleapis.com/youtube/v3/playlistItems?${qs}`, fetchImpl);
      data = await res.json();
      if (!data || typeof data !== 'object') throw new UpstreamError('bad API response');
    } catch (err) {
      // First page failed: let the caller fall back to RSS. Later page: keep what we already have.
      if (!videos.length) throw err;
      console.warn(`YouTube API page ${page + 1} failed for ${playlistId}:`, err.message);
      break;
    }
    for (const item of data.items || []) {
      const v = mapApiItem(item);
      if (v && !seen.has(v.videoId)) {
        seen.add(v.videoId);
        videos.push(v);
      }
    }
    pageToken = data.nextPageToken || '';
    if (!pageToken) {
      complete = true;
      break;
    }
  }
  return { videos: videos.slice(0, API_MAX_VIDEOS), source: 'api', complete };
}

async function fetchFromRss(playlistId, fetchImpl = fetch) {
  const res = await fetchWithTimeout(`https://www.youtube.com/feeds/videos.xml?playlist_id=${encodeURIComponent(playlistId)}`, fetchImpl);
  const xml = await res.text();
  return { videos: parsePlaylistRss(xml), source: 'rss', complete: false };
}

// ---------------------------------------------------------------------------
// Cache (TTL + max size, oldest evicted first; concurrent misses share one fetch)
// ---------------------------------------------------------------------------
const cache = new Map();
const inflight = new Map();

function cacheGet(key, now = Date.now()) {
  const hit = cache.get(key);
  if (!hit) return null;
  if (now - hit.at > (hit.ttl || CACHE_TTL_MS)) {
    cache.delete(key);
    return null;
  }
  return hit.value;
}

function cacheSet(key, value, now = Date.now(), ttl = CACHE_TTL_MS) {
  cache.delete(key);
  cache.set(key, { at: now, value, ttl });
  while (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);
}

const failures = new Map(); // playlistId -> time of the last failed upstream fetch

// No video list available: the app plays the playlist by id in the YouTube player instead.
const playerOnlyResult = () => ({ videos: [], source: 'player', complete: false, playerOnly: true });

let apiKeyHintLogged = false;
function logApiKeyHint() {
  if (apiKeyHintLogged) return;
  apiKeyHintLogged = true;
  console.warn('Videos: playlist RSS feed unavailable, answering in player mode. Set YOUTUBE_API_KEY to list playlist videos.');
}

async function loadPlaylist(playlistId, { apiKey = process.env.YOUTUBE_API_KEY, fetchImpl = fetch, now = Date.now } = {}) {
  const cached = cacheGet(playlistId, now());
  if (cached) return cached;
  if (inflight.has(playlistId)) return inflight.get(playlistId);
  const failedAt = failures.get(playlistId);
  if (failedAt !== undefined && now() - failedAt < FAILURE_TTL_MS) throw new UpstreamError('recent upstream failure');
  const p = (async () => {
    let result;
    const key = (apiKey || '').trim();
    if (key) {
      try {
        result = await fetchFromApi(playlistId, key, fetchImpl);
      } catch (err) {
        console.warn(`YouTube API failed for ${playlistId}, falling back to RSS:`, err.message);
      }
    }
    let ttl;
    if (!result) {
      try {
        result = await fetchFromRss(playlistId, fetchImpl);
      } catch (err) {
        // API key set and both sources failed: a real outage, the route answers 502.
        if (key) throw err;
        logApiKeyHint();
        console.warn(`Playlist RSS failed for ${playlistId} (${err.message}); answering in player mode`);
        result = playerOnlyResult();
        ttl = PLAYER_TTL_MS;
      }
    }
    if (ttl === undefined) ttl = result.videos.length ? CACHE_TTL_MS : EMPTY_TTL_MS;
    cacheSet(playlistId, result, now(), ttl);
    failures.delete(playlistId);
    return result;
  })();
  inflight.set(playlistId, p);
  try {
    return await p;
  } catch (err) {
    failures.set(playlistId, now());
    if (failures.size > CACHE_MAX) failures.delete(failures.keys().next().value);
    throw err;
  } finally {
    inflight.delete(playlistId);
  }
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
router.get('/playlists', (req, res) => {
  res.set('Cache-Control', 'public, max-age=3600');
  res.json({
    categories: CATEGORIES,
    playlists: PLAYLISTS.map((p) => ({
      no: p.no,
      title: p.title,
      category: p.category,
      playlistId: p.playlistId,
      ...(p.thumbnail ? { thumbnail: p.thumbnail } : {}),
    })),
  });
});

router.get('/playlists/:playlistId', optionalAuthenticateToken, async (req, res) => {
  const playlistId = String(req.params.playlistId || '');
  const meta = PLAYLIST_BY_ID.get(playlistId);
  if (!meta) return res.status(404).json({ error: 'Playlist not found.', code: 'PLAYLIST_NOT_FOUND' });

  let data;
  try {
    data = await loadPlaylist(playlistId);
  } catch (err) {
    console.error(`Playlist ${playlistId} fetch failed:`, err.message);
    return res.status(502).json({ error: 'Could not load videos right now. Please try again in a little while.', code: 'UPSTREAM_ERROR' });
  }

  const body = { playlistId, title: meta.title, videos: data.videos, source: data.source, complete: data.complete };
  // Nothing to list: the app plays the playlist by id in the YouTube player instead.
  if (data.playerOnly || !data.videos.length) body.playerOnly = true;
  if (req.user && req.user.role !== 'guest') {
    try {
      const ids = data.videos.map((v) => v.videoId);
      const r = ids.length
        ? await db.query(`SELECT ref FROM coin_ledger WHERE user_id = $1 AND reason = 'video' AND ref = ANY($2::text[])`, [req.user.userId, ids])
        : { rows: [] };
      body.watched = r.rows.map((x) => x.ref);
    } catch (err) {
      console.error('Watched lookup failed:', err.message);
      body.watched = [];
    }
  }
  res.json(body);
});

router._internals = {
  decodeXml, parsePlaylistRss, mapApiItem, fetchFromApi, fetchFromRss, loadPlaylist, cache, failures, cacheGet, cacheSet,
  CACHE_MAX, CACHE_TTL_MS, EMPTY_TTL_MS, FAILURE_TTL_MS, PLAYER_TTL_MS, API_MAX_VIDEOS
};

module.exports = router;
