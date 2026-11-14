// Birth details shared in the AI chat -> a request for the app to build the Kundli.
//
// Users often go straight to the AI astrologer and type their date, time and place of birth
// there instead of using the birth-details form. The chart must come from our own engine
// (astrology_service / Swiss Ephemeris), never from the language model, so the chat only
// *collects* the details: the model extracts them as JSON, this file validates them in code,
// and /api/chat answers with action { type: 'generate_kundli', birthDetails } so the app can
// geocode the place and call /api/kundli/generate exactly like the form does.
const { chatCompletion } = require('./openai_client');

const MAX_TRANSCRIPT_CHARS = 4000;

function pad(n) {
  return String(n).padStart(2, '0');
}

// 'YYYY-MM-DD' when it is a real calendar date between 1900 and today (IST), else null.
function cleanDate(value, today) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || '').trim());
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null;
  const iso = `${m[1]}-${m[2]}-${m[3]}`;
  if (y < 1900 || iso > today) return null;
  return iso;
}

// 'HH:MM' (24h) or null.
function cleanTime(value) {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(value || '').trim());
  if (!m) return null;
  const h = Number(m[1]);
  const mi = Number(m[2]);
  if (h > 23 || mi > 59) return null;
  return `${pad(h)}:${pad(mi)}`;
}

function cleanText(value, max) {
  if (typeof value !== 'string') return null;
  const s = value.replace(/\s+/g, ' ').trim();
  if (!s || /^(unknown|null|none|n\/a)$/i.test(s)) return null;
  return s.slice(0, max);
}

/**
 * Validates the model's JSON. Returns
 *   { complete: true, birthDetails: { dateOfBirth, timeOfBirth, birthTimeKnown, placeOfBirth, name, gender } }
 * or { complete: false, missing: [...], problems: [...] }.
 * A user who says they don't know the time gets noon with birthTimeKnown=false (same as the form).
 */
function validateExtraction(raw, today) {
  const r = raw && typeof raw === 'object' ? raw : {};
  const problems = [];
  const dateOfBirth = cleanDate(r.dateOfBirth, today);
  if (r.dateOfBirth && !dateOfBirth) problems.push('date');
  const timeUnknown = r.timeUnknown === true;
  const time = cleanTime(r.timeOfBirth);
  if (r.timeOfBirth && !time && !timeUnknown) problems.push('time');
  const placeOfBirth = cleanText(r.placeOfBirth, 200);
  const name = cleanText(r.name, 100);
  const gender = r.gender === 'Male' || r.gender === 'Female' ? r.gender : null;

  const missing = [];
  if (!dateOfBirth) missing.push('date');
  if (!time && !timeUnknown) missing.push('time');
  if (!placeOfBirth) missing.push('place');
  if (missing.length) return { complete: false, missing, problems };
  return {
    complete: true,
    birthDetails: {
      dateOfBirth,
      timeOfBirth: time || '12:00',
      birthTimeKnown: !!time,
      placeOfBirth,
      name,
      gender,
    },
  };
}

// Only worth an extraction call when the user has typed something that could be a date.
function mightContainBirthDetails(userTexts) {
  return userTexts.some((t) => /\d/.test(t)) && userTexts.join(' ').length >= 4;
}

/**
 * Reads the user's recent messages and returns validateExtraction(...) for them,
 * or null when nothing could be extracted (no AI key, model failure, nothing date-like).
 * @param {string[]} userTexts the user's messages, oldest first (current message last)
 * @param {string} today IST date 'YYYY-MM-DD'
 */
async function extractBirthDetails(userTexts, today) {
  const texts = (userTexts || []).filter((t) => typeof t === 'string' && t.trim());
  if (!texts.length || !mightContainBirthDetails(texts)) return null;
  let transcript = texts.map((t, i) => `${i + 1}. ${t.trim()}`).join('\n');
  if (transcript.length > MAX_TRANSCRIPT_CHARS) transcript = transcript.slice(-MAX_TRANSCRIPT_CHARS);

  const raw = await chatCompletion({
    models: ['gpt-4o-mini', 'gpt-4o'],
    json: true,
    temperature: 0,
    maxTokens: 200,
    timeoutMs: 12000,
    messages: [
      {
        role: 'system',
        content: `Today is ${today}. Extract the user's OWN birth details from their chat messages (any language; Indian formats like 14.9.2024 or 14/09/2024 are DAY.MONTH.YEAR). Use only what the user actually wrote; later messages override earlier ones. Never guess.
Return ONLY JSON: {"dateOfBirth": "YYYY-MM-DD" or null, "timeOfBirth": "HH:MM" 24-hour or null, "timeUnknown": true only if the user says they do not know their birth time, "placeOfBirth": "City, State/Country" as written or null, "name": the person's name if they gave it or null, "gender": "Male" | "Female" | null}`,
      },
      { role: 'user', content: transcript },
    ],
  });
  if (!raw || typeof raw !== 'object') return null;
  return validateExtraction(raw, today);
}

// "14 Sep 2024" / "5:35 AM" for the confirmation message.
function describeBirthDetails(d) {
  const [y, m, day] = d.dateOfBirth.split('-').map(Number);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const date = `${day} ${months[m - 1]} ${y}`;
  let time = 'time unknown (using 12:00 noon)';
  if (d.birthTimeKnown) {
    const [h, mi] = d.timeOfBirth.split(':').map(Number);
    time = `${((h + 11) % 12) + 1}:${pad(mi)} ${h < 12 ? 'AM' : 'PM'}`;
  }
  return { date, time };
}

module.exports = {
  extractBirthDetails,
  validateExtraction,
  describeBirthDetails,
  _internals: { cleanDate, cleanTime, mightContainBirthDetails },
};
