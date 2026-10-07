-- Schema for AI Astrology Application (Neon PostgreSQL Database)
-- Idempotent: safe to run on every cold start. CREATE TABLE IF NOT EXISTS does not add
-- columns to existing tables, so every column added after the first release is also
-- declared with ALTER TABLE ... ADD COLUMN IF NOT EXISTS below.

-- 1. Users
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    gender VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE users ADD COLUMN IF NOT EXISTS wallet_balance NUMERIC(10, 2) DEFAULT 250.00;
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(50) DEFAULT 'user';

-- 2. Birth Details
CREATE TABLE IF NOT EXISTS birth_details (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    full_name VARCHAR(255) NOT NULL,
    gender VARCHAR(50),
    date_of_birth DATE NOT NULL,
    time_of_birth TIME NOT NULL,
    place_of_birth VARCHAR(255) NOT NULL,
    latitude NUMERIC(9, 6),
    longitude NUMERIC(9, 6),
    timezone VARCHAR(50) DEFAULT 'Asia/Kolkata',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Kundli Charts
CREATE TABLE IF NOT EXISTS kundlis (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE REFERENCES users(id) ON DELETE CASCADE,
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
ALTER TABLE kundlis ADD COLUMN IF NOT EXISTS ai_report TEXT;
ALTER TABLE kundlis ADD COLUMN IF NOT EXISTS kundli_data JSONB;
ALTER TABLE kundlis ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- 4. Family Kundlis (multiple family members under one account)
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
ALTER TABLE family_kundlis ADD COLUMN IF NOT EXISTS ai_report TEXT;
ALTER TABLE family_kundlis ADD COLUMN IF NOT EXISTS kundli_data JSONB;
ALTER TABLE family_kundlis ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'Asia/Kolkata';

-- 5. Chat Messages (AI astrologer history)
CREATE TABLE IF NOT EXISTS chat_messages (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) CHECK (role IN ('user', 'assistant', 'system')) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS astrologer_name VARCHAR(255);
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS specialty VARCHAR(255);
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS field VARCHAR(255);
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS is_diagnostic BOOLEAN DEFAULT FALSE;

-- 6. Daily horoscope cache (one row per user per day)
CREATE TABLE IF NOT EXISTS daily_horoscopes (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    astro_pulse JSONB NOT NULL,
    panchang JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_daily_horoscope UNIQUE (user_id, date)
);

-- 7. Pandits
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
ALTER TABLE pandits ADD COLUMN IF NOT EXISTS rating NUMERIC(3, 2) DEFAULT 4.90;
ALTER TABLE pandits ADD COLUMN IF NOT EXISTS total_reviews INTEGER DEFAULT 0;
ALTER TABLE pandits ADD COLUMN IF NOT EXISTS earnings_balance NUMERIC(10, 2) DEFAULT 0.00;
ALTER TABLE pandits ADD COLUMN IF NOT EXISTS total_minutes_consulted INTEGER DEFAULT 0;

-- 8. Consultation queue / sessions
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

-- 9. Pandit reviews
CREATE TABLE IF NOT EXISTS pandit_reviews (
    id SERIAL PRIMARY KEY,
    pandit_id INTEGER REFERENCES pandits(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    user_name VARCHAR(255) NOT NULL,
    rating NUMERIC(2, 1) NOT NULL,
    review_text TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10. Prescriptions given during consultations
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

-- 11. Wallet ledger
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    pandit_id INTEGER REFERENCES pandits(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_birth_details_user_id ON birth_details(user_id);
CREATE INDEX IF NOT EXISTS idx_kundlis_user_id ON kundlis(user_id);
CREATE INDEX IF NOT EXISTS idx_family_kundlis_user_id ON family_kundlis(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_user_id ON chat_messages(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_user_astrologer ON chat_messages(user_id, astrologer_name, created_at);
CREATE INDEX IF NOT EXISTS idx_daily_horoscopes_user_date ON daily_horoscopes(user_id, date);
CREATE INDEX IF NOT EXISTS idx_pandits_user_id ON pandits(user_id);
CREATE INDEX IF NOT EXISTS idx_consultation_queue_pandit ON consultation_queue(pandit_id, status);
CREATE INDEX IF NOT EXISTS idx_consultation_queue_user ON consultation_queue(user_id, status);
CREATE INDEX IF NOT EXISTS idx_pandit_reviews_pandit ON pandit_reviews(pandit_id);
CREATE INDEX IF NOT EXISTS idx_prescriptions_user ON consultation_prescriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON wallet_transactions(user_id);

-- Per-minute billing bookkeeping for consultation sessions
ALTER TABLE consultation_queue ADD COLUMN IF NOT EXISTS billed_minutes INTEGER DEFAULT 0;
ALTER TABLE consultation_queue ADD COLUMN IF NOT EXISTS last_billed_at TIMESTAMP WITH TIME ZONE;

-- 12. Seeker <-> Pandit consultation chat messages
CREATE TABLE IF NOT EXISTS consultation_messages (
    id SERIAL PRIMARY KEY,
    session_id INTEGER REFERENCES consultation_queue(id) ON DELETE CASCADE,
    sender_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    sender_role VARCHAR(20) NOT NULL CHECK (sender_role IN ('seeker', 'pandit')),
    content TEXT NOT NULL,
    is_prescription BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_consultation_messages_session ON consultation_messages(session_id, id);
ALTER TABLE consultation_prescriptions ADD COLUMN IF NOT EXISTS session_id INTEGER REFERENCES consultation_queue(id) ON DELETE SET NULL;
ALTER TABLE consultation_queue ADD COLUMN IF NOT EXISTS amount_charged NUMERIC(10, 2) DEFAULT 0.00;
CREATE INDEX IF NOT EXISTS idx_wallet_tx_pandit ON wallet_transactions(pandit_id);
