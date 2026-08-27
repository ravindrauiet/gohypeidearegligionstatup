const express = require('express');
const router = express.Router();
const db = require('../db');
const { optionalAuthenticateToken } = require('./auth');

// POST /api/chat
// Kundli-Aware AI Chatbot Endpoint with Neon DB Persistence
router.post('/', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { message } = req.body;

    if (!message) {
      return res.status(400).json({ error: 'Message content is required' });
    }

    // 1. Fetch User's Kundli & Birth Details from Neon DB
    const kundliQuery = await db.query(
      `SELECT bd.full_name, bd.date_of_birth, bd.time_of_birth, bd.place_of_birth,
              k.ascendant, k.sun_sign, k.moon_sign, k.nakshatra, k.nakshatra_pada,
              k.planetary_positions, k.houses, k.dasha_info
       FROM birth_details bd
       LEFT JOIN kundlis k ON bd.user_id = k.user_id
       WHERE bd.user_id = $1`,
      [userId]
    );

    let kundliContext = '';
    if (kundliQuery.rows.length > 0) {
      const k = kundliQuery.rows[0];
      kundliContext = `
USER'S KUNDLI & BIRTH DETAILS:
Name: ${k.full_name || 'User'}
Date of Birth: ${k.date_of_birth || 'N/A'}
Time of Birth: ${k.time_of_birth || 'N/A'}
Place of Birth: ${k.place_of_birth || 'N/A'}
Ascendant (Lagna): ${k.ascendant || 'Aries'}
Sun Sign: ${k.sun_sign || 'N/A'}
Moon Sign (Rasi): ${k.moon_sign || 'N/A'}
Nakshatra: ${k.nakshatra || 'N/A'} (Pada ${k.nakshatra_pada || 1})
Current Mahadasha: ${k.dasha_info?.currentMahadasha || 'Jupiter'}
      `;
    } else {
      kundliContext = `No birth chart provided yet. Provide general Vedic astrology guidance.`;
    }

    // 2. Save User Message to Neon DB
    await db.query(
      'INSERT INTO chat_messages (user_id, role, content) VALUES ($1, $2, $3)',
      [userId, 'user', message]
    );

    // 3. System Prompt Creation
    const systemPrompt = `You are AstroAI, an expert Vedic Astrologer and Cosmic Life Guide. 
You possess deep knowledge of Jyotish Shastra, planetary alignments, houses, dashas, and remedies.
You have full access to the user's specific birth chart and Kundli details below:

${kundliContext}

INSTRUCTIONS FOR ASTROLOGER AI:
1. Always base your answers on the user's specific Ascendant, Moon sign, Nakshatra, and Mahadasha.
2. Provide practical, compassionate, and precise guidance regarding Love, Career, Wealth, Health, or Remedies.
3. Be respectful, encouraging, and clear. Avoid frightening predictions; highlight cosmic solutions and gemstone/mantra remedies.`;

    // 4. Generate AI Response (Integrated fallback mechanism)
    let aiReply = '';
    const openAIKey = process.env.OPENAI_API_KEY;

    if (openAIKey && openAIKey.length > 10) {
      try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openAIKey}`
          },
          body: JSON.stringify({
            model: 'gpt-3.5-turbo',
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: message }
            ],
            temperature: 0.7
          })
        });
        const data = await response.json();
        if (data.choices && data.choices.length > 0) {
          aiReply = data.choices[0].message.content;
        }
      } catch (err) {
        console.error('OpenAI call failed, using rule-based astrology fallback:', err);
      }
    }

    if (!aiReply) {
      aiReply = generateAstrologyFallbackResponse(message, kundliQuery.rows[0]);
    }

    // 5. Save AI Message to Neon DB
    await db.query(
      'INSERT INTO chat_messages (user_id, role, content) VALUES ($1, $2, $3)',
      [userId, 'assistant', aiReply]
    );

    res.json({
      role: 'assistant',
      content: aiReply,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Chat error:', error);
    res.status(500).json({ error: 'Failed to process AI Kundli chat message' });
  }
});

// GET /api/chat/history
router.get('/history', optionalAuthenticateToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const result = await db.query(
      'SELECT id, role, content, created_at AS timestamp FROM chat_messages WHERE user_id = $1 ORDER BY created_at ASC',
      [userId]
    );
    res.json({ history: result.rows });
  } catch (error) {
    console.error('Fetch history error:', error);
    res.status(500).json({ error: 'Failed to fetch chat history' });
  }
});

function generateAstrologyFallbackResponse(message, userKundli) {
  const query = message.toLowerCase();
  const name = userKundli?.full_name || 'seeker';
  const ascendant = userKundli?.ascendant || 'Aries';
  const moonSign = userKundli?.moon_sign || 'Taurus';
  const nakshatra = userKundli?.nakshatra || 'Rohini';
  const dasha = userKundli?.dasha_info?.currentMahadasha || 'Jupiter';

  if (query.includes('love') || query.includes('relationship') || query.includes('partner') || query.includes('marriage')) {
    return `Namaste ${name}, based on your Kundli with **${ascendant} Ascendant** and **${moonSign} Moon Sign**, your 7th house of relationships is currently under the favorable influence of **${dasha} Mahadasha**. \n\nCosmic Insight for Love:\n- Your Nakshatra (**${nakshatra}**) gives you deep emotional sensitivity and loyalty.\n- The current planetary transit supports open communication and mutual harmony. For strengthening bonds, chanting the *Om Namah Shivaya* mantra daily brings alignment.`;
  }

  if (query.includes('career') || query.includes('job') || query.includes('work') || query.includes('business') || query.includes('money')) {
    return `Greetings ${name}, analyzing your 10th house of career and 11th house of gains under your **${dasha} Mahadasha**:\n\n- With **${ascendant} Lagna**, your natural leadership and determination are your strong suits.\n- Expect positive momentum in career development. Opportunities for growth or financial expansion are opening up. Consider offering water to the Sun (Surya Arghya) at sunrise to boost confidence and focus.`;
  }

  if (query.includes('health') || query.includes('mind') || query.includes('stress') || query.includes('peace')) {
    return `Dear ${name}, your **${moonSign} Moon sign** combined with **${nakshatra} Nakshatra** indicates a deeply sensitive mind. During your current **${dasha} Mahadasha**, maintaining inner peace through morning meditation and spending time near natural water bodies will greatly rejuvenate your energy.`;
  }

  return `Namaste ${name}. Looking at your chart with **${ascendant} Lagna**, **${moonSign} Moon Sign** (${nakshatra} Nakshatra) currently running **${dasha} Mahadasha**:\n\nThe planets align to support your personal growth. Focus your intentions on positive action and trust your intuition. If you have specific questions about Love, Career, Wealth, or Kundli Remedies, feel free to ask!`;
}

module.exports = router;
