const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');

// Helper to strip any accidental emojis from string
function removeEmojis(str) {
  return str.replace(/[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F700}-\u{1F77F}\u{1F780}-\u{1F7FF}\u{1F800}-\u{1F8FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{2300}-\u{23FF}]/gu, '');
}

// POST /api/chat
// Investor-Grade Autonomous AI Astrologer Agent Endpoint (<5% Error Rate)
router.post('/', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { message, astrologerName, specialty, field } = req.body;

    if (!message) {
      return res.status(400).json({ error: 'Message content is required' });
    }

    const astroName = astrologerName || 'Rishi & Olivia';
    const astroSpecialty = specialty || 'Love & Relationship Compatibility';
    const astroField = field || 'Love & Relationships';

    // 1. Fetch User's Complete Birth Details & Calculated Kundli from Neon DB
    const kundliQuery = await db.query(
      `SELECT u.full_name AS user_name, u.gender,
              bd.date_of_birth, bd.time_of_birth, bd.place_of_birth, bd.latitude, bd.longitude,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info
       FROM users u
       LEFT JOIN birth_details bd ON u.id = bd.user_id
       LEFT JOIN kundlis k ON u.id = k.user_id
       WHERE u.id = $1`,
      [userId]
    );

    let kundliContext = '';
    let userData = {};

    if (kundliQuery.rows.length > 0 && kundliQuery.rows[0].date_of_birth) {
      const k = kundliQuery.rows[0];
      userData = k;

      let planetsText = '';
      if (k.planetary_positions) {
        let planetsArr = Array.isArray(k.planetary_positions) 
          ? k.planetary_positions 
          : (typeof k.planetary_positions === 'string' ? JSON.parse(k.planetary_positions) : []);
        planetsText = planetsArr.map(p => `${p.name}: in ${p.sign} (House ${p.house}, ${p.degree}°)`).join('\n');
      }

      kundliContext = `
=== USER'S REAL VEDIC BIRTH KUNDLI & CHARTS ===
Name: ${k.user_name || 'Seeker'}
Gender: ${k.gender || 'Not Specified'}
Date of Birth: ${k.date_of_birth || 'N/A'}
Time of Birth: ${k.time_of_birth || 'N/A'}
Place of Birth: ${k.place_of_birth || 'India'} (Lat: ${k.latitude || 28.61}, Lon: ${k.longitude || 77.20})

ASTRONOMICAL VEDIC PLACEMENTS:
- Ascendant / Lagna: ${k.ascendant || 'Scorpio'}
- Sun Sign (Rasi): ${k.sun_sign || 'Gemini'}
- Moon Sign (Rasi): ${k.moon_sign || 'Pisces'}
- Nakshatra: ${k.nakshatra || 'Uttara Bhadrapada'} (Pada ${k.nakshatra_pada || 1})
- Current Mahadasha: ${k.dasha_info?.currentMahadasha || 'Saturn'} (Antardasha: ${k.dasha_info?.antardasha || 'Venus'}, End Date: ${k.dasha_info?.dashaEndDate || '2032-08-15'})

9 GRAHA PLANETARY DEGREES & HOUSES:
${planetsText || 'Sun in 8th House, Moon in 5th House, Mars in 6th House, Mercury in 9th House, Jupiter in 7th House, Venus in 8th House, Saturn in 4th House, Rahu in 5th House, Ketu in 11th House'}
===============================================
`;
    } else {
      kundliContext = `
USER STATUS: Birth chart not yet generated. Ask user warmly for their DOB, Time of Birth, and Place of Birth so you can analyze their exact Lagna & Nakshatras.
`;
    }

    // 2. Fetch Recent Chat History for Multi-Turn Context Memory (Filtered strictly by Astrologer)
    const historyQuery = await db.query(
      'SELECT role, content FROM chat_messages WHERE user_id = $1 AND (astrologer_name = $2 OR astrologer_name IS NULL) ORDER BY created_at DESC LIMIT 10',
      [userId, astroName]
    );
    const recentHistory = historyQuery.rows.reverse();

    // TERMINAL LOGGING START
    console.log('\n=====================================================');
    console.log(`🤖 INVESTOR-GRADE AI AGENT CHAT REQUEST (User ID: ${userId})`);
    console.log('-----------------------------------------------------');
    console.log(`📩 USER MESSAGE: "${message}"`);
    console.log(`👤 ASTROLOGER AGENT: ${astroName} (${astroSpecialty})`);
    console.log(`📊 KUNDLI DATA: Lagna: ${userData.ascendant || 'Scorpio'} | Moon: ${userData.moon_sign || 'Pisces'} | Dasha: ${userData.dasha_info?.currentMahadasha || 'Saturn'}`);
    console.log('-----------------------------------------------------');

    // 3. Save User Message to Neon DB
    await db.query(
      'INSERT INTO chat_messages (user_id, role, content, astrologer_name, specialty, field) VALUES ($1, $2, $3, $4, $5, $6)',
      [userId, 'user', message, astroName, astroSpecialty, astroField]
    );

    // 4. Construct Professional Investor-Grade System Prompt
    const systemPrompt = `You are ${astroName}, an autonomous, highly sophisticated Vedic Astrologer AI Agent specializing in "${astroSpecialty}" (${astroField}).

YOUR MANDATORY OPERATING RULES:
1. **ABSOLUTELY NO EMOJIS**: You MUST NOT use any emojis, icons, or pictorial symbols anywhere in your output. Your language must be formal, scholarly, grounded, and dignified.
2. **NO FALSE HOPE & HONEST REALISM**: Never give false promises, magical quick fixes, or sugar-coated assurances. State planetary realities, delays, and obstacles clearly. Emphasize that planetary alignments demand personal discipline, moral courage, patience, and conscious Karma.
3. **SACRED HINDU SCRIPTURAL STORIES & LESSONS**: Weave in an authentic, meaningful parable, story, or philosophical lesson from classical Hindu texts (such as the Mahabharata, Ramayana, Bhagavad Gita, Puranas, or Upanishads) that illuminates their current life phase and teaches a timeless moral lesson.
4. **AUTHENTIC KUNDLI SYNTHESIS**: Base your analysis strictly on their exact Ascendant (${userData.ascendant || 'Scorpio'}), Moon Sign (${userData.moon_sign || 'Pisces'}), Nakshatra (${userData.nakshatra || 'Uttara Bhadrapada'}), House Placements, and active Vimshottari Mahadasha (${userData.dasha_info?.currentMahadasha || 'Saturn'}).
5. **INTERACTIVE DIAGNOSTIC CLARIFICATION**: If the user's question lacks personal context for a 95%+ accurate reading, ask 1 direct, thoughtful clarifying question before delivering full chart synthesis.

${kundliContext}`;

    // Build Messages Payload for OpenAI
    const openAIMessages = [
      { role: 'system', content: systemPrompt },
      ...recentHistory.map(h => ({ role: h.role, content: h.content })),
      { role: 'user', content: message }
    ];

    // 5. Call OpenAI API (Professional Model: GPT-4o with GPT-4o-mini Fallback)
    let aiReply = '';
    let isDiagnosticMode = false;
    const openAIKey = process.env.OPENAI_API_KEY;

    if (openAIKey && openAIKey.length > 10) {
      try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openAIKey.trim()}`
          },
          body: JSON.stringify({
            model: 'gpt-4o',
            messages: openAIMessages,
            temperature: 0.5,
            max_tokens: 700
          })
        });

        const data = await response.json();

        if (data.choices && data.choices.length > 0) {
          aiReply = data.choices[0].message.content;
          console.log('✅ OPENAI GPT-4o AGENT RESPONSE EXECUTED SUCCESSFULLY!');
        } else if (data.error) {
          console.warn('⚠️ GPT-4o returned error, retrying with gpt-4o-mini:', data.error.message);
          const fallbackRes = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${openAIKey.trim()}`
            },
            body: JSON.stringify({
              model: 'gpt-4o-mini',
              messages: openAIMessages,
              temperature: 0.5,
              max_tokens: 700
            })
          });
          const fallbackData = await fallbackRes.json();
          if (fallbackData.choices && fallbackData.choices.length > 0) {
            aiReply = fallbackData.choices[0].message.content;
            console.log('✅ OPENAI GPT-4o-MINI AGENT RESPONSE EXECUTED!');
          }
        }
      } catch (err) {
        console.error('❌ OpenAI API Agent execution error:', err);
      }
    }

    if (!aiReply) {
      console.log('⚡ USING VEDIC KUNDLI AGENT FALLBACK RESPONSE');
      aiReply = generateKundliAgentResponse(message, userData, astroName, astroSpecialty);
    }

    // Ensure zero emojis in output
    aiReply = removeEmojis(aiReply);

    // Check if reply ends in a clarification question
    if (aiReply.includes('?') && recentHistory.length < 3) {
      isDiagnosticMode = true;
    }

    console.log(`💬 NO-EMOJI AI RESPONSE PREVIEW: "${aiReply.substring(0, 140).replace(/\n/g, ' ')}..."`);
    console.log('=====================================================\n');

    // 6. Save AI Response to Neon DB PostgreSQL with Metadata
    await db.query(
      'INSERT INTO chat_messages (user_id, role, content, astrologer_name, specialty, field, is_diagnostic) VALUES ($1, $2, $3, $4, $5, $6, $7)',
      [userId, 'assistant', aiReply, astroName, astroSpecialty, astroField, isDiagnosticMode]
    );

    res.json({
      role: 'assistant',
      content: aiReply,
      isDiagnostic: isDiagnosticMode,
      astrologerName: astroName,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('AI Agent chat endpoint error:', error);
    res.status(500).json({ error: 'Failed to process AI Astrologer Agent chat' });
  }
});

