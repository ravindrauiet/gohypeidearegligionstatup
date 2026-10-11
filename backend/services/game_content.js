// Content for the four CosmicGuide games: Graha Quest, Nakshatra Cards, Moksha Patam, Cosmic Match.
// Pure data + tiny text helpers. No astronomy and no database here.
//
// Tone: playful, warm, second person, no fear. Every mission is a small real-life action that is
// safe, free (or nearly free) and doable today in 5-20 minutes.

const PLANET_ORDER = ['Sun', 'Moon', 'Mars', 'Mercury', 'Jupiter', 'Venus', 'Saturn', 'Rahu', 'Ketu'];
const CATEGORIES = ['action', 'kindness', 'mind', 'body', 'learn'];

// ---------------------------------------------------------------------------
// Planet characters
// ---------------------------------------------------------------------------
const PLANET_CHARACTERS = {
  Sun: {
    emoji: '☀️', role: 'Your inner leader',
    personality: 'Warm, proud and generous. Surya lights up when you take charge and show up as yourself.',
    loves: 'confidence, honesty and morning light',
    titles: ['Little Spark', 'Rising Flame', 'Bright Leader', 'Golden Heart', 'Radiant King']
  },
  Moon: {
    emoji: '🌙', role: 'Your inner heart',
    personality: 'Soft, caring and a little moody. Chandra feels everything and relaxes when you feel at home.',
    loves: 'rest, family and anything that feels like home',
    titles: ['Shy Crescent', 'Gentle Glow', 'Calm Tide', 'Silver Heart', 'Full Moon Soul']
  },
  Mars: {
    emoji: '🔥', role: 'Your inner warrior',
    personality: 'Bold, restless and loyal. Mangal hates waiting and loves it when you move your body and finish things.',
    loves: 'action, courage and a good sweat',
    titles: ['Young Cadet', 'Brave Scout', 'Steady Fighter', 'Fearless Captain', 'Unstoppable Commander']
  },
  Mercury: {
    emoji: '🪶', role: 'Your quick-witted messenger',
    personality: 'Curious, funny and always chatting. Budh is happiest when you learn something tiny and share it.',
    loves: 'words, puzzles and clever shortcuts',
    titles: ['Curious Kid', 'Quick Learner', 'Sharp Talker', 'Clever Fox', 'Master of Wit']
  },
  Jupiter: {
    emoji: '🪔', role: 'Your wise teacher',
    personality: 'Big-hearted, hopeful and generous. Guru grows every time you learn, teach or say thank you.',
    loves: 'wisdom, gratitude and sharing what you know',
    titles: ['Eager Student', 'Kind Helper', 'Trusted Guide', 'Generous Guru', 'Great Blessing']
  },
  Venus: {
    emoji: '🌸', role: 'Your inner artist',
    personality: 'Charming, stylish and affectionate. Shukra blooms when you enjoy beauty and make someone feel special.',
    loves: 'beauty, music and small sweet gestures',
    titles: ['Budding Bloom', 'Sweet Charmer', 'Graceful Artist', 'Heart Winner', 'Star of Delight']
  },
  Saturn: {
    emoji: '🪐', role: 'Your inner coach',
    personality: 'Strict but fair. Shani never forgets effort and quietly rewards patience, discipline and helping others.',
    loves: 'finished tasks, kept promises and quiet service',
    titles: ['Patient Beginner', 'Steady Worker', 'Reliable Rock', 'Master Builder', 'Lord of Time']
  },
  Rahu: {
    emoji: '🐉', role: 'Your inner explorer',
    personality: 'Hungry, inventive and a rule-bender. Rahu calms down when you try new things on purpose instead of scrolling.',
    loves: 'new experiences, tech and big dreams',
    titles: ['Restless Dreamer', 'Bold Explorer', 'Trend Hunter', 'Game Changer', 'Fearless Pioneer']
  },
  Ketu: {
    emoji: '🪷', role: 'Your inner monk',
    personality: 'Quiet, intuitive and free. Ketu shines when you let go of clutter, noise and old grudges.',
    loves: 'silence, simplicity and letting go',
    titles: ['Quiet Wanderer', 'Light Traveller', 'Inner Listener', 'Free Spirit', 'Silent Sage']
  }
};

function planetTitle(planet, level) {
  const t = PLANET_CHARACTERS[planet].titles;
  return t[Math.max(0, Math.min(t.length - 1, Math.floor((level - 1) / 2)))];
}

// ---------------------------------------------------------------------------
// Mission library. key: stable id, c: category, xp: 20 easy / 30 medium / 40 stretch.
// ---------------------------------------------------------------------------
const m = (key, c, xp, title) => ({ key, c, xp, title });

