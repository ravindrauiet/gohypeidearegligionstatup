// Birth details typed into the AI chat -> generate_kundli action (routes/chat.js +
// services/chat_birth_details.js). db and the OpenAI client are stubbed; nothing leaves the process.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const Module = require('module');
const express = require('express');

function stubModule(rel, exports) {
  const p = require.resolve(path.join(__dirname, '..', rel));
  const m = new Module(p);
  m.loaded = true;
  m.exports = exports;
  require.cache[p] = m;
}

// --- db stub: one user without a chart, a short history, records every insert
const calls = [];
let history = [];
let hasChart = false;
stubModule('db.js', {
  query: async (text, params) => {
    const sql = String(text).replace(/\s+/g, ' ').trim();
    calls.push({ sql, params });
    if (sql.startsWith('SELECT u.full_name AS user_name')) {
      return { rows: [hasChart
        ? { user_name: 'Asha', gender: 'Female', date_of_birth: '1990-01-01', time_of_birth: '10:00', ascendant: 'Leo', moon_sign: 'Aries', sun_sign: 'Capricorn', nakshatra: 'Ashwini', planetary_positions: '[]', dasha_info: '{}' }
        : { user_name: 'Guest User', gender: null }] };
    }
    if (sql.startsWith('SELECT role, content FROM chat_messages')) return { rows: [...history].reverse() };
    if (sql.startsWith('SELECT role FROM users WHERE id = $1')) return { rows: [{ role: 'user' }] };
    return { rows: [] };
  },
  withTransaction: async (fn) => fn({ query: async () => ({ rows: [] }) }),
});

// --- OpenAI stub: JSON extraction answers from `extraction`, chat answers with a fixed reply
let extraction = null;
const aiCalls = [];
stubModule('services/openai_client.js', {
  hasOpenAIKey: () => true,
  chatCompletion: async (opts) => {
    aiCalls.push(opts);
    if (opts.json) return extraction;
    return 'AI reply';
  },
});

process.env.JWT_SECRET = 'test-jwt-secret-0123456789abcdef';
const { signToken } = require('../routes/auth');
const chatRouter = require('../routes/chat');
const { validateExtraction, describeBirthDetails, _internals } = require('../services/chat_birth_details');

const TODAY = '2026-11-12';

test('validateExtraction: complete, unknown time, future/invalid dates, missing pieces', () => {
  const ok = validateExtraction({ dateOfBirth: '2024-09-14', timeOfBirth: '05:35', placeOfBirth: 'Namakkal, Tamil Nadu' }, TODAY);
  assert.deepEqual(ok, { complete: true, birthDetails: { dateOfBirth: '2024-09-14', timeOfBirth: '05:35', birthTimeKnown: true, placeOfBirth: 'Namakkal, Tamil Nadu', name: null, gender: null } });

  const noTime = validateExtraction({ dateOfBirth: '1990-02-03', timeUnknown: true, placeOfBirth: 'Pune', gender: 'Male', name: 'Ravi' }, TODAY);
  assert.equal(noTime.complete, true);
  assert.equal(noTime.birthDetails.timeOfBirth, '12:00');
  assert.equal(noTime.birthDetails.birthTimeKnown, false);

  const future = validateExtraction({ dateOfBirth: '2027-01-01', timeOfBirth: '05:35', placeOfBirth: 'Pune' }, TODAY);
  assert.deepEqual(future.missing, ['date']);
  assert.deepEqual(future.problems, ['date']);
  assert.equal(validateExtraction({ dateOfBirth: '2024-02-30', timeOfBirth: '05:35', placeOfBirth: 'Pune' }, TODAY).complete, false);
  assert.deepEqual(validateExtraction({ dateOfBirth: '2024-09-14', timeOfBirth: '25:00', placeOfBirth: 'unknown' }, TODAY).missing, ['time', 'place']);
  assert.deepEqual(validateExtraction(null, TODAY).missing, ['date', 'time', 'place']);
});

test('describeBirthDetails and helpers', () => {
  assert.deepEqual(describeBirthDetails({ dateOfBirth: '2024-09-14', timeOfBirth: '05:35', birthTimeKnown: true }), { date: '14 Sep 2024', time: '5:35 AM' });
  assert.equal(describeBirthDetails({ dateOfBirth: '2024-09-14', timeOfBirth: '12:00', birthTimeKnown: false }).time, 'time unknown (using 12:00 noon)');
  assert.equal(describeBirthDetails({ dateOfBirth: '2000-01-01', timeOfBirth: '00:10', birthTimeKnown: true }).time, '12:10 AM');
  assert.equal(_internals.mightContainBirthDetails(['Hi', 'Can we talk in Tamil']), false);
  assert.equal(_internals.mightContainBirthDetails(['14.9.2024']), true);
});

