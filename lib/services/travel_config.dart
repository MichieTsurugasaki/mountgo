import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class TravelConfig {
  final int directionsCoordDecimals;
  // Flight penalties/thresholds
  final int perTransferMinutes;
  final int lowFrequencyThreshold; // flights/day
  final int lowFrequencyPenaltyPerSide;
  final int bothLowFrequencyExtra;
  final int nonMajorPenaltyPerSide;
  final int regionalHopThresholdKm; // regional-regional single hop from
  final int oneMajorTransferKm; // one-major scenarios
  final int regionalLongTwoTransfersKm; // regional-regional 2 hops from
  final List<String> majorHubCodes;

  const TravelConfig({
    required this.directionsCoordDecimals,
    required this.perTransferMinutes,
    required this.lowFrequencyThreshold,
    required this.lowFrequencyPenaltyPerSide,
    required this.bothLowFrequencyExtra,
    required this.nonMajorPenaltyPerSide,
    required this.regionalHopThresholdKm,
    required this.oneMajorTransferKm,
    required this.regionalLongTwoTransfersKm,
    required this.majorHubCodes,
  });

  static TravelConfig? _cache;

  static TravelConfig defaults() => const TravelConfig(
        directionsCoordDecimals: 3,
        perTransferMinutes: 40,
        lowFrequencyThreshold: 30,
        lowFrequencyPenaltyPerSide: 10,
        bothLowFrequencyExtra: 10,
        nonMajorPenaltyPerSide: 10,
        regionalHopThresholdKm: 400,
        oneMajorTransferKm: 600,
        regionalLongTwoTransfersKm: 1200,
        majorHubCodes: [
          'HND',
          'NRT',
          'KIX',
          'ITM',
          'CTS',
          'NGO',
          'FUK',
          'OKA',
          'UKB'
        ],
      );

  static Future<TravelConfig> load() async {
    if (_cache != null) return _cache!;
    try {
      final str =
          await rootBundle.loadString('assets/config/travel_config.json');
      final Map<String, dynamic> m = json.decode(str) as Map<String, dynamic>;
      final dir = m['directions'] as Map<String, dynamic>? ?? const {};
      final fl = m['flight'] as Map<String, dynamic>? ?? const {};
      _cache = TravelConfig(
        directionsCoordDecimals: (dir['coordDecimals'] is num)
            ? (dir['coordDecimals'] as num).toInt()
            : defaults().directionsCoordDecimals,
        perTransferMinutes: (fl['perTransferMinutes'] is num)
            ? (fl['perTransferMinutes'] as num).toInt()
            : defaults().perTransferMinutes,
        lowFrequencyThreshold: (fl['lowFrequencyThreshold'] is num)
            ? (fl['lowFrequencyThreshold'] as num).toInt()
            : defaults().lowFrequencyThreshold,
        lowFrequencyPenaltyPerSide: (fl['lowFrequencyPenaltyPerSide'] is num)
            ? (fl['lowFrequencyPenaltyPerSide'] as num).toInt()
            : defaults().lowFrequencyPenaltyPerSide,
        bothLowFrequencyExtra: (fl['bothLowFrequencyExtra'] is num)
            ? (fl['bothLowFrequencyExtra'] as num).toInt()
            : defaults().bothLowFrequencyExtra,
        nonMajorPenaltyPerSide: (fl['nonMajorPenaltyPerSide'] is num)
            ? (fl['nonMajorPenaltyPerSide'] as num).toInt()
            : defaults().nonMajorPenaltyPerSide,
        regionalHopThresholdKm: (fl['regionalHopThresholdKm'] is num)
            ? (fl['regionalHopThresholdKm'] as num).toInt()
            : defaults().regionalHopThresholdKm,
        oneMajorTransferKm: (fl['oneMajorTransferKm'] is num)
            ? (fl['oneMajorTransferKm'] as num).toInt()
            : defaults().oneMajorTransferKm,
        regionalLongTwoTransfersKm: (fl['regionalLongTwoTransfersKm'] is num)
            ? (fl['regionalLongTwoTransfersKm'] as num).toInt()
            : defaults().regionalLongTwoTransfersKm,
        majorHubCodes: (fl['majorHubCodes'] is List)
            ? (fl['majorHubCodes'] as List)
                .map((e) => e.toString().toUpperCase())
                .toList()
            : defaults().majorHubCodes,
      );
    } catch (_) {
      _cache = defaults();
    }
    return _cache!;
  }
}
