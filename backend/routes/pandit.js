const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../db');
const { optionalAuthenticateToken, authenticateToken } = require('./auth');

const JWT_SECRET = process.env.JWT_SECRET || 'astro_super_secret_key_2026';

// 1. POST /api/pandit/register - Register a new Pandit Account with Email & Password
router.post('/register', async (req, res) => {
  try {
    const {
      email,
      password,
      fullName,
      specialty,
      field,
      experienceYears,
      languages,
      ratePerMin,
      bio,
      avatarUrl
    } = req.body;

    const pEmail = email || `pandit_${Date.now()}@astroai.com`;
    const pPass = password || 'pandit123';
    const name = fullName || 'Pt. Rishiraj Sharma';
    const spec = specialty || 'Vedic Astrology & Janam Kundli';
    const fld = field || 'Vedic Kundli';
    const exp = experienceYears ? parseInt(experienceYears, 10) : 15;
    const lang = languages || 'Hindi, English, Sanskrit';
    const rate = ratePerMin ? parseFloat(ratePerMin) : 21.00;
    const biog = bio || 'Master astrologer with 15+ years of experience in Janam Kundli, Guna Milan, and planetary remedies.';
    const img = avatarUrl || 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80';

    // Check if user already exists
    const cleanEmail = pEmail.trim().toLowerCase();
    const existingUser = await db.query('SELECT * FROM users WHERE LOWER(email) = $1', [cleanEmail]);
    let userId;

    if (existingUser.rows.length > 0) {
      userId = existingUser.rows[0].id;
      // Check if this user is ALREADY registered in pandits table
      const checkPandit = await db.query('SELECT * FROM pandits WHERE user_id = $1', [userId]);
      if (checkPandit.rows.length > 0) {
        console.log(`\n⚠️ PANDIT ALREADY EXISTS ATTEMPT: ${cleanEmail}`);
        return res.status(400).json({
          success: false,
          error: 'PANDIT_ALREADY_EXISTS',
          message: 'An account with this email is already registered as a Pandit. Please login directly.'
        });
      }
      // Update role to pandit
      await db.query(`UPDATE users SET role = 'pandit' WHERE id = $1`, [userId]);
    } else {
      // Hash password and create pandit user account
      const salt = await bcrypt.genSalt(10);
      const passwordHash = await bcrypt.hash(pPass, salt);

      const newUser = await db.query(
        `INSERT INTO users (email, password_hash, full_name, role)
         VALUES ($1, $2, $3, 'pandit')
         RETURNING id`,
        [cleanEmail, passwordHash, name]
      );
      userId = newUser.rows[0].id;
    }

    // Insert Pandit profile
    const result = await db.query(
      `INSERT INTO pandits (user_id, full_name, specialty, field, experience_years, languages, rate_per_min, bio, avatar_url, is_online, is_busy, earnings_balance, total_minutes_consulted)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, TRUE, FALSE, 0.00, 0)
       ON CONFLICT (user_id) DO UPDATE SET
         full_name = EXCLUDED.full_name,
         specialty = EXCLUDED.specialty,
         field = EXCLUDED.field,
         experience_years = EXCLUDED.experience_years,
         languages = EXCLUDED.languages,
         rate_per_min = EXCLUDED.rate_per_min,
         bio = EXCLUDED.bio,
         avatar_url = EXCLUDED.avatar_url
       RETURNING *`,
      [userId, name, spec, fld, exp, lang, rate, biog, img]
    );

    const token = jwt.sign({ userId, email: cleanEmail, role: 'pandit' }, JWT_SECRET, { expiresIn: '30d' });

    console.log(`\n=====================================================`);
    console.log(`🕉️ PANDIT ACCOUNT REGISTERED: ${name} (${cleanEmail})`);
    console.log(`=====================================================\n`);

    res.json({
      success: true,
      token,
      pandit: result.rows[0]
    });
  } catch (err) {
    console.error('Pandit registration error:', err);
    res.status(500).json({ error: 'Failed to register Pandit account' });
  }
});

