const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const db = require('../db');
const {
  authenticateToken,
  optionalAuthenticateToken,
  guestOrAuthenticateToken,
  signToken,
  kundliFromRow
} = require('./auth');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const DEMO_PANDIT_EMAIL = 'rishiraj@astroai.com';
const DEFAULT_AVATAR = 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80';
const MIN_BILLING_INTERVAL_SECONDS = 50;

const str = (v, max = 255) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

function toId(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

// Fields safe to expose publicly (no earnings / internal ids)
function publicPandit(p) {
  if (!p) return null;
  const { earnings_balance, total_minutes_consulted, ...rest } = p;
  return rest;
}

async function getPanditByUserId(userId, client = db) {
  const r = await client.query('SELECT * FROM pandits WHERE user_id = $1', [userId]);
  return r.rows[0] || null;
}

// Requires a valid token belonging to a registered Pandit
async function requirePandit(req, res, next) {
  try {
    const pandit = await getPanditByUserId(req.user.userId);
    if (!pandit) {
      return res.status(403).json({ error: 'NOT_A_PANDIT', message: 'This action requires a Pandit account.' });
    }
    req.pandit = pandit;
    return next();
  } catch (err) {
    console.error('Pandit lookup error:', err);
    return res.status(500).json({ error: 'Failed to verify Pandit account' });
  }
}

/**
 * Bill up to `minutes` minutes of a session at the Pandit's rate, limited to what the
 * seeker can afford.
 */
async function chargeMinutes(client, session, pandit, minutes) {
  const rate = Number(pandit.rate_per_min) || 0;
  const bal = await client.query('SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE', [session.user_id]);
  const balance = bal.rows[0] ? Number(bal.rows[0].wallet_balance) || 0 : 0;
  const affordable = rate > 0 ? Math.floor((balance + 1e-9) / rate) : minutes;
  const billable = Math.max(0, Math.min(minutes, affordable));
  const amount = Math.round(billable * rate * 100) / 100;
  if (billable === 0) {
    return { minutesCharged: 0, amount: 0, seekerBalance: balance, rate, insufficient: minutes > 0 };
  }
  const debit = await client.query(
    'UPDATE users SET wallet_balance = wallet_balance - $1 WHERE id = $2 RETURNING wallet_balance',
    [amount, session.user_id]
  );
  const credit = await client.query(
    `UPDATE pandits
     SET earnings_balance = COALESCE(earnings_balance, 0) + $1,
         total_minutes_consulted = COALESCE(total_minutes_consulted, 0) + $2
     WHERE id = $3
     RETURNING earnings_balance, total_minutes_consulted`,
    [amount, billable, pandit.id]
  );
  await client.query(
    `UPDATE consultation_queue
     SET billed_minutes = COALESCE(billed_minutes, 0) + $1,
         amount_charged = COALESCE(amount_charged, 0) + $2,
         last_billed_at = NOW()
     WHERE id = $3`,
    [billable, amount, session.id]
  );
  await client.query(
    `INSERT INTO wallet_transactions (user_id, pandit_id, type, amount, description)
     VALUES ($1, $2, 'debit', $3, $4), ($1, $2, 'payout', $3, $5)`,
    [session.user_id, pandit.id, amount,
      `Consultation with ${pandit.full_name}: ${billable} min @ ₹${rate.toFixed(2)}/min`,
      `Consultation payout: ${billable} min`]
  );
  return {
    minutesCharged: billable,
    amount,
    rate,
    seekerBalance: Number(debit.rows[0].wallet_balance),
    earnings: Number(credit.rows[0].earnings_balance),
    totalMinutes: Number(credit.rows[0].total_minutes_consulted),
    insufficient: billable < minutes
  };
}

/**
 * Close a session. Active sessions are billed server-side for any minutes not yet billed
 * (elapsed minutes rounded up). Frees the Pandit when nobody else is waiting.
 */
async function closeSession(client, sessionId, finalStatus = 'completed') {
  const sq = await client.query('SELECT * FROM consultation_queue WHERE id = $1 FOR UPDATE', [sessionId]);
  const session = sq.rows[0];
  if (!session || !['active', 'waiting'].includes(session.status)) return { session, billing: null };

  const pq = await client.query('SELECT * FROM pandits WHERE id = $1 FOR UPDATE', [session.pandit_id]);
  const pandit = pq.rows[0];
  let billing = null;

  if (session.status === 'active' && pandit && session.started_at) {
    const elapsedMin = Math.ceil((Date.now() - new Date(session.started_at).getTime()) / 60000);
    const unbilled = Math.max(0, elapsedMin - (Number(session.billed_minutes) || 0));
    billing = await chargeMinutes(client, session, pandit, unbilled);
  }

  const status = session.status === 'waiting' ? 'cancelled' : finalStatus;
  const updated = await client.query(
    'UPDATE consultation_queue SET status = $1, ended_at = NOW() WHERE id = $2 RETURNING *',
    [status, session.id]
  );

  if (session.status === 'waiting') {
    await client.query(
      `UPDATE consultation_queue SET queue_position = queue_position - 1
       WHERE pandit_id = $1 AND status = 'waiting' AND queue_position > $2`,
      [session.pandit_id, session.queue_position]
    );
  } else if (pandit) {
    const waiting = await client.query(
      `SELECT 1 FROM consultation_queue WHERE pandit_id = $1 AND status = 'waiting' LIMIT 1`,
      [pandit.id]
    );
    if (waiting.rows.length === 0) {
      await client.query('UPDATE pandits SET is_busy = FALSE WHERE id = $1', [pandit.id]);
    }
  }
  return { session: updated.rows[0], billing };
}

// Loads a session and the caller's role in it ('seeker' | 'pandit'); role is null for outsiders
async function sessionForParticipant(client, sessionId, userId) {
  const sq = await client.query(
    `SELECT q.*, p.user_id AS pandit_user_id, p.full_name AS pandit_name
     FROM consultation_queue q JOIN pandits p ON p.id = q.pandit_id
     WHERE q.id = $1`,
    [sessionId]
  );
  const session = sq.rows[0];
  if (!session) return { session: null, role: null };
  if (session.user_id === userId) return { session, role: 'seeker' };
  if (session.pandit_user_id === userId) return { session, role: 'pandit' };
  return { session, role: null };
}

// 1. POST /api/pandit/register
router.post('/register', async (req, res) => {
  try {
    const body = req.body || {};
    const email = str(body.email).toLowerCase();
    const password = typeof body.password === 'string' ? body.password : '';
    const fullName = str(body.fullName);

    if (!email || !password || !fullName) {
      return res.status(400).json({ success: false, error: 'MISSING_FIELDS', message: 'Email, password and full name are required.' });
    }
    if (!EMAIL_RE.test(email)) {
      return res.status(400).json({ success: false, error: 'INVALID_EMAIL', message: 'Please enter a valid email address.' });
    }
    if (password.length < 6) {
      return res.status(400).json({ success: false, error: 'WEAK_PASSWORD', message: 'Password must be at least 6 characters.' });
    }

    const specialty = str(body.specialty) || 'Vedic Astrology & Janam Kundli';
    const field = str(body.field) || 'Vedic Kundli';
    const exp = Math.min(80, Math.max(0, parseInt(body.experienceYears, 10) || 0));
    const languages = str(body.languages) || 'Hindi, English';
    const rateRaw = parseFloat(body.ratePerMin);
    const rate = Number.isFinite(rateRaw) ? Math.min(1000, Math.max(1, rateRaw)) : 21.0;
    const bio = str(body.bio, 2000) || null;
    const avatar = str(body.avatarUrl, 1000);
    const img = /^https?:\/\//i.test(avatar) ? avatar : DEFAULT_AVATAR;

    const result = await db.withTransaction(async (client) => {
      const existingUser = await client.query('SELECT * FROM users WHERE LOWER(email) = $1', [email]);
      let userId;

      if (existingUser.rows.length > 0) {
        const user = existingUser.rows[0];
        if (await getPanditByUserId(user.id, client)) {
          return { status: 400, body: { success: false, error: 'PANDIT_ALREADY_EXISTS', message: 'An account with this email is already registered as a Pandit. Please login directly.' } };
        }
        // Upgrading an existing account requires proving ownership of it
        const ok = await bcrypt.compare(password, user.password_hash);
        if (!ok) {
          return { status: 401, body: { success: false, error: 'INVALID_PASSWORD', message: 'This email already has an account. Enter that account\'s password to register it as a Pandit.' } };
        }
        userId = user.id;
        await client.query(`UPDATE users SET role = 'pandit' WHERE id = $1`, [userId]);
      } else {
        const passwordHash = await bcrypt.hash(password, 10);
        const newUser = await client.query(
          `INSERT INTO users (email, password_hash, full_name, role) VALUES ($1, $2, $3, 'pandit') RETURNING id`,
          [email, passwordHash, fullName]
        );
        userId = newUser.rows[0].id;
      }

      const inserted = await client.query(
        `INSERT INTO pandits (user_id, full_name, specialty, field, experience_years, languages, rate_per_min, bio, avatar_url, is_online, is_busy, earnings_balance, total_minutes_consulted, total_reviews)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, TRUE, FALSE, 0.00, 0, 0)
         RETURNING *`,
        [userId, fullName, specialty, field, exp, languages, rate, bio, img]
      );
      return { status: 201, userId, pandit: inserted.rows[0] };
    });

    if (result.status !== 201) return res.status(result.status).json(result.body);

    const token = signToken({ userId: result.userId, email, role: 'pandit' });
    res.status(201).json({ success: true, token, pandit: result.pandit });
  } catch (err) {
    if (err && err.code === '23505') {
      return res.status(400).json({ success: false, error: 'PANDIT_ALREADY_EXISTS', message: 'An account with this email is already registered. Please login directly.' });
    }
    console.error('Pandit registration error:', err);
    res.status(500).json({ error: 'Failed to register Pandit account' });
  }
});

// 1B. POST /api/pandit/login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (typeof email !== 'string' || typeof password !== 'string' || !email.trim() || !password) {
      return res.status(400).json({ success: false, error: 'MISSING_FIELDS', message: 'Email and password are required.' });
    }

    const cleanEmail = email.trim().toLowerCase();
    await db.ensureInitialized(); // guarantees the demo Pandit seed has run
    const userRes = await db.query('SELECT * FROM users WHERE LOWER(email) = $1', [cleanEmail]);

    if (userRes.rows.length === 0) {
      return res.status(401).json({
        success: false,
        error: 'NO_ACCOUNT_FOUND',
        message: 'No Pandit account found with this email. Please register first.'
      });
    }

    const user = userRes.rows[0];
    const isMatch = user.password_hash ? await bcrypt.compare(password, user.password_hash) : false;
    if (!isMatch) {
      return res.status(401).json({
        success: false,
        error: 'INVALID_PASSWORD',
        message: 'Incorrect password entered. Please try again.'
      });
    }

    const panditProfile = await getPanditByUserId(user.id);
    if (!panditProfile) {
      return res.status(403).json({
        success: false,
        error: 'NOT_A_PANDIT',
        message: 'This account is not registered as a Pandit. Please register as a Pandit first.'
      });
    }
    if (user.role !== 'pandit') {
      await db.query(`UPDATE users SET role = 'pandit' WHERE id = $1`, [user.id]);
    }

    const token = signToken({ userId: user.id, email: user.email, role: 'pandit' });
    res.json({ success: true, token, pandit: panditProfile });
  } catch (err) {
    console.error('Pandit login error:', err);
    res.status(500).json({ error: 'Failed to login Pandit' });
  }
});

