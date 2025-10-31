import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class DirectionsService {
  static String? get _apiKey =>
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? dotenv.env['GEOCODING_API_KEY'];

  static bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  static Future<int?> drivingMinutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    return _fetchDurationMinutes(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      mode: 'driving',
    );
  }

  static Future<int?> transitMinutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    return _fetchDurationMinutes(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      mode: 'transit',
    );
  }

  static Future<int?> _fetchDurationMinutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String mode,
  }) async {
    // Flutter Web 環境では Google Maps Web Services を直接叩くと
    // CORS/Referer 制約で失敗しやすいため、安全にスキップする
    if (kIsWeb) {
      debugPrint('DirectionsService: skip HTTP call on Web (mode=$mode)');
      return null;
    }
    if (!isConfigured) return null;
    final origin =
        '${originLat.toStringAsFixed(6)},${originLng.toStringAsFixed(6)}';
    final dest = '${destLat.toStringAsFixed(6)},${destLng.toStringAsFixed(6)}';
    final params = <String, String>{
      'origin': origin,
      'destination': dest,
      'mode': mode,
      // 出発時刻: now（transit は必須）
      'departure_time':
          (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      'language': 'ja',
      'region': 'jp',
      'key': _apiKey!,
    };
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/directions/json', params);
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        debugPrint(
            'DirectionsService $_apiKey status=${data['status']} msg=${data['error_message']}');
        return null;
      }
      final routes = (data['routes'] as List).cast<Map<String, dynamic>>();
      if (routes.isEmpty) return null;
      final legs = (routes.first['legs'] as List).cast<Map<String, dynamic>>();
      if (legs.isEmpty) return null;
      final dur = (legs.first['duration_in_traffic'] ?? legs.first['duration'])
          as Map<String, dynamic>;
      final seconds = (dur['value'] as num).toInt();
      return (seconds / 60).round();
    } catch (e, st) {
      debugPrint('DirectionsService error: $e\n$st');
      return null;
    }
  }
}