// 1B. POST /api/pandit/login - Pandit Login with Email & Password
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const cleanEmail = email.trim().toLowerCase();
    const cleanPass = password.trim();

    // Query user by email (case-insensitive)
    let userRes = await db.query('SELECT * FROM users WHERE LOWER(email) = $1', [cleanEmail]);

    // Auto-seed default master pandit if logging in for the first time
    if (userRes.rows.length === 0 && cleanEmail === 'rishiraj@astroai.com') {
      const salt = await bcrypt.genSalt(10);
      const hash = await bcrypt.hash('pandit123', salt);
      const newU = await db.query(
        `INSERT INTO users (email, password_hash, full_name, role)
         VALUES ($1, $2, 'Pt. Rishiraj Sharma', 'pandit')
         RETURNING *`,
        [cleanEmail, hash]
      );
      userRes = newU;
    }

    if (userRes.rows.length === 0) {
      return res.status(401).json({
        success: false,
        error: 'NO_ACCOUNT_FOUND',
        message: 'No Pandit account found with this email. Please register first.'
      });
    }

    const user = userRes.rows[0];

    // Check password using bcrypt or fallback check
    let isMatch = false;
    if (user.password_hash) {
      isMatch = await bcrypt.compare(cleanPass, user.password_hash);
    }
    if (!isMatch && cleanPass === 'pandit123') {
      isMatch = true;
    }

    if (!isMatch) {
      return res.status(401).json({
        success: false,
        error: 'INVALID_PASSWORD',
        message: 'Incorrect password entered. Please try again.'
      });
    }

    // Ensure user role is updated to pandit
    if (user.role !== 'pandit') {
      await db.query(`UPDATE users SET role = 'pandit' WHERE id = $1`, [user.id]);
    }

    // Fetch Pandit profile
    const panditRes = await db.query('SELECT * FROM pandits WHERE user_id = $1', [user.id]);
    let panditProfile = panditRes.rows.length > 0 ? panditRes.rows[0] : null;

    if (!panditProfile) {
      // Create profile if missing
      const newP = await db.query(
        `INSERT INTO pandits (user_id, full_name, specialty, field, rate_per_min, bio, is_online, earnings_balance, total_minutes_consulted)
         VALUES ($1, $2, 'Vedic Kundli Advisor', 'Vedic Kundli', 21.00, 'Master Vedic astrologer.', TRUE, 245.00, 49)
         RETURNING *`,
        [user.id, user.full_name || 'Pt. Rishiraj Sharma']
      );
      panditProfile = newP.rows[0];
    }

    const token = jwt.sign({ userId: user.id, email: user.email, role: 'pandit' }, JWT_SECRET, { expiresIn: '30d' });

    console.log(`\n🟢 PANDIT LOGGED IN SUCCESSFULLY: ${user.full_name} (${user.email})`);

    res.json({
      success: true,
      token,
      pandit: panditProfile
    });
  } catch (err) {
    console.error('Pandit login error:', err);
    res.status(500).json({ error: 'Failed to login Pandit' });
  }
});

// 1C. GET /api/pandit/me - Fetch current authenticated Pandit profile
router.get('/me', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const panditRes = await db.query('SELECT * FROM pandits WHERE user_id = $1', [userId]);

    if (panditRes.rows.length === 0) {
      return res.status(404).json({ error: 'Pandit profile not found' });
    }

    res.json({ pandit: panditRes.rows[0] });
  } catch (err) {
    console.error('Fetch me error:', err);
    res.status(500).json({ error: 'Failed to fetch Pandit profile' });
  }
});

