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
    `);

    console.log('✅ Database schema, metadata columns, and family_kundlis verified/created in Neon DB.');
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