// 1C. GET /api/pandit/me
router.get('/me', authenticateToken, requirePandit, (req, res) => {
  res.json({ pandit: req.pandit });
});

// 2. GET /api/pandit/list
router.get('/list', async (req, res) => {
  try {
    const result = await db.query(`
      SELECT p.*, COALESCE(q.waiting_count, 0)::INTEGER AS waiting_count
      FROM pandits p
      LEFT JOIN (
        SELECT pandit_id, COUNT(*) AS waiting_count
        FROM consultation_queue
        WHERE status = 'waiting'
        GROUP BY pandit_id
      ) q ON p.id = q.pandit_id
      ORDER BY p.is_online DESC, p.id ASC
    `);
    res.json({ pandits: result.rows.map(publicPandit) });
  } catch (err) {
    console.error('Fetch Pandits list error:', err);
    res.status(500).json({ error: 'Failed to fetch Pandits list' });
  }
});

// 3. POST /api/pandit/toggle-status
router.post('/toggle-status', authenticateToken, requirePandit, async (req, res) => {
  try {
    const { isOnline, isBusy } = req.body || {};
    if ((isOnline !== undefined && typeof isOnline !== 'boolean') || (isBusy !== undefined && typeof isBusy !== 'boolean')) {
      return res.status(400).json({ error: 'isOnline and isBusy must be booleans' });
    }
    const result = await db.query(
      `UPDATE pandits
       SET is_online = COALESCE($1, is_online),
           is_busy = COALESCE($2, is_busy)
       WHERE id = $3
       RETURNING *`,
      [isOnline === undefined ? null : isOnline, isBusy === undefined ? null : isBusy, req.pandit.id]
    );
    res.json({ success: true, pandit: result.rows[0] });
  } catch (err) {
    console.error('Toggle status error:', err);
    res.status(500).json({ error: 'Failed to update status' });
  }
});