const MISSIONS = {
  Sun: [
    m('sun01', 'action', 30, 'Take the lead on one thing today instead of waiting'),
    m('sun02', 'body', 20, 'Stand in the morning sunlight for 5 minutes'),
    m('sun03', 'kindness', 30, 'Call or message your father or a father figure'),
    m('sun04', 'mind', 20, "Write down 3 things you're proud of about yourself"),
    m('sun05', 'action', 30, "Make one small decision you've been putting off"),
    m('sun06', 'body', 20, 'Stand tall for 2 minutes and take 10 deep breaths'),
    m('sun07', 'kindness', 20, 'Give honest praise to someone who did good work'),
    m('sun08', 'learn', 30, 'Read about a leader you admire for 10 minutes'),
    m('sun09', 'action', 40, 'Share one idea out loud in a group or meeting'),
    m('sun10', 'mind', 20, 'Politely say no to one thing that drains you'),
    m('sun11', 'body', 30, 'Do 5 rounds of Surya Namaskar or a 10-minute stretch'),
    m('sun12', 'kindness', 30, 'Thank a mentor or teacher who shaped you')
  ],
  Moon: [
    m('moon01', 'kindness', 30, 'Call your mother or someone who raised you'),
    m('moon02', 'body', 20, 'Drink a glass of water slowly, with no phone'),
    m('moon03', 'mind', 20, 'Write 3 lines about how you feel right now'),
    m('moon04', 'kindness', 40, 'Cook or share a simple meal with someone at home'),
    m('moon05', 'mind', 20, 'Look at the Moon or the evening sky for 5 minutes'),
    m('moon06', 'action', 30, 'Tidy one small corner of your home'),
    m('moon07', 'body', 30, 'Go to bed 30 minutes earlier tonight'),
    m('moon08', 'kindness', 30, 'Send a voice note to someone you miss'),
    m('moon09', 'mind', 20, 'Listen to a song from your childhood'),
    m('moon10', 'learn', 40, 'Ask an elder for a family recipe or an old story'),
    m('moon11', 'mind', 20, 'Sit quietly for 5 minutes and just breathe'),
    m('moon12', 'kindness', 20, 'Water a plant or care for something living')
  ],
  Mars: [
    m('mars01', 'body', 30, 'Do 20 squats or a brisk 10-minute walk'),
    m('mars02', 'action', 40, 'Do your hardest task first today'),
    m('mars03', 'body', 20, 'Take the stairs every chance you get today'),
    m('mars04', 'action', 30, 'Speak up for yourself once, calmly'),
    m('mars05', 'action', 30, 'Fix one small thing at home that has been bugging you'),
    m('mars06', 'mind', 30, 'Count to 10 before replying when you feel irritated'),
    m('mars07', 'kindness', 30, 'Help someone carry their bags or groceries'),
    m('mars08', 'body', 30, 'Hold a 30-second plank or do 10 push-ups your way'),
    m('mars09', 'learn', 30, 'Learn one basic first-aid tip'),
    m('mars10', 'kindness', 20, 'Call or message your brother or a close buddy'),
    m('mars11', 'action', 40, 'Start that thing you keep saying you will start'),
    m('mars12', 'action', 20, 'Clear and organise your desk in 10 minutes')
  ],
  Mercury: [
    m('mer01', 'learn', 20, 'Learn 3 words in a new language'),
    m('mer02', 'action', 20, "Reply to one message you've been ignoring"),
    m('mer03', 'mind', 20, "Write tomorrow's to-do list in 5 lines"),
    m('mer04', 'learn', 30, 'Read 5 pages of any book'),
    m('mer05', 'kindness', 30, 'Explain something you know to a friend or a child'),
    m('mer06', 'mind', 20, 'Solve a puzzle, sudoku or riddle'),
    m('mer07', 'action', 30, 'Clear 20 old emails or photos from your phone'),
    m('mer08', 'kindness', 20, 'Have a friendly chat with a neighbour or shopkeeper'),
    m('mer09', 'body', 20, 'Take a 10-minute walk and notice 5 new things'),
    m('mer10', 'learn', 20, 'Learn one keyboard shortcut or phone trick'),
    m('mer11', 'kindness', 30, 'Write a short thank-you note to someone'),
    m('mer12', 'mind', 30, 'Do your small sums in your head today, no calculator'),
    m('mer13', 'kindness', 30, 'Call or message a cousin, niece or nephew')
  ],
  Jupiter: [
    m('jup01', 'kindness', 30, 'Teach someone one useful thing you know'),
    m('jup02', 'learn', 30, 'Read or listen to something wise for 10 minutes'),
    m('jup03', 'kindness', 30, 'Take blessings from an elder, or simply thank them'),
    m('jup04', 'mind', 30, 'Write down one lesson life taught you this year'),
    m('jup05', 'kindness', 30, 'Share food or sweets with someone today'),
    m('jup06', 'kindness', 30, 'Send a thank-you to a teacher, past or present'),
    m('jup07', 'mind', 30, 'In one conversation today, only listen. No advice'),
    m('jup08', 'learn', 20, 'Learn the meaning of one shloka, proverb or quote'),
    m('jup09', 'body', 20, 'Walk for 10 minutes under trees or open sky'),
    m('jup10', 'action', 30, 'Plan one goal for next month in 3 small steps'),
    m('jup11', 'mind', 20, 'Sit for 5 minutes at a temple or any peaceful spot'),
    m('jup12', 'kindness', 20, 'Encourage someone younger who is trying hard')
  ],
  Venus: [
    m('ven01', 'kindness', 30, 'Wear something you love and compliment one person'),
    m('ven02', 'action', 30, 'Make your room or desk a little more beautiful'),
    m('ven03', 'mind', 20, 'Listen to your favourite music for 10 minutes'),
    m('ven04', 'kindness', 30, 'Do something sweet for your partner or a close friend'),
    m('ven05', 'mind', 20, 'Draw, doodle, sing or dance for 5 minutes'),
    m('ven06', 'mind', 20, 'Enjoy your chai or coffee slowly, without your phone'),
    m('ven07', 'body', 20, 'Dress and groom yourself nicely today, just for you'),
    m('ven08', 'learn', 20, 'Take one beautiful photo of something ordinary'),
    m('ven09', 'action', 30, 'Put a flower or a plant where you can see it'),
    m('ven10', 'body', 30, 'Stretch gently or do 10 minutes of easy yoga'),
    m('ven11', 'kindness', 30, 'Tell someone exactly what you appreciate about them'),
    m('ven12', 'learn', 30, 'Learn one new recipe, song line or dance step')
  ],
  Saturn: [
    m('sat01', 'action', 40, "Finish one task you've been avoiding"),
    m('sat02', 'kindness', 30, 'Help someone older than you with something small'),
    m('sat03', 'action', 30, 'Do one boring chore fully, without your phone'),
    m('sat04', 'action', 20, 'Be 5 minutes early for one thing today'),
    m('sat05', 'kindness', 30, 'Thank someone whose work usually goes unnoticed'),
    m('sat06', 'mind', 20, 'Sit in silence for 5 minutes'),
    m('sat07', 'body', 30, 'Walk for 15 minutes at a steady pace'),
    m('sat08', 'action', 30, 'Clear one pending thing: a form, a reply or a return'),
    m('sat09', 'action', 30, 'Declutter one drawer or shelf'),
    m('sat10', 'mind', 20, 'Do one thing slowly and properly instead of quickly'),
    m('sat11', 'learn', 40, 'Practise one skill for 15 focused minutes'),
    m('sat12', 'kindness', 30, 'Feed a bird, a cow or a stray animal'),
    m('sat13', 'action', 30, 'Keep one small promise you made to yourself')
  ],
  Rahu: [
    m('rahu01', 'action', 40, 'Try one small thing you have never done before'),
    m('rahu02', 'mind', 30, 'Stay off social media for one full hour'),
    m('rahu03', 'action', 20, 'Take a new route on your walk or commute'),
    m('rahu04', 'learn', 20, 'Learn one new tech trick or app feature'),
    m('rahu05', 'kindness', 30, 'Have a real chat with someone outside your usual circle'),
    m('rahu06', 'mind', 20, 'Write down one big, wild dream. No judging it'),
    m('rahu07', 'action', 30, "Taste a fruit or dish you've never tried"),
    m('rahu08', 'learn', 20, 'Watch a short video on a topic you know nothing about'),
    m('rahu09', 'mind', 30, 'Unfollow 5 accounts that make you feel small'),
    m('rahu10', 'mind', 30, 'Question one habit: do I still need this?'),
    m('rahu11', 'body', 20, 'Take a 10-minute walk without headphones'),
    m('rahu12', 'kindness', 20, 'Greet one person you usually walk past, with a smile')
  ],
  Ketu: [
    m('ketu01', 'kindness', 30, 'Give away one thing you no longer use'),
    m('ketu02', 'mind', 20, 'Sit with your eyes closed for 5 quiet minutes'),
    m('ketu03', 'kindness', 40, 'Do one good deed and tell nobody'),
    m('ketu04', 'action', 20, "Delete 10 things from your phone you don't need"),
    m('ketu05', 'mind', 30, 'Go completely screen-free for 15 minutes'),
    m('ketu06', 'mind', 30, 'Let one small annoyance go today, fully'),
    m('ketu07', 'body', 20, 'Walk barefoot on grass or a clean floor for 5 minutes'),
    m('ketu08', 'mind', 20, 'Light a diya or candle and watch it for 2 minutes'),
    m('ketu09', 'mind', 30, 'Quietly forgive someone today. It can be you'),
    m('ketu10', 'learn', 20, 'Read one page about a saint, sage or philosopher'),
    m('ketu11', 'body', 20, 'Take 10 slow, deep breaths before you sleep'),
    m('ketu12', 'kindness', 30, 'Leave a bowl of water out for birds or street animals')
  ]
};