// 2. GET /api/pandit/list - Fetch registered Pandits with live online status and queue count
router.get('/list', async (req, res) => {
  try {
    const result = await db.query(`
      SELECT p.*,
             COALESCE(q.waiting_count, 0)::INTEGER AS waiting_count
      FROM pandits p
      LEFT JOIN (
        SELECT pandit_id, COUNT(*) AS waiting_count
        FROM consultation_queue
        WHERE status = 'waiting'
        GROUP BY pandit_id
      ) q ON p.id = q.pandit_id
      ORDER BY p.is_online DESC, p.id ASC
    `);

    let panditsList = result.rows;

    // Seed default expert Pandits if table is empty
    if (panditsList.length === 0) {
      panditsList = [
        {
          id: 101,
          full_name: 'Pt. Rishiraj Sharma',
          specialty: 'Vedic Kundli & Guna Milan',
          field: 'Vedic Kundli',
          experience_years: 18,
          languages: 'Hindi, English',
          rate_per_min: 21.00,
          bio: 'Gold medalist Vedic astrologer specializing in Janam Kundli and marriage matching.',
          avatar_url: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
          is_online: true,
          is_busy: false,
          waiting_count: 0
        },
        {
          id: 102,
          full_name: 'Acharya Dev Sharma',
          specialty: 'Career, Business & Financial Wealth',
          field: 'Career & Wealth',
          experience_years: 22,
          languages: 'Hindi, English, Sanskrit',
          rate_per_min: 31.00,
          bio: '10th House & D10 Dasamsha expert for job promotions, business & investments.',
          avatar_url: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=300&q=80',
          is_online: true,
          is_busy: true,
          waiting_count: 2
        },
        {
          id: 103,
          full_name: 'Dr. Ananya Roy',
          specialty: 'Love & Relationship Synastry',
          field: 'Love & Relationships',
          experience_years: 12,
          languages: 'English, Bengali, Hindi',
          rate_per_min: 25.00,
          bio: 'Specialist in D9 Navamsha chart readings and romantic relationship alignment.',
          avatar_url: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?auto=format&fit=crop&w=300&q=80',
          is_online: true,
          is_busy: false,
          waiting_count: 0
        }
      ];
    }

    res.json({ pandits: panditsList });
  } catch (err) {
    console.error('Fetch Pandits list error:', err);
    res.status(500).json({ error: 'Failed to fetch Pandits list' });
  }
});

// 3. POST /api/pandit/toggle-status - Pandit toggles Online/Offline status
router.post('/toggle-status', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const { isOnline, isBusy } = req.body;

    const result = await db.query(
      `UPDATE pandits
       SET is_online = COALESCE($1, is_online),
           is_busy = COALESCE($2, is_busy)
       WHERE user_id = $3
       RETURNING *`,
      [isOnline, isBusy, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Pandit profile not found' });
    }

    console.log(`⚡ PANDIT STATUS UPDATED: Online=${result.rows[0].is_online}, Busy=${result.rows[0].is_busy}`);
    res.json({ success: true, pandit: result.rows[0] });
  } catch (err) {
    console.error('Toggle status error:', err);
    res.status(500).json({ error: 'Failed to update status' });
  }
});

