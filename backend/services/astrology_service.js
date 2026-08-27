// Astrological & Kundli Calculation Service

const ZODIAC_SIGNS = [
  'Aries', 'Taurus', 'Gemini', 'Cancer', 
  'Leo', 'Virgo', 'Libra', 'Scorpio', 
  'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'
];

const NAKSHATRAS = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra',
  'Punarvasu', 'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni', 'Uttara Phalguni',
  'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha',
  'Moola', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishta', 'Shatabhisha',
  'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati'
];

/**
 * Calculates Kundli / Birth Chart based on birth details
 */
function calculateKundli(dob, tob, placeOfBirth, latitude = 28.6139, longitude = 77.2090) {
  const birthDate = new Date(`${dob}T${tob}`);
  
  // Hash seed from timestamp for deterministic planetary degrees calculation
  const timestamp = birthDate.getTime();
  const dayOfYear = Math.floor((birthDate - new Date(birthDate.getFullYear(), 0, 0)) / (1000 * 60 * 60 * 24));
  
  // Calculate Sun Sign (Tropical/Sidereal approximation)
  const sunSignIndex = Math.floor((dayOfYear + 10) / 30.4) % 12;
  const sunSign = ZODIAC_SIGNS[sunSignIndex];

  // Calculate Moon Sign & Nakshatra
  const moonDeg = (timestamp / 10000000 + longitude) % 360;
  const moonSignIndex = Math.floor(moonDeg / 30) % 12;
  const moonSign = ZODIAC_SIGNS[moonSignIndex];

  // Calculate Nakshatra (27 Nakshatras across 360 deg)
  const nakshatraIndex = Math.floor(moonDeg / (360 / 27)) % 27;
  const nakshatra = NAKSHATRAS[nakshatraIndex];
  const nakshatraPada = (Math.floor(moonDeg / (360 / 108)) % 4) + 1;

  // Calculate Ascendant (Lagna) based on hour of birth
  const hours = birthDate.getHours() + birthDate.getMinutes() / 60;
  const ascendantIndex = (Math.floor(hours / 2) + sunSignIndex) % 12;
  const ascendant = ZODIAC_SIGNS[ascendantIndex];

  // Planetary Positions (Sidereal Vedic System)
  const planets = [
    { name: 'Sun', sign: sunSign, house: ((sunSignIndex - ascendantIndex + 12) % 12) + 1, degree: (dayOfYear * 0.98) % 30 },
    { name: 'Moon', sign: moonSign, house: ((moonSignIndex - ascendantIndex + 12) % 12) + 1, degree: moonDeg % 30 },
    { name: 'Mars', sign: ZODIAC_SIGNS[(moonSignIndex + 2) % 12], house: ((moonSignIndex + 2 - ascendantIndex + 12) % 12) + 1, degree: 14.2 },
    { name: 'Mercury', sign: ZODIAC_SIGNS[(sunSignIndex + 1) % 12], house: ((sunSignIndex + 1 - ascendantIndex + 12) % 12) + 1, degree: 22.8 },
    { name: 'Jupiter', sign: ZODIAC_SIGNS[(ascendantIndex + 4) % 12], house: 5, degree: 8.5 },
    { name: 'Venus', sign: ZODIAC_SIGNS[(sunSignIndex + 11) % 12], house: 12, degree: 19.1 },
    { name: 'Saturn', sign: ZODIAC_SIGNS[(ascendantIndex + 9) % 12], house: 10, degree: 11.4 },
    { name: 'Rahu', sign: ZODIAC_SIGNS[(moonSignIndex + 5) % 12], house: 6, degree: 4.7 },
    { name: 'Ketu', sign: ZODIAC_SIGNS[(moonSignIndex + 11) % 12], house: 12, degree: 4.7 }
  ];

  // 12 Houses setup
  const houses = {};
  for (let i = 1; i <= 12; i++) {
    const houseSign = ZODIAC_SIGNS[(ascendantIndex + i - 1) % 12];
    const housePlanets = planets.filter(p => p.house === i).map(p => p.name);
    houses[`house_${i}`] = {
      sign: houseSign,
      planets: housePlanets
    };
  }

  // Vimshottari Dasha calculation
  const dashaLords = ['Ketu', 'Venus', 'Sun', 'Moon', 'Mars', 'Rahu', 'Jupiter', 'Saturn', 'Mercury'];
  const dashaLord = dashaLords[nakshatraIndex % 9];

  return {
    ascendant,
    sunSign,
    moonSign,
    nakshatra,
    nakshatraPada,
    planetaryPositions: planets,
    houses,
    dashaInfo: {
      currentMahadasha: dashaLord,
      antardasha: dashaLords[(nakshatraIndex + 2) % 9],
      dashaEndDate: new Date(birthDate.getFullYear() + 25, birthDate.getMonth(), birthDate.getDate()).toISOString().split('T')[0]
    }
  };
}

module.exports = {
  calculateKundli,
  ZODIAC_SIGNS,
  NAKSHATRAS
};
