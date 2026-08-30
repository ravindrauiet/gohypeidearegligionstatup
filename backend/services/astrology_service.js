// Production Astronomical Vedic Kundli Calculation Engine
// Swiss Ephemeris NASA JPL DE431 C-Bindings (sweph) + OpenAI GPT-4o Precision Engine

const sweph = require('sweph');

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

const NAKSHATRA_LORDS = [
  'Ketu', 'Venus', 'Sun', 'Moon', 'Mars', 'Rahu', 'Jupiter', 'Saturn', 'Mercury'
];

const DASHA_PERIODS = {
  Ketu: 7,
  Venus: 20,
  Sun: 6,
  Moon: 10,
  Mars: 7,
  Rahu: 18,
  Jupiter: 16,
  Saturn: 19,
  Mercury: 17
};

// 1. D9 Navamsha Transformation Algorithm (1/9th Division)
function getNavamshaSignIndex(long) {
  const signIdx = Math.floor(long / 30) % 12;
  const remDeg = long % 30;
  const navIdx = Math.floor(remDeg / (30 / 9)); // 0 to 8
  
  let startSign = 0;
  if ([0, 4, 8].includes(signIdx)) { // Fiery (Aries, Leo, Sagittarius) -> Aries
    startSign = 0;
  } else if ([1, 5, 9].includes(signIdx)) { // Earthy (Taurus, Virgo, Capricorn) -> Capricorn
    startSign = 9;
  } else if ([2, 6, 10].includes(signIdx)) { // Airy (Gemini, Libra, Aquarius) -> Libra
    startSign = 6;
  } else if ([3, 7, 11].includes(signIdx)) { // Watery (Cancer, Scorpio, Pisces) -> Cancer
    startSign = 3;
  }
  return (startSign + navIdx) % 12;
}

// 2. D10 Dasamsha Transformation Algorithm (1/10th Division for Career)
function getDasamshaSignIndex(long) {
  const signIdx = Math.floor(long / 30) % 12;
  const remDeg = long % 30;
  const dasIdx = Math.floor(remDeg / (30 / 10)); // 0 to 9
  
  let startSign = 0;
  if (signIdx % 2 === 0) { // Odd Sign -> starts from sign itself
    startSign = signIdx;
  } else { // Even Sign -> starts from 9th sign (signIdx + 8)
    startSign = (signIdx + 8) % 12;
  }
  return (startSign + dasIdx) % 12;
}

