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
      console.log('✅ Database schema and tables verified/created in Neon DB.');
    }
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
