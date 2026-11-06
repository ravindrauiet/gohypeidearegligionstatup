// Trust features (v3): verified badge selfies, phone-check hashing, biodata validation and the
// Kundli basics shown to family. Pure helpers only (no db), unit-tested in test/trust.test.js.
const crypto = require('crypto');
const A = require('./astrology_service');

// ---------------------------------------------------------------------------
// Verified badge (selfie with a gesture)
// ---------------------------------------------------------------------------
// Same list as lib/services/trust_service.dart (TrustGestures.all). The app picks one at random.
const GESTURES = [
  'Hold up two fingers',
  'Touch your ear',
  'Thumbs up',
  'Hand on your forehead',
  'Three fingers up',
  'Wave with an open palm',
  'Point at your nose',
  'Cover one eye with your hand',
];
const MAX_SELFIE_BYTES = 400 * 1024;
const VERIFICATIONS_PER_DAY = 3;
const REJECT_REASON_MAX = 300;

/**
 * Validates a base64 selfie (optionally a data: URI). Returns the clean base64 string, or throws
 * an Error whose message is safe to show. JPEG or PNG only, at most MAX_SELFIE_BYTES decoded.
 */
function cleanSelfie(input) {
  if (typeof input !== 'string' || !input) throw new Error('Take a selfie first');
  let s = input.trim();
  const m = /^data:image\/(jpeg|jpg|png);base64,/i.exec(s);
  if (m) s = s.slice(m[0].length);
  s = s.replace(/\s+/g, '');
  // Reject before decoding anything huge (base64 is ~4/3 of the bytes).
  if (s.length > Math.ceil(MAX_SELFIE_BYTES / 3) * 4 + 4) throw new Error('This photo is too large. Please retake it.');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(s) || s.length % 4 !== 0) throw new Error('This photo could not be read');
  const buf = Buffer.from(s, 'base64');
  if (buf.length < 1024) throw new Error('This photo could not be read');
  if (buf.length > MAX_SELFIE_BYTES) throw new Error('This photo is too large. Please retake it.');
  const jpeg = buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
  const png = buf.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  if (!jpeg && !png) throw new Error('Please send a JPEG or PNG photo');
  return { base64: s, mime: jpeg ? 'image/jpeg' : 'image/png', bytes: buf.length };
}

function mimeOf(base64) {
  return String(base64 || '').startsWith('iVBOR') ? 'image/png' : 'image/jpeg';
}

// ---------------------------------------------------------------------------
// Phone check: only a keyed hash of the E.164 number is stored, never the number.
// PHONE_HASH_PEPPER (optional, keep it stable) makes the hash an HMAC so the 10-digit space
// cannot be brute-forced from a leaked table; without it a namespaced SHA-256 is used.
// ---------------------------------------------------------------------------
function phoneHash(e164) {
  const n = String(e164 || '').replace(/[^\d+]/g, '');
  const pepper = (process.env.PHONE_HASH_PEPPER || '').trim();
  return pepper
    ? crypto.createHmac('sha256', pepper).update(n).digest('hex')
    : crypto.createHash('sha256').update(`cosmicguide:phone:${n}`).digest('hex');
}

// ---------------------------------------------------------------------------
// Biodata (life-partner details). All optional. Stored in buddy_profiles.biodata (JSONB).
// ---------------------------------------------------------------------------
const BIODATA_TEXT = {
  education: 80,
  profession: 80,
  community: 40,
  gotra: 40,
  fatherOccupation: 80,
  motherOccupation: 80,
  siblings: 120,
  aboutFamily: 300,
  partnerExpectations: 300,
};
// Same keys as lib/services/trust_service.dart (BiodataOptions).
const INCOME_RANGES = ['under_3l', '3_6l', '6_10l', '10_20l', '20_35l', '35_50l', '50l_1cr', 'above_1cr', 'prefer_not'];
const DIETS = ['veg', 'non_veg', 'eggetarian', 'jain', 'vegan'];
const HEIGHT_MIN = 120;
const HEIGHT_MAX = 230;
const BIODATA_KEYS = ['heightCm', 'incomeRange', 'diet', ...Object.keys(BIODATA_TEXT)];
const LONG_TEXT = new Set(['aboutFamily', 'partnerExpectations']);

/** Validates a biodata body. Returns the normalised object (empty fields dropped) or throws Error. */
function validateBiodata(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('Biodata must be an object');
  const out = {};
  const has = (k) => Object.prototype.hasOwnProperty.call(body, k) && body[k] !== undefined && body[k] !== null && body[k] !== '';
  if (has('heightCm')) {
    const h = Number(body.heightCm);
    if (!Number.isInteger(h) || h < HEIGHT_MIN || h > HEIGHT_MAX) throw new Error(`Height must be ${HEIGHT_MIN} to ${HEIGHT_MAX} cm`);
    out.heightCm = h;
  }
  if (has('incomeRange')) {
    if (!INCOME_RANGES.includes(body.incomeRange)) throw new Error('Choose an income range from the list');
    out.incomeRange = body.incomeRange;
  }
  if (has('diet')) {
    if (!DIETS.includes(body.diet)) throw new Error('Choose a diet from the list');
    out.diet = body.diet;
  }
  for (const [k, max] of Object.entries(BIODATA_TEXT)) {
    if (!has(k)) continue;
    if (typeof body[k] !== 'string') throw new Error(`${k} must be text`);
    const v = LONG_TEXT.has(k)
      ? body[k].replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim()
      : body[k].replace(/\s+/g, ' ').trim();
    if (v.length > max) throw new Error(`${k} can be at most ${max} characters`);
    if (v) out[k] = v;
  }
  return out;
}

/** Safe read of a stored biodata value (JSONB object or JSON text); only known keys survive. */
function biodataView(raw) {
  let b = raw;
  if (typeof b === 'string') { try { b = JSON.parse(b); } catch (_) { b = null; } }
  if (!b || typeof b !== 'object' || Array.isArray(b)) return {};
  try { return validateBiodata(Object.fromEntries(BIODATA_KEYS.filter((k) => k in b).map((k) => [k, b[k]]))); } catch (_) {
    // A stored row that no longer validates: keep only the fields that still do.
    const out = {};
    for (const k of BIODATA_KEYS) {
      try { Object.assign(out, validateBiodata({ [k]: b[k] })); } catch (__) { /* drop */ }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Kundli basics for family pages: Moon sign, nakshatra, manglik only (never birth date/time/place).
// ---------------------------------------------------------------------------
function manglikFrom(planets) {
  let list = planets;
  if (typeof list === 'string') { try { list = JSON.parse(list); } catch (_) { list = null; } }
  if (list && !Array.isArray(list) && typeof list === 'object') list = Object.entries(list).map(([name, v]) => ({ name, ...(v || {}) }));
  const s = A.manglikStatus(list || []).status;
  return s === 'Manglik' ? true : s === 'Non-Manglik' ? false : null;
}

module.exports = {
  GESTURES,
  MAX_SELFIE_BYTES,
  VERIFICATIONS_PER_DAY,
  REJECT_REASON_MAX,
  cleanSelfie,
  mimeOf,
  phoneHash,
  BIODATA_TEXT,
  BIODATA_KEYS,
  INCOME_RANGES,
  DIETS,
  HEIGHT_MIN,
  HEIGHT_MAX,
  validateBiodata,
  biodataView,
  manglikFrom,
};
