// Firebase ID-token verification for the optional phone check (POST /api/buddy/verification/phone).
// Shares the firebase-admin app (and FIREBASE_SERVICE_ACCOUNT parsing) with services/push_service.js:
// both look up / create the same named app lazily, so whichever runs first initialises it.
// Without FIREBASE_SERVICE_ACCOUNT (or when init fails) phone verification is simply unavailable.
// Tests swap the client with setAuthClient({ verifyIdToken }) (null = disabled, undefined = lazy init).
const push = require('./push_service');

const APP_NAME = 'cosmicguide-push';

let auth; // undefined: not initialised; null: disabled; otherwise an Auth-like client

function getAuthClient() {
  if (auth !== undefined) return auth;
  auth = null;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw || !String(raw).trim()) return null;
  try {
    const sa = push._internals.parseServiceAccount(raw);
    const { initializeApp, getApps, cert } = require('firebase-admin/app');
    const { getAuth } = require('firebase-admin/auth');
    const app = getApps().find((a) => a.name === APP_NAME) || initializeApp({ credential: cert(sa), projectId: sa.project_id }, APP_NAME);
    auth = getAuth(app);
  } catch (err) {
    auth = null;
    console.warn(`Phone verification disabled: firebase-admin init failed (${err.message})`);
  }
  return auth;
}

function setAuthClient(client) {
  auth = client;
}

const available = () => !!getAuthClient();

/**
 * Verifies a Firebase ID token and returns the E.164 phone number it proves, or throws an Error
 * with .code: 'UNAVAILABLE' (no Firebase on the server), 'BAD_TOKEN' or 'NO_PHONE'.
 */
async function phoneFromIdToken(idToken) {
  const client = getAuthClient();
  if (!client) { const e = new Error('Phone verification is not available right now'); e.code = 'UNAVAILABLE'; throw e; }
  let decoded;
  try {
    decoded = await client.verifyIdToken(String(idToken));
  } catch (_) {
    const e = new Error('Could not confirm this phone number. Please try again.');
    e.code = 'BAD_TOKEN';
    throw e;
  }
  const phone = decoded && typeof decoded.phone_number === 'string' ? decoded.phone_number.trim() : '';
  if (!/^\+[1-9]\d{6,14}$/.test(phone)) {
    const e = new Error('This sign-in did not include a verified phone number');
    e.code = 'NO_PHONE';
    throw e;
  }
  return phone;
}

module.exports = { getAuthClient, setAuthClient, available, phoneFromIdToken };
