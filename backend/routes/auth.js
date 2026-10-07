const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const db = require('../db');
const { refreshDashaInfo, recomputeLegacyKundli } = require('../services/astrology_service');

// ---------------------------------------------------------------------------
// JWT secret: must be configured. A hard-coded fallback would let anyone who
// has read this repository forge tokens, so production refuses to start.
// ---------------------------------------------------------------------------
const IS_PRODUCTION = process.env.NODE_ENV === 'production' || !!process.env.VERCEL;
let JWT_SECRET = (process.env.JWT_SECRET || '').trim();
if (!JWT_SECRET) {
  if (IS_PRODUCTION) {
    throw new Error('FATAL: JWT_SECRET environment variable is not set. Refusing to start in production.');
  }
  JWT_SECRET = crypto.randomBytes(32).toString('hex');
  console.warn('\n⚠️  JWT_SECRET is not set. Using a random development-only secret; all tokens will be invalidated on restart.\n');
} else if (JWT_SECRET.length < 16) {
  console.warn('⚠️  JWT_SECRET is shorter than 16 characters. Use a long random value in production.');
}

const TOKEN_TTL = '30d';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MIN_PASSWORD_LENGTH = 6;

function signToken(payload) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: TOKEN_TTL });
}

function extractToken(req) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || typeof authHeader !== 'string') return null;
  const [scheme, token] = authHeader.split(' ');
  if (!/^Bearer$/i.test(scheme) || !token || token === 'null' || token === 'undefined') return null;
  return token;
}

function verifyToken(token) {
  const decoded = jwt.verify(token, JWT_SECRET);
  if (!decoded || !Number.isInteger(Number(decoded.userId))) {
    throw new Error('Malformed token payload');
  }
  decoded.userId = Number(decoded.userId);
  return decoded;
}

// Verifies a token. Guest tokens are only honoured while the account is still a guest
// account (after the guest registers, the old guest token must stop working).
async function verifySessionToken(token) {
  const decoded = verifyToken(token);
  if (decoded.role === 'guest') {
    const r = await db.query('SELECT role FROM users WHERE id = $1', [decoded.userId]);
    if (!r.rows[0] || r.rows[0].role !== 'guest') throw new Error('Guest session no longer valid');
  }
  return decoded;
}

// Requires a valid token.
async function authenticateToken(req, res, next) {
  const token = extractToken(req);
  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }
  try {
    req.user = await verifySessionToken(token);
    return next();
  } catch (_) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Uses the token when present; anonymous requests proceed with req.user = null.