// 4. POST /api/pandit/request - start a consultation or join the waiting queue
router.post('/request', guestOrAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const panditId = toId((req.body || {}).panditId);
    const seekerName = str((req.body || {}).userName, 255) || 'Seeker';

    if (!panditId) {
      return res.status(400).json({ error: 'A valid panditId is required' });
    }

    const outcome = await db.withTransaction(async (client) => {
      const pq = await client.query('SELECT * FROM pandits WHERE id = $1 FOR UPDATE', [panditId]);
      const pandit = pq.rows[0];

      if (!pandit) {
        // Not a registered human Pandit (e.g. one of the app's AI astrologer personas):
        // the chat is served by the AI astrologer, no queue / billing applies.
        return {
          status: 'active',
          aiAstrologer: true,
          message: 'Connected to AI astrologer.',
          session: null,
          queuePosition: 0,
          estimatedWaitMins: 0
        };
      }

      if (pandit.user_id === userId) {
        return { httpStatus: 400, body: { error: 'SELF_CONSULTATION', message: 'You cannot book a consultation with yourself.' } };
      }

      // Already in a session or queue with this Pandit? Return it instead of duplicating.
      const existing = await client.query(
        `SELECT * FROM consultation_queue
         WHERE pandit_id = $1 AND user_id = $2 AND status IN ('active', 'waiting')
         ORDER BY id DESC LIMIT 1`,
        [panditId, userId]
      );
      if (existing.rows.length > 0) {
        const s = existing.rows[0];
        return {
          status: s.status,
          message: s.status === 'active' ? 'You are already in a live consultation.' : `You are Position #${s.queue_position} in line.`,
          session: s,
          queuePosition: s.status === 'active' ? 0 : s.queue_position,
          estimatedWaitMins: s.status === 'active' ? 0 : s.queue_position * 5
        };
      }

      if (!pandit.is_online) {
        return { httpStatus: 409, body: { error: 'PANDIT_OFFLINE', message: `${pandit.full_name} is currently offline.` } };
      }

      const wallet = await client.query('SELECT wallet_balance FROM users WHERE id = $1', [userId]);
      const balance = wallet.rows[0] ? Number(wallet.rows[0].wallet_balance) || 0 : 0;
      const rate = Number(pandit.rate_per_min) || 0;
      if (balance < rate) {
        return {
          httpStatus: 402,
          body: {
            error: 'INSUFFICIENT_BALANCE',
            walletBalance: balance,
            ratePerMin: rate,
            message: `Your wallet balance (₹${balance.toFixed(2)}) is below the per-minute rate (₹${rate.toFixed(2)}). Please recharge.`
          }
        };
      }

      if (!pandit.is_busy) {
        await client.query('UPDATE pandits SET is_busy = TRUE WHERE id = $1', [panditId]);
        const session = await client.query(
          `INSERT INTO consultation_queue (pandit_id, user_id, user_name, status, queue_position, started_at)
           VALUES ($1, $2, $3, 'active', 0, NOW()) RETURNING *`,
          [panditId, userId, seekerName]
        );
        return {
          status: 'active',
          message: 'Connected to Pandit immediately!',
          session: session.rows[0],
          queuePosition: 0,
          estimatedWaitMins: 0
        };
      }

      const pos = await client.query(
        `SELECT COALESCE(MAX(queue_position), 0) + 1 AS next_pos
         FROM consultation_queue WHERE pandit_id = $1 AND status = 'waiting'`,
        [panditId]
      );
      const position = Number(pos.rows[0].next_pos) || 1;
      const session = await client.query(
        `INSERT INTO consultation_queue (pandit_id, user_id, user_name, status, queue_position)
         VALUES ($1, $2, $3, 'waiting', $4) RETURNING *`,
        [panditId, userId, seekerName, position]
      );
      return {
        status: 'waiting',
        message: `Pandit is currently consulting. You are Position #${position} in line.`,
        session: session.rows[0],
        queuePosition: position,
        estimatedWaitMins: position * 5
      };
    });

    if (outcome.httpStatus) return res.status(outcome.httpStatus).json(outcome.body);
    res.json(outcome);
  } catch (err) {
    console.error('Request consultation error:', err);
    res.status(500).json({ error: 'Failed to request consultation' });
  }
});

