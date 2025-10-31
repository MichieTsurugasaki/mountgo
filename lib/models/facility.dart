class Facility {
  final String id; // Firestore document ID
  final String mountainId; // 山のID（外部キー）
  final String type; // 'トイレ'|'山小屋'|'お店'
  final String name;
  final double? distanceKm; // 登山口からの距離（km）
  final int? elevationM;
  final double? lat;
  final double? lng;
  final String openSeason; // 例: "通年" / "4-11" / "5-10月"
  final bool winterClosed; // トイレ向け: 冬季凍結で閉鎖される可能性
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Facility({
    required this.id,
    required this.mountainId,
    required this.type,
    required this.name,
    this.distanceKm,
    this.elevationM,
    this.lat,
    this.lng,
    this.openSeason = '',
    this.winterClosed = false,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Firestore → Dart
  factory Facility.fromFirestore(Map<String, dynamic> data, String docId) {
    return Facility(
      id: docId,
      mountainId: data['mountainId'] ?? '',
      type: data['type'] ?? 'トイレ',
      name: data['name'] ?? '',
      distanceKm: (data['distanceKm'] as num?)?.toDouble(),
      elevationM: data['elevationM'] as int?,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      openSeason: data['openSeason'] ?? '',
      winterClosed: data['winterClosed'] ?? false,
      notes: data['notes'] ?? '',
      createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
    );
  }

  // Dart → Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'mountainId': mountainId,
      'type': type,
      'name': name,
      'distanceKm': distanceKm,
      'elevationM': elevationM,
      'lat': lat,
      'lng': lng,
      'openSeason': openSeason,
      'winterClosed': winterClosed,
      'notes': notes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  Facility copyWith({
    String? id,
    String? mountainId,
    String? type,
    String? name,
    double? distanceKm,
    int? elevationM,
    double? lat,
    double? lng,
    String? openSeason,
    bool? winterClosed,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Facility(
      id: id ?? this.id,
      mountainId: mountainId ?? this.mountainId,
      type: type ?? this.type,
      name: name ?? this.name,
      distanceKm: distanceKm ?? this.distanceKm,
      elevationM: elevationM ?? this.elevationM,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      openSeason: openSeason ?? this.openSeason,
      winterClosed: winterClosed ?? this.winterClosed,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