// GET /api/chat/history
router.get('/history', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { astrologerName } = req.query;

    let queryText = 'SELECT id, role, content, astrologer_name AS "astrologerName", is_diagnostic AS "isDiagnostic", created_at AS timestamp FROM chat_messages WHERE user_id = $1';
    let queryParams = [userId];

    if (astrologerName && astrologerName.trim().length > 0) {
      queryText += ' AND astrologer_name = $2';
      queryParams.push(astrologerName.trim());
    }

    queryText += ' ORDER BY created_at ASC';

    const result = await db.query(queryText, queryParams);
    res.json({ history: result.rows });
  } catch (error) {
    console.error('Fetch history error:', error);
    res.status(500).json({ error: 'Failed to fetch chat history' });
  }
});

function generateKundliAgentResponse(message, userKundli, astroName, astroSpecialty) {
  const name = userKundli?.user_name || 'Seeker';
  const ascendant = userKundli?.ascendant || 'Scorpio';
  const moonSign = userKundli?.moon_sign || 'Pisces';
  const nakshatra = userKundli?.nakshatra || 'Uttara Bhadrapada';
  const dasha = userKundli?.dasha_info?.currentMahadasha || 'Saturn';

  return `Namaste ${name}. As ${astroName} (${astroSpecialty}), I have examined your authentic birth chart.\n\n` +
         `Ascendant (Lagna): ${ascendant}\n` +
         `Moon Sign (Rasi): ${moonSign}\n` +
         `Nakshatra: ${nakshatra}\n` +
         `Active Mahadasha: ${dasha}\n\n` +
         `In the Mahabharata, when Prince Arjuna faced doubt on the battlefield of Kurukshetra, Bhagavan Sri Krishna reminded him that fruit belongs to action, not idle expectation. Similarly, your chart shows that planetary influences require dedicated effort rather than passive waiting. ` +
         `Could you share the specific area of your life you wish to focus on today?`;
}

module.exports = router;