// 5. GET /api/pandit/queue-status[?panditId=]
router.get('/queue-status', optionalAuthenticateToken, async (req, res) => {
  try {
    if (req.query.panditId !== undefined) {
      // Pandit's view: only the Pandit themself may see their queue
      if (!req.user) return res.status(401).json({ error: 'Access token required' });
      const panditId = toId(req.query.panditId);
      const pandit = await getPanditByUserId(req.user.userId);
      if (!pandit || !panditId || pandit.id !== panditId) {
        return res.status(403).json({ error: 'You can only view your own consultation queue' });
      }

      const activeQuery = await db.query(
        `SELECT * FROM consultation_queue WHERE pandit_id = $1 AND status = 'active' ORDER BY id DESC LIMIT 1`,
        [panditId]
      );
      const waitingQuery = await db.query(
        `SELECT * FROM consultation_queue WHERE pandit_id = $1 AND status = 'waiting' ORDER BY queue_position ASC, id ASC`,
        [panditId]
      );
      return res.json({
        activeSession: activeQuery.rows[0] || null,
        waitingQueue: waitingQuery.rows
      });
    }

    // Seeker's view
    if (!req.user) return res.json({ status: 'idle', session: null });
    const userQueueQuery = await db.query(
      `SELECT q.*, p.full_name AS pandit_name, p.specialty, p.avatar_url, p.rate_per_min, p.experience_years
       FROM consultation_queue q
       LEFT JOIN pandits p ON q.pandit_id = p.id
       WHERE q.user_id = $1 AND q.status IN ('active', 'waiting')
       ORDER BY q.id DESC LIMIT 1`,
      [req.user.userId]
    );

    if (userQueueQuery.rows.length === 0) {
      return res.json({ status: 'idle', session: null });
    }

    const session = userQueueQuery.rows[0];
    const totalWaitQuery = await db.query(
      `SELECT COUNT(*) AS count FROM consultation_queue WHERE pandit_id = $1 AND status = 'waiting'`,
      [session.pandit_id]
    );
    const activeSessionQuery = await db.query(
      `SELECT started_at, user_name FROM consultation_queue WHERE pandit_id = $1 AND status = 'active' ORDER BY id DESC LIMIT 1`,
      [session.pandit_id]
    );
    const activeSession = activeSessionQuery.rows[0] || null;
    const position = session.status === 'active' ? 0 : session.queue_position;

    return res.json({
      status: session.status,
      session,
      queuePosition: position,
      totalWaiting: Number(totalWaitQuery.rows[0].count) || 0,
      estimatedWaitMins: position * 5,
      panditName: session.pandit_name,
      specialty: session.specialty,
      avatarUrl: session.avatar_url || DEFAULT_AVATAR,
      ratePerMin: session.rate_per_min,
      activeSessionInfo: activeSession ? {
        startedAt: activeSession.started_at,
        seekerName: session.status === 'active' ? activeSession.user_name : 'Another seeker'
      } : null
    });
  } catch (err) {
    console.error('Fetch queue status error:', err);
    res.status(500).json({ error: 'Failed to fetch queue status' });
  }
});

// 6. POST /api/pandit/next - Pandit ends the current chat and calls the next seeker
router.post('/next', authenticateToken, requirePandit, async (req, res) => {
  try {
    const requested = (req.body || {}).panditId;
    if (requested !== undefined && requested !== null && toId(requested) !== req.pandit.id) {
      return res.status(403).json({ error: 'You can only manage your own consultation queue' });
    }
    const panditId = req.pandit.id;

    const outcome = await db.withTransaction(async (client) => {
      await client.query('SELECT id FROM pandits WHERE id = $1 FOR UPDATE', [panditId]);
      const actives = await client.query(
        `SELECT id FROM consultation_queue WHERE pandit_id = $1 AND status = 'active'`,
        [panditId]
      );
      let lastBilling = null;
      for (const a of actives.rows) {
        const closed = await closeSession(client, a.id, 'completed');
        lastBilling = closed.billing || lastBilling;
      }

      const nextQuery = await client.query(
        `SELECT * FROM consultation_queue
         WHERE pandit_id = $1 AND status = 'waiting'
         ORDER BY queue_position ASC, id ASC LIMIT 1`,
        [panditId]
      );

      if (nextQuery.rows.length === 0) {
        await client.query('UPDATE pandits SET is_busy = FALSE WHERE id = $1', [panditId]);
        return { status: 'idle', message: 'Queue is empty. You are now available.', activeSession: null, completedBilling: lastBilling };
      }

      const updated = await client.query(
        `UPDATE consultation_queue SET status = 'active', started_at = NOW(), queue_position = 0
         WHERE id = $1 RETURNING *`,
        [nextQuery.rows[0].id]
      );
      await client.query(
        `UPDATE consultation_queue SET queue_position = GREATEST(queue_position - 1, 1)
         WHERE pandit_id = $1 AND status = 'waiting'`,
        [panditId]
      );
      await client.query('UPDATE pandits SET is_busy = TRUE WHERE id = $1', [panditId]);
      return {
        status: 'active',
        message: `Started consultation with ${updated.rows[0].user_name}`,
        activeSession: updated.rows[0],
        completedBilling: lastBilling
      };
    });

    res.json(outcome);
  } catch (err) {
    console.error('Advance queue error:', err);
    res.status(500).json({ error: 'Failed to advance consultation queue' });
  }
});