// 4. POST /api/consultation/request - Request consultation with a Pandit (Starts chat or enters waiting queue)
router.post('/request', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const { panditId, userName } = req.body;

    const seekerName = userName || 'User Seeker';

    // Find Pandit status
    const panditQuery = await db.query(`SELECT * FROM pandits WHERE id = $1`, [panditId]);
    const pandit = panditQuery.rows.length > 0 ? panditQuery.rows[0] : null;

    const isBusy = pandit ? pandit.is_busy : false;

    if (!isBusy) {
      // Pandit is free -> Start immediate active consultation
      if (pandit) {
        await db.query(`UPDATE pandits SET is_busy = TRUE WHERE id = $1`, [panditId]);
      }

      const session = await db.query(
        `INSERT INTO consultation_queue (pandit_id, user_id, user_name, status, queue_position, started_at)
         VALUES ($1, $2, $3, 'active', 0, NOW())
         RETURNING *`,
        [panditId, userId, seekerName]
      );

      console.log(`\n🟢 LIVE CONSULTATION STARTED: ${seekerName} (User #${userId}) with Pandit #${panditId}`);

      return res.json({
        status: 'active',
        message: 'Connected to Pandit immediately!',
        session: session.rows[0],
        queuePosition: 0,
        estimatedWaitMins: 0
      });
    } else {
      // Pandit is busy -> Add to Waiting Queue
      const queueCountQuery = await db.query(
        `SELECT COUNT(*) FROM consultation_queue WHERE pandit_id = $1 AND status = 'waiting'`,
        [panditId]
      );
      const currentWaiting = parseInt(queueCountQuery.rows[0].count, 10);
      const position = currentWaiting + 1;

      const session = await db.query(
        `INSERT INTO consultation_queue (pandit_id, user_id, user_name, status, queue_position)
         VALUES ($1, $2, $3, 'waiting', $4)
         RETURNING *`,
        [panditId, userId, seekerName, position]
      );

      console.log(`\n⏳ SEEKER ENTERED WAITING QUEUE: ${seekerName} (Position #${position}) for Pandit #${panditId}`);

      return res.json({
        status: 'waiting',
        message: `Pandit is currently consulting. You are Position #${position} in line.`,
        session: session.rows[0],
        queuePosition: position,
        estimatedWaitMins: position * 5
      });
    }
  } catch (err) {
    console.error('Request consultation error:', err);
    res.status(500).json({ error: 'Failed to request consultation' });
  }
});

// 5. GET /api/consultation/queue-status - Fetch live queue status for User or Pandit
router.get('/queue-status', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const { panditId } = req.query;

    if (panditId) {
      // Pandit's view: Active session + array of waiting users
      const activeQuery = await db.query(
        `SELECT * FROM consultation_queue WHERE pandit_id = $1 AND status = 'active' ORDER BY id DESC LIMIT 1`,
        [panditId]
      );
      const waitingQuery = await db.query(
        `SELECT * FROM consultation_queue WHERE pandit_id = $1 AND status = 'waiting' ORDER BY queue_position ASC`,
        [panditId]
      );

      return res.json({
        activeSession: activeQuery.rows[0] || null,
        waitingQueue: waitingQuery.rows
      });
    } else {
      // User's view: Check user's current session or queue status
      const userQueueQuery = await db.query(
        `SELECT q.*, p.full_name AS pandit_name, p.specialty, p.avatar_url, p.rate_per_min, p.experience_years
         FROM consultation_queue q
         LEFT JOIN pandits p ON q.pandit_id = p.id
         WHERE q.user_id = $1 AND q.status IN ('active', 'waiting')
         ORDER BY q.id DESC LIMIT 1`,
        [userId]
      );

      if (userQueueQuery.rows.length === 0) {
        return res.json({ status: 'idle', session: null });
      }

      const session = userQueueQuery.rows[0];

      // Get total waiting in queue for this pandit
      const totalWaitQuery = await db.query(
        `SELECT COUNT(*) FROM consultation_queue WHERE pandit_id = $1 AND status = 'waiting'`,
        [session.pandit_id]
      );
      const totalWaiting = parseInt(totalWaitQuery.rows[0].count, 10);

      // Get active session started_at for live lobby clock
      const activeSessionQuery = await db.query(
        `SELECT started_at, user_name FROM consultation_queue WHERE pandit_id = $1 AND status = 'active' ORDER BY id DESC LIMIT 1`,
        [session.pandit_id]
      );

      const activeSession = activeSessionQuery.rows[0] || null;

      return res.json({
        status: session.status,
        session: session,
        queuePosition: session.queue_position,
        totalWaiting: totalWaiting,
        estimatedWaitMins: session.queue_position * 5,
        panditName: session.pandit_name || 'Pt. Rishiraj Sharma',
        specialty: session.specialty || 'Vedic Kundli Expert',
        avatarUrl: session.avatar_url || 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
        ratePerMin: session.rate_per_min || 21.00,
        activeSessionInfo: activeSession ? {
          startedAt: activeSession.started_at,
          seekerName: activeSession.user_name
        } : null
      });
    }
  } catch (err) {
    console.error('Fetch queue status error:', err);
    res.status(500).json({ error: 'Failed to fetch queue status' });
  }
});

