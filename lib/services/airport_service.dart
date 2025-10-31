import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'travel_config.dart';

class Airport {
  final String code;
  final String name;
  final double lat;
  final double lng;
  final String type; // legacy: 'major' | 'regional' | ''
  final String category; // new: 'major' | 'regional' | ''
  final int dailyFlights; // approximate frequency if known
  const Airport({
    required this.code,
    required this.name,
    required this.lat,
    required this.lng,
    this.type = '',
    this.category = '',
    this.dailyFlights = 0,
  });
  // Major definition: explicit category/type OR hub codes OR frequency threshold
  bool get isMajor {
    final hubCodes = AirportService.majorHubCodes;
    if (category == 'major' || type == 'major') return true;
    if (hubCodes.contains(code.toUpperCase())) return true;
    return dailyFlights >= 100;
  }
}

class AirportService {
  static List<Airport>? _cache;
  static Map<String, Map<String, dynamic>>? _meta;
  static Set<String> _majorHubs = {
    'HND',
    'NRT',
    'KIX',
    'ITM',
    'CTS',
    'NGO',
    'FUK',
    'OKA',
    'UKB'
  };
  static Set<String> get majorHubCodes => _majorHubs;

  static Future<List<Airport>> _loadAirports() async {
    if (_cache != null) return _cache!;
    // Load configurable major hubs once
    try {
      final tc = await TravelConfig.load();
      _majorHubs = tc.majorHubCodes.map((e) => e.toUpperCase()).toSet();
    } catch (_) {}
    final jsonStr =
        await rootBundle.loadString('assets/config/airports_jp.json');
    final List list = json.decode(jsonStr) as List;
    // メタ情報の読み込み（任意）
    try {
      final metaStr =
          await rootBundle.loadString('assets/config/airports_meta.json');
      final List metaList = json.decode(metaStr) as List;
      _meta = {
        for (final m in metaList)
          (m['code'] ?? '').toString(): Map<String, dynamic>.from(m as Map)
      };
    } catch (_) {
      _meta = {};
    }

    _cache = list.map((e) {
      final code = (e['code'] ?? '').toString();
      final m = _meta?[code] ?? const {};
      return Airport(
        code: code,
        name: (e['name'] ?? '').toString(),
        lat: (e['lat'] as num).toDouble(),
        lng: (e['lng'] as num).toDouble(),
        type: (m['type'] ?? '').toString(),
        category: (m['category'] ?? m['type'] ?? '').toString(),
        dailyFlights:
            (m['dailyFlights'] is num) ? (m['dailyFlights'] as num).toInt() : 0,
      );
    }).toList();
    return _cache!;
  }

  static Future<Airport?> nearestAirport(double lat, double lng) async {
    final airports = await _loadAirports();
    Airport? best;
    double bestKm = double.infinity;
    for (final a in airports) {
      final d = _distanceKm(lat, lng, a.lat, a.lng);
      if (d < bestKm) {
        bestKm = d;
        best = a;
      }
    }
    return best;
  }

  /// 主要空港を優先して選択するスマート版。
  /// - 最寄りが地方空港で、主要空港が「最寄り＋toleranceKm」以内なら主要を採用。
  static Future<Airport?> nearestAirportSmart(double lat, double lng,
      {double toleranceKm = 50.0}) async {
    final airports = await _loadAirports();
    Airport? nearest;
    double nearestKm = double.infinity;
    Airport? nearestMajor;
    double nearestMajorKm = double.infinity;
    for (final a in airports) {
      final d = _distanceKm(lat, lng, a.lat, a.lng);
      if (d < nearestKm) {
        nearestKm = d;
        nearest = a;
      }
      if (a.isMajor && d < nearestMajorKm) {
        nearestMajorKm = d;
        nearestMajor = a;
      }
    }
    if (nearest == null) return null;
    if (nearest.isMajor) return nearest;
    if (nearestMajor != null && nearestMajorKm <= (nearestKm + toleranceKm)) {
      return nearestMajor;
    }
    return nearest;
  }

