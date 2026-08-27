const express = require('express');
const router = express.Router();
const { ZODIAC_SIGNS } = require('../services/astrology_service');

const HOROSCOPE_DATA = {
  Aries: {
    love: 85,
    career: 78,
    luck: 90,
    wealth: 82,
    todayFocus: "Clear Communication",
    prediction: "A conversation with a friend or partner may set a positive tone today. With the Moon forming a favorable aspect, your communication house works smoothly."
  },
  Taurus: {
    love: 92,
    career: 84,
    luck: 88,
    wealth: 95,
    todayFocus: "Financial Growth",
    prediction: "Focus on long-term stability and personal comfort today. Favorable planetary transits highlight opportunity in financial and career investments."
  },
  Gemini: {
    love: 80,
    career: 90,
    luck: 85,
    wealth: 88,
    todayFocus: "Creative Expression",
    prediction: "Your mind is vibrant and full of new ideas today. Share your vision with colleagues and trust your quick intellect."
  },
  Cancer: {
    love: 94,
    career: 76,
    luck: 82,
    wealth: 80,
    todayFocus: "Emotional Harmony",
    prediction: "Home and family take priority. Listening to your intuition brings deep peace and clarity for upcoming decisions."
  },
  Leo: {
    love: 88,
    career: 95,
    luck: 91,
    wealth: 89,
    todayFocus: "Leadership & Confidence",
    prediction: "Your natural charisma shines bright today. Take the initiative in projects and inspire those around you."
  },
  Virgo: {
    love: 82,
    career: 91,
    luck: 84,
    wealth: 93,
    todayFocus: "Detail & Health",
    prediction: "Organization and practical planning bring peace of mind. Pay attention to wellness routines and mindfulness."
  },
  Libra: {
    love: 95,
    career: 83,
    luck: 89,
    wealth: 84,
    todayFocus: "Balance & Relationships",
    prediction: "Harmonious energy flows in your interactions. A wonderful day to connect with close friends or your romantic partner."
  },
  Scorpio: {
    love: 86,
    career: 89,
    luck: 93,
    wealth: 87,
    todayFocus: "Intuition & Strategy",
    prediction: "Deep insights and secret wisdom surface today. Trust your instinct and focus on strategic long-term goals."
  },
  Sagittarius: {
    love: 89,
    career: 87,
    luck: 96,
    wealth: 85,
    todayFocus: "Adventure & Wisdom",
    prediction: "Jupiter's blessing brings optimism and spiritual growth. Expand your horizons and explore new knowledge."
  },
  Capricorn: {
    love: 81,
    career: 96,
    luck: 83,
    wealth: 94,
    todayFocus: "Ambition & Discipline",
    prediction: "Your steady determination moves mountains today. Hard work pays off with recognized success."
  },
  Aquarius: {
    love: 87,
    career: 88,
    luck: 90,
    wealth: 86,
    todayFocus: "Innovation & Friendship",
    prediction: "Collaboration with friends and networking opens exciting doors. Embrace your unique vision."
  },
  Pisces: {
    love: 93,
    career: 82,
    luck: 92,
    wealth: 85,
    todayFocus: "Spiritual Connection",
    prediction: "Dreamy and inspiring vibrations surround you. Meditation and artistic endevours nourish your soul."
  }
};

// GET /api/horoscope/daily?sign=Aries
router.get('/daily', (req, res) => {
  const sign = req.query.sign || 'Aries';
  const signKey = ZODIAC_SIGNS.find(s => s.toLowerCase() === sign.toLowerCase()) || 'Aries';
  
  const data = HOROSCOPE_DATA[signKey] || HOROSCOPE_DATA['Aries'];
  res.json({
    sign: signKey,
    date: new Date().toISOString().split('T')[0],
    ...data
  });
});

module.exports = router;