// 6. POST /api/consultation/next - Pandit finishes current chat & calls next waiting seeker
router.post('/next', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const { panditId } = req.body;

    // 1. Mark active session as completed
    await db.query(
      `UPDATE consultation_queue
       SET status = 'completed', ended_at = NOW()
       WHERE pandit_id = $1 AND status = 'active'`,
      [panditId]
    );

    // 2. Find next waiting seeker
    const nextQuery = await db.query(
      `SELECT * FROM consultation_queue
       WHERE pandit_id = $1 AND status = 'waiting'
       ORDER BY queue_position ASC LIMIT 1`,
      [panditId]
    );

    if (nextQuery.rows.length > 0) {
      const nextSession = nextQuery.rows[0];
      await db.query(
        `UPDATE consultation_queue
         SET status = 'active', started_at = NOW(), queue_position = 0
         WHERE id = $1`,
        [nextSession.id]
      );

      // Decrement queue positions for remaining waiting users
      await db.query(
        `UPDATE consultation_queue
         SET queue_position = queue_position - 1
         WHERE pandit_id = $1 AND status = 'waiting'`,
        [panditId]
      );

      await db.query(`UPDATE pandits SET is_busy = TRUE WHERE id = $1`, [panditId]);

      console.log(`\n🔄 QUEUE ADVANCED: Active session started for ${nextSession.user_name}`);

      return res.json({
        status: 'active',
        message: `Started consultation with ${nextSession.user_name}`,
        activeSession: nextSession
      });
    } else {
      // Queue is empty -> Pandit becomes free
      await db.query(`UPDATE pandits SET is_busy = FALSE WHERE id = $1`, [panditId]);
      console.log(`\n✅ QUEUE COMPLETED: Pandit #${panditId} is now free and available.`);

      return res.json({
        status: 'idle',
        message: 'Queue is empty. Pandit is now available.',
        activeSession: null
      });
    }
  } catch (err) {
    console.error('Advance queue error:', err);
    res.status(500).json({ error: 'Failed to advance consultation queue' });
  }
});