const MISSION_BY_KEY = {};
for (const p of PLANET_ORDER) for (const x of MISSIONS[p]) MISSION_BY_KEY[x.key] = { ...x, planet: p };

// ---------------------------------------------------------------------------
// "Why" sentences: one plain sentence that names the real driver.
// ---------------------------------------------------------------------------
const TARA_PLAIN = {
  Janma: 'your own birth-star group',
  Sampat: 'the star of plenty',
  Vipat: 'a go-slow star',
  Kshema: 'the star of comfort',
  Pratyari: 'a pick-your-battles star',
  Sadhaka: 'the star of getting things done',
  Vadha: 'a keep-it-simple star',
  Mitra: 'the friendly star',
  'Param Mitra': 'your best-friend star'
};

const WEEKDAY_OF_LORD = { Sun: 'Sunday', Moon: 'Monday', Mars: 'Tuesday', Mercury: 'Wednesday', Jupiter: 'Thursday', Venus: 'Friday', Saturn: 'Saturday' };

/**
 * @param {object} r reason: { type, planet, simple?, tara?, nakshatra?, favorable? }
 * types: transit_tough | transit_good | natal_weak | tara | chandrashtama | day_lord | dasha | antardasha | nak_lord | fallback
 */
function whyLine(r) {
  const lum = r.planet === 'Sun' || r.planet === 'Moon';
  const P = lum ? `the ${r.planet}` : r.planet; // mid-sentence
  const S = lum ? `The ${r.planet}` : r.planet; // sentence start
  switch (r.type) {
    case 'transit_tough':
      return `${r.simple} right now, and a small win like this keeps ${P} on your side.`;
    case 'transit_good':
      return `${r.simple} right now, so this is the perfect day to ride that wave.`;
    case 'natal_weak':
      return `${S} is the quiet one in your birth chart, and small acts like this make it stronger.`;
    case 'chandrashtama':
      return 'The Moon is passing a sensitive spot in your chart today, so something soothing is the smartest move.';
    case 'tara':
      return r.favorable
        ? `Today the Moon is in ${r.tara} Tara for you (${TARA_PLAIN[r.tara] || 'a helpful star'}), so your heart is ready for this.`
        : `Today the Moon is in ${r.tara} Tara for you (${TARA_PLAIN[r.tara] || 'a gentle-day star'}), so a calm, caring act works best.`;
    case 'day_lord':
      return `It's ${WEEKDAY_OF_LORD[r.planet] || 'the day'}, ${P}'s own day of the week, the easiest day to win ${P} over.`;
    case 'dasha':
      return `${S} is running the current big chapter of your life (your dasha), so pleasing ${P} pays off the most right now.`;
    case 'antardasha':
      return `${S} is the co-pilot of your current life chapter (your sub-period), so keeping ${P} happy smooths the ride.`;
    case 'nak_lord':
      return `The Moon is in ${r.nakshatra} today, a star looked after by ${P}, so ${P} is listening closely.`;
    default:
      return `${S} has a soft spot for this today. Give it a go.`;
  }
}

