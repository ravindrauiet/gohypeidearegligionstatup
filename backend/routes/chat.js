const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken, guestOrAuthenticateToken, kundliFromRow } = require('./auth');
const { chatContext } = require('../services/forecast_service');
const { chatCompletion } = require('../services/openai_client');
const { extractBirthDetails, describeBirthDetails } = require('../services/chat_birth_details');
const { istDate } = require('../services/coins_service');

const MAX_MESSAGE_LENGTH = 4000;
const MAX_META_LENGTH = 255;

// Strip emojis / pictographs from generated text
function removeEmojis(str) {
  return String(str || '')
    .replace(/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]/gu, '')
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
}

function cleanMeta(value, fallback) {
  if (typeof value !== 'string' || !value.trim()) return fallback;
  return value.trim().slice(0, MAX_META_LENGTH);
}

function parseJson(value, fallback) {
  if (value === null || value === undefined) return fallback;
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch (_) {
    return fallback;
  }
}

// POST /api/chat
router.post('/', guestOrAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { message, astrologerName, specialty, field } = req.body || {};

    if (typeof message !== 'string' || !message.trim()) {
      return res.status(400).json({ error: 'Message content is required' });
    }
    if (message.length > MAX_MESSAGE_LENGTH) {
      return res.status(400).json({ error: `Message is too long (max ${MAX_MESSAGE_LENGTH} characters)` });
    }
    const userMessage = message.trim();
    const today = istDate();
    // App builds from 1.3.3 build the Kundli themselves when we send action generate_kundli;
    // older builds would ignore it, so they are pointed to the birth-details form instead.
    const canBuildKundli = Array.isArray(req.body.clientActions) && req.body.clientActions.includes('generate_kundli');

    const astroName = cleanMeta(astrologerName, 'Rishi & Olivia');
    const astroSpecialty = cleanMeta(specialty, 'Love & Relationship Compatibility');
    const astroField = cleanMeta(field, 'Love & Relationships');

    // 1. User's birth details & Kundli
    const kundliQuery = await db.query(
      `SELECT u.full_name AS user_name, u.gender,
              bd.date_of_birth, bd.time_of_birth, bd.place_of_birth, bd.latitude, bd.longitude, bd.timezone,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info, k.kundli_data
       FROM users u
       LEFT JOIN birth_details bd ON u.id = bd.user_id
       LEFT JOIN kundlis k ON u.id = k.user_id
       WHERE u.id = $1`,
      [userId]
    );

    const row = kundliQuery.rows[0] || {};
    const hasKundli = !!(row.date_of_birth && row.ascendant);
    const dasha = parseJson(row.dasha_info, {}) || {};

    let kundliContext;
    if (hasKundli) {
      const planetsArr = parseJson(row.planetary_positions, []);
      const planetsText = Array.isArray(planetsArr)
        ? planetsArr.map((p) => `${p.name}: ${p.sign} (House ${p.house}, ${p.degree}°${p.speed === 'Retrograde' ? ', retrograde' : ''})`).join('\n')
        : '';

      kundliContext = `
=== USER'S VEDIC BIRTH CHART (sidereal, Lahiri) ===
Name: ${row.user_name || 'Seeker'}
Gender: ${row.gender || 'Not Specified'}
Date of Birth: ${row.date_of_birth}
Time of Birth: ${row.time_of_birth}
Place of Birth: ${row.place_of_birth || 'Unknown'}

- Ascendant / Lagna: ${row.ascendant}
- Sun Sign: ${row.sun_sign}
- Moon Sign (Rasi): ${row.moon_sign}
- Nakshatra: ${row.nakshatra} (Pada ${row.nakshatra_pada || 1})
- Vimshottari Mahadasha at chart creation: ${dasha.currentMahadasha || 'Unknown'} (Antardasha: ${dasha.antardasha || 'Unknown'}, Mahadasha ends: ${dasha.dashaEndDate || 'Unknown'})

PLANETARY POSITIONS:
${planetsText || 'Not available'}
===============================================
`;
    } else {
      kundliContext = !canBuildKundli ? `
USER STATUS: Birth chart not yet generated. The user can create their Kundli in this app from the Kundli / birth details screen (date, time and place of birth); it is calculated precisely there. Ask them to do that for chart-specific guidance. Never say charts cannot be generated, and never send the user to another app, website or astrologer. Do not invent placements.
` : `
USER STATUS: Birth chart not yet generated. This app builds the user's Kundli automatically, with precise astronomical calculations, as soon as they have shared their date of birth, time of birth and place of birth in this chat. Ask for whichever of these three is still missing (one short question; if they do not know the time, they can say so). Never say you cannot create or generate a birth chart, and never send the user to another app, website or astrologer. Do not invent placements or give chart-specific predictions before the chart exists.
`;
    }

    // 1b. Compact "today for this user" block from the forecast engine (dasha, Moon, transits, events).
    // Best effort: a failure here must never break chat.
    if (hasKundli) {
      try {
        const kundli = kundliFromRow(row, row.user_name);
        if (kundli) kundliContext += `
${chatContext(kundli, { profile: { name: row.user_name || 'Seeker', isFamily: false, familyId: null, relationship: null } })}
`;
      } catch (e) {
        console.warn('Chat forecast context skipped:', e && e.message ? e.message : e);
      }
    }

    // 2. Recent conversation with this astrologer (context memory)
    const historyQuery = await db.query(
      `SELECT role, content FROM chat_messages
       WHERE user_id = $1 AND (astrologer_name = $2 OR astrologer_name IS NULL) AND role IN ('user', 'assistant')
       ORDER BY created_at DESC, id DESC LIMIT 10`,
      [userId, astroName]
    );
    const recentHistory = historyQuery.rows.reverse();

    // 3. Persist the user's message
    await db.query(
      'INSERT INTO chat_messages (user_id, role, content, astrologer_name, specialty, field) VALUES ($1, $2, $3, $4, $5, $6)',
      [userId, 'user', userMessage, astroName, astroSpecialty, astroField]
    );

    // 3b. No chart yet: if the user has now shared date, time and place of birth in the chat,
    // hand them to the app to build the Kundli with our own engine (never an AI-made chart).
    // Best effort: any failure just falls through to the normal AI reply.
    if (!hasKundli && canBuildKundli) {
      try {
        const userTexts = recentHistory.filter((h) => h.role === 'user').map((h) => h.content).concat(userMessage);
        const found = await extractBirthDetails(userTexts, today);
        if (found && found.complete) {
          const details = found.birthDetails;
          const { date, time } = describeBirthDetails(details);
          const confirmation = `Thank you. I have your birth details: ${date}, ${time}, ${details.placeOfBirth}. ` +
            'I am preparing your Kundli now with precise planetary calculations. Once it is ready I will read it for you.';
          await db.query(
            'INSERT INTO chat_messages (user_id, role, content, astrologer_name, specialty, field, is_diagnostic) VALUES ($1, $2, $3, $4, $5, $6, $7)',
            [userId, 'assistant', confirmation, astroName, astroSpecialty, astroField, false]
          );
          const accountName = row.user_name && row.user_name !== 'Guest User' ? row.user_name : null;
          return res.json({
            role: 'assistant',
            content: confirmation,
            isDiagnostic: false,
            astrologerName: astroName,
            aiAvailable: true,
            timestamp: new Date().toISOString(),
            action: {
              type: 'generate_kundli',
              birthDetails: {
                fullName: details.name || accountName || 'Me',
                gender: details.gender || (row.gender && row.gender !== 'Not Specified' ? row.gender : 'Not Specified'),
                dateOfBirth: details.dateOfBirth,
                timeOfBirth: details.timeOfBirth,
                birthTimeKnown: details.birthTimeKnown,
                placeOfBirth: details.placeOfBirth,
              },
            },
          });
        }
      } catch (e) {
        console.warn('Chat birth-detail extraction skipped:', e && e.message ? e.message : e);
      }
    }

    // 4. System prompt
    const systemPrompt = `You are ${astroName}, a Vedic astrologer specializing in "${astroSpecialty}" (${astroField}).
Today's date is ${today} (India). Any date before today is in the past.

RULES:
1. Do not use emojis or pictographic symbols. Keep a formal, warm, grounded tone.
2. Be honest and realistic. Never promise guaranteed outcomes or quick fixes; never give medical, legal or financial guarantees. Encourage professional help where appropriate.
3. Where it genuinely helps, include a short lesson or story from classical Hindu texts (Mahabharata, Ramayana, Bhagavad Gita, Puranas, Upanishads).
4. Base chart analysis strictly on the user's actual data below. Never invent placements that are not provided.
5. If the question lacks context needed for a meaningful answer, ask one clear clarifying question.
6. Keep answers concise (under about 250 words) unless the user asks for detail.
7. Reply in the language the user writes in or asks for (for example Tamil, Hindi, Telugu, Bengali, Marathi), using its own script. Never refuse a language or send the user to a translation tool.

${kundliContext}`;

    const openAIMessages = [
      { role: 'system', content: systemPrompt },
      ...recentHistory.map((h) => ({ role: h.role, content: h.content })),
      { role: 'user', content: userMessage }
    ];

    // 5. Generate reply (OpenAI with deterministic fallback)
    let aiReply = await chatCompletion({
      messages: openAIMessages,
      temperature: 0.5,
      maxTokens: 700,
      timeoutMs: 25000
    });
    const usedFallback = !aiReply;
    if (!aiReply) {
      aiReply = generateKundliAgentResponse(row, hasKundli, astroName, astroSpecialty);
    }

    aiReply = removeEmojis(aiReply) || 'I am unable to respond right now. Please try again in a moment.';
    const isDiagnosticMode = /\?\s*$/.test(aiReply) && recentHistory.length < 3;

    // 6. Persist the reply
    await db.query(
      'INSERT INTO chat_messages (user_id, role, content, astrologer_name, specialty, field, is_diagnostic) VALUES ($1, $2, $3, $4, $5, $6, $7)',
      [userId, 'assistant', aiReply, astroName, astroSpecialty, astroField, isDiagnosticMode]
    );

    res.json({
      role: 'assistant',
      content: aiReply,
      isDiagnostic: isDiagnosticMode,
      astrologerName: astroName,
      aiAvailable: !usedFallback,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('AI chat endpoint error:', error);
    res.status(500).json({ error: 'Failed to process AI astrologer chat' });
  }
});

