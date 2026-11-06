// Admin "Verification queue" (v3 trust). Mounted inside routes/admin.js, after its x-admin-key check.
//   GET  /api/admin/verifications?status=pending|approved|rejected|all   (default pending)
//   POST /api/admin/verifications/:id/decide {action: approve|reject, reason?}
// The selfie is only ever sent for pending rows and is set to NULL the moment a decision is made.
// Approving sets buddy_profiles.verified_at, pays 50 coins once (verified / selfie) and pushes
// `verification_update` {status, verificationId, reason?}. SQL is /*q:name*/-tagged for the fake dbs.
const express = require('express');
const db = require('../db');
const C = require('../services/coins_service');
const push = require('../services/push_service');
const T = require('../services/trust_service');
const { ageOn } = require('../services/buddy_matching');
const { todayISO } = require('../services/astrology_service');

const router = express.Router();
const STATUSES = ['pending', 'approved', 'rejected'];
const DEFAULT_REJECT_REASON = 'The selfie did not clearly show your face and the requested gesture.';

class TrustAdminError extends Error {
  constructor(statusCode, code, message) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
  }
}
const handle = (fn) => async (req, res) => {
  try {
    res.json(await fn(req));
  } catch (err) {
    if (err instanceof TrustAdminError) return res.status(err.statusCode).json({ error: err.message, code: err.code });
    console.error('Admin verification error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};
const iso = (d) => (d instanceof Date ? d.toISOString() : d || null);
const isoDate = (v) => (!v ? null : v instanceof Date ? v.toISOString().slice(0, 10) : String(v).slice(0, 10));

function view(r) {
  return {
    id: Number(r.id),
    status: r.status,
    gesture: r.gesture,
    reason: r.reason || null,
    selfie: r.status === 'pending' && r.selfie ? `data:${T.mimeOf(r.selfie)};base64,${r.selfie}` : null,
    user: {
      userId: Number(r.user_id),
      name: r.display_name || r.full_name || null,
      fullName: r.full_name || null,
      email: r.email || null,
      age: ageOn(isoDate(r.date_of_birth), todayISO('Asia/Kolkata')),
      city: r.city || null,
      banned: !!r.banned_at,
      verified: !!r.verified_at,
    },
    createdAt: iso(r.created_at),
    decidedAt: iso(r.decided_at),
  };
}

// GET /api/admin/verifications
router.get('/verifications', handle(async (req) => {
  const status = typeof req.query.status === 'string' && req.query.status.trim() ? req.query.status.trim() : 'pending';
  if (status !== 'all' && !STATUSES.includes(status)) {
    throw new TrustAdminError(400, 'BAD_STATUS', `status must be one of: all, ${STATUSES.join(', ')}`);
  }
  // Pending (with photos) oldest first and capped small; decided ones newest first.
  const r = await db.query(
    `/*q:adminVerifications*/ SELECT v.id, v.user_id, v.gesture, v.status, v.reason, v.created_at, v.decided_at,
            CASE WHEN v.status = 'pending' THEN v.selfie END AS selfie,
            u.full_name, u.email, bp.display_name, bp.city, bp.banned_at, bp.verified_at, bd.date_of_birth
     FROM buddy_verifications v
     JOIN users u ON u.id = v.user_id
     LEFT JOIN buddy_profiles bp ON bp.user_id = v.user_id
     LEFT JOIN birth_details bd ON bd.user_id = v.user_id
     WHERE ($1::text = 'all' OR v.status = $1::text)
     ORDER BY CASE WHEN $1::text = 'pending' THEN v.id END ASC, v.id DESC
     LIMIT $2`,
    [status, status === 'pending' ? 30 : 100]
  );
  return { verifications: r.rows.map(view) };
}));

// POST /api/admin/verifications/:id/decide
router.post('/verifications/:id/decide', handle(async (req) => {
  const id = Number(req.params.id);
  const body = req.body || {};
  const action = body.action;
  if (!['approve', 'reject'].includes(action)) throw new TrustAdminError(400, 'BAD_ACTION', 'action must be approve or reject');
  if (!Number.isInteger(id) || id <= 0 || id > 2147483647) throw new TrustAdminError(404, 'NOT_FOUND', 'Verification not found');
  let reason = null;
  if (action === 'reject') {
    reason = typeof body.reason === 'string' ? body.reason.replace(/\s+/g, ' ').trim() : '';
    if (reason.length > T.REJECT_REASON_MAX) throw new TrustAdminError(400, 'BAD_REASON', `reason can be at most ${T.REJECT_REASON_MAX} characters`);
    if (!reason) reason = DEFAULT_REJECT_REASON;
  }

  const result = await db.withTransaction(async (client) => {
    const cur = await client.query(
      `/*q:adminVerificationLock*/ SELECT v.id, v.user_id, v.status, bp.banned_at
       FROM buddy_verifications v LEFT JOIN buddy_profiles bp ON bp.user_id = v.user_id
       WHERE v.id = $1 FOR UPDATE OF v`,
      [id]
    );
    const v = cur.rows[0];
    if (!v) throw new TrustAdminError(404, 'NOT_FOUND', 'Verification not found');
    if (v.status !== 'pending') throw new TrustAdminError(409, 'NOT_PENDING', `This request was already ${v.status}`);
    if (action === 'approve' && v.banned_at) {
      throw new TrustAdminError(409, 'USER_BANNED', 'This user is banned from Buddy and cannot be verified. Reject the request instead.');
    }
    const status = action === 'approve' ? 'approved' : 'rejected';
    // Privacy: the photo is deleted in the same statement that records the decision.
    await client.query(
      `/*q:adminVerificationDecide*/ UPDATE buddy_verifications
       SET status = $2, reason = $3, decided_at = CURRENT_TIMESTAMP, selfie = NULL
       WHERE id = $1`,
      [id, status, reason]
    );
    let coins = 0;
    if (status === 'approved') {
      await client.query(
        `/*q:adminVerifiedProfile*/ UPDATE buddy_profiles SET verified_at = COALESCE(verified_at, CURRENT_TIMESTAMP)
         WHERE user_id = $1 AND banned_at IS NULL`,
        [v.user_id]
      );
      coins = await C.awardCoins(client, v.user_id, C.VERIFIED_COINS, C.VERIFIED_REASON, C.VERIFIED_REF, 'Verified badge');
    }
    return { id, userId: Number(v.user_id), status, reason, coins };
  });

  // After commit, so a rolled-back decision never notifies anyone.
  await push.sendToUser(result.userId, {
    type: 'verification_update',
    title: result.status === 'approved' ? 'You are verified!' : 'Verification not approved',
    body: result.status === 'approved'
      ? `Your blue Verified badge is live.${result.coins ? ` +${result.coins} coins added.` : ''}`
      : `${result.reason} You can try again.`,
    data: { status: result.status, verificationId: result.id, ...(result.reason ? { reason: result.reason } : {}) },
  }, { pref: 'buddy' });
  return { verification: { id: result.id, status: result.status, reason: result.reason }, coins: result.coins };
}));

router._internals = { DEFAULT_REJECT_REASON, view };
module.exports = router;
