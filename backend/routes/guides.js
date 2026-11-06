// Puja & vrat guides (public, read-only).
//   GET /api/guides?lat=&lng=&tz=        -> { version, guides: [summary + nextDate] }
//   GET /api/guides/:id?lat=&lng=&tz=    -> full guide + nextDate / nextDates
// Content: data/puja_guides.json (also bundled in the app for offline use).
const express = require('express');
const G = require('../services/guide_service');

const router = express.Router();

function locationOf(q) {
  const lat = Number(q.lat);
  const lng = Number(q.lng);
  const ok = q.lat !== undefined && q.lng !== undefined && Number.isFinite(lat) && Number.isFinite(lng)
    && Math.abs(lat) <= 66 && Math.abs(lng) <= 180;
  const tz = typeof q.tz === 'string' && q.tz.trim() ? q.tz.trim() : undefined;
  return ok ? { lat, lng, tz } : { tz };
}

// Next dates are a convenience: a calendar failure must never hide the content.
function datesOrNull(q) {
  try {
    return G.upcomingDates(locationOf(q));
  } catch (e) {
    console.warn('guides: date calculation failed', e.message);
    return null;
  }
}

router.get('/', (req, res) => {
  res.set('Cache-Control', 'public, max-age=3600');
  res.json({ version: G.GUIDES.version, guides: G.listGuides(datesOrNull(req.query)) });
});

router.get('/:id', (req, res) => {
  const id = String(req.params.id || '');
  if (!/^[a-z0-9_]{1,60}$/.test(id)) return res.status(404).json({ error: 'Guide not found' });
  const guide = G.getGuide(id, datesOrNull(req.query));
  if (!guide) return res.status(404).json({ error: 'Guide not found' });
  res.set('Cache-Control', 'public, max-age=3600');
  return res.json({ guide });
});

module.exports = router;