// Plain natal-strength lines (no fear, no jargon)
const DIGNITY_LINE = {
  exalted: (s) => `Exalted in ${s}: a natural gift`,
  moolatrikona: (s) => `At full power in ${s}: a reliable superpower`,
  own: (s) => `At home in ${s}: steady and confident`,
  friend: (s) => `Comfortable in ${s}: among friends`,
  neutral: (s) => `Balanced in ${s}: follows your effort`,
  enemy: (s) => `A little uneasy in ${s}: grows with attention`,
  debilitated: (s) => `Shy in ${s}: your biggest room to grow`
};
const SHADOW_LINE = {
  Rahu: (s, host) => `Shadow planet in ${s}: borrows its style from ${host}`,
  Ketu: (s, host) => `Shadow planet in ${s}: works quietly through ${host}`
};
const RETRO_NOTE = ' (retrograde: works best on second tries)';

// ---------------------------------------------------------------------------
// Player level titles
// ---------------------------------------------------------------------------
const PLAYER_TITLES = [
  [1, 'Star Seeker'],
  [2, 'Sky Watcher'],
  [3, 'Sky Walker'],
  [5, 'Moon Rider'],
  [7, 'Star Weaver'],
  [10, 'Graha Friend'],
  [13, 'Karma Shaper'],
  [17, 'Cosmic Sage'],
  [22, 'Light Bearer'],
  [30, 'Moksha Master']
];
function playerTitle(level) {
  let t = PLAYER_TITLES[0][1];
  for (const [min, name] of PLAYER_TITLES) if (level >= min) t = name;
  return t;
}