  static double _distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);
}

class FlightEstimator {
  // シンプル推定: 750km/h としてフライト時間を算出し、地上手続きのバッファを加算
  static int estimateFlightMinutes(
      double depLat, double depLng, double arrLat, double arrLng) {
    final km = AirportService._distanceKm(depLat, depLng, arrLat, arrLng);
    final flightMin = (km / 750.0 * 60.0);
    // 事前90分 + 到着後30分 に加え、ユーザー要望により待機時間として +60分 追加
    const prepost = 90 + 30 + 60; // 合計: 180分
    return (prepost + flightMin).round();
  }

  /// 強化版: 距離・時間帯・週末係数などの簡易補正を加味
  /// - 長距離補正: >1200km +45分, >1800km +60分（上位を優先）
  /// - 時間帯補正: 朝夕ピーク(7-9,17-20) +20分
  /// - 週末補正: 土日 +10分
  static Future<int> estimateFlightMinutesEnhanced(
    double depLat,
    double depLng,
    double arrLat,
    double arrLng, {
    DateTime? when,
  }) async {
    final km = AirportService._distanceKm(depLat, depLng, arrLat, arrLng);
    final base = estimateFlightMinutes(depLat, depLng, arrLat, arrLng);
    int extra = 0;
    final tc = await TravelConfig.load();
    if (km > 1800) {
      extra += 60;
    } else if (km > 1200) {
      extra += 45;
    }
    final t = when ?? DateTime.now();
    final h = t.hour;
    if ((h >= 7 && h <= 9) || (h >= 17 && h <= 20)) {
      extra += 20;
    }
    if (t.weekday == DateTime.saturday || t.weekday == DateTime.sunday) {
      extra += 10;
    }
    // 便数/空港タイプ・乗継回数による簡易補正
    try {
      final depA = await AirportService.nearestAirportSmart(depLat, depLng);
      final arrA = await AirportService.nearestAirportSmart(arrLat, arrLng);
      if (depA != null && arrA != null) {
        // Frequency penalties
        final lowFreqDep = (depA.dailyFlights > 0 &&
            depA.dailyFlights < tc.lowFrequencyThreshold);
        final lowFreqArr = (arrA.dailyFlights > 0 &&
            arrA.dailyFlights < tc.lowFrequencyThreshold);
        if (lowFreqDep) extra += tc.lowFrequencyPenaltyPerSide;
        if (lowFreqArr) extra += tc.lowFrequencyPenaltyPerSide;
        if (lowFreqDep && lowFreqArr)
          extra += tc.bothLowFrequencyExtra; // both sides low frequency

        // Major/regional handling overhead
        if (!depA.isMajor) extra += tc.nonMajorPenaltyPerSide;
        if (!arrA.isMajor) extra += tc.nonMajorPenaltyPerSide;

        // Expected transfers heuristic
        int transfers = 0;
        final bothMajor = depA.isMajor && arrA.isMajor;
        final oneMajor =
            (depA.isMajor && !arrA.isMajor) || (!depA.isMajor && arrA.isMajor);
        final bothRegional = !depA.isMajor && !arrA.isMajor;
        if (bothMajor) {
          transfers = 0; // direct likely
        } else if (oneMajor) {
          transfers = km > tc.oneMajorTransferKm
              ? 1
              : 0; // sometimes direct, long distance needs a hop
        } else if (bothRegional) {
          if (km > tc.regionalLongTwoTransfersKm)
            transfers = 2; // regional → hub → hub → regional
          else if (km > tc.regionalHopThresholdKm)
            transfers = 1;
          else
            transfers = 1; // even short regional may need at least one hop
        }
        extra += transfers * tc.perTransferMinutes;
      }
    } catch (_) {}
    return base + extra;
  }
}