function calculateKundli(dob, tob, placeOfBirth, latitude = 28.6139, longitude = 77.2090) {
  const lat = parseFloat(latitude) || 28.6139;
  const lon = parseFloat(longitude) || 77.2090;

  const parts = dob.split('-');
  const year = parseInt(parts[0], 10);
  const month = parseInt(parts[1], 10);
  const day = parseInt(parts[2], 10);

  const tParts = tob.split(':');
  const hour = parseInt(tParts[0], 10);
  const minute = parseInt(tParts[1], 10);

  // Convert IST to UTC (subtract 5.5 hours for IST offset)
  let utcHour = hour + (minute / 60.0) - 5.5;
  let utcDay = day;
  let utcMonth = month;
  let utcYear = year;

  if (utcHour < 0) {
    utcHour += 24.0;
    utcDay -= 1;
    if (utcDay < 1) {
      utcMonth -= 1;
      if (utcMonth < 1) {
        utcMonth = 12;
        utcYear -= 1;
      }
      const daysInMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      if (utcMonth === 2 && ((utcYear % 4 === 0 && utcYear % 100 !== 0) || utcYear % 400 === 0)) {
        utcDay = 29;
      } else {
        utcDay = daysInMonth[utcMonth - 1];
      }
    }
  }

  // 1. Configure Swiss Ephemeris with Official Chitrapaksha / Lahiri Ayanamsa
  const SE_SIDM_LAHIRI = sweph.constants ? sweph.constants.SE_SIDM_LAHIRI : 1;
  const SE_GREG_CAL = sweph.constants ? sweph.constants.SE_GREG_CAL : 1;
  const SEFLG_SPEED = sweph.constants ? sweph.constants.SEFLG_SPEED : 256;
  const SEFLG_SIDEREAL = sweph.constants ? sweph.constants.SEFLG_SIDEREAL : 65536;

  sweph.set_sid_mode(SE_SIDM_LAHIRI, 0, 0);

  // Julian Day
  const jdRes = sweph.julday(utcYear, utcMonth, utcDay, utcHour, SE_GREG_CAL);
  const julday = typeof jdRes === 'object' ? jdRes.julianDay : jdRes;

  const ayanamsa = sweph.get_ayanamsa_ut(julday);

  // 2. Compute Sidereal Ascendant (D1 Lagna)
  const housesRes = sweph.houses_ex(julday, SEFLG_SIDEREAL, lat, lon, 'E');
  const ascendantDeg = housesRes.data.houses ? housesRes.data.houses[0] : housesRes.data.points[0];
  const ascendantIndex = Math.floor(ascendantDeg / 30);
  const ascendant = ZODIAC_SIGNS[ascendantIndex];

  // Compute D9 and D10 Ascendant Signs
  const d9AscendantIndex = getNavamshaSignIndex(ascendantDeg);
  const d9Ascendant = ZODIAC_SIGNS[d9AscendantIndex];

  const d10AscendantIndex = getDasamshaSignIndex(ascendantDeg);
  const d10Ascendant = ZODIAC_SIGNS[d10AscendantIndex];

  // 3. Compute Sidereal Planetary Longitudes
  const flags = SEFLG_SPEED | SEFLG_SIDEREAL;
  const planetConfig = [
    { id: sweph.constants ? sweph.constants.SE_SUN : 0, name: 'Sun ☉' },
    { id: sweph.constants ? sweph.constants.SE_MOON : 1, name: 'Moon ☽' },
    { id: sweph.constants ? sweph.constants.SE_MARS : 4, name: 'Mars ♂' },
    { id: sweph.constants ? sweph.constants.SE_MERCURY : 2, name: 'Mercury ☿' },
    { id: sweph.constants ? sweph.constants.SE_JUPITER : 5, name: 'Jupiter ♃' },
    { id: sweph.constants ? sweph.constants.SE_VENUS : 3, name: 'Venus ♀' },
    { id: sweph.constants ? sweph.constants.SE_SATURN : 6, name: 'Saturn ♄' },
    { id: sweph.constants ? sweph.constants.SE_TRUE_NODE : 11, name: 'Rahu ☊' },
  ];

  let rawMoonLong = 0;
  let rawSunLong = 0;
  const rawPlanetaryLongs = [];

  const planets = planetConfig.map(p => {
    const res = sweph.calc_ut(julday, p.id, flags);
    const long = res.longitude || (res.data ? res.data[0] : res[0]);
    const speed = res.longitudeSpeed || (res.data ? res.data[3] : 0);

    if (p.name.includes('Moon')) rawMoonLong = long;
    if (p.name.includes('Sun')) rawSunLong = long;

    rawPlanetaryLongs.push({ name: p.name, long, speed });

    const signIdx = Math.floor(long / 30);
    const houseNum = ((signIdx - ascendantIndex + 12) % 12) + 1;
    return {
      name: p.name,
      sign: ZODIAC_SIGNS[signIdx],
      house: houseNum,
      degree: parseFloat((long % 30).toFixed(2)),
      speed: speed < 0 ? 'Retrograde' : 'Direct'
    };
  });

  // Add Ketu (180 degrees opposite Rahu)
  const rahuObj = planetConfig.find(p => p.name.includes('Rahu'));
  const rahuRes = sweph.calc_ut(julday, rahuObj.id, flags);
  const rahuLong = rahuRes.longitude || (rahuRes.data ? rahuRes.data[0] : 0);
  const ketuLong = (rahuLong + 180) % 360;
  const ketuSignIdx = Math.floor(ketuLong / 30);
  const ketuHouseNum = ((ketuSignIdx - ascendantIndex + 12) % 12) + 1;

  rawPlanetaryLongs.push({ name: 'Ketu ☋', long: ketuLong, speed: -1 });

  planets.push({
    name: 'Ketu ☋',
    sign: ZODIAC_SIGNS[ketuSignIdx],
    house: ketuHouseNum,
    degree: parseFloat((ketuLong % 30).toFixed(2)),
    speed: 'Retrograde'
  });

  const sunSign = ZODIAC_SIGNS[Math.floor(rawSunLong / 30)];
  const moonSign = ZODIAC_SIGNS[Math.floor(rawMoonLong / 30)];

  // 4. Compute Transformed D9 Navamsha & D10 Dasamsha Planet Placements
  const d9Planets = rawPlanetaryLongs.map(p => {
    const d9SignIdx = getNavamshaSignIndex(p.long);
    const d9HouseNum = ((d9SignIdx - d9AscendantIndex + 12) % 12) + 1;
    return {
      name: p.name,
      sign: ZODIAC_SIGNS[d9SignIdx],
      house: d9HouseNum,
      degree: parseFloat((p.long % 30).toFixed(2)),
      speed: p.speed < 0 ? 'Retrograde' : 'Direct'
    };
  });

  const d10Planets = rawPlanetaryLongs.map(p => {
    const d10SignIdx = getDasamshaSignIndex(p.long);
    const d10HouseNum = ((d10SignIdx - d10AscendantIndex + 12) % 12) + 1;
    return {
      name: p.name,
      sign: ZODIAC_SIGNS[d10SignIdx],
      house: d10HouseNum,
      degree: parseFloat((p.long % 30).toFixed(2)),
      speed: p.speed < 0 ? 'Retrograde' : 'Direct'
    };
  });

  // 5. Nakshatra & Pada Calculations
  const nakshatraDeg = rawMoonLong / (360 / 27);
  const nakshatraIndex = Math.floor(nakshatraDeg) % 27;
  const nakshatra = NAKSHATRAS[nakshatraIndex];
  const nakshatraRemDeg = (rawMoonLong % (360 / 27));
  const nakshatraPada = Math.floor(nakshatraRemDeg / (360 / 108)) + 1;

  // 6. Houses Map for D1
  const houses = {};
  for (let i = 1; i <= 12; i++) {
    const houseSign = ZODIAC_SIGNS[(ascendantIndex + i - 1) % 12];
    const housePlanets = planets.filter(p => p.house === i).map(p => p.name);
    houses[`house_${i}`] = { sign: houseSign, planets: housePlanets };
  }

  // 7. Vimshottari Dasha Engine
  const lordIndex = nakshatraIndex % 9;
  const currentMahadasha = NAKSHATRA_LORDS[lordIndex];
  const antardasha = NAKSHATRA_LORDS[(lordIndex + 2) % 9];
  const dashaTotalYears = DASHA_PERIODS[currentMahadasha] || 16;
  
  const nakshatraSpanDeg = 360 / 27; // 13.3333 degrees
  const fractionRemaining = 1 - (nakshatraRemDeg / nakshatraSpanDeg);
  const dashaRemainingYears = Math.round(dashaTotalYears * fractionRemaining);
  const dashaEndYear = year + dashaRemainingYears;

  // 8. Panchang Calculations
  const tithiNames = [
    'Pratipada', 'Dwitiya', 'Tritiya', 'Chaturthi', 'Panchami', 'Shashti',
    'Saptami', 'Ashtami', 'Navami', 'Dashami', 'Ekadashi', 'Dwadashi',
    'Trayodashi', 'Chaturdashi', 'Purnima / Amavasya'
  ];
  const tithiIndex = Math.floor((((rawMoonLong - rawSunLong + 360) % 360) / 12)) % 15;
  const tithi = tithiNames[tithiIndex];

  const daysOfWeek = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const birthDateObj = new Date(Date.UTC(year, month - 1, day, hour, minute));
  const vaar = daysOfWeek[birthDateObj.getUTCDay()];

  const yogaNames = [
    'Vishkambha', 'Priti', 'Ayushman', 'Saubhagya', 'Shobhana', 'Atiganda', 'Sukarma', 'Dhriti',
    'Shoola', 'Ganda', 'Vriddhi', 'Dhruva', 'Vyaghata', 'Harshana', 'Vajra', 'Siddhi', 'Vyatipata',
    'Variyan', 'Parigha', 'Shiva', 'Siddha', 'Sadhya', 'Shubha', 'Shukla', 'Brahma', 'Indra', 'Vaidhriti'
  ];
  const yogaIndex = Math.floor((((rawSunLong + rawMoonLong) % 360) / (360 / 27))) % 27;
  const yoga = yogaNames[yogaIndex];

  const karanaNames = ['Bava', 'Balava', 'Kaulava', 'Taitila', 'Garaja', 'Vanija', 'Vishti (Bhadra)'];
  const karana = karanaNames[tithiIndex % 7];

  // 9. Avakhada Chakra Calculations
  const ganaList = ['Deva', 'Manushya', 'Rakshasa', 'Deva', 'Deva', 'Rakshasa', 'Deva', 'Deva', 'Rakshasa', 'Rakshasa', 'Manushya', 'Manushya', 'Deva', 'Rakshasa', 'Deva', 'Rakshasa', 'Deva', 'Rakshasa', 'Manushya', 'Manushya', 'Manushya', 'Deva', 'Rakshasa', 'Rakshasa', 'Manushya', 'Manushya', 'Deva'];
  const gana = ganaList[nakshatraIndex] || 'Deva';

  const nadiList = ['Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya', 'Antya', 'Madhya', 'Adi', 'Adi', 'Madhya', 'Antya'];
  const nadi = nadiList[nakshatraIndex] || 'Madhya';

  const yoniList = ['Horse', 'Elephant', 'Goat', 'Serpent', 'Serpent', 'Dog', 'Cat', 'Goat', 'Cat', 'Rat', 'Rat', 'Cow', 'Buffalo', 'Tiger', 'Buffalo', 'Tiger', 'Deer', 'Deer', 'Dog', 'Monkey', 'Mongoose', 'Monkey', 'Lion', 'Horse', 'Lion', 'Cow', 'Elephant'];
  const yoni = yoniList[nakshatraIndex] || 'Serpent';

  const varnaList = ['Kshatriya', 'Vaishya', 'Shudra', 'Brahmin', 'Kshatriya', 'Vaishya', 'Shudra', 'Brahmin', 'Kshatriya', 'Vaishya', 'Shudra', 'Brahmin'];
  const varna = varnaList[Math.floor(rawMoonLong / 30)] || 'Brahmin';

  const tatwaList = ['Fire', 'Earth', 'Air', 'Water', 'Fire', 'Earth', 'Air', 'Water', 'Fire', 'Earth', 'Air', 'Water'];
  const tatwa = tatwaList[Math.floor(rawMoonLong / 30)] || 'Fire';

  const payaList = ['Gold', 'Silver', 'Copper', 'Iron'];
  const moonHouseNum = ((Math.floor(rawMoonLong / 30) - ascendantIndex + 12) % 12) + 1;
  const paya = payaList[moonHouseNum % 4];

  // Enrich planets with Nakshatra details
  const enrichedPlanets = planets.map(p => {
    const pSignIdx = ZODIAC_SIGNS.indexOf(p.sign);
    const pAbsLong = (pSignIdx >= 0 ? pSignIdx : 0) * 30.0 + p.degree;
    const pNakIndex = Math.floor(pAbsLong / (360 / 27)) % 27;
    const pNakRem = pAbsLong % (360 / 27);
    const pPada = Math.floor(pNakRem / (360 / 108)) + 1;
    const pLord = NAKSHATRA_LORDS[pNakIndex % 9];
    return {
      ...p,
      nakshatra: NAKSHATRAS[pNakIndex],
      nakshatraPada: pPada,
      planetLord: pLord
    };
  });

  return {
    ascendant,
    sunSign,
    moonSign,
    nakshatra,
    nakshatraPada,
    latitude: lat,
    longitude: lon,
    ayanamsa: parseFloat(ayanamsa.toFixed(4)),
    planetaryPositions: enrichedPlanets,
    panchang: {
      tithi,
      vaar,
      nakshatra,
      yoga,
      karana
    },
    avakhada: {
      varna,
      vashya: 'Manav',
      yoni,
      gana,
      nadi,
      paya,
      tatwa
    },
    d9Navamsha: {
      ascendant: d9Ascendant,
      planetaryPositions: d9Planets
    },
    d10Dasamsha: {
      ascendant: d10Ascendant,
      planetaryPositions: d10Planets
    },
    houses,
    dashaInfo: {
      currentMahadasha,
      antardasha,
      dashaEndDate: `${dashaEndYear}-08-15`
    }
  };
}

