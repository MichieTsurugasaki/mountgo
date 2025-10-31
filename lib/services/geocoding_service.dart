import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeocodingService {
  /// Google Maps Geocoding API を使って逆ジオコーディングします。
  /// 成功時は「渋谷区」などの短い地名を返し、失敗時は null。
  static Future<String?> reverseGeocode(double lat, double lng,
      {bool detailed = false}) async {
    // 優先: GOOGLE_MAPS_API_KEY, 代替: GEOCODING_API_KEY
    final apiKey =
        dotenv.env['GOOGLE_MAPS_API_KEY'] ?? dotenv.env['GEOCODING_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('GeocodingService: API key not set');
      return null;
    }

    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=$lat,$lng&language=ja&key=$apiKey',
    );

    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        debugPrint('GeocodingService: HTTP ${res.statusCode}');
        return null;
      }
      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['status'] != 'OK' || (data['results'] as List).isEmpty) {
        debugPrint('GeocodingService: status=${data['status']}');
        return null;
      }
      final results = data['results'] as List<dynamic>;

      // 詳細モード: 町名・番地まで含めた住所を返す
      if (detailed && results.isNotEmpty) {
        // デバッグ: レスポンス全体をログ出力
        debugPrint(
            'GeocodingService: Full response: ${json.encode(results.first)}');

        // formatted_addressをそのまま使用（最も正確な住所表記）
        final firstResult = results.first as Map<String, dynamic>;
        final formatted = firstResult['formatted_address'] as String?;

        if (formatted != null && formatted.isNotEmpty) {
          // 「日本、〒xxx-xxxx 」などの不要なプレフィックスを除去
          String cleaned = formatted;

          // 「日本、」を除去
          if (cleaned.startsWith('日本、')) {
            cleaned = cleaned.substring(3);
          }

          // 郵便番号パターン「〒xxx-xxxx 」を除去
          final postalPattern = RegExp(r'^〒?\d{3}-?\d{4}\s*');
          cleaned = cleaned.replaceFirst(postalPattern, '');

          // 末尾の空白を除去
          cleaned = cleaned.trim();

          debugPrint('GeocodingService: Cleaned address: $cleaned');
          return cleaned;
        }

        // フォールバック: 住所コンポーネントから構築
        final comps = (firstResult['address_components'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

        // 都道府県、市区町村、町名、番地を取得
        String? prefecture;
        String? city;
        String? ward;
        final List<String> sublocalities = [];
        String? premise;

        for (final c in comps) {
          final types = (c['types'] as List).cast<String>();
          final longName = c['long_name'] as String?;

          if (longName == null || longName.isEmpty) continue;

          if (types.contains('administrative_area_level_1')) {
            prefecture = longName;
          } else if (types.contains('locality')) {
            city = longName;
          } else if (types.contains('ward')) {
            ward = longName;
          } else if (types.contains('sublocality_level_1')) {
            sublocalities.insert(0, longName); // 優先度高
          } else if (types.contains('sublocality_level_2')) {
            if (sublocalities.length < 2) sublocalities.add(longName);
          } else if (types.contains('sublocality_level_3')) {
            if (sublocalities.length < 3) sublocalities.add(longName);
          } else if (types.contains('sublocality_level_4')) {
            if (sublocalities.length < 4) sublocalities.add(longName);
          } else if (types.contains('premise')) {
            premise = longName;
          }
        }

        // 詳細住所を構築
        final parts = <String>[];
        if (prefecture != null) parts.add(prefecture);
        if (city != null) parts.add(city);
        if (ward != null) parts.add(ward);
        parts.addAll(sublocalities);
        if (premise != null) parts.add(premise);

        if (parts.isNotEmpty) {
          final result = parts.join('');
          debugPrint('GeocodingService: Component-based address: $result');
          return result;
        }
      }

      // 短い名前を優先: locality -> sublocality_level_1 -> administrative_area_level_2
      String? pickShortName(Map<String, dynamic> result) {
        final comps = (result['address_components'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        String? findByType(String type) {
          for (final c in comps) {
            final types = (c['types'] as List).cast<String>();
            if (types.contains(type)) return c['long_name'] as String?;
          }
          return null;
        }

        return findByType('locality') ??
            findByType('sublocality_level_1') ??
            findByType('administrative_area_level_2');
      }

      // 最初に短い名称を探す
      for (final r in results) {
        final name = pickShortName((r as Map<String, dynamic>));
        if (name != null && name.isNotEmpty) return name;
      }

      // フォールバック: formatted_address を短縮
      final formatted = results.first['formatted_address'] as String?;
      if (formatted == null || formatted.isEmpty) return null;
      // 「日本、東京都渋谷区…」のような文を区切って短めに
      final parts = formatted.split('、');
      if (parts.length >= 2) {
        // 2番目以降に市区町村が入ることが多い
        return parts[1].split(' ').first;
      }
      return formatted;
    } catch (e, st) {
      debugPrint('GeocodingService: error $e\n$st');
      return null;
    }
  }
}
