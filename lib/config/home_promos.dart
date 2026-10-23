// ============================================================================
// Home screen ad / promo slot (the carousel just below the search bar).
//
// To place an ad, add a `HomePromo` to `kHomePromos`. Each slide can be an
// image or a video, from the app bundle (`assets/...`, also list the folder in
// pubspec.yaml) or from the internet (`https://...`).
//
// Creative size: 2:1 landscape, e.g. 1200 x 600 px images or 1280 x 640 video
// (MP4 / H.264, under ~5 MB, 5 to 20 seconds). Keep important content in the
// left two thirds when you also set a title, because the text sits there.
//
// Videos play muted (viewers can unmute), only while the slide is on screen,
// and fall back to `poster` (or a dark card) if they cannot load.
// ============================================================================

// A third kind, `HomePromo.card`, needs no artwork: the app draws a bright
// gradient card with your text on the left and a framed picture on the right.

enum PromoMediaType { image, video, card }

/// What happens when a promo is tapped.
sealed class PromoAction {
  const PromoAction();
}

/// Opens a named route from `AppRoutes`, e.g. `PromoRoute('/panchang')`.
class PromoRoute extends PromoAction {
  final String name;
  final Object? arguments;
  const PromoRoute(this.name, [this.arguments]);
}

/// Switches the bottom tab: 0 Home, 1 Kundli, 2 More, 3 Ask Astro, 4 Love.
class PromoTab extends PromoAction {
  final int index;
  const PromoTab(this.index);
}

/// Opens a web page / Play Store link / WhatsApp link outside the app.
class PromoLink extends PromoAction {
  final String url;
  const PromoLink(this.url);
}

/// Opens the AI astrologer chat.
class PromoAiChat extends PromoAction {
  const PromoAiChat();
}

/// Opens the Kundli life report.
class PromoKundliReport extends PromoAction {
  const PromoKundliReport();
}

class HomePromo {
  final PromoMediaType type;

  /// `assets/images/x.jpg`, `assets/videos/x.mp4` or an `https://` URL.
  final String source;

  /// Still image shown while a video loads or if it fails. Optional.
  final String? poster;

  /// Overlay text. Leave all three null for a creative that has its own text.
  final String? title;
  final String? subtitle;
  final String? cta;

  /// Shows a small "Ad" label, for paid placements from other brands.
  final bool sponsored;

  /// Card only: gradient colours (ARGB, e.g. 0xFFFF8A2B), top-left to bottom-right.
  final List<int>? gradient;

  /// Card only: a small label above the title, e.g. "FREE" or "NEW".
  final String? eyebrow;

  final PromoAction action;

  const HomePromo.image(
    this.source, {
    this.title,
    this.subtitle,
    this.cta,
    this.sponsored = false,
    required this.action,
  })  : type = PromoMediaType.image,
        poster = null,
        gradient = null,
        eyebrow = null;

  const HomePromo.video(
    this.source, {
    this.poster,
    this.title,
    this.subtitle,
    this.cta,
    this.sponsored = false,
    required this.action,
  })  : type = PromoMediaType.video,
        gradient = null,
        eyebrow = null;

  /// A designed card: [source] is the picture shown on the right (asset or URL).
  const HomePromo.card(
    this.source, {
    required String this.title,
    this.subtitle,
    this.cta,
    this.eyebrow,
    required List<int> this.gradient,
    this.sponsored = false,
    required this.action,
  })  : type = PromoMediaType.card,
        poster = null;
}

/// Slides shown on Home, in order.
const List<HomePromo> kHomePromos = [
  HomePromo.card(
    'assets/images/astrologers/rishi_anand.jpg',
    eyebrow: 'FREE · 24/7',
    gradient: [0xFFFFA24C, 0xFFFF6A13, 0xFFD9480F],
    title: 'Ask the AI astrologer',
    subtitle: 'Answers from your own Kundli',
    cta: 'Start chat',
    action: PromoAiChat(),
  ),
  HomePromo.card(
    'assets/images/topic_birth_chart.jpg',
    eyebrow: 'NEW',
    gradient: [0xFF7B6CFF, 0xFF4F46E5, 0xFF2E2275],
    title: 'Your full life report',
    subtitle: 'Career, marriage and your running dasha',
    cta: 'Read report',
    action: PromoKundliReport(),
  ),
  HomePromo.card(
    'assets/images/topic_love_compatibility.jpg',
    eyebrow: '36 GUNAS',
    gradient: [0xFFFF8FB1, 0xFFE8457A, 0xFFB8285B],
    title: 'Check your match',
    subtitle: 'Guna Milan for any two charts',
    cta: 'Match now',
    action: PromoTab(4),
  ),

  // Examples (uncomment and replace with your own creative):
  //
  // HomePromo.video(
  //   'https://your-cdn.com/ads/diwali-puja.mp4',
  //   poster: 'assets/images/diwali_lakshmi_puja.jpg',
  //   title: 'Diwali Lakshmi Puja',
  //   subtitle: 'Book a live puja with a verified pandit',
  //   cta: 'Book now',
  //   action: PromoTab(3),
  // ),
  // HomePromo.image(
  //   'https://your-cdn.com/ads/partner-banner.jpg',
  //   sponsored: true,
  //   action: PromoLink('https://partner.example.com'),
  // ),
];