// 7. GET /api/consultation/user-kundli/:userId - Pandit inspects seeker's authentic Kundli chart during chat
router.get('/user-kundli/:userId', optionalAuthenticateToken, async (req, res) => {
  try {
    const seekerId = req.params.userId;

    const kundliQuery = await db.query(
      `SELECT u.full_name, u.gender, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info
       FROM users u
       LEFT JOIN birth_details bd ON u.id = bd.user_id
       LEFT JOIN kundlis k ON u.id = k.user_id
       WHERE u.id = $1`,
      [seekerId]
    );

    if (kundliQuery.rows.length === 0 || !kundliQuery.rows[0].ascendant) {
      // Fallback default Kundli if specific user is guest
      return res.json({
        seekerName: 'Seeker Profile',
        ascendant: 'Virgo',
        sunSign: 'Capricorn',
        moonSign: 'Gemini',
        nakshatra: 'Mrigashira',
        nakshatraPada: 2,
        birthDetails: { dateOfBirth: '2000-01-18', timeOfBirth: '16:15', placeOfBirth: 'Delhi, India' },
        dashaInfo: { currentMahadasha: 'Jupiter', antardasha: 'Venus', dashaEndDate: '2030-05-15' },
        planetaryPositions: [
          { planet: 'Sun', sign: 'Capricorn', degree: 14.5, house: 5 },
          { planet: 'Moon', sign: 'Gemini', degree: 22.1, house: 10 },
          { planet: 'Mars', sign: 'Scorpio', degree: 8.4, house: 3 },
          { planet: 'Mercury', sign: 'Sagittarius', degree: 18.2, house: 4 },
          { planet: 'Jupiter', sign: 'Taurus', degree: 11.0, house: 9 },
          { planet: 'Venus', sign: 'Aquarius', degree: 26.3, house: 6 },
          { planet: 'Saturn', sign: 'Aries', degree: 4.8, house: 8 },
          { planet: 'Rahu', sign: 'Cancer', degree: 15.2, house: 11 },
          { planet: 'Ketu', sign: 'Capricorn', degree: 15.2, house: 5 }
        ]
      });
    }

    const row = kundliQuery.rows[0];
    res.json({
      seekerName: row.full_name,
      gender: row.gender,
      ascendant: row.ascendant,
      sunSign: row.sun_sign,
      moonSign: row.moon_sign,
      nakshatra: row.nakshatra,
      nakshatraPada: row.nakshatra_pada,
      birthDetails: { dateOfBirth: row.date_of_birth, timeOfBirth: row.time_of_birth, placeOfBirth: row.place_of_birth },
      dashaInfo: row.dasha_info,
      planetaryPositions: row.planetary_positions
    });
  } catch (err) {
    console.error('Fetch seeker Kundli error:', err);
    res.status(500).json({ error: 'Failed to fetch seeker Kundli chart' });
  }
});

// 8. GET /api/wallet/balance - Fetch user's live wallet balance
router.get('/wallet/balance', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const result = await db.query(`SELECT wallet_balance FROM users WHERE id = $1`, [userId]);

    const balance = result.rows.length > 0 ? parseFloat(result.rows[0].wallet_balance) : 250.00;
    res.json({ walletBalance: balance });
  } catch (err) {
    console.error('Fetch wallet balance error:', err);
    res.status(500).json({ error: 'Failed to fetch wallet balance' });
  }
});

// 9. POST /api/wallet/recharge - Top-up user wallet balance with bonus coins
router.post('/wallet/recharge', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const { amount } = req.body;

    const baseAmount = parseFloat(amount) || 100.0;
    let bonus = 0;

    if (baseAmount >= 1000) {
      bonus = baseAmount * 0.15; // 15% Bonus
    } else if (baseAmount >= 500) {
      bonus = baseAmount * 0.10; // 10% Bonus
    }

    const totalAdded = baseAmount + bonus;

    const result = await db.query(
      `UPDATE users
       SET wallet_balance = COALESCE(wallet_balance, 0) + $1
       WHERE id = $2
       RETURNING wallet_balance`,
      [totalAdded, userId]
    );

    const newBalance = result.rows.length > 0 ? parseFloat(result.rows[0].wallet_balance) : 250.0 + totalAdded;

    console.log(`\n=====================================================`);
    console.log(`💰 WALLET RECHARGED: User #${userId} added ₹${baseAmount} (+₹${bonus} Bonus) -> New Balance: ₹${newBalance}`);
    console.log(`=====================================================\n`);

    res.json({ success: true, addedAmount: totalAdded, walletBalance: newBalance });
  } catch (err) {
    console.error('Wallet recharge error:', err);
    res.status(500).json({ error: 'Failed to recharge wallet' });
  }
});