// GET /api/chat/history?astrologerName=...
router.get('/history', optionalAuthenticateToken, async (req, res) => {
  try {
    if (!req.user) {
      return res.json({ history: [] });
    }
    const userId = req.user.userId;
    const astrologerName = typeof req.query.astrologerName === 'string' ? req.query.astrologerName.trim() : '';

    let queryText = `SELECT id, role, content, astrologer_name AS "astrologerName", is_diagnostic AS "isDiagnostic", created_at AS timestamp
                     FROM chat_messages WHERE user_id = $1 AND role IN ('user', 'assistant')`;
    const queryParams = [userId];

    if (astrologerName) {
      queryText += ' AND astrologer_name = $2';
      queryParams.push(astrologerName);
    }

    queryText += ' ORDER BY created_at ASC, id ASC LIMIT 500';

    const result = await db.query(queryText, queryParams);
    res.json({ history: result.rows });
  } catch (error) {
    console.error('Fetch history error:', error);
    res.status(500).json({ error: 'Failed to fetch chat history' });
  }
});

function generateKundliAgentResponse(row, hasKundli, astroName, astroSpecialty) {
  const name = row.user_name && row.user_name !== 'Guest User' ? row.user_name : 'Seeker';
  if (!hasKundli) {
    return `Namaste ${name}. I am ${astroName}, and my focus is ${astroSpecialty}. ` +
      'To give you an accurate reading I need your birth chart. Please share your date of birth, exact time of birth and place of birth, or generate your Kundli in the app. ' +
      'Meanwhile, which area of life would you like guidance on?';
  }
  const dasha = parseJson(row.dasha_info, {}) || {};
  return `Namaste ${name}. As ${astroName} (${astroSpecialty}), I have looked at your birth chart.\n\n` +
    `Ascendant (Lagna): ${row.ascendant}\n` +
    `Moon Sign (Rasi): ${row.moon_sign}\n` +
    `Nakshatra: ${row.nakshatra}\n` +
    `Mahadasha: ${dasha.currentMahadasha || 'Unknown'}\n\n` +
    'In the Bhagavad Gita, Sri Krishna reminds Arjuna that our right is to the action, not to its fruits. Planetary periods describe tendencies; steady effort and right conduct shape how they unfold. ' +
    'Which specific area of your life would you like to focus on today?';
}

module.exports = router;
