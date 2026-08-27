const { Pool } = require('pg');
require('dotenv').config();

// Neon DB connection configuration
const connectionString = process.env.NEON_DATABASE_URL || process.env.DATABASE_URL;

const pool = new Pool({
  connectionString: connectionString || 'postgresql://neondb_owner:npg_password@ep-cool-site-a5xyz.us-east-2.aws.neon.tech/neondb?sslmode=require',
  ssl: {
    rejectUnauthorized: false
  }
});

pool.on('connect', () => {
  console.log('Connected to Neon PostgreSQL Database');
});

pool.on('error', (err) => {
  console.error('Unexpected database error on idle client:', err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool
};