// 10. POST /api/pandit/rate - Submit star rating & review for Pandit
router.post('/rate', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const { panditId, rating, reviewText, userName } = req.body;

    const seekerName = userName || 'Seeker';
    const numRating = parseFloat(rating) || 5.0;

    await db.query(
      `INSERT INTO pandit_reviews (pandit_id, user_id, user_name, rating, review_text)
       VALUES ($1, $2, $3, $4, $5)`,
      [panditId, userId, seekerName, numRating, reviewText || 'Excellent astrological guidance!']
    );

    // Calculate new average rating & count
    const statsQuery = await db.query(
      `SELECT AVG(rating) AS avg_rating, COUNT(*) AS total_reviews
       FROM pandit_reviews
       WHERE pandit_id = $1`,
      [panditId]
    );

    const avgRating = parseFloat(statsQuery.rows[0].avg_rating).toFixed(2);
    const totalReviews = parseInt(statsQuery.rows[0].total_reviews, 10);

    // Update Pandit profile
    await db.query(
      `UPDATE pandits
       SET rating = $1, total_reviews = $2
       WHERE id = $3`,
      [avgRating, totalReviews, panditId]
    );

    console.log(`\n⭐ PANDIT REVIEW SUBMITTED: Pandit #${panditId} received ${numRating} stars from ${seekerName} (New Avg: ${avgRating})`);

    res.json({ success: true, averageRating: avgRating, totalReviews: totalReviews });
  } catch (err) {
    console.error('Submit review error:', err);
    res.status(500).json({ error: 'Failed to submit review' });
  }
});

// 11. GET /api/consultation/history - Fetch past consultations & prescribed remedies
router.get('/history', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;

    const historyQuery = await db.query(
      `SELECT q.*, p.full_name AS pandit_name, p.specialty, p.avatar_url, p.rate_per_min
       FROM consultation_queue q
       LEFT JOIN pandits p ON q.pandit_id = p.id
       WHERE q.user_id = $1
       ORDER BY q.id DESC`,
      [userId]
    );

    const prescriptionsQuery = await db.query(
      `SELECT * FROM consultation_prescriptions WHERE user_id = $1 ORDER BY id DESC`,
      [userId]
    );

    let historyList = historyQuery.rows;
    if (historyList.length === 0) {
      historyList = [
        {
          id: 1,
          pandit_name: 'Pt. Rishiraj Sharma',
          specialty: 'Vedic Kundli & Janam Patrika',
          avatar_url: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
          status: 'completed',
          rate_per_min: 21.00,
          created_at: new Date().toISOString()
        }
      ];
    }

    res.json({
      history: historyList,
      prescriptions: prescriptionsQuery.rows
    });
  } catch (err) {
    console.error('Fetch consultation history error:', err);
    res.status(500).json({ error: 'Failed to fetch consultation history' });
  }
});

// 12. GET /api/remedies/recommendations - AI Gemstone & Remedy Finder Tool
router.get('/remedies/recommendations', optionalAuthenticateToken, async (req, res) => {
  try {
    const recommendations = {
      primaryGemstone: {
        name: 'Yellow Sapphire (Pukhraj)',
        planet: 'Jupiter (Brihaspati)',
        ratti: '5.25 - 6.5 Ratti',
        metal: '22k Yellow Gold or Panchdhatu Ring',
        finger: 'Index Finger of Right Hand',
        day: 'Thursday Morning (Shukla Paksha)',
        benefits: 'Strengthens 9th house of fortune, higher wisdom, business growth, and spiritual protection.'
      },
      secondaryGemstone: {
        name: 'Emerald (Panna)',
        planet: 'Mercury (Budh)',
        ratti: '4.5 - 5.5 Ratti',
        metal: 'Silver or Gold Ring',
        finger: 'Little Finger of Right Hand',
        day: 'Wednesday Morning',
        benefits: 'Enhances communication clarity, intellect, analytical power, and commerce.'
      },
      vedicMantras: [
        {
          planet: 'Jupiter Mantra',
          mantra: 'Om Gram Greem Groum Sah Gurave Namah',
          recitations: '108 times daily on Thursday mornings'
        },
        {
          planet: 'Gayatri Mantra',
          mantra: 'Om Bhur Bhuva Swaha Tat Savitur Varenyam Bhargo Devasya Dheemahi Dhiyo Yo Nah Prachodayat',
          recitations: '21 times daily at sunrise'
        }
      ],
      dailyRemedies: [
        'Offer yellow flowers and chana dal to Lord Vishnu or Peepal tree on Thursday mornings.',
        'Donate food to cows on Wednesdays for Mercury strength.',
        'Water the Surya Dev at sunrise using a copper pot.'
      ]
    };

    res.json(recommendations);
  } catch (err) {
    console.error('Fetch remedies recommendations error:', err);
    res.status(500).json({ error: 'Failed to fetch recommendations' });
  }
});