// ---------------------------------------------------------------------------
// Nakshatra cards (order matches astrology_service.NAKSHATRAS)
// ruler = Vimshottari lord of the star.
// ---------------------------------------------------------------------------
const n = (name, symbol, ruler, deity, power, keywords) => ({ name, symbol, ruler, deity, power, keywords });
const NAKSHATRA_CARDS = [
  n('Ashwini', '🐎', 'Ketu', 'Ashwini Kumaras', 'The Horse Riders: first off the mark, quick to heal', ['swift', 'healing', 'fresh starts']),
  n('Bharani', '🏺', 'Venus', 'Yama', "The Bearer: carries what others can't", ['courage', 'responsibility', 'transformation']),
  n('Krittika', '🔥', 'Sun', 'Agni', 'The Blade of Fire: cuts straight through the nonsense', ['sharp', 'purifying', 'determined']),
  n('Rohini', '🌹', 'Moon', 'Brahma', 'The Red One: everything grows around you', ['charm', 'growth', 'beauty']),
  n('Mrigashira', '🦌', 'Mars', 'Soma', "The Deer's Head: forever curious, forever searching", ['curious', 'gentle', 'seeking']),
  n('Ardra', '💧', 'Rahu', 'Rudra', 'The Teardrop: after your storm, everything is fresh', ['intense', 'renewal', 'brilliant']),
  n('Punarvasu', '🏹', 'Jupiter', 'Aditi', 'The Returning Light: you always bounce back', ['renewal', 'optimism', 'homecoming']),
  n('Pushya', '🌼', 'Saturn', 'Brihaspati', 'The Nourisher: the most auspicious star of all', ['caring', 'nourishing', 'auspicious']),
  n('Ashlesha', '🐍', 'Mercury', 'Nagas', "The Coiled Serpent: hypnotic, wise, nobody's fool", ['insight', 'mystery', 'intuition']),
  n('Magha', '👑', 'Ketu', 'Pitris (ancestors)', 'The Throne: born to lead', ['royal', 'legacy', 'honour']),
  n('Purva Phalguni', '🛋️', 'Venus', 'Bhaga', 'The Hammock: joy, romance and well-earned rest', ['pleasure', 'creativity', 'charm']),
  n('Uttara Phalguni', '🤝', 'Sun', 'Aryaman', 'The Patron: the friend everyone can count on', ['loyal', 'generous', 'commitment']),
  n('Hasta', '✋', 'Moon', 'Savitar', 'The Hand: whatever you touch takes shape', ['skill', 'craft', 'clever']),
  n('Chitra', '💎', 'Mars', 'Vishwakarma', "The Bright Jewel: the sky's own artist", ['design', 'brilliance', 'style']),
  n('Swati', '🌱', 'Rahu', 'Vayu', 'The Young Shoot: bends with the wind, never breaks', ['independent', 'flexible', 'balanced']),
  n('Vishakha', '🎯', 'Jupiter', 'Indra and Agni', 'The Victory Arch: locks onto a goal and gets there', ['ambition', 'focus', 'determination']),
  n('Anuradha', '🪷', 'Saturn', 'Mitra', 'The Lotus: friendship that blooms anywhere', ['devotion', 'friendship', 'harmony']),
  n('Jyeshtha', '☂️', 'Mercury', 'Indra', 'The Eldest: the protector who takes charge', ['seniority', 'protective', 'capable']),
  n('Moola', '🌿', 'Ketu', 'Nirriti', 'The Root: digs until the truth comes out', ['depth', 'research', 'clean slate']),
  n('Purva Ashadha', '🌊', 'Venus', 'Apas (the waters)', "The Invincible: once you start, you don't lose", ['confidence', 'unbeaten', 'refreshing']),
  n('Uttara Ashadha', '🐘', 'Sun', 'Vishvadevas', 'The Final Victory: slow, right and lasting', ['integrity', 'endurance', 'leadership']),
  n('Shravana', '👂', 'Moon', 'Vishnu', 'The Listener: hears what others miss', ['listening', 'learning', 'connection']),
  n('Dhanishta', '🥁', 'Mars', 'The eight Vasus', 'The Drum: you set the rhythm, others follow', ['rhythm', 'abundance', 'music']),
  n('Shatabhisha', '⭕', 'Rahu', 'Varuna', 'The Hundred Healers: secret keeper and quiet fixer', ['healing', 'independent', 'mysterious']),
  n('Purva Bhadrapada', '⚡', 'Jupiter', 'Aja Ekapada', 'The Fiery Idealist: burns for what truly matters', ['passion', 'vision', 'transformation']),
  n('Uttara Bhadrapada', '🐉', 'Saturn', 'Ahir Budhnya', 'The Serpent of the Deep: calm outside, ocean inside', ['wisdom', 'patience', 'depth']),
  n('Revati', '🐟', 'Mercury', 'Pushan', 'The Guiding Fish: gets everyone home safely', ['kindness', 'safe journeys', 'completion'])
];

