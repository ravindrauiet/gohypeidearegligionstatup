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
-- Google account id ("sub" claim) for users who signed in with Google.
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(255) UNIQUE;

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

-- 13. Personal forecast AI narrative cache (rules output is recomputed; only GPT text is cached)
CREATE TABLE IF NOT EXISTS forecast_cache (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    profile_key TEXT NOT NULL,
    period_type TEXT NOT NULL,
    period_key TEXT NOT NULL,
    kundli_hash TEXT NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_forecast_cache UNIQUE (user_id, profile_key, period_type, period_key, kundli_hash)
);
CREATE INDEX IF NOT EXISTS idx_forecast_cache_user ON forecast_cache(user_id, profile_key);

-- =====================================================================
-- 14. Games (Graha Quest, Nakshatra Cards, Moksha Patam, Cosmic Match)
-- =====================================================================
-- Short shareable code for Cosmic Match; generated lazily for registered users only.
ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_code VARCHAR(12);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_invite_code ON users(invite_code);

-- One row per account: player XP, streak and per-planet XP.
CREATE TABLE IF NOT EXISTS game_profiles (
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    xp INTEGER NOT NULL DEFAULT 0,
    streak INTEGER NOT NULL DEFAULT 0,
    best_streak INTEGER NOT NULL DEFAULT 0,
    last_mission_date DATE,
    planet_xp JSONB NOT NULL DEFAULT '{}'::jsonb,
    bonus_roll_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Completed daily missions (local_date = the player's local calendar day).
CREATE TABLE IF NOT EXISTS game_mission_log (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    mission_id TEXT NOT NULL,
    mission_key TEXT NOT NULL,
    planet VARCHAR(20) NOT NULL,
    xp INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_game_mission UNIQUE (user_id, local_date, mission_id)
);
CREATE INDEX IF NOT EXISTS idx_game_mission_log_user_date ON game_mission_log(user_id, local_date);

-- Collected nakshatra / rare cards.
CREATE TABLE IF NOT EXISTS game_cards (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_id TEXT NOT NULL,
    kind VARCHAR(20) NOT NULL DEFAULT 'nakshatra',
    collected_on DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_game_card UNIQUE (user_id, card_id)
);
CREATE INDEX IF NOT EXISTS idx_game_cards_user ON game_cards(user_id);

-- Card-set rewards, each claimable once.
CREATE TABLE IF NOT EXISTS game_set_claims (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    set_id TEXT NOT NULL,
    reward_type VARCHAR(20) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_game_set_claim UNIQUE (user_id, set_id)
);

-- Moksha Patam tokens: profile_key = 'self' or 'fam:<family_kundlis.id>'.
CREATE TABLE IF NOT EXISTS moksha_players (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profile_key TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 1,
    wins INTEGER NOT NULL DEFAULT 0,
    rolls_date DATE,
    rolls_used INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_moksha_player UNIQUE (user_id, profile_key)
);

CREATE TABLE IF NOT EXISTS moksha_moves (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    profile_key TEXT NOT NULL,
    player_name VARCHAR(255),
    dice INTEGER NOT NULL,
    from_square INTEGER NOT NULL,
    landed_square INTEGER NOT NULL,
    to_square INTEGER NOT NULL,
    event TEXT,
    won BOOLEAN NOT NULL DEFAULT FALSE,
    local_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_moksha_moves_user ON moksha_moves(user_id, id DESC);

-- Cosmic Match friendships: one row per direction (A->B and B->A).
CREATE TABLE IF NOT EXISTS friend_links (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_friend_link UNIQUE (user_id, friend_user_id),
    CONSTRAINT friend_link_not_self CHECK (user_id <> friend_user_id)
);
CREATE INDEX IF NOT EXISTS idx_friend_links_friend ON friend_links(friend_user_id);

-- ===========================================================================
-- Rewards: coins ledger (balance = SUM(amount)). Every reward has a unique
-- (user_id, reason, ref) so double taps / retries can never pay twice:
--   daily_login  ref = YYYY-MM-DD (IST)          +1
--   game         ref = <game>:<YYYY-MM-DD>        +10 (once per game per day)
--   video        ref = <youtube video id>         +1  (once per video, ever)
--   question     ref = <question id>              +50 (once per question, ever)
--   trip         ref = trip:<request id>          -10000 (refund: trip_refund)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS coin_ledger (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount INTEGER NOT NULL,
    reason VARCHAR(40) NOT NULL,
    ref VARCHAR(160) NOT NULL,
    note VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_coin_reward UNIQUE (user_id, reason, ref)
);
CREATE INDEX IF NOT EXISTS idx_coin_ledger_user ON coin_ledger(user_id, id DESC);

-- Mindset questionnaire answers (questions live in backend/data/mindset_questions.json).
CREATE TABLE IF NOT EXISTS mindset_answers (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question_id VARCHAR(40) NOT NULL,
    option_index INTEGER NOT NULL,
    answered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, question_id)
);

-- Buddy profile (opt-in). Location is stored rounded to ~1 km and never shown exactly.
CREATE TABLE IF NOT EXISTS buddy_profiles (
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    display_name VARCHAR(80) NOT NULL,
    bio VARCHAR(500) DEFAULT '',
    intents TEXT[] NOT NULL DEFAULT '{}',          -- life_partner, business, friend, travel, spiritual
    gender VARCHAR(20),
    interested_in VARCHAR(20) DEFAULT 'any',       -- for life_partner: male, female, any
    city VARCHAR(120),
    lat NUMERIC(7, 2),
    lng NUMERIC(7, 2),
    photo_url VARCHAR(500),
    languages TEXT[] NOT NULL DEFAULT '{}',
    show_nearby BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_nearby_check TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Connection requests between buddies (one row per pair and intent).
CREATE TABLE IF NOT EXISTS buddy_connections (
    id SERIAL PRIMARY KEY,
    from_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    intent VARCHAR(20) NOT NULL,
    message VARCHAR(300),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending, accepted, declined, cancelled
    score INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT buddy_connection_not_self CHECK (from_user_id <> to_user_id),
    CONSTRAINT unique_buddy_request UNIQUE (from_user_id, to_user_id)
);
CREATE INDEX IF NOT EXISTS idx_buddy_connections_to ON buddy_connections(to_user_id, status);

-- Messages between accepted buddies.
CREATE TABLE IF NOT EXISTS buddy_messages (
    id SERIAL PRIMARY KEY,
    connection_id INTEGER NOT NULL REFERENCES buddy_connections(id) ON DELETE CASCADE,
    sender_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body VARCHAR(2000) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_buddy_messages_conn ON buddy_messages(connection_id, id);

-- Safety: blocks hide both people from each other everywhere; reports are reviewed by the team.
CREATE TABLE IF NOT EXISTS buddy_blocks (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, blocked_user_id)
);
CREATE TABLE IF NOT EXISTS buddy_reports (
    id SERIAL PRIMARY KEY,
    reporter_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(40) NOT NULL,
    details VARCHAR(1000),
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Temple trip requests (10,000 coins). Reviewed and arranged by the team.
CREATE TABLE IF NOT EXISTS trip_requests (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    buddy_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    temple_id VARCHAR(60) NOT NULL,
    preferred_month VARCHAR(7),                       -- YYYY-MM
    status VARCHAR(20) NOT NULL DEFAULT 'pending',    -- pending, approved, completed, rejected, cancelled
    coins_spent INTEGER NOT NULL DEFAULT 0,
    note VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_trip_requests_user ON trip_requests(user_id, id DESC);

-- Hot lookups for the v2 routes: "blocked me" (the PK only covers blocks I made), per-sender message
-- and per-reporter report rate limits, the trip list for the buddy side, and the discover prefilter.
CREATE INDEX IF NOT EXISTS idx_buddy_blocks_blocked ON buddy_blocks(blocked_user_id);
CREATE INDEX IF NOT EXISTS idx_buddy_messages_sender ON buddy_messages(sender_id, created_at);
CREATE INDEX IF NOT EXISTS idx_buddy_reports_reporter ON buddy_reports(reporter_id, created_at);
CREATE INDEX IF NOT EXISTS idx_buddy_reports_reported ON buddy_reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_trip_requests_buddy ON trip_requests(buddy_user_id);
CREATE INDEX IF NOT EXISTS idx_buddy_profiles_active ON buddy_profiles(updated_at DESC) WHERE is_active = TRUE;

-- admin moderation
-- (routes/admin.js) Report resolution and buddy bans. status values: open, dismissed, banned.
ALTER TABLE buddy_reports ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'open';
ALTER TABLE buddy_reports ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMP WITH TIME ZONE;
CREATE INDEX IF NOT EXISTS idx_buddy_reports_status ON buddy_reports(status, id);
ALTER TABLE buddy_profiles ADD COLUMN IF NOT EXISTS banned_at TIMESTAMP WITH TIME ZONE;
CREATE INDEX IF NOT EXISTS idx_trip_requests_status ON trip_requests(status, id);

-- notifications
-- (services/push_service.js, routes/notifications.js) FCM device tokens, the per-user inbox,
-- admin broadcasts (one row each, read state per user) and per-category push preferences.
CREATE TABLE IF NOT EXISTS device_tokens (
    id SERIAL PRIMARY KEY,
    token VARCHAR(4096) NOT NULL UNIQUE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform VARCHAR(20) NOT NULL DEFAULT 'android',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(40) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body VARCHAR(500) NOT NULL DEFAULT '',
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id) WHERE read_at IS NULL;

CREATE TABLE IF NOT EXISTS broadcasts (
    id SERIAL PRIMARY KEY,
    title VARCHAR(80) NOT NULL,
    body VARCHAR(300) NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_broadcasts_created ON broadcasts(created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS broadcast_reads (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    broadcast_id INTEGER NOT NULL REFERENCES broadcasts(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, broadcast_id)
);

CREATE TABLE IF NOT EXISTS notification_prefs (
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    buddy BOOLEAN NOT NULL DEFAULT TRUE,
    messages BOOLEAN NOT NULL DEFAULT TRUE,
    trips BOOLEAN NOT NULL DEFAULT TRUE,
    rewards BOOLEAN NOT NULL DEFAULT TRUE,
    announcements BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- v3 trust
-- (routes/buddy.js verification + biodata, routes/admin_trust.js, routes/family.js)
-- Verified badge: a selfie with a gesture, reviewed by the team. The selfie (base64 JPEG/PNG, capped)
-- is set to NULL the moment an admin decides, so only status / decided_at / reason are kept.
ALTER TABLE buddy_profiles ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE buddy_profiles ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMP WITH TIME ZONE;
-- Optional life-partner biodata (height, education, profession, family ...), validated in routes/buddy.js.
ALTER TABLE buddy_profiles ADD COLUMN IF NOT EXISTS biodata JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE TABLE IF NOT EXISTS buddy_verifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    gesture VARCHAR(40) NOT NULL,
    selfie TEXT,                                     -- base64, NULL once decided
    status VARCHAR(20) NOT NULL DEFAULT 'pending',   -- pending, approved, rejected
    reason VARCHAR(300),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    decided_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT buddy_verification_selfie_size CHECK (selfie IS NULL OR length(selfie) <= 560000)
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_buddy_verification_pending ON buddy_verifications(user_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_buddy_verifications_user ON buddy_verifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_buddy_verifications_status ON buddy_verifications(status, id);
-- Phone check: only a hash of the E.164 number (never the number) so one phone verifies one account.
CREATE TABLE IF NOT EXISTS phone_verifications (
    phone_hash CHAR(64) PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    verified_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
-- Family mode: read-only share links (own profile, or an accepted buddy as a "match") + notes from family.
CREATE TABLE IF NOT EXISTS family_links (
    id SERIAL PRIMARY KEY,
    token VARCHAR(64) NOT NULL UNIQUE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind VARCHAR(10) NOT NULL DEFAULT 'self',         -- self, match
    match_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_family_links_user ON family_links(user_id, id DESC);
CREATE TABLE IF NOT EXISTS family_notes (
    id SERIAL PRIMARY KEY,
    link_id INTEGER NOT NULL REFERENCES family_links(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(40) NOT NULL,
    relation VARCHAR(20) NOT NULL,
    message VARCHAR(500) NOT NULL,
    ip_hash CHAR(64) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_family_notes_user ON family_notes(user_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_family_notes_link ON family_notes(link_id, ip_hash, created_at);

-- v3 meetups
-- (routes/meetups.js) Satsang meetups: small group events at public venues. host_user_id NULL =
-- official CosmicGuide event. status: pending, approved, rejected, cancelled, completed.
-- lat/lng are the venue's (public place) and never leave the server. RSVP status: going, cancelled, checked_in.
CREATE TABLE IF NOT EXISTS meetups (
    id SERIAL PRIMARY KEY,
    title VARCHAR(80) NOT NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'satsang',     -- aarti, bhajan_sandhya, seva, yoga, satsang, kirtan, other
    description VARCHAR(1000) NOT NULL DEFAULT '',
    venue_name VARCHAR(120) NOT NULL,
    temple_id VARCHAR(60),                           -- backend/data/temples.json id (optional)
    address VARCHAR(300) NOT NULL DEFAULT '',
    lat NUMERIC(9,6) NOT NULL,
    lng NUMERIC(9,6) NOT NULL,
    city VARCHAR(80),
    starts_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ends_at TIMESTAMP WITH TIME ZONE NOT NULL,
    capacity INTEGER NOT NULL CHECK (capacity BETWEEN 5 AND 50),
    women_only BOOLEAN NOT NULL DEFAULT FALSE,
    host_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    checkin_code VARCHAR(6) NOT NULL,
    admin_note VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_meetups_upcoming ON meetups(status, starts_at);
CREATE INDEX IF NOT EXISTS idx_meetups_host ON meetups(host_user_id, created_at);

CREATE TABLE IF NOT EXISTS meetup_rsvps (
    meetup_id INTEGER NOT NULL REFERENCES meetups(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'going',
    code_attempts INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    checked_in_at TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (meetup_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_meetup_rsvps_user ON meetup_rsvps(user_id, status);

-- Admin analytics (services/usage_tracking.js, routes/admin_analytics.js)
-- One row per person (or anonymous device) per IST day per platform. visitor_key is 'u:<userId>'
-- for signed-in users and guests, 'd:<installId>' for an app/web open before any account exists.
-- requests is approximate: each server instance writes at most once every few minutes per row.
CREATE TABLE IF NOT EXISTS daily_activity (
    day DATE NOT NULL,
    visitor_key VARCHAR(80) NOT NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    platform VARCHAR(20) NOT NULL,
    requests INTEGER NOT NULL DEFAULT 0,
    opens INTEGER NOT NULL DEFAULT 0,
    first_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (day, visitor_key, platform)
);
CREATE INDEX IF NOT EXISTS idx_daily_activity_user ON daily_activity(user_id, day);

-- One row per successful OpenAI call. cost_usd is estimated from the token counts OpenAI returns
-- and the per-model prices in services/usage_tracking.js. user_id is NULL for calls made outside
-- a user request.
CREATE TABLE IF NOT EXISTS ai_usage (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    feature VARCHAR(40) NOT NULL,
    model VARCHAR(60) NOT NULL,
    platform VARCHAR(20),
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    total_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd NUMERIC(12, 6) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ai_usage_created ON ai_usage(created_at);
CREATE INDEX IF NOT EXISTS idx_ai_usage_user ON ai_usage(user_id, created_at);