// 7. GET /api/pandit/user-kundli/:userId - seeker's chart (the seeker themself, or a Pandit consulting them)
router.get('/user-kundli/:userId', authenticateToken, async (req, res) => {
  try {
    const seekerId = toId(req.params.userId);
    if (!seekerId) return res.status(400).json({ error: 'Invalid user id' });

    if (seekerId !== req.user.userId) {
      const pandit = await getPanditByUserId(req.user.userId);
      const link = pandit
        ? await db.query(
          "SELECT 1 FROM consultation_queue WHERE pandit_id = $1 AND user_id = $2 AND status IN ('active', 'waiting') LIMIT 1",
          [pandit.id, seekerId]
        )
        : { rows: [] };
      if (link.rows.length === 0) {
        return res.status(403).json({ error: 'You are not allowed to view this Kundli' });
      }
    }

    const q = await db.query(
      `SELECT u.full_name AS user_full_name, bd.full_name, bd.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth,
              bd.latitude, bd.longitude, bd.timezone,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info, k.ai_report, k.kundli_data
       FROM users u
       LEFT JOIN birth_details bd ON u.id = bd.user_id
       LEFT JOIN kundlis k ON u.id = k.user_id
       WHERE u.id = $1`,
      [seekerId]
    );
    if (q.rows.length === 0) return res.status(404).json({ error: 'Seeker not found' });

    const row = q.rows[0];
    const kundli = kundliFromRow(row, row.user_full_name);
    if (!kundli) {
      return res.status(404).json({ error: 'NO_KUNDLI', message: 'This seeker has not generated a Kundli yet.', seekerName: row.user_full_name });
    }

    const planets = Array.isArray(kundli.planetaryPositions) ? kundli.planetaryPositions : [];
    res.json({
      seekerName: row.full_name || row.user_full_name,
      gender: row.gender,
      ascendant: kundli.ascendant,
      sunSign: kundli.sunSign,
      moonSign: kundli.moonSign,
      nakshatra: kundli.nakshatra,
      nakshatraPada: kundli.nakshatraPada,
      birthDetails: kundli.birthDetails,
      dashaInfo: kundli.dashaInfo,
      planetaryPositions: planets.map((p) => ({ ...p, planet: String(p.name || '').split(' ')[0] }))
    });
  } catch (err) {
    console.error('Fetch seeker Kundli error:', err);
    res.status(500).json({ error: 'Failed to fetch seeker Kundli chart' });
  }
});

// 8. GET /api/pandit/wallet/balance
router.get('/wallet/balance', optionalAuthenticateToken, async (req, res) => {
  try {
    if (!req.user) return res.json({ walletBalance: 0 });
    const result = await db.query('SELECT wallet_balance FROM users WHERE id = $1', [req.user.userId]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    res.json({ walletBalance: Number(result.rows[0].wallet_balance) || 0 });
  } catch (err) {
    console.error('Fetch wallet balance error:', err);
    res.status(500).json({ error: 'Failed to fetch wallet balance' });
  }
});

// 9. POST /api/pandit/wallet/recharge
// NOTE: no payment gateway is integrated; this credits the wallet directly (demo behaviour).
router.post('/wallet/recharge', guestOrAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const baseAmount = parseFloat((req.body || {}).amount);
    if (!Number.isFinite(baseAmount) || baseAmount <= 0 || baseAmount > 100000) {
      return res.status(400).json({ error: 'Amount must be a number between 1 and 100000' });
    }
    const amount = Math.round(baseAmount * 100) / 100;
    let bonus = 0;
    if (amount >= 1000) bonus = amount * 0.15;
    else if (amount >= 500) bonus = amount * 0.10;
    bonus = Math.round(bonus * 100) / 100;
    const totalAdded = amount + bonus;

    const newBalance = await db.withTransaction(async (client) => {
      const r = await client.query(
        `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + $1 WHERE id = $2 RETURNING wallet_balance`,
        [totalAdded, userId]
      );
      if (r.rows.length === 0) throw Object.assign(new Error('User not found'), { status: 404 });
      await client.query(
        `INSERT INTO wallet_transactions (user_id, type, amount, description) VALUES ($1, 'recharge', $2, $3)`,
        [userId, totalAdded, `Wallet recharge ₹${amount.toFixed(2)}${bonus ? ` + ₹${bonus.toFixed(2)} bonus` : ''}`]
      );
      return Number(r.rows[0].wallet_balance);
    });

    res.json({ success: true, addedAmount: totalAdded, bonus, walletBalance: newBalance });
  } catch (err) {
    if (err.status === 404) return res.status(404).json({ error: 'User not found' });
    console.error('Wallet recharge error:', err);
    res.status(500).json({ error: 'Failed to recharge wallet' });
  }
});

// 10. POST /api/pandit/rate
router.post('/rate', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const body = req.body || {};
    const panditId = toId(body.panditId);
    const rating = parseFloat(body.rating);
    if (!panditId) return res.status(400).json({ error: 'A valid panditId is required' });
    if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
      return res.status(400).json({ error: 'Rating must be between 1 and 5' });
    }
    const reviewText = str(body.reviewText, 2000) || null;
    const seekerName = str(body.userName) || 'Seeker';

    const stats = await db.withTransaction(async (client) => {
      const p = await client.query('SELECT id, user_id FROM pandits WHERE id = $1 FOR UPDATE', [panditId]);
      if (p.rows.length === 0) return null;
      if (p.rows[0].user_id === userId) return { self: true };

      await client.query(
        `INSERT INTO pandit_reviews (pandit_id, user_id, user_name, rating, review_text) VALUES ($1, $2, $3, $4, $5)`,
        [panditId, userId, seekerName, Math.round(rating * 10) / 10, reviewText]
      );
      const s = await client.query(
        `SELECT AVG(rating) AS avg_rating, COUNT(*) AS total_reviews FROM pandit_reviews WHERE pandit_id = $1`,
        [panditId]
      );
      const avg = Math.round(Number(s.rows[0].avg_rating) * 100) / 100;
      const total = Number(s.rows[0].total_reviews);
      await client.query('UPDATE pandits SET rating = $1, total_reviews = $2 WHERE id = $3', [avg, total, panditId]);
      return { avg, total };
    });

    if (!stats) return res.status(404).json({ error: 'Pandit not found' });
    if (stats.self) return res.status(400).json({ error: 'You cannot rate yourself' });
    res.json({ success: true, averageRating: stats.avg, totalReviews: stats.total });
  } catch (err) {
    console.error('Submit review error:', err);
    res.status(500).json({ error: 'Failed to submit review' });
  }
});