const slug = (s) => String(s).toLowerCase().replace(/\(.*?\)/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
const nakCardId = (index) => `nak:${slug(NAKSHATRA_CARDS[index].name)}`;

// Rare cards. Static ones are collectable once; eclipse cards are one per eclipse date.
const RARE_STATIC = {
  'rare:birth_star': { name: 'Birth Star Return', symbol: '🌟', rarity: 'rare', power: 'The Moon is back in your own star: your personal reset day', keywords: ['you', 'reset', 'homecoming'], how: 'Open the app on a day the Moon returns to your birth star (about every 27 days).' },
  'rare:purnima': { name: 'Purnima', symbol: '🌕', rarity: 'rare', power: 'Full Moon night: everything is lit up, including you', keywords: ['fullness', 'gratitude', 'glow'], how: 'Collect on any full-moon day.' },
  'rare:moksha': { name: 'Moksha', symbol: '🕉️', rarity: 'legendary', power: 'You climbed every ladder and outlasted every snake', keywords: ['freedom', 'victory', 'peace'], how: 'Reach square 100 in Moksha Patam.' },
  'rare:streak_7': { name: 'Seven Suns', symbol: '🔥', rarity: 'rare', power: 'Seven days in a row: the planets have noticed', keywords: ['habit', 'momentum', 'week one'], how: 'Reach a 7-day mission streak.' },
  'rare:streak_30': { name: 'One Full Moon Cycle', symbol: '🌗', rarity: 'rare', power: 'Thirty days in a row: a whole lunar month of showing up', keywords: ['discipline', 'rhythm', 'devotion'], how: 'Reach a 30-day mission streak.' },
  'rare:streak_100': { name: 'Hundred Dawns', symbol: '🏆', rarity: 'legendary', power: "A hundred days in a row: Saturn's proudest student", keywords: ['mastery', 'patience', 'legend'], how: 'Reach a 100-day mission streak.' }
};
const STREAK_MILESTONES = [7, 30, 100];

// Festival cards (forecast event titles -> card). Unlisted festivals do not produce cards.
const FESTIVAL_CARDS = {
  'Maha Shivaratri': { id: 'rare:festival_maha_shivaratri', name: 'Maha Shivaratri', symbol: '🔱', power: 'The great night of Shiva: stillness is your superpower', keywords: ['stillness', 'devotion', 'night'] },
  Holi: { id: 'rare:festival_holi', name: 'Holi', symbol: '🎨', power: 'Colours fly, grudges melt', keywords: ['colour', 'play', 'forgiveness'] },
  'Chaitra Navratri / Ugadi / Gudi Padwa': { id: 'rare:festival_new_year', name: 'Ugadi / Gudi Padwa', symbol: '🌾', power: 'A brand-new year, sweet and bitter together', keywords: ['new year', 'hope', 'beginnings'] },
  'Ram Navami': { id: 'rare:festival_ram_navami', name: 'Ram Navami', symbol: '🏹', power: 'The day of the noble hero: do the right thing', keywords: ['dharma', 'courage', 'grace'] },
  'Guru Purnima': { id: 'rare:festival_guru_purnima', name: 'Guru Purnima', symbol: '🙏', power: 'Full Moon of the teachers: say thank you', keywords: ['teachers', 'gratitude', 'learning'] },
  'Raksha Bandhan': { id: 'rare:festival_raksha_bandhan', name: 'Raksha Bandhan', symbol: '🧵', power: 'One thread, one promise: I have your back', keywords: ['siblings', 'protection', 'bond'] },
  'Krishna Janmashtami': { id: 'rare:festival_janmashtami', name: 'Janmashtami', symbol: '🦚', power: 'The midnight birth of joy and mischief', keywords: ['joy', 'play', 'love'] },
  'Ganesh Chaturthi': { id: 'rare:festival_ganesh_chaturthi', name: 'Ganesh Chaturthi', symbol: '🐘', power: 'Obstacles, please step aside', keywords: ['new starts', 'wisdom', 'sweetness'] },
  'Sharad Navratri begins': { id: 'rare:festival_navratri', name: 'Navratri', symbol: '🌺', power: 'Nine nights of Shakti: your inner strength is awake', keywords: ['strength', 'dance', 'devotion'] },
  'Dussehra (Vijayadashami)': { id: 'rare:festival_dussehra', name: 'Dussehra', symbol: '🎇', power: 'Victory day: the good side wins', keywords: ['victory', 'courage', 'new ventures'] },
  'Diwali (Lakshmi Puja)': { id: 'rare:festival_diwali', name: 'Diwali', symbol: '🪔', power: 'A thousand lamps: light wins tonight', keywords: ['light', 'prosperity', 'family'] }
};
const FESTIVAL_CARD_BY_ID = {};
for (const f of Object.values(FESTIVAL_CARDS)) FESTIVAL_CARD_BY_ID[f.id] = f;

function eclipseCardMeta(kind, date) {
  const solar = kind === 'solar';
  return {
    id: `rare:${solar ? 'solar' : 'lunar'}_eclipse_${date}`,
    name: solar ? 'Solar Eclipse' : 'Lunar Eclipse',
    symbol: solar ? '🌑' : '🌘',
    rarity: 'legendary',
    power: solar ? 'The Sun plays hide and seek: a rare day to pause and reset' : 'The Moon wears a shadow: a rare night to let old things go',
    keywords: solar ? ['pause', 'reset', 'rare sky'] : ['release', 'rest', 'rare sky']
  };
}

// Card XP
const CARD_XP = { common: 15, rare: 40, legendary: 75 };

// ---------------------------------------------------------------------------
// Card sets. `row` sets use fixed indices; birth-star sets are resolved per user.
// rewardKind: 'row' | 'full' use the (configurable) wallet reward for registered users, xp otherwise.
// ---------------------------------------------------------------------------
const range = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => a + i);
const CARD_SETS = [
  { id: 'row1', name: "Ashwini's Row (1–9)", indices: () => range(0, 8), rewardKind: 'row', xp: 150 },
  { id: 'row2', name: "Magha's Row (10–18)", indices: () => range(9, 17), rewardKind: 'row', xp: 150 },
  { id: 'row3', name: "Moola's Row (19–27)", indices: () => range(18, 26), rewardKind: 'row', xp: 150 },
  // Janma, Anujanma and Trijanma stars: the 1st, 10th and 19th from the birth star (same ruler)
  { id: 'janma_trio', name: 'Your Birth-Star Trio', indices: (birthNak) => [0, 9, 18].map((d) => (birthNak + d) % 27), rewardKind: 'xp', xp: 100 },
  // The nine stars counted from the birth star: one for each Tara, Janma to Param Mitra
  { id: 'navatara', name: 'Navatara of Your Birth Star', indices: (birthNak) => range(0, 8).map((d) => (birthNak + d) % 27), rewardKind: 'xp', xp: 200 },
  { id: 'full_sky', name: 'The Whole Sky (all 27)', indices: () => range(0, 26), rewardKind: 'full', xp: 500 }
];

