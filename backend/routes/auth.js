const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../db');

const JWT_SECRET = process.env.JWT_SECRET || 'astro_super_secret_key_2026';

// Middleware to authenticate JWT token
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ error: 'Invalid or expired token' });
    req.user = user;
    next();
  });
}

// Middleware for optional JWT token (creates guest user in Neon DB if unauthenticated)
async function optionalAuthenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (token) {
    try {
      const decoded = jwt.verify(token, JWT_SECRET);
      req.user = decoded;
      return next();
    } catch (err) {
      console.warn('Invalid token passed, proceeding to create/assign guest user session.');
    }
  }

  // Create auto guest user in Neon DB
  try {
    const guestEmail = `guest_${Date.now()}_${Math.floor(Math.random() * 1000)}@astroai.com`;
    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash('guestpass123', salt);
    
    const result = await db.query(
      'INSERT INTO users (email, password_hash, full_name, gender) VALUES ($1, $2, $3, $4) RETURNING id, email',
      [guestEmail, passwordHash, 'Guest User', 'Not Specified']
    );

    const guestUser = result.rows[0];
    req.user = { userId: guestUser.id, email: guestUser.email };
    next();
  } catch (err) {
    console.error('Guest creation error:', err);
    req.user = { userId: 1, email: 'default@astroai.com' };
    next();
  }
}

// POST /api/auth/register
router.post('/register', async (req, res) => {
  try {
    const { email, password, fullName, gender } = req.body;

    if (!email || !password || !fullName) {
      return res.status(400).json({ error: 'Email, password, and full name are required' });
    }

    const existing = await db.query('SELECT * FROM users WHERE email = $1', [email.toLowerCase().trim()]);
    if (existing.rows.length > 0) {
      return res.status(400).json({ error: 'User with this email already exists' });
    }

    const salt = await bcrypt.genSalt(10);
    const passwordHash = await bcrypt.hash(password, salt);

    const result = await db.query(
      'INSERT INTO users (email, password_hash, full_name, gender) VALUES ($1, $2, $3, $4) RETURNING id, email, full_name, gender, created_at',
      [email.toLowerCase().trim(), passwordHash, fullName, gender || 'Not Specified']
    );

    const user = result.rows[0];
    const token = jwt.sign({ userId: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });

    res.status(201).json({
      message: 'Registration successful',
      token,
      user
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Server error during registration' });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const cleanEmail = email.toLowerCase().trim();
    const result = await db.query('SELECT * FROM users WHERE email = $1', [cleanEmail]);

    // If account doesn't exist yet, auto-register seamless account in Neon DB
    if (result.rows.length === 0) {
      const salt = await bcrypt.genSalt(10);
      const passwordHash = await bcrypt.hash(password, salt);
      const defaultName = cleanEmail.split('@')[0];

      const newUserRes = await db.query(
        'INSERT INTO users (email, password_hash, full_name, gender) VALUES ($1, $2, $3, $4) RETURNING id, email, full_name, gender, created_at',
        [cleanEmail, passwordHash, defaultName, 'Not Specified']
      );

      const user = newUserRes.rows[0];
      const token = jwt.sign({ userId: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });

      return res.status(200).json({
        message: 'Account created & logged in successfully',
        token,
        user: {
          id: user.id,
          email: user.email,
          fullName: user.full_name,
          gender: user.gender
        }
      });
    }

    const user = result.rows[0];
    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ error: 'Incorrect password for this account.' });
    }

    // Fetch existing birth details and Kundli if available
    const kundliRes = await db.query(
      `SELECT bd.full_name, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth, bd.latitude, bd.longitude,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada, k.planetary_positions, k.houses, k.dasha_info
       FROM birth_details bd
       LEFT JOIN kundlis k ON bd.user_id = k.user_id
       WHERE bd.user_id = $1`,
      [user.id]
    );

    let existingKundli = null;
    let hasBirthDetails = false;

    if (kundliRes.rows.length > 0 && kundliRes.rows[0].date_of_birth) {
      hasBirthDetails = true;
      const k = kundliRes.rows[0];
      existingKundli = {
        ascendant: k.ascendant || 'Aries',
        sunSign: k.sun_sign || 'Leo',
        moonSign: k.moon_sign || 'Taurus',
        nakshatra: k.nakshatra || 'Rohini',
        nakshatraPada: k.nakshatra_pada || 1,
        birthDetails: {
          fullName: k.full_name || user.full_name,
          dateOfBirth: k.date_of_birth,
          timeOfBirth: k.time_of_birth,
          placeOfBirth: k.place_of_birth,
        },
        planetaryPositions: k.planetary_positions,
        houses: k.houses,
        dashaInfo: k.dasha_info
      };
    }

    const token = jwt.sign({ userId: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });

    res.json({
      message: 'Login successful',
      token,
      hasBirthDetails,
      kundli: existingKundli,
      user: {
        id: user.id,
        email: user.email,
        fullName: user.full_name,
        gender: user.gender
      }
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
      `SELECT u.id, u.email, u.full_name, u.gender, 
              bd.date_of_birth, bd.time_of_birth, bd.place_of_birth,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra
       FROM users u
       LEFT JOIN birth_details bd ON u.id = bd.user_id
       LEFT JOIN kundlis k ON u.id = k.user_id
       WHERE u.id = $1`,
      [req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ user: result.rows[0] });
  } catch (error) {
    console.error('Fetch me error:', error);
    res.status(500).json({ error: 'Server error fetching user profile' });
  }
});

module.exports = { router, authenticateToken, optionalAuthenticateToken };