// 11. GET /api/pandit/history - seeker's past consultations & prescriptions
router.get('/history', optionalAuthenticateToken, async (req, res) => {
  try {
    if (!req.user) return res.json({ history: [], prescriptions: [] });
    const userId = req.user.userId;

    const historyQuery = await db.query(
      `SELECT q.*, p.full_name AS pandit_name, p.specialty, p.avatar_url, p.rate_per_min
       FROM consultation_queue q
       LEFT JOIN pandits p ON q.pandit_id = p.id
       WHERE q.user_id = $1
       ORDER BY q.id DESC LIMIT 200`,
      [userId]
    );
    const prescriptionsQuery = await db.query(
      'SELECT * FROM consultation_prescriptions WHERE user_id = $1 ORDER BY id DESC LIMIT 200',
      [userId]
    );

    res.json({ history: historyQuery.rows, prescriptions: prescriptionsQuery.rows });
  } catch (err) {
    console.error('Fetch consultation history error:', err);
    res.status(500).json({ error: 'Failed to fetch consultation history' });
  }
});

// 12. GET /api/pandit/remedies/recommendations
// Traditional rule: gemstones of the Lagna lord (primary) and the 9th / 5th house lords (secondary).
const GEMSTONES = {
  Sun: { name: 'Ruby (Manik)', planet: 'Sun (Surya)', ratti: '3 - 5 Ratti', metal: 'Gold or Copper Ring', finger: 'Ring Finger of Right Hand', day: 'Sunday Morning', benefits: 'Strengthens confidence, leadership, vitality and recognition.' },
  Moon: { name: 'Pearl (Moti)', planet: 'Moon (Chandra)', ratti: '4 - 6 Ratti', metal: 'Silver Ring', finger: 'Little Finger of Right Hand', day: 'Monday Morning', benefits: 'Brings emotional balance, calmness and mental clarity.' },
  Mars: { name: 'Red Coral (Moonga)', planet: 'Mars (Mangal)', ratti: '5 - 7 Ratti', metal: 'Gold or Copper Ring', finger: 'Ring Finger of Right Hand', day: 'Tuesday Morning', benefits: 'Enhances courage, energy, and decisiveness.' },
  Mercury: { name: 'Emerald (Panna)', planet: 'Mercury (Budh)', ratti: '4.5 - 5.5 Ratti', metal: 'Gold or Silver Ring', finger: 'Little Finger of Right Hand', day: 'Wednesday Morning', benefits: 'Enhances communication, intellect, analytical power and commerce.' },
  Jupiter: { name: 'Yellow Sapphire (Pukhraj)', planet: 'Jupiter (Brihaspati)', ratti: '5.25 - 6.5 Ratti', metal: 'Gold Ring', finger: 'Index Finger of Right Hand', day: 'Thursday Morning (Shukla Paksha)', benefits: 'Supports wisdom, fortune, growth and spiritual protection.' },
  Venus: { name: 'Diamond (Heera) or White Sapphire', planet: 'Venus (Shukra)', ratti: '0.5 - 1 Carat (Diamond)', metal: 'Platinum or Silver Ring', finger: 'Middle or Ring Finger of Right Hand', day: 'Friday Morning', benefits: 'Supports harmony in relationships, creativity and comforts.' },
  Saturn: { name: 'Blue Sapphire (Neelam)', planet: 'Saturn (Shani)', ratti: '4 - 6 Ratti (wear only after trial)', metal: 'Silver or Panchdhatu Ring', finger: 'Middle Finger of Right Hand', day: 'Saturday Evening', benefits: 'Supports discipline, perseverance and steady career growth.' }
};
const PLANET_MANTRAS = {
  Sun: 'Om Hraam Hreem Hraum Sah Suryaya Namah',
  Moon: 'Om Shraam Shreem Shraum Sah Chandraya Namah',
  Mars: 'Om Kraam Kreem Kraum Sah Bhaumaya Namah',
  Mercury: 'Om Braam Breem Braum Sah Budhaya Namah',
  Jupiter: 'Om Graam Greem Graum Sah Gurave Namah',
  Venus: 'Om Draam Dreem Draum Sah Shukraya Namah',
  Saturn: 'Om Praam Preem Praum Sah Shanaischaraya Namah'
};
const PLANET_DAY = { Sun: 'Sunday', Moon: 'Monday', Mars: 'Tuesday', Mercury: 'Wednesday', Jupiter: 'Thursday', Venus: 'Friday', Saturn: 'Saturday' };
const SIGN_LORDS = ['Mars', 'Venus', 'Mercury', 'Moon', 'Sun', 'Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Saturn', 'Jupiter'];
const SIGNS = ['Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo', 'Libra', 'Scorpio', 'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'];

router.get('/remedies/recommendations', optionalAuthenticateToken, async (req, res) => {
  try {
    let ascIdx = -1;
    if (req.user) {
      const k = await db.query('SELECT ascendant FROM kundlis WHERE user_id = $1', [req.user.userId]);
      if (k.rows.length > 0) ascIdx = SIGNS.indexOf(k.rows[0].ascendant);
    }

    let primaryLord = 'Jupiter';
    let secondaryLord = 'Mercury';
    if (ascIdx >= 0) {
      primaryLord = SIGN_LORDS[ascIdx];
      const ninthLord = SIGN_LORDS[(ascIdx + 8) % 12];
      const fifthLord = SIGN_LORDS[(ascIdx + 4) % 12];
      secondaryLord = ninthLord !== primaryLord ? ninthLord : fifthLord;
    }

    res.json({
      personalized: ascIdx >= 0,
      basis: ascIdx >= 0
        ? `Lagna lord ${primaryLord} and 9th/5th lord ${secondaryLord} for ${SIGNS[ascIdx]} Ascendant`
        : 'General recommendation (generate your Kundli for personalised remedies)',
      primaryGemstone: GEMSTONES[primaryLord],
      secondaryGemstone: GEMSTONES[secondaryLord],
      vedicMantras: [
        { planet: `${primaryLord} Mantra`, mantra: PLANET_MANTRAS[primaryLord], recitations: `108 times on ${PLANET_DAY[primaryLord]} mornings` },
        { planet: 'Gayatri Mantra', mantra: 'Om Bhur Bhuva Swaha Tat Savitur Varenyam Bhargo Devasya Dheemahi Dhiyo Yo Nah Prachodayat', recitations: '21 times daily at sunrise' }
      ],
      dailyRemedies: [
        `Recite the ${primaryLord} mantra on ${PLANET_DAY[primaryLord]}s with a calm mind.`,
        `Donate items associated with ${secondaryLord} on ${PLANET_DAY[secondaryLord]}s.`,
        'Offer water to the rising Sun using a copper vessel.'
      ],
      disclaimer: 'Consult a qualified astrologer before wearing any gemstone.'
    });
  } catch (err) {
    console.error('Fetch remedies recommendations error:', err);
    res.status(500).json({ error: 'Failed to fetch recommendations' });
  }
});

