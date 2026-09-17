const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const connectionString = process.env.NEON_DATABASE_URL || process.env.DATABASE_URL;

const pool = new Pool({
  connectionString: connectionString,
  ssl: {
    rejectUnauthorized: false
  }
});

async function initDatabase() {
  try {
    const client = await pool.connect();
    console.log('⚡ Connected to Neon PostgreSQL Database successfully!');
    
    // Read and run schema.sql
    const schemaPath = path.join(__dirname, 'schema.sql');
    if (fs.existsSync(schemaPath)) {
      const sql = fs.readFileSync(schemaPath, 'utf8');
      await client.query(sql);
    }

    // Auto-migrate chat_messages metadata columns and family_kundlis table if missing
    await client.query(`
      ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS astrologer_name VARCHAR(255);
      ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS specialty VARCHAR(255);
      ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS field VARCHAR(255);
      ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS is_diagnostic BOOLEAN DEFAULT FALSE;

      CREATE TABLE IF NOT EXISTS family_kundlis (
          id SERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          relationship VARCHAR(100) NOT NULL,
          full_name VARCHAR(255) NOT NULL,
          gender VARCHAR(50),
          date_of_birth DATE NOT NULL,
          time_of_birth TIME NOT NULL,
          place_of_birth VARCHAR(255) NOT NULL,
          latitude NUMERIC(9, 6),
          longitude NUMERIC(9, 6),
          ascendant VARCHAR(100) NOT NULL,
          sun_sign VARCHAR(100) NOT NULL,
          moon_sign VARCHAR(100) NOT NULL,
          nakshatra VARCHAR(100) NOT NULL,
          nakshatra_pada INTEGER DEFAULT 1,
          planetary_positions JSONB NOT NULL,
          houses JSONB NOT NULL,
          dasha_info JSONB NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX IF NOT EXISTS idx_family_kundlis_user_id ON family_kundlis(user_id);

      CREATE TABLE IF NOT EXISTS daily_horoscopes (
          id SERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          date DATE NOT NULL,
          astro_pulse JSONB NOT NULL,
          panchang JSONB NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          CONSTRAINT unique_user_daily_horoscope UNIQUE (user_id, date)
      );
      CREATE INDEX IF NOT EXISTS idx_daily_horoscopes_user_date ON daily_horoscopes(user_id, date);

      CREATE TABLE IF NOT EXISTS pandits (
          id SERIAL PRIMARY KEY,
          user_id INTEGER UNIQUE REFERENCES users(id) ON DELETE CASCADE,
          full_name VARCHAR(255) NOT NULL,
          specialty VARCHAR(255) NOT NULL,
          field VARCHAR(255) NOT NULL,
          experience_years INTEGER DEFAULT 5,
          languages VARCHAR(255) DEFAULT 'Hindi, English',
          rate_per_min NUMERIC(6, 2) DEFAULT 21.00,
          bio TEXT,
          avatar_url TEXT,
          is_online BOOLEAN DEFAULT TRUE,
          is_busy BOOLEAN DEFAULT FALSE,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX IF NOT EXISTS idx_pandits_user_id ON pandits(user_id);

      CREATE TABLE IF NOT EXISTS consultation_queue (
          id SERIAL PRIMARY KEY,
          pandit_id INTEGER REFERENCES pandits(id) ON DELETE CASCADE,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          user_name VARCHAR(255) NOT NULL,
          status VARCHAR(50) DEFAULT 'waiting',
          queue_position INTEGER DEFAULT 1,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          started_at TIMESTAMP WITH TIME ZONE,
          ended_at TIMESTAMP WITH TIME ZONE
      );
      CREATE INDEX IF NOT EXISTS idx_consultation_queue_pandit ON consultation_queue(pandit_id, status);

      ALTER TABLE users ADD COLUMN IF NOT EXISTS wallet_balance NUMERIC(10, 2) DEFAULT 250.00;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(50) DEFAULT 'user';
      ALTER TABLE pandits ADD COLUMN IF NOT EXISTS rating NUMERIC(3, 2) DEFAULT 4.90;
      ALTER TABLE pandits ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 180;

      CREATE TABLE IF NOT EXISTS pandit_reviews (
          id SERIAL PRIMARY KEY,
          pandit_id INTEGER REFERENCES pandits(id) ON DELETE CASCADE,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          user_name VARCHAR(255) NOT NULL,
          rating NUMERIC(2, 1) NOT NULL,
          review_text TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX IF NOT EXISTS idx_pandit_reviews_pandit ON pandit_reviews(pandit_id);

      CREATE TABLE IF NOT EXISTS consultation_prescriptions (
          id SERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          pandit_id INTEGER REFERENCES pandits(id) ON DELETE CASCADE,
          pandit_name VARCHAR(255) NOT NULL,
          gemstone VARCHAR(255),
          mantra TEXT,
          remedy TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX IF NOT EXISTS idx_prescriptions_user ON consultation_prescriptions(user_id);

      ALTER TABLE pandits ADD COLUMN IF NOT EXISTS earnings_balance NUMERIC(10, 2) DEFAULT 0.00;
      ALTER TABLE pandits ADD COLUMN IF NOT EXISTS total_minutes_consulted INTEGER DEFAULT 0;

      CREATE TABLE IF NOT EXISTS wallet_transactions (
          id SERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          pandit_id INTEGER REFERENCES pandits(id) ON DELETE CASCADE,
          type VARCHAR(50) NOT NULL,
          amount NUMERIC(10, 2) NOT NULL,
          description TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON wallet_transactions(user_id);

      // Seed default master Pandit account
      const bcrypt = require('bcryptjs');
      const passHash = await bcrypt.hash('pandit123', 10);
      const masterUser = await pool.query(
        `INSERT INTO users (email, password_hash, full_name, role)
         VALUES ('rishiraj@astroai.com', $1, 'Pt. Rishiraj Sharma', 'pandit')
         ON CONFLICT (email) DO UPDATE SET role = 'pandit', password_hash = $1
         RETURNING id`,
        [passHash]
      );
      if (masterUser.rows.length > 0) {
        await pool.query(
          `INSERT INTO pandits (user_id, full_name, specialty, field, experience_years, languages, rate_per_min, bio, avatar_url, is_online, is_busy, earnings_balance, total_minutes_consulted)
           VALUES ($1, 'Pt. Rishiraj Sharma', 'Vedic Astrology & Janam Kundli', 'Vedic Kundli', 15, 'Hindi, English, Sanskrit', 21.00, 'Gold medalist Vedic astrologer with 15+ years of experience in Janam Kundli and planetary remedies.', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80', TRUE, FALSE, 245.00, 49)
           ON CONFLICT (user_id) DO NOTHING`,
          [masterUser.rows[0].id]
        );
      }
    `);

    console.log('✅ Database schema, metadata columns, and master Pandit seeded in Neon DB.');
    client.release();
  } catch (err) {
    console.error('❌ Neon Database connection or initialization error:', err.message);
  }
}

initDatabase();

pool.on('error', (err) => {
  console.error('Unexpected database error on idle client:', err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool
};