// ---------------------------------------------------------------------------
// Moksha Patam board: 100 squares, ladders = virtues, snakes = vices.
// ---------------------------------------------------------------------------
const BOARD = {
  size: 100,
  ladders: [
    { from: 3, to: 21, name: 'Generosity', line: 'You shared without counting. Up you go.' },
    { from: 8, to: 30, name: 'Truth', line: 'You said the honest thing, even though it was hard.' },
    { from: 15, to: 34, name: 'Gratitude', line: 'You said thank you and meant it. The path opens.' },
    { from: 28, to: 49, name: 'Patience', line: 'You waited calmly, and time carried you forward.' },
    { from: 37, to: 60, name: 'Service', line: 'You helped with no reward in mind. Karma took note.' },
    { from: 44, to: 63, name: 'Courage', line: 'You did the scary thing anyway.' },
    { from: 51, to: 74, name: 'Knowledge', line: 'You learned something true, and the fog lifted.' },
    { from: 61, to: 80, name: 'Self-control', line: 'You wanted to react, and you chose not to.' },
    { from: 70, to: 94, name: 'Devotion', line: 'You gave it your whole heart. A shortcut to the top.' }
  ],
  snakes: [
    { from: 18, to: 6, name: 'Gossip', line: 'A little loose talk, and down you slide.' },
    { from: 26, to: 9, name: 'Laziness', line: '"Later" turned into "never". Back you go.' },
    { from: 39, to: 20, name: 'Lies', line: 'A small lie needed a bigger one to hold it up.' },
    { from: 47, to: 25, name: 'Envy', line: "You watched someone else's plate and dropped your own." },
    { from: 55, to: 33, name: 'Attachment', line: 'You held on too tight, and it pulled you back.' },
    { from: 68, to: 46, name: 'Greed', line: 'Enough was not enough. The snake agrees.' },
    { from: 76, to: 53, name: 'Anger', line: 'One hot moment, a long slide down.' },
    { from: 87, to: 64, name: 'Lust for power', line: 'You climbed over others, and the ground gave way.' },
    { from: 93, to: 71, name: 'Pride', line: 'So close to the top that you forgot to look down.' },
    { from: 98, to: 12, name: 'Ego', line: 'The longest snake of all waits right by the finish. Stay humble.' }
  ]
};

