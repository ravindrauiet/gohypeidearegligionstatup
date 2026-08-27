class HoroscopeModel {
  final String id;
  final String zodiacSign;
  final DateTime date;
  final String overview;
  final String love;
  final String career;
  final String health;
  final String finance;
  final String luckyColor;
  final String luckyNumber;
  final String luckyDay;
  final String mood;
  final int compatibilityScore;
  final List<String> bestCompatibleSigns;
  final List<String> recommendations;
  final String spiritualGuidance;
  final Map<String, dynamic> planetaryPositions;
  final DateTime createdAt;
  final DateTime updatedAt;

  HoroscopeModel({
    required this.id,
    required this.zodiacSign,
    required this.date,
    required this.overview,
    required this.love,
    required this.career,
    required this.health,
    required this.finance,
    required this.luckyColor,
    required this.luckyNumber,
    required this.luckyDay,
    required this.mood,
    required this.compatibilityScore,
    required this.bestCompatibleSigns,
    required this.recommendations,
    required this.spiritualGuidance,
    required this.planetaryPositions,
    required this.createdAt,
    required this.updatedAt,
  });

  factory HoroscopeModel.fromMap(Map<String, dynamic> map) {
    return HoroscopeModel(
      id: map['id'] ?? '',
      zodiacSign: map['zodiacSign'] ?? '',
      date: map['date'] is DateTime ? map['date'] : DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
      overview: map['overview'] ?? '',
      love: map['love'] ?? '',
      career: map['career'] ?? '',
      health: map['health'] ?? '',
      finance: map['finance'] ?? '',
      luckyColor: map['luckyColor'] ?? '',
      luckyNumber: map['luckyNumber'] ?? '',
      luckyDay: map['luckyDay'] ?? '',
      mood: map['mood'] ?? '',
      compatibilityScore: map['compatibilityScore'] ?? 0,
      bestCompatibleSigns: List<String>.from(map['bestCompatibleSigns'] ?? []),
      recommendations: List<String>.from(map['recommendations'] ?? []),
      spiritualGuidance: map['spiritualGuidance'] ?? '',
      planetaryPositions: Map<String, dynamic>.from(map['planetaryPositions'] ?? {}),
      createdAt: map['createdAt'] is DateTime ? map['createdAt'] : DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: map['updatedAt'] is DateTime ? map['updatedAt'] : DateTime.parse(map['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'zodiacSign': zodiacSign,
      'date': date.toIso8601String(),
      'overview': overview,
      'love': love,
      'career': career,
      'health': health,
      'finance': finance,
      'luckyColor': luckyColor,
      'luckyNumber': luckyNumber,
      'luckyDay': luckyDay,
      'mood': mood,
      'compatibilityScore': compatibilityScore,
      'bestCompatibleSigns': bestCompatibleSigns,
      'recommendations': recommendations,
      'spiritualGuidance': spiritualGuidance,
      'planetaryPositions': planetaryPositions,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  HoroscopeModel copyWith({
    String? id,
    String? zodiacSign,
    DateTime? date,
    String? overview,
    String? love,
    String? career,
    String? health,
    String? finance,
    String? luckyColor,
    String? luckyNumber,
    String? luckyDay,
    String? mood,
    int? compatibilityScore,
    List<String>? bestCompatibleSigns,
    List<String>? recommendations,
    String? spiritualGuidance,
    Map<String, dynamic>? planetaryPositions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HoroscopeModel(
      id: id ?? this.id,
      zodiacSign: zodiacSign ?? this.zodiacSign,
      date: date ?? this.date,
      overview: overview ?? this.overview,
      love: love ?? this.love,
      career: career ?? this.career,
      health: health ?? this.health,
      finance: finance ?? this.finance,
      luckyColor: luckyColor ?? this.luckyColor,
      luckyNumber: luckyNumber ?? this.luckyNumber,
      luckyDay: luckyDay ?? this.luckyDay,
      mood: mood ?? this.mood,
      compatibilityScore: compatibilityScore ?? this.compatibilityScore,
      bestCompatibleSigns: bestCompatibleSigns ?? this.bestCompatibleSigns,
      recommendations: recommendations ?? this.recommendations,
      spiritualGuidance: spiritualGuidance ?? this.spiritualGuidance,
      planetaryPositions: planetaryPositions ?? this.planetaryPositions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class BirthChartModel {
  final String id;
  final String userId;
  final String name;
  final DateTime birthDate;
  final String? birthTime;
  final String birthPlace;
  final Map<String, dynamic> planetaryPositions;
  final Map<String, dynamic> houses;
  final Map<String, dynamic> aspects;
  final String sunSign;
  final String moonSign;
  final String risingSign;
  final String? nakshatra;
  final String? lagna;
  final bool isManglik;
  final String manglikStatus;
  final Map<String, dynamic> personalityTraits;
  final List<String> strengths;
  final List<String> challenges;
  final Map<String, dynamic> compatibility;
  final List<String> careerSuggestions;
  final List<String> relationshipInsights;
  final String lifePath;
  final Map<String, dynamic> spiritualGuidance;
  final String? currentDasha;
  final String? dashaAnalysis;
  final String? careerAnalysis;
  final String? wealthAnalysis;
  final String? marriageAnalysis;
  final String? healthAnalysis;
  final Map<String, String>? housePlacements;
  final Map<String, dynamic>? detailedPlanetaryPositions;
  final Map<String, dynamic>? ascendantDetails;
  final String? summary;
  final DateTime createdAt;
  final DateTime updatedAt;

  BirthChartModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.birthDate,
    this.birthTime,
    required this.birthPlace,
    required this.planetaryPositions,
    required this.houses,
    required this.aspects,
    required this.sunSign,
    required this.moonSign,
    required this.risingSign,
    this.nakshatra,
    this.lagna,
    this.isManglik = false,
    this.manglikStatus = 'Not Manglik',
    required this.personalityTraits,
    required this.strengths,
    required this.challenges,
    required this.compatibility,
    required this.careerSuggestions,
    required this.relationshipInsights,
    required this.lifePath,
    required this.spiritualGuidance,
    this.currentDasha,
    this.dashaAnalysis,
    this.careerAnalysis,
    this.wealthAnalysis,
    this.marriageAnalysis,
    this.healthAnalysis,
    this.housePlacements,
    this.detailedPlanetaryPositions,
    this.ascendantDetails,
    this.summary,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BirthChartModel.fromMap(Map<String, dynamic> map) {
    Map<String, String>? housePlacements;
    if (map['housePlacements'] is Map) {
      housePlacements = {};
      (map['housePlacements'] as Map).forEach((key, value) {
        housePlacements![key.toString()] = value.toString();
      });
    }
    
    return BirthChartModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      birthDate: map['birthDate'] is DateTime ? map['birthDate'] : DateTime.parse(map['birthDate'] ?? DateTime.now().toIso8601String()),
      birthTime: map['birthTime'],
      birthPlace: map['birthPlace'] ?? '',
      planetaryPositions: Map<String, dynamic>.from(map['planetaryPositions'] ?? {}),
      houses: Map<String, dynamic>.from(map['houses'] ?? {}),
      aspects: Map<String, dynamic>.from(map['aspects'] ?? {}),
      sunSign: map['sunSign'] ?? '',
      moonSign: map['moonSign'] ?? '',
      risingSign: map['risingSign'] ?? '',
      nakshatra: map['nakshatra'],
      lagna: map['lagna'],
      isManglik: map['isManglik'] ?? false,
      manglikStatus: map['manglikStatus'] ?? 'Not Manglik',
      personalityTraits: Map<String, dynamic>.from(map['personalityTraits'] ?? {}),
      strengths: List<String>.from(map['strengths'] ?? []),
      challenges: List<String>.from(map['challenges'] ?? []),
      compatibility: Map<String, dynamic>.from(map['compatibility'] ?? {}),
      careerSuggestions: List<String>.from(map['careerSuggestions'] ?? []),
      relationshipInsights: List<String>.from(map['relationshipInsights'] ?? []),
      lifePath: map['lifePath'] ?? '',
      spiritualGuidance: Map<String, dynamic>.from(map['spiritualGuidance'] ?? {}),
      currentDasha: map['currentDasha'],
      dashaAnalysis: map['dashaAnalysis'],
      careerAnalysis: map['careerAnalysis'],
      wealthAnalysis: map['wealthAnalysis'],
      marriageAnalysis: map['marriageAnalysis'],
      healthAnalysis: map['healthAnalysis'],
      housePlacements: housePlacements,
      detailedPlanetaryPositions: map['detailedPlanetaryPositions'] != null ? Map<String, dynamic>.from(map['detailedPlanetaryPositions']) : null,
      ascendantDetails: map['ascendantDetails'] != null ? Map<String, dynamic>.from(map['ascendantDetails']) : null,
      summary: map['summary'],
      createdAt: map['createdAt'] is DateTime ? map['createdAt'] : DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: map['updatedAt'] is DateTime ? map['updatedAt'] : DateTime.parse(map['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'birthDate': birthDate.toIso8601String(),
      'birthTime': birthTime,
      'birthPlace': birthPlace,
      'planetaryPositions': planetaryPositions,
      'houses': houses,
      'aspects': aspects,
      'sunSign': sunSign,
      'moonSign': moonSign,
      'risingSign': risingSign,
      'nakshatra': nakshatra,
      'lagna': lagna,
      'isManglik': isManglik,
      'manglikStatus': manglikStatus,
      'personalityTraits': personalityTraits,
      'strengths': strengths,
      'challenges': challenges,
      'compatibility': compatibility,
      'careerSuggestions': careerSuggestions,
      'relationshipInsights': relationshipInsights,
      'lifePath': lifePath,
      'spiritualGuidance': spiritualGuidance,
      'currentDasha': currentDasha,
      'dashaAnalysis': dashaAnalysis,
      'careerAnalysis': careerAnalysis,
      'wealthAnalysis': wealthAnalysis,
      'marriageAnalysis': marriageAnalysis,
      'healthAnalysis': healthAnalysis,
      'housePlacements': housePlacements,
      'detailedPlanetaryPositions': detailedPlanetaryPositions,
      'ascendantDetails': ascendantDetails,
      'summary': summary,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class AIConsultationModel {
  final String id;
  final String userId;
  final String question;
  final String answer;
  final String category;
  final Map<String, dynamic> context;
  final List<String> recommendations;
  final String followUpQuestion;
  final DateTime createdAt;
  final bool isResolved;

  AIConsultationModel({
    required this.id,
    required this.userId,
    required this.question,
    required this.answer,
    required this.category,
    required this.context,
    required this.recommendations,
    required this.followUpQuestion,
    required this.createdAt,
    this.isResolved = false,
  });

  factory AIConsultationModel.fromMap(Map<String, dynamic> map) {
    return AIConsultationModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      question: map['question'] ?? '',
      answer: map['answer'] ?? '',
      category: map['category'] ?? '',
      context: Map<String, dynamic>.from(map['context'] ?? {}),
      recommendations: List<String>.from(map['recommendations'] ?? []),
      followUpQuestion: map['followUpQuestion'] ?? '',
      createdAt: map['createdAt'] is DateTime ? map['createdAt'] : DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      isResolved: map['isResolved'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'question': question,
      'answer': answer,
      'category': category,
      'context': context,
      'recommendations': recommendations,
      'followUpQuestion': followUpQuestion,
      'createdAt': createdAt.toIso8601String(),
      'isResolved': isResolved,
    };
  }
}
