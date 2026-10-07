const { Pool, types } = require('pg');
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
require('dotenv').config({ path: path.join(__dirname, '.env') });

// --- Type parsers -----------------------------------------------------------
// NUMERIC (1700) is returned as a string by default, which breaks clients that
// expect numbers (e.g. Dart `(x as num).toDouble()`). Values here are money /
// ratings / coordinates, all well within double precision.
types.setTypeParser(1700, (v) => (v === null ? null : parseFloat(v)));
// BIGINT (20) from COUNT(*) etc.
types.setTypeParser(20, (v) => (v === null ? null : parseInt(v, 10)));
// DATE (1082): keep as 'YYYY-MM-DD'. The default parser builds a JS Date at
// local midnight which serialises to the previous day in UTC for IST servers.
types.setTypeParser(1082, (v) => v);

const connectionString = process.env.NEON_DATABASE_URL || process.env.DATABASE_URL;

if (!connectionString) {
  console.error('❌ NEON_DATABASE_URL / DATABASE_URL is not set. Database queries will fail.');
}

const isLocalDb = !!connectionString && /@(localhost|127\.0\.0\.1)(:|\/)/.test(connectionString);

const pool = new Pool({
  connectionString,
  ssl: connectionString && !isLocalDb ? { rejectUnauthorized: false } : false,
  max: Number(process.env.PG_POOL_MAX) || 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
});

pool.on('error', (err) => {
  console.error('Unexpected database error on idle client:', err.message);
});

async function seedDemoPandit(client) {
  if (process.env.SEED_DEMO_PANDIT === 'false') return;
  const email = 'rishiraj@astroai.com';
  const existing = await client.query('SELECT id FROM users WHERE LOWER(email) = $1', [email]);
  let userId;
  if (existing.rows.length > 0) {
    userId = existing.rows[0].id;
    await client.query(`UPDATE users SET role = 'pandit' WHERE id = $1`, [userId]);
  } else {
    const passHash = await bcrypt.hash('pandit123', 10);
    const inserted = await client.query(
      `INSERT INTO users (email, password_hash, full_name, role)
       VALUES ($1, $2, 'Pt. Rishiraj Sharma', 'pandit')
       ON CONFLICT (email) DO UPDATE SET role = 'pandit'
       RETURNING id`,
      [email, passHash]
    );
    userId = inserted.rows[0].id;
  }
  await client.query(
    `INSERT INTO pandits (user_id, full_name, specialty, field, experience_years, languages, rate_per_min, bio, avatar_url, is_online, is_busy)
     VALUES ($1, 'Pt. Rishiraj Sharma', 'Vedic Astrology & Janam Kundli', 'Vedic Kundli', 15, 'Hindi, English, Sanskrit', 21.00,
             'Gold medalist Vedic astrologer with 15+ years of experience in Janam Kundli and planetary remedies.',
             'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80', TRUE, FALSE)
     ON CONFLICT (user_id) DO NOTHING`,
    [userId]
  );
}

async function initDatabase() {
  if (!connectionString) throw new Error('Database connection string is not configured');
  const client = await pool.connect();
  try {
    console.log('⚡ Connected to PostgreSQL database.');
    const schemaPath = path.join(__dirname, 'schema.sql');
    const sql = fs.readFileSync(schemaPath, 'utf8');
    await client.query(sql);
    await seedDemoPandit(client);
    console.log('✅ Database schema verified and demo Pandit seeded.');
  } finally {
    client.release();
  }
}

// Initialise once; every query waits for it so the first requests on a cold
// start never race the schema creation. A failed init is retried on next use.
let initPromise = null;
function ensureInitialized() {
  if (!initPromise) {
    initPromise = initDatabase().catch((err) => {
      console.error('❌ Database initialization error:', err.message);
      initPromise = null;
      throw err;
    });
  }
  return initPromise;
}
ensureInitialized().catch(() => { /* logged above; retried lazily */ });

async function query(text, params) {
  await ensureInitialized();
  return pool.query(text, params);
}

// Run `fn(client)` inside a transaction; rolls back on any error.
async function withTransaction(fn) {
  await ensureInitialized();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { /* ignore */ }
    throw err;
  } finally {
    client.release();
  }
}

module.exports = {
  query,
  withTransaction,
  ensureInitialized,
  pool
};