async function post(body) {
  const app = express();
  app.use(express.json());
  app.use('/api/chat', chatRouter);
  const server = await new Promise((r) => { const s = app.listen(0, () => r(s)); });
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${signToken({ userId: 9, email: 'x@y.z', role: 'user' })}` },
      // New app builds announce they can build the chart; pass clientActions: undefined for an old build.
      body: JSON.stringify({ clientActions: ['generate_kundli'], ...body }),
    });
    return { status: res.status, body: await res.json() };
  } finally {
    server.close();
  }
}

test('the real-user conversation: details spread over messages -> generate_kundli action, no AI reading', async () => {
  calls.length = 0; aiCalls.length = 0; hasChart = false;
  history = [
    { role: 'user', content: 'Can you give jadham based on data which is given from my end' },
    { role: 'assistant', content: 'Please share date, time and place.' },
    { role: 'user', content: '14.9.2024' },
    { role: 'assistant', content: 'And the time?' },
    { role: 'user', content: '05.35 am' },
    { role: 'assistant', content: 'And the place?' },
  ];
  extraction = { dateOfBirth: '2024-09-14', timeOfBirth: '05:35', placeOfBirth: 'Namakkal, Tamil Nadu', name: null, gender: null };
  const r = await post({ message: 'Namakkal,Tamilnadu', astrologerName: 'Rishi Anand' });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.action, {
    type: 'generate_kundli',
    birthDetails: { fullName: 'Me', gender: 'Not Specified', dateOfBirth: '2024-09-14', timeOfBirth: '05:35', birthTimeKnown: true, placeOfBirth: 'Namakkal, Tamil Nadu' },
  });
  assert.match(r.body.content, /14 Sep 2024, 5:35 AM, Namakkal, Tamil Nadu/);
  // the extractor saw every user message, oldest first, with today's date
  const ex = aiCalls.find((c) => c.json);
  assert.match(ex.messages[0].content, /^Today is \d{4}-\d{2}-\d{2}\./);
  assert.match(ex.messages[1].content, /1\. Can you give jadham[\s\S]*2\. 14\.9\.2024[\s\S]*3\. 05\.35 am[\s\S]*4\. Namakkal,Tamilnadu/);
  // no chart reading was generated by the model
  assert.equal(aiCalls.filter((c) => !c.json).length, 0);
  // both the user's message and the confirmation are stored
  const inserts = calls.filter((c) => c.sql.startsWith('INSERT INTO chat_messages'));
  assert.deepEqual(inserts.map((c) => c.params[1]), ['user', 'assistant']);
});

test('incomplete details -> normal AI reply that knows today and must not refuse charts or languages', async () => {
  aiCalls.length = 0; hasChart = false;
  history = [];
  extraction = { dateOfBirth: '2024-09-14', timeOfBirth: null, placeOfBirth: null };
  const r = await post({ message: '14.9.2024' });
  assert.equal(r.status, 200);
  assert.equal(r.body.action, undefined);
  assert.equal(r.body.content, 'AI reply');
  const sys = aiCalls.find((c) => !c.json).messages[0].content;
  assert.match(sys, /Today's date is \d{4}-\d{2}-\d{2}/);
  assert.match(sys, /builds the user's Kundli automatically/);
  assert.match(sys, /Never say you cannot create or generate a birth chart/);
  assert.match(sys, /Reply in the language the user writes in/);
});

test('no extraction call for chit-chat, and none once the user already has a chart', async () => {
  aiCalls.length = 0; hasChart = false; history = [];
  await post({ message: 'Hi' });
  assert.equal(aiCalls.filter((c) => c.json).length, 0);

  aiCalls.length = 0; hasChart = true;
  extraction = { dateOfBirth: '2024-09-14', timeOfBirth: '05:35', placeOfBirth: 'Namakkal' };
  const r = await post({ message: 'My friend was born 14.9.2024 05:35 in Namakkal' });
  assert.equal(r.body.action, undefined);
  assert.equal(aiCalls.filter((c) => c.json).length, 0);
  hasChart = false;
});

test('extraction failure falls back to the normal reply', async () => {
  aiCalls.length = 0; history = [];
  extraction = null; // model unavailable / bad JSON
  const r = await post({ message: '14.9.2024 05:35 Namakkal' });
  assert.equal(r.status, 200);
  assert.equal(r.body.action, undefined);
  assert.equal(r.body.content, 'AI reply');
});

test('older app builds (no clientActions) never get the action and are sent to the form', async () => {
  aiCalls.length = 0; hasChart = false; history = [];
  extraction = { dateOfBirth: '2024-09-14', timeOfBirth: '05:35', placeOfBirth: 'Namakkal, Tamil Nadu' };
  const r = await post({ message: '14.9.2024 05:35 Namakkal', clientActions: undefined });
  assert.equal(r.status, 200);
  assert.equal(r.body.action, undefined);
  assert.equal(aiCalls.filter((c) => c.json).length, 0);
  const sys = aiCalls.find((c) => !c.json).messages[0].content;
  assert.ok(sys.includes('create their Kundli in this app from the Kundli / birth details screen'));
  assert.match(sys, /Today's date is/);
});