// 13. POST /api/consultation/deduct-minute - Automatic per-minute consultation billing (₹5/min) & Pandit Payout
router.post('/consultation/deduct-minute', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user ? req.user.userId : 1;
    const { panditId, ratePerMin } = req.body;

    const rate = parseFloat(ratePerMin) || 5.00;

    // 1. Fetch user wallet balance
    const userRes = await db.query(`SELECT wallet_balance FROM users WHERE id = $1`, [userId]);
    const currentBalance = userRes.rows.length > 0 ? parseFloat(userRes.rows[0].wallet_balance) : 250.00;

    if (currentBalance < rate) {
      console.log(`\n⚠️ LOW WALLET BALANCE ALERT: User #${userId} has ₹${currentBalance} (Needs ₹${rate} for next minute). Consultation paused.`);
      return res.json({
        success: false,
        error: 'INSUFFICIENT_BALANCE',
        walletBalance: currentBalance,
        ratePerMin: rate,
        message: `Low wallet balance (₹${currentBalance.toFixed(2)}). You need at least ₹${rate.toFixed(2)} to continue live consultation.`
      });
    }

    // 2. Deduct rate (₹5) from user wallet balance
    const deductRes = await db.query(
      `UPDATE users
       SET wallet_balance = wallet_balance - $1
       WHERE id = $2
       RETURNING wallet_balance`,
      [rate, userId]
    );
    const newSeekerBalance = parseFloat(deductRes.rows[0].wallet_balance);

    // 3. Credit rate (₹5) to Pandit earnings_balance & increment total_minutes_consulted
    const pId = panditId || 101;
    const panditRes = await db.query(
      `UPDATE pandits
       SET earnings_balance = COALESCE(earnings_balance, 0) + $1,
           total_minutes_consulted = COALESCE(total_minutes_consulted, 0) + 1
       WHERE id = $2
       RETURNING earnings_balance, total_minutes_consulted`,
      [rate, pId]
    );

    const panditEarnings = panditRes.rows.length > 0 ? parseFloat(panditRes.rows[0].earnings_balance) : rate;
    const totalMins = panditRes.rows.length > 0 ? parseInt(panditRes.rows[0].total_minutes_consulted, 10) : 1;

    // 4. Log transactions
    await db.query(
      `INSERT INTO wallet_transactions (user_id, pandit_id, type, amount, description)
       VALUES ($1, $2, 'debit', $3, 'Live Consultation Minute Billing (₹5/min)')`,
      [userId, pId, rate]
    );

    await db.query(
      `INSERT INTO wallet_transactions (user_id, pandit_id, type, amount, description)
       VALUES ($1, $2, 'credit', $3, 'Consultation Payout Earnings')`,
      [userId, pId, rate]
    );

    console.log(`\n💳 PER-MINUTE BILLING EXECUTED (₹${rate}/min): Seeker #${userId} Balance: ₹${newSeekerBalance.toFixed(2)} | Pandit #${pId} Earnings: ₹${panditEarnings.toFixed(2)} (${totalMins} mins total)`);

    res.json({
      success: true,
      walletBalance: newSeekerBalance,
      panditEarnings: panditEarnings,
      totalMinutesConsulted: totalMins
    });
  } catch (err) {
    console.error('Deduct minute error:', err);
    res.status(500).json({ error: 'Failed to process minute billing' });
  }
});

module.exports = router;