// 13. POST /api/pandit/consultation/deduct-minute
// Bills one minute of an ACTIVE session at the Pandit's own rate. Callable by the Pandit
// (bills the seeker in their active session) or by the seeker (bills themself).
router.post('/consultation/deduct-minute', authenticateToken, async (req, res) => {
  try {
    const callerId = req.user.userId;
    const requestedPanditId = toId((req.body || {}).panditId);

    const outcome = await db.withTransaction(async (client) => {
      const callerPandit = await getPanditByUserId(callerId, client);
      let session;
      if (callerPandit && (!requestedPanditId || requestedPanditId === callerPandit.id)) {
        const s = await client.query(
          `SELECT * FROM consultation_queue WHERE pandit_id = $1 AND status = 'active' ORDER BY id DESC LIMIT 1 FOR UPDATE`,
          [callerPandit.id]
        );
        session = s.rows[0];
      } else if (requestedPanditId) {
        const s = await client.query(
          `SELECT * FROM consultation_queue WHERE pandit_id = $1 AND user_id = $2 AND status = 'active' ORDER BY id DESC LIMIT 1 FOR UPDATE`,
          [requestedPanditId, callerId]
        );
        session = s.rows[0];
      }
      if (!session) {
        return { httpStatus: 409, body: { success: false, error: 'NO_ACTIVE_SESSION', message: 'There is no active consultation to bill.' } };
      }

      if (session.last_billed_at) {
        const elapsed = (Date.now() - new Date(session.last_billed_at).getTime()) / 1000;
        if (elapsed < MIN_BILLING_INTERVAL_SECONDS) {
          return { httpStatus: 429, body: { success: false, error: 'TOO_SOON', message: 'This minute has already been billed.' } };
        }
      }

      const p = await client.query('SELECT * FROM pandits WHERE id = $1 FOR UPDATE', [session.pandit_id]);
      const pandit = p.rows[0];
      const billing = await chargeMinutes(client, session, pandit, 1);
      const chargedSelf = session.user_id === callerId;

      if (billing.minutesCharged === 0) {
        return {
          body: {
            success: false,
            error: 'INSUFFICIENT_BALANCE',
            walletBalance: billing.seekerBalance,
            ratePerMin: billing.rate,
            chargedSelf,
            message: `Low wallet balance (₹${billing.seekerBalance.toFixed(2)}). At least ₹${billing.rate.toFixed(2)} is needed to continue the consultation.`
          }
        };
      }

      return {
        body: {
          success: true,
          walletBalance: billing.seekerBalance,
          chargedSelf,
          ratePerMin: billing.rate,
          panditEarnings: callerPandit && callerPandit.id === pandit.id ? billing.earnings : undefined,
          totalMinutesConsulted: billing.totalMinutes
        }
      };
    });

    if (outcome.httpStatus) return res.status(outcome.httpStatus).json(outcome.body);
    res.json(outcome.body);
  } catch (err) {
    console.error('Deduct minute error:', err);
    res.status(500).json({ error: 'Failed to process minute billing' });
  }
});

// 14. POST /api/pandit/cancel - seeker leaves the queue or ends their live session
// body: { sessionId? }  (defaults to the caller's current active/waiting session)
router.post('/cancel', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const requested = toId((req.body || {}).sessionId);
    const outcome = await db.withTransaction(async (client) => {
      const q = requested
        ? await client.query('SELECT id, user_id, status FROM consultation_queue WHERE id = $1', [requested])
        : await client.query(
          `SELECT id, user_id, status FROM consultation_queue
           WHERE user_id = $1 AND status IN ('active', 'waiting') ORDER BY id DESC LIMIT 1`,
          [userId]
        );
      const row = q.rows[0];
      if (!row) return { httpStatus: 404, body: { error: 'No active or waiting consultation found' } };
      if (row.user_id !== userId) return { httpStatus: 403, body: { error: 'You can only cancel your own consultation' } };
      if (!['active', 'waiting'].includes(row.status)) {
        return { httpStatus: 409, body: { error: 'Consultation has already ended', status: row.status } };
      }
      const closed = await closeSession(client, row.id, 'completed');
      return { body: { success: true, status: closed.session.status, session: closed.session, billing: closed.billing } };
    });
    if (outcome.httpStatus) return res.status(outcome.httpStatus).json(outcome.body);
    res.json(outcome.body);
  } catch (err) {
    console.error('Cancel consultation error:', err);
    res.status(500).json({ error: 'Failed to cancel consultation' });
  }
});

// 15. POST /api/pandit/session/:id/end - either participant ends a session (billed server-side)
router.post('/session/:id/end', authenticateToken, async (req, res) => {
  try {
    const sessionId = toId(req.params.id);
    if (!sessionId) return res.status(400).json({ error: 'Invalid session id' });
    const outcome = await db.withTransaction(async (client) => {
      const { session, role } = await sessionForParticipant(client, sessionId, req.user.userId);
      if (!session) return { httpStatus: 404, body: { error: 'Session not found' } };
      if (!role) return { httpStatus: 403, body: { error: 'You are not a participant of this session' } };
      if (!['active', 'waiting'].includes(session.status)) {
        return { httpStatus: 409, body: { error: 'Session has already ended', status: session.status } };
      }
      const closed = await closeSession(client, sessionId, 'completed');
      return { body: { success: true, status: closed.session.status, session: closed.session, billing: closed.billing } };
    });
    if (outcome.httpStatus) return res.status(outcome.httpStatus).json(outcome.body);
    res.json(outcome.body);
  } catch (err) {
    console.error('End session error:', err);
    res.status(500).json({ error: 'Failed to end session' });
  }
});