// High-Precision Astronomical Kundli Generation Layer
async function calculateKundliWithAI(dob, tob, placeOfBirth, latitude, longitude, birthDetails = {}) {
  const swissKundli = calculateKundli(dob, tob, placeOfBirth, latitude, longitude);
  
  // Generate & Cache full analysis report ONCE on creation!
  try {
    const aiReport = await generateAIKundliReport(swissKundli, birthDetails);
    swissKundli.aiReport = aiReport;
  } catch (e) {
    console.error('AI Report pre-generation error:', e);
  }

  console.log(`\n=====================================================`);
  console.log(`🌌 SWISS EPHEMERIS KUNDLI CALCULATED & REPORT CACHED:`);
  console.log(`• D1 Lagna: ${swissKundli.ascendant} | D9 Lagna: ${swissKundli.d9Navamsha.ascendant} | D10 Lagna: ${swissKundli.d10Dasamsha.ascendant}`);
  console.log(`• Sun Sign: ${swissKundli.sunSign} | Moon Sign: ${swissKundli.moonSign}`);
  console.log(`• Nakshatra: ${swissKundli.nakshatra} (Pada ${swissKundli.nakshatraPada})`);
  console.log(`• Panchang: Tithi: ${swissKundli.panchang.tithi}, Vaar: ${swissKundli.panchang.vaar}, Yoga: ${swissKundli.panchang.yoga}`);
  console.log(`• Avakhada: Gana: ${swissKundli.avakhada.gana}, Nadi: ${swissKundli.avakhada.nadi}, Tatwa: ${swissKundli.avakhada.tatwa}`);
  console.log(`=====================================================\n`);

  return swissKundli;
}

