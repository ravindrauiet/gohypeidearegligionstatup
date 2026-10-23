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

enum PromoMediaType { image, video }

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

  final PromoAction action;

  const HomePromo.image(
    this.source, {
    this.title,
    this.subtitle,
    this.cta,
    this.sponsored = false,
    required this.action,
  })  : type = PromoMediaType.image,
        poster = null;

  const HomePromo.video(
    this.source, {
    this.poster,
    this.title,
    this.subtitle,
    this.cta,
    this.sponsored = false,
    required this.action,
  }) : type = PromoMediaType.video;
}

/// Slides shown on Home, in order.
const List<HomePromo> kHomePromos = [
  HomePromo.image(
    'assets/images/astrology-hero.jpg',
    title: 'Ask the AI astrologer',
    subtitle: 'Answers read from your own Kundli, any time',
    cta: 'Start chat',
    action: PromoAiChat(),
  ),
  HomePromo.image(
    'assets/images/topic_birth_chart.jpg',
    title: 'Your full life report',
    subtitle: 'Personality, career, marriage and your running dasha',
    cta: 'Read report',
    action: PromoKundliReport(),
  ),
  HomePromo.image(
    'assets/images/topic_love_compatibility.jpg',
    title: 'Check your match',
    subtitle: 'Compare two charts with Guna Milan',
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
