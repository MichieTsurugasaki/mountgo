import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

class PlaceSuggestion {
  final String description;
  final String placeId;
  const PlaceSuggestion({required this.description, required this.placeId});
}

class PlaceDetail {
  final double lat;
  final double lng;
  final String? name;
  const PlaceDetail({required this.lat, required this.lng, this.name});
}

class PlacesService {
  static String? get _apiKey =>
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? dotenv.env['GEOCODING_API_KEY'];

  static bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  static Future<List<PlaceSuggestion>> autocomplete(String input) async {
    if (kIsWeb) {
      debugPrint('PlacesService.autocomplete: skip HTTP call on Web');
      return [];
    }
    if (_apiKey == null || _apiKey!.isEmpty) return [];
    if (input.trim().length < 2) return [];
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(input)}&language=ja&region=jp&components=country:jp&key=${_apiKey!}',
    );
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return [];
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        debugPrint('PlacesService.autocomplete status=${data['status']}');
        return [];
      }
      final preds = (data['predictions'] as List).cast<Map<String, dynamic>>();
      return preds
          .map((p) => PlaceSuggestion(
                description: p['description'] as String,
                placeId: p['place_id'] as String,
              ))
          .toList();
    } catch (e, st) {
      debugPrint('PlacesService.autocomplete error: $e\n$st');
      return [];
    }
  }

  static Future<PlaceDetail?> fetchPlaceDetail(String placeId) async {
    if (kIsWeb) {
      debugPrint('PlacesService.details: skip HTTP call on Web');
      return null;
    }
    if (_apiKey == null || _apiKey!.isEmpty) return null;
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId&fields=geometry/location,name&language=ja&key=${_apiKey!}',
    );
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        debugPrint('PlacesService.details status=${data['status']}');
        return null;
      }
      final result = data['result'] as Map<String, dynamic>;
      final loc = (result['geometry'] as Map<String, dynamic>)['location']
          as Map<String, dynamic>;
      return PlaceDetail(
        lat: (loc['lat'] as num).toDouble(),
        lng: (loc['lng'] as num).toDouble(),
        name: result['name'] as String?,
      );
    } catch (e, st) {
      debugPrint('PlacesService.details error: $e\n$st');
      return null;
    }
  }

  /// 温泉・食事系スポットを周辺から検索し、評価や距離でソートして返す
  static Future<List<Map<String, dynamic>>> nearbyOnsenAndFoodWeighted(
    double lat,
    double lng, {
    int radiusMeters = 15000,
    String sort = 'rating', // or 'distance'
  }) async {
    if (kIsWeb) {
      debugPrint('PlacesService.nearby: skip HTTP call on Web');
      return [];
    }
    if (!isConfigured) return [];

    Future<List<Map<String, dynamic>>> query(String keyword) async {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
        '&radius=$radiusMeters'
        '&language=ja&keyword=${Uri.encodeComponent(keyword)}'
        '&key=${_apiKey!}',
      );
      try {
        final res = await http.get(uri);
        if (res.statusCode != 200) return [];
        final data = json.decode(res.body) as Map<String, dynamic>;
        final results =
            (data['results'] as List?)?.cast<Map<String, dynamic>>() ??
                const [];
        return results.map((r) {
          final loc = (r['geometry']?['location'] as Map?) ?? const {};
          final plat = (loc['lat'] as num?)?.toDouble();
          final plng = (loc['lng'] as num?)?.toDouble();
          final distanceKm = (plat != null && plng != null)
              ? _distanceKm(lat, lng, plat, plng)
              : null;
          final name = (r['name'] ?? '').toString();
          final rating =
              (r['rating'] is num) ? (r['rating'] as num).toDouble() : null;
          final types =
              ((r['types'] as List?)?.map((e) => e.toString()).toList()) ??
                  const [];
          final desc = types.isNotEmpty ? types.first : '';
          return {
            'place_id': r['place_id'],
            'name': name,
            'rating': rating,
            'distanceKm': distanceKm,
            'url':
                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}',
            'desc': desc,
          };
        }).toList();
      } catch (e) {
        debugPrint('PlacesService.nearby query failed: $e');
        return [];
      }
    }

    final onsen = await query('温泉');
    final food = await query('郷土料理');
    final combined = <String, Map<String, dynamic>>{};
    for (final e in [...onsen, ...food]) {
      final id = (e['place_id'] ?? '') as String;
      if (id.isEmpty) continue;
      combined[id] = e;
    }
    var list = combined.values.toList();
    list.removeWhere((e) => (e['name'] as String).isEmpty);

    if (sort == 'distance') {
      list.sort((a, b) {
        final da = (a['distanceKm'] as num?)?.toDouble() ?? double.infinity;
        final db = (b['distanceKm'] as num?)?.toDouble() ?? double.infinity;
        return da.compareTo(db);
      });
    } else {
      list.sort((a, b) {
        final ra = (a['rating'] as num?)?.toDouble() ?? -1;
        final rb = (b['rating'] as num?)?.toDouble() ?? -1;
        // rating 降順、距離昇順の複合
        final r = rb.compareTo(ra);
        if (r != 0) return r;
        final da = (a['distanceKm'] as num?)?.toDouble() ?? double.infinity;
        final db = (b['distanceKm'] as num?)?.toDouble() ?? double.infinity;
        return da.compareTo(db);
      });
    }
    // 上位15件程度に抑制
    return list.take(15).toList();
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