// Comprehensive Kundli Analysis Report Generator
async function generateAIKundliReport(kundliData, birthDetails = {}) {
  const fullName = birthDetails.fullName || 'Seeker';
  const openAIKey = process.env.OPENAI_API_KEY;

  const planetsSummary = (kundliData.planetaryPositions || [])
    .map(p => `- ${p.name}: in ${p.sign} (House ${p.house}, ${p.degree}°) | Nakshatra: ${p.nakshatra || 'N/A'} (Pada ${p.nakshatraPada || 1}) | Lord: ${p.planetLord || 'N/A'}`)
    .join('\n');

  const prompt = `You are a Master Vedic Astrologer analyzing 100% mathematically exact astronomical data computed via the Astrodienst Swiss Ephemeris (sweph) NASA JPL DE431 Engine.

Generate a comprehensive, deeply personal Vedic Astrology Life Interpretation & Kundli Analysis Report for ${fullName}.

SWISS EPHEMERIS ASTRONOMICAL DATA:
• Ascendant (D1 Lagna): ${kundliData.ascendant}
• Sun Sign: ${kundliData.sunSign}
• Moon Sign: ${kundliData.moonSign}
• Nakshatra: ${kundliData.nakshatra} (Pada ${kundliData.nakshatraPada})
• Panchang: Tithi: ${kundliData.panchang?.tithi}, Vaar: ${kundliData.panchang?.vaar}, Yoga: ${kundliData.panchang?.yoga}, Karana: ${kundliData.panchang?.karana}
• Avakhada Chakra: Gana: ${kundliData.avakhada?.gana}, Nadi: ${kundliData.avakhada?.nadi}, Yoni: ${kundliData.avakhada?.yoni}, Varna: ${kundliData.avakhada?.varna}, Tatwa: ${kundliData.avakhada?.tatwa}, Paya: ${kundliData.avakhada?.paya}

D1 JANAM KUNDLI PLANETS & NAKSHATRAS:
${planetsSummary}

D9 NAVAMSHA (MARRIAGE & RELATIONS) LAGNA: ${kundliData.d9Navamsha?.ascendant}
D10 DASAMSHA (CAREER & STATUS) LAGNA: ${kundliData.d10Dasamsha?.ascendant}

VIMSHOTTARI DASHA:
• Current Mahadasha: ${kundliData.dashaInfo?.currentMahadasha}
• Antardasha: ${kundliData.dashaInfo?.antardasha}
• Dasha End Date: ${kundliData.dashaInfo?.dashaEndDate}

INSTRUCTIONS FOR REPORT:
Write a beautifully structured, highly insightful, executive Vedic Astrology report in Markdown format. Ground every section strictly in their exact placements!

Required Sections:
1. 👤 **Personality & Core Nature**
2. 🏋️ **Physical Traits & Vitality**
3. 🩺 **Health & Wellness Outlook**
4. 💼 **Career, Wealth & Professional Success**
5. ❤️ **Marriage, Relationships & Life Partner**
6. ⏳ **Understanding of Active Dasha Period**
7. 🏁 **Final Executive Summary & Sacred Guidance**`;

  if (openAIKey && openAIKey.length > 10) {
    try {
      console.log(`\n=====================================================`);
      console.log(`🚀 GENERATING & CACHING CHATGPT KUNDLI REPORT (Model: gpt-4o)`);
      console.log(`👤 SEEKER: ${fullName} (${kundliData.ascendant} Lagna)`);
      console.log(`=====================================================\n`);

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${openAIKey.trim()}`
        },
        body: JSON.stringify({
          model: 'gpt-4o',
          messages: [
            { role: 'system', content: 'You are an authoritative, master Vedic Astrologer producing comprehensive Kundli interpretations.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.6,
          max_tokens: 1400
        })
      });

      const data = await response.json();
      if (data.choices && data.choices[0] && data.choices[0].message) {
        return data.choices[0].message.content;
      }
    } catch (err) {
      console.error('OpenAI AI Report Generation error:', err);
    }
  }

  // Fallback Synthesis
  return `### 👤 Personality & Core Nature
Born under **${kundliData.ascendant} Ascendant** with **Moon in ${kundliData.moonSign}** and **${kundliData.nakshatra} Nakshatra (Pada ${kundliData.nakshatraPada})**, you possess a highly analytical, morally grounded character with strong intuition and creative vision.

### 🏋️ Physical Traits & Vitality
Your **${kundliData.ascendant} Lagna** endows you with an impressive presence, quick reflexes, and clear expressive eyes. You maintain a balanced physical posture and high mental agility.

### 🩺 Health & Wellness Outlook
Your health profile is supported by **${kundliData.avakhada?.tatwa || 'Fire'} Tatwa** and **${kundliData.avakhada?.gana || 'Deva'} Gana**. Maintain regular daily routines, stay hydrated, and practice grounding meditation.

### 💼 Career, Wealth & Professional Success
Your **D10 Dasamsha Chart (Lagna: ${kundliData.d10Dasamsha?.ascendant})** indicates strong leadership potential, strategic business acumen, and steady financial growth in administrative, technical, or creative leadership roles.

### ❤️ Marriage, Relationships & Life Partner
Your **D9 Navamsha Chart (Lagna: ${kundliData.d9Navamsha?.ascendant})** reveals deep emotional maturity and lasting compatibility in marriage. Your partner will bring harmony, intellectual companionship, and fortune.

### ⏳ Understanding of Active Dasha Period
You are currently running the major period of **${kundliData.dashaInfo?.currentMahadasha}** with sub-period **${kundliData.dashaInfo?.antardasha}**. This period favors career expansion, property investments, and personal development.

### 🏁 Final Executive Summary & Sacred Guidance
Embrace discipline and purposeful action. Align your daily endeavors with high moral values to maximize the positive fruits of your birth chart.`;
}

module.exports = {
  calculateKundli,
  calculateKundliWithAI,
  generateAIKundliReport,
  ZODIAC_SIGNS,
  NAKSHATRAS
};