// 16. GET /api/pandit/session/:id/messages?afterId=N
router.get('/session/:id/messages', authenticateToken, async (req, res) => {
  try {
    const sessionId = toId(req.params.id);
    if (!sessionId) return res.status(400).json({ error: 'Invalid session id' });
    const { session, role } = await sessionForParticipant(db, sessionId, req.user.userId);
    if (!session) return res.status(404).json({ error: 'Session not found' });
    if (!role) return res.status(403).json({ error: 'You are not a participant of this session' });

    const afterId = toId(req.query.afterId) || 0;
    const msgs = await db.query(
      `SELECT id, session_id AS "sessionId", sender_role AS "senderRole", content,
              is_prescription AS "isPrescription", created_at AS "createdAt"
       FROM consultation_messages WHERE session_id = $1 AND id > $2
       ORDER BY id ASC LIMIT 500`,
      [sessionId, afterId]
    );
    res.json({ sessionStatus: session.status, role, messages: msgs.rows });
  } catch (err) {
    console.error('Fetch session messages error:', err);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

// 17. POST /api/pandit/session/:id/messages  body: { content }
router.post('/session/:id/messages', authenticateToken, async (req, res) => {
  try {
    const sessionId = toId(req.params.id);
    if (!sessionId) return res.status(400).json({ error: 'Invalid session id' });
    const content = str((req.body || {}).content, 4000);
    if (!content) return res.status(400).json({ error: 'Message content is required' });

    const { session, role } = await sessionForParticipant(db, sessionId, req.user.userId);
    if (!session) return res.status(404).json({ error: 'Session not found' });
    if (!role) return res.status(403).json({ error: 'You are not a participant of this session' });
    if (session.status !== 'active') return res.status(409).json({ error: 'Messages can only be sent during an active session' });

    const ins = await db.query(
      `INSERT INTO consultation_messages (session_id, sender_user_id, sender_role, content)
       VALUES ($1, $2, $3, $4)
       RETURNING id, session_id AS "sessionId", sender_role AS "senderRole", content,
                 is_prescription AS "isPrescription", created_at AS "createdAt"`,
      [sessionId, req.user.userId, role, content]
    );
    res.status(201).json({ message: ins.rows[0] });
  } catch (err) {
    console.error('Send session message error:', err);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// 18. POST /api/pandit/prescription  body: { sessionId, gemstone?, mantra?, remedy? } (Pandit only)
router.post('/prescription', authenticateToken, requirePandit, async (req, res) => {
  try {
    const body = req.body || {};
    const sessionId = toId(body.sessionId);
    const gemstone = str(body.gemstone, 255) || null;
    const mantra = str(body.mantra, 2000) || null;
    const remedy = str(body.remedy, 4000) || null;
    if (!sessionId) return res.status(400).json({ error: 'A valid sessionId is required' });
    if (!gemstone && !mantra && !remedy) {
      return res.status(400).json({ error: 'Provide at least one of gemstone, mantra or remedy' });
    }

    const outcome = await db.withTransaction(async (client) => {
      const sq = await client.query('SELECT * FROM consultation_queue WHERE id = $1', [sessionId]);
      const session = sq.rows[0];
      if (!session) return { httpStatus: 404, body: { error: 'Session not found' } };
      if (session.pandit_id !== req.pandit.id) return { httpStatus: 403, body: { error: 'This session does not belong to you' } };

      const pres = await client.query(
        `INSERT INTO consultation_prescriptions (user_id, pandit_id, pandit_name, gemstone, mantra, remedy, session_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [session.user_id, req.pandit.id, req.pandit.full_name, gemstone, mantra, remedy, sessionId]
      );
      const text = [
        gemstone ? `Gemstone: ${gemstone}` : null,
        mantra ? `Mantra: ${mantra}` : null,
        remedy ? `Remedy: ${remedy}` : null
      ].filter(Boolean).join('\n');
      await client.query(
        `INSERT INTO consultation_messages (session_id, sender_user_id, sender_role, content, is_prescription)
         VALUES ($1, $2, 'pandit', $3, TRUE)`,
        [sessionId, req.user.userId, text]
      );
      return { body: { success: true, prescription: pres.rows[0] } };
    });
    if (outcome.httpStatus) return res.status(outcome.httpStatus).json(outcome.body);
    res.status(201).json(outcome.body);
  } catch (err) {
    console.error('Create prescription error:', err);
    res.status(500).json({ error: 'Failed to save prescription' });
  }
});

// 19. GET /api/pandit/wallet/transactions
// Seekers see their recharges/debits; Pandits additionally see payouts credited to them.
router.get('/wallet/transactions', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const pandit = await getPanditByUserId(userId);
    const params = [userId];
    let where = "(t.user_id = $1 AND t.type IN ('recharge', 'debit'))";
    if (pandit) {
      params.push(pandit.id);
      where += " OR (t.pandit_id = $2 AND t.type IN ('payout', 'credit'))";
    }
    const r = await db.query(
      `SELECT t.id, t.type, t.amount, t.description, t.created_at AS "createdAt",
              t.pandit_id AS "panditId", p.full_name AS "panditName"
       FROM wallet_transactions t
       LEFT JOIN pandits p ON p.id = t.pandit_id
       WHERE ${where}
       ORDER BY t.id DESC LIMIT 200`,
      params
    );
    const transactions = r.rows.map((t) => ({
      ...t,
      direction: t.type === 'recharge' || t.type === 'payout' || t.type === 'credit' ? 'credit' : 'debit'
    }));
    res.json({ transactions });
  } catch (err) {
    console.error('Fetch wallet transactions error:', err);
    res.status(500).json({ error: 'Failed to fetch wallet transactions' });
  }
});

module.exports = router;