// ---------------------------------------------------------------------------
// Luck lines (Tara Bala in plain words)
// ---------------------------------------------------------------------------
const LUCK_LINES = {
  Janma: 'Janma Tara: a day to be gentle with yourself',
  Sampat: 'Sampat Tara: the star of plenty is smiling at you',
  Vipat: 'Vipat Tara: slow and steady wins today',
  Kshema: 'Kshema Tara: a cosy, protected kind of day',
  Pratyari: 'Pratyari Tara: pick your battles and keep it light',
  Sadhaka: 'Sadhaka Tara: what you start today tends to work',
  Vadha: 'Vadha Tara: keep it simple and kind today',
  Mitra: 'Mitra Tara: the sky is on your side',
  'Param Mitra': 'Param Mitra Tara: your best-friend star is shining'
};
const CHANDRASHTAMA_LINE = 'The Moon is resting for you today (Chandrashtama): go easy and keep things simple';

// ---------------------------------------------------------------------------
// Cosmic Match: kootas in plain words + rankings
// ---------------------------------------------------------------------------
const KOOTA_PLAIN = {
  Varna: { strong: 'You respect how each other works', weak: 'Different ideas about work and pride, so swap roles sometimes' },
  Vashya: { strong: 'A natural pull towards each other', weak: 'Neither likes being told what to do, so ask rather than tell' },
  Tara: { strong: 'You bring each other good luck', weak: "Your timing is often off, so plan together and don't assume" },
  Yoni: { strong: 'Instant comfort, like old friends', weak: 'Different instincts, so give each other space' },
  Maitri: { strong: 'Same wavelength: you just get each other', weak: 'You think very differently, so explain a little more' },
  Gana: { strong: 'Matching temperaments make for easy company', weak: 'Different speeds and tempers, so go gently' },
  Bhakoot: { strong: 'Your moods rise and fall together', weak: 'Emotional rhythms differ, so check in often' },
  Nadi: { strong: 'Your energies balance each other', weak: 'Very similar energy, so take turns leading' }
};

const COMPAT_LABELS = [[28, 'Soul-level'], [22, 'Strong'], [17, 'Easy'], [11, 'Spicy'], [-1, 'Opposites']];
function compatLabel(score) {
  for (const [min, label] of COMPAT_LABELS) if (score >= min) return label;
  return 'Opposites';
}
const COMPAT_NOTES = {
  'Soul-level': 'Feels like you have known each other for lifetimes',
  Strong: 'A solid, easy bond',
  Easy: 'Comfortable company',
  Spicy: 'Never boring together',
  Opposites: 'You balance each other out'
};

// kootas: which Ashtakoot parts feed each ranking (scores are direction-averaged)
const RANKINGS = [
  { id: 'cosmicTwin', title: 'Your Cosmic Twin', emoji: '👯', needMembers: 1, kootas: null /* all 8, out of 36 */ },
  { id: 'luckiestToday', title: 'Luckiest Today', emoji: '🍀', needMembers: 1, kootas: null /* today's forecast score */ },
  { id: 'funPartner', title: 'Best Partner in Fun', emoji: '🎉', needMembers: 2, kootas: ['Yoni', 'Gana', 'Vashya'], note: 'Easy laughs and matching energy' },
  { id: 'travelBuddy', title: 'Best Travel Buddy', emoji: '🧳', needMembers: 3, kootas: ['Tara', 'Maitri', 'Vashya'], note: 'Lucky together and easy to plan with' },
  { id: 'businessPartner', title: 'Best Business Partner', emoji: '💼', needMembers: 4, kootas: ['Varna', 'Maitri', 'Bhakoot', 'Tara'], note: 'You think alike and grow together' },
  { id: 'calmingPresence', title: 'Your Calming Presence', emoji: '🕊️', needMembers: 5, kootas: ['Nadi', 'Gana', 'Maitri'], note: 'Being around them settles you' }
];

const MOOD_NOTES = {
  excellent: 'The stars are spoiling them today',
  good: 'A bright, easy day for them',
  mixed: 'A bit of everything today',
  challenging: 'Could use a kind word today'
};

module.exports = {
  PLANET_ORDER,
  CATEGORIES,
  PLANET_CHARACTERS,
  planetTitle,
  MISSIONS,
  MISSION_BY_KEY,
  whyLine,
  TARA_PLAIN,
  DIGNITY_LINE,
  SHADOW_LINE,
  RETRO_NOTE,
  PLAYER_TITLES,
  playerTitle,
  NAKSHATRA_CARDS,
  nakCardId,
  slug,
  RARE_STATIC,
  STREAK_MILESTONES,
  FESTIVAL_CARDS,
  FESTIVAL_CARD_BY_ID,
  eclipseCardMeta,
  CARD_XP,
  CARD_SETS,
  BOARD,
  LUCK_LINES,
  CHANDRASHTAMA_LINE,
  KOOTA_PLAIN,
  compatLabel,
  COMPAT_NOTES,
  RANKINGS,
  MOOD_NOTES
};
