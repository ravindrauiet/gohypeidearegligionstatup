// Blocked accounts (admin "Block user", routes/admin_users.js).
//
// auth.js asks isBlocked() on every authenticated request, so it must not cost a DB query each
// time: each server instance keeps the full set of blocked user ids in memory and reloads it when
// it is older than CACHE_MS. Blocking is rare and the set is tiny. The admin route calls refresh()
// after a block/unblock so this instance sees the change at once; other instances pick it up
// within CACHE_MS.
//
// A failed load (DB down, or a test stub that does not know the query) counts as "nobody blocked":
// failing open keeps the app usable, and email/Google login still read users.is_blocked directly.
const db = require('../db');

const CACHE_MS = 30 * 1000;

let blocked = new Set();
let loadedAt = 0; // 0 = must reload on next call
let loading = null; // in-flight load, shared by concurrent callers
let warned = false;
let generation = 0; // bumped by refresh(); a load that started before a refresh stays stale

async function load() {
  const gen = generation;
  try {
    const r = await db.query('SELECT id FROM users WHERE is_blocked');
    const rows = (r && Array.isArray(r.rows)) ? r.rows : [];
    blocked = new Set(rows.map((row) => Number(row.id)).filter((id) => Number.isInteger(id) && id > 0));
  } catch (err) {
    if (!warned) {
      warned = true;
      console.warn('Blocked-user list could not be loaded; treating nobody as blocked:', err.message);
    }
    blocked = new Set();
  }
  // Also set on failure, so a broken query is retried every CACHE_MS rather than on every request.
  // Not when refresh() ran meanwhile: this result may predate the block/unblock.
  if (gen === generation) loadedAt = Date.now();
}

// true when the account is blocked. Never throws.
async function isBlocked(userId) {
  const id = Number(userId);
  if (!Number.isInteger(id) || id <= 0) return false;
  if (!loadedAt || Date.now() - loadedAt > CACHE_MS) {
    // Join an in-flight load only if it started after the last refresh().
    if (!loading || loading.gen !== generation) {
      const p = load().finally(() => { if (loading === p) loading = null; });
      p.gen = generation;
      loading = p;
    }
    await loading;
  }
  return blocked.has(id);
}

// Forces a reload on the next isBlocked() call (after an admin block/unblock).
function refresh() {
  generation += 1;
  loadedAt = 0;
}

module.exports = { isBlocked, refresh, CACHE_MS };