// An invalid/expired token is rejected so the client can re-authenticate instead
// of silently being switched to a different (empty) account.
async function optionalAuthenticateToken(req, res, next) {
  const token = extractToken(req);
  if (!token) {
    req.user = null;
    return next();
  }
  try {
    req.user = await verifySessionToken(token);
    return next();
  } catch (_) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Like optionalAuthenticateToken, but anonymous callers get a persistent guest
// account. The guest token is returned in the `X-Guest-Token` response header so
// the client can keep using the same guest account on subsequent requests.
async function guestOrAuthenticateToken(req, res, next) {
  const token = extractToken(req);
  if (token) {
    try {
      req.user = await verifySessionToken(token);
      return next();
    } catch (_) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
  }

  try {
    const guestEmail = `guest_${Date.now()}_${crypto.randomBytes(6).toString('hex')}@guest.astroai.com`;
    const passwordHash = await bcrypt.hash(crypto.randomBytes(24).toString('hex'), 10);
    const result = await db.query(
      `INSERT INTO users (email, password_hash, full_name, gender, role)
       VALUES ($1, $2, $3, $4, 'guest') RETURNING id, email`,
      [guestEmail, passwordHash, 'Guest User', 'Not Specified']
    );
    const guestUser = result.rows[0];
    req.user = { userId: guestUser.id, email: guestUser.email, role: 'guest' };
    const guestToken = signToken({ userId: guestUser.id, email: guestUser.email, role: 'guest' });
    res.setHeader('X-Guest-Token', guestToken);
    return next();
  } catch (err) {
    console.error('Guest creation error:', err);
    return res.status(503).json({ error: 'Unable to create a guest session right now. Please try again or log in.' });
  }
}

function publicUser(row) {
  return {
    id: row.id,
    email: row.email,
    fullName: row.full_name,
    gender: row.gender,
    role: row.role || 'user',
    createdAt: row.created_at
  };
}

function kundliFromRow(row, fallbackName) {
  if (!row || !row.ascendant) return null;
  const stored = row.kundli_data && typeof row.kundli_data === 'object' ? row.kundli_data : null;
  const legacy = stored ? null : recomputeLegacyKundli(row);
  return refreshDashaInfo({
    ...(stored || {}),
    ascendant: row.ascendant,
    sunSign: row.sun_sign,
    moonSign: row.moon_sign,
    nakshatra: row.nakshatra,
    nakshatraPada: row.nakshatra_pada,
    planetaryPositions: row.planetary_positions,
    houses: row.houses,
    dashaInfo: row.dasha_info,
    ...(legacy || {}),
    aiReport: row.ai_report || (stored && stored.aiReport) || null,
    birthDetails: {
      fullName: row.full_name || fallbackName,
      gender: row.gender,
      dateOfBirth: row.date_of_birth,
      timeOfBirth: row.time_of_birth,
      placeOfBirth: row.place_of_birth,
      latitude: row.latitude,
      longitude: row.longitude,
      timezone: row.timezone
    }
  });
}

async function loadUserKundli(userId, fallbackName) {
  const kundliRes = await db.query(
    `SELECT bd.full_name, bd.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth, bd.latitude, bd.longitude, bd.timezone,
            k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada, k.planetary_positions, k.houses,
            k.dasha_info, k.ai_report, k.kundli_data
     FROM birth_details bd
     LEFT JOIN kundlis k ON bd.user_id = k.user_id
     WHERE bd.user_id = $1`,
    [userId]
  );
  return kundliFromRow(kundliRes.rows[0], fallbackName);
}

function validateCredentials(email, password) {
  if (typeof email !== 'string' || typeof password !== 'string') {
    return 'Email and password are required';
  }
  if (!EMAIL_RE.test(email.trim())) return 'Please enter a valid email address';
  if (password.length < MIN_PASSWORD_LENGTH) return `Password must be at least ${MIN_PASSWORD_LENGTH} characters`;
  return null;
}

// POST /api/auth/register
router.post('/register', async (req, res) => {
  try {
    const { email, password, fullName, gender } = req.body || {};

    if (!email || !password || !fullName || typeof fullName !== 'string' || !fullName.trim()) {
      return res.status(400).json({ error: 'Email, password, and full name are required' });
    }
    const credError = validateCredentials(email, password);
    if (credError) return res.status(400).json({ error: credError });

    const cleanEmail = email.toLowerCase().trim();
    const existing = await db.query('SELECT id FROM users WHERE LOWER(email) = $1', [cleanEmail]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'User with this email already exists' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const cleanName = fullName.trim().slice(0, 255);
    const cleanGender = (gender || 'Not Specified').toString().slice(0, 50);

    // If the caller is using a guest session, upgrade that guest account in place so the
    // Kundli, chats and wallet created as a guest are kept.
    let guestUserId = null;
    const bearer = extractToken(req);
    if (bearer) {
      try {
        const decoded = verifyToken(bearer);
        if (decoded.role === 'guest') guestUserId = decoded.userId;
      } catch (_) { /* ignore invalid token; register a fresh account */ }
    }

    let result = { rows: [] };
    if (guestUserId) {
      result = await db.query(
        `UPDATE users SET email = $1, password_hash = $2, full_name = $3, gender = $4, role = 'user'
         WHERE id = $5 AND role = 'guest'
         RETURNING id, email, full_name, gender, role, created_at`,
        [cleanEmail, passwordHash, cleanName, cleanGender, guestUserId]
      );
    }
    if (result.rows.length === 0) {
      result = await db.query(
        `INSERT INTO users (email, password_hash, full_name, gender, role)
         VALUES ($1, $2, $3, $4, 'user')
         RETURNING id, email, full_name, gender, role, created_at`,
        [cleanEmail, passwordHash, cleanName, cleanGender]
      );
    }

    const user = result.rows[0];
    const token = signToken({ userId: user.id, email: user.email, role: 'user' });
    const kundli = await loadUserKundli(user.id, user.full_name);

    res.status(201).json({
      message: 'Registration successful',
      token,
      hasBirthDetails: !!kundli,
      kundli,
      user: publicUser(user)
    });
  } catch (error) {
    if (error && error.code === '23505') {
      return res.status(409).json({ error: 'User with this email already exists' });
    }
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Server error during registration' });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }
    if (typeof email !== 'string' || typeof password !== 'string') {
      return res.status(400).json({ error: 'Email and password must be strings' });
    }

    const cleanEmail = email.toLowerCase().trim();
    const result = await db.query('SELECT * FROM users WHERE LOWER(email) = $1', [cleanEmail]);

    // First-time login with an unknown email creates the account (seamless sign-up).
    if (result.rows.length === 0) {
      const credError = validateCredentials(email, password);
      if (credError) return res.status(400).json({ error: credError });

      const passwordHash = await bcrypt.hash(password, 10);
      const defaultName = cleanEmail.split('@')[0];

      const newUserRes = await db.query(
        `INSERT INTO users (email, password_hash, full_name, gender, role)
         VALUES ($1, $2, $3, $4, 'user')
         RETURNING id, email, full_name, gender, role, created_at`,
        [cleanEmail, passwordHash, defaultName, 'Not Specified']
      );

      const user = newUserRes.rows[0];
      const token = signToken({ userId: user.id, email: user.email, role: 'user' });

      return res.status(200).json({
        message: 'Account created & logged in successfully',
        isNewUser: true,
        token,
        hasBirthDetails: false,
        kundli: null,
        user: publicUser(user)
      });
    }

    const user = result.rows[0];
    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ error: 'Incorrect password for this account.' });
    }

    const existingKundli = await loadUserKundli(user.id, user.full_name);
    const role = user.role === 'guest' ? 'user' : (user.role || 'user');
    const token = signToken({ userId: user.id, email: user.email, role });

    res.json({
      message: 'Login successful',
      token,
      hasBirthDetails: !!existingKundli,
      kundli: existingKundli,
      user: publicUser(user)
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Server error during login' });
  }
});

// GET /api/auth/me
router.get('/me', authenticateToken, async (req, res) => {
  try {
    const result = await db.query(
      'SELECT id, email, full_name, gender, role, created_at, wallet_balance FROM users WHERE id = $1',
      [req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const row = result.rows[0];
    const kundli = await loadUserKundli(row.id, row.full_name);
    res.json({
      user: { ...publicUser(row), walletBalance: row.wallet_balance },
      hasBirthDetails: !!kundli,
      kundli
    });
  } catch (error) {
    console.error('Fetch me error:', error);
    res.status(500).json({ error: 'Server error fetching user profile' });
  }
});

module.exports = {
  router,
  authenticateToken,
  optionalAuthenticateToken,
  guestOrAuthenticateToken,
  signToken,
  kundliFromRow,
  JWT_SECRET
};
