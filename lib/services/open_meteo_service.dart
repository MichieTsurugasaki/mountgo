import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:yamabiyori_flutter/utils/logger.dart';
import 'package:http/http.dart' as http;

/// Minimal Open-Meteo adapter used by Result/Detail pages.
/// This is a lightweight stub that returns reasonable defaults so the app
/// and tests can run without network calls.
class OpenMeteoService {
  /// Tests can set this to true to avoid real network calls.
  static bool forceStub = false;
  static Duration httpTimeout = const Duration(seconds: 6);

  /// Returns a simple daily forecast list for [days].
  /// Each entry contains keys compatible with the app's usage.
  static Future<List<Map<String, dynamic>>> fetchDaily(
    double lat,
    double lng, {
    int days = 7,
  }) async {
    if (forceStub) {
      Log.v('🔧 [OpenMeteo] forceStub=true, using stub data');
      return _stubDaily(lat, lng, days: days);
    }
    // Web環境の場合、実際のAPIデータを使用（CORSは問題なし）
    if (kIsWeb) {
      Log.v('🌐 [OpenMeteo] Running on Web, attempting real API call');
    }
    // Real API call with safe defaults and graceful fallback to stub.
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(6),
      'longitude': lng.toStringAsFixed(6),
      'daily': [
        'weathercode',
        'precipitation_sum',
        'precipitation_hours',
        'rain_sum',
        'snowfall_sum',
        'precipitation_probability_max',
        'windspeed_10m_max',
        'cloudcover_mean',
        'temperature_2m_max',
      ].join(','),
      'timezone': 'auto',
      'forecast_days': days.toString(),
    });
    try {
      Log.v('🌐 [OpenMeteo] Fetching daily weather: $uri');
      final res = await http.get(uri).timeout(httpTimeout);
      Log.v('🌐 [OpenMeteo] Response status: ${res.statusCode}');
      if (res.statusCode != 200) {
        debugPrint('⚠️ [OpenMeteo] Non-200 status, falling back to stub');
        return _stubDaily(lat, lng, days: days);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final daily = body['daily'] as Map<String, dynamic>?;
      if (daily == null) return _stubDaily(lat, lng, days: days);

      List<T?> listOf<T>(String key) {
        final v = daily[key];
        if (v is List) {
          return v.map<T?>((e) => e as T?).toList();
        }
        return const [];
      }

      final times = listOf<String>('time');
      final wcode = listOf<num>('weathercode');
      final precipSum = listOf<num>('precipitation_sum');
      final precipHours = listOf<num>('precipitation_hours');
      final rainSum = listOf<num>('rain_sum');
      final snowSum = listOf<num>('snowfall_sum');
      final popMax = listOf<num>('precipitation_probability_max');
      final windKmh = listOf<num>('windspeed_10m_max');
      final cloud = listOf<num>('cloudcover_mean');
      final tempMax = listOf<num>('temperature_2m_max');

      final len = [
        times.length,
        wcode.length,
        precipSum.length,
        popMax.length,
        windKmh.length,
        cloud.length,
        tempMax.length,
      ].where((e) => e > 0).fold<int>(0, (p, e) => p == 0 ? e : min(p, e));
      if (len == 0) return _stubDaily(lat, lng, days: days);

      final result = List.generate(len, (i) {
        final dateStr = times[i] ?? DateTime.now().toIso8601String();
        final dt = DateTime.tryParse(dateStr) ?? DateTime.now();
        final kmh = (windKmh[i] ?? 0).toDouble();
        final ms = kmh / 3.6;
        final double pSum = (precipSum[i] ?? 0).toDouble();
        final double rSum = (i < rainSum.length && rainSum[i] != null)
            ? (rainSum[i] ?? 0).toDouble()
            : 0.0;
        final double sSum = (i < snowSum.length && snowSum[i] != null)
            ? (snowSum[i] ?? 0).toDouble()
            : 0.0;
        final double combinedPrecip = _mergePrecipSources(pSum, rSum, sSum);
        final num? rawPop = (i < popMax.length) ? popMax[i] : null;
        double probability;
        final double popVal = (rawPop?.toDouble() ?? -1);
        if (popVal > 0) {
          probability = (popVal.clamp(0.0, 100.0)) / 100.0;
        } else {
          // 原始popがnullまたは0の場合のフォールバック
          final double hours =
              (i < precipHours.length && precipHours[i] != null)
                  ? (precipHours[i] ?? 0).toDouble()
                  : 0.0;
          if (hours > 0) {
            probability = (hours / 24.0).clamp(0.0, 1.0);
            // 少量の降水でも時間が長ければそれなりに確率を表す
          } else {
            probability = _normalizeProbability(null, combinedPrecip,
                fallbackFactor: 20.0, maxPercent: 90.0);
          }
        }
        return {
          'date': dt,
          'weathercode': (wcode[i] ?? 0).toInt(),
          'cloud_pct': (cloud[i] ?? 0).toDouble(),
          'wind_m_s': ms,
          'pop': probability,
          'temp_c': (tempMax[i] ?? 0).toDouble(),
          'precip_mm': combinedPrecip,
        };
      });
      Log.v('✅ [OpenMeteo] Successfully parsed $len days of weather data');
      return result;
    } catch (e) {
      debugPrint(
          '❌ [OpenMeteo] Exception during fetch: $e, falling back to stub');
      return _stubDaily(lat, lng, days: days);
    }
  }

  /// Picks the entry closest to [targetDate] (by day). If absent, returns
  /// the first entry.
  static Map<String, dynamic>? chooseBestOrDate(
    List<Map<String, dynamic>> daily, {
    DateTime? targetDate,
    DateTime? target,
  }) {
    if (daily.isEmpty) return null;
    final effectiveTarget = targetDate ?? target;
    if (effectiveTarget == null) return daily.first;
    final tgt = DateTime(
        effectiveTarget.year, effectiveTarget.month, effectiveTarget.day);
    Map<String, dynamic>? best;
    int bestDiff = 1 << 30;
    for (final d in daily) {
      final dt = d['date'] as DateTime?;
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      final diff = (day.difference(tgt).inDays).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = d;
      }
    }
    return best ?? daily.first;
  }

  /// Simple emoji mapping for weather codes used in the UI.
  static String emojiFromWeatherCode(int code) {
    if (code == 0) return '☀️';
    if (code < 20) return '🌤️';
    if (code < 30) return '⛅️';
    if (code < 40) return '☁️';
    if (code < 60) return '🌧️';
    return '🌦️';
  }

  /// Fetch hourly forecast and normalize to app-friendly structure.
  /// Returns a list of hourly maps with keys similar to daily:
  /// time(DateTime), weathercode, cloud_pct, wind_m_s, pop, temp_c, precip_mm
  static Future<List<Map<String, dynamic>>> fetchHourly(
    double lat,
    double lng, {
    int hours = 24,
    DateTime? day,
  }) async {
    if (forceStub) {
      return _stubHourly(lat, lng, hours: hours, day: day);
    }

    // Request up to 48 hours then trim to [hours]
    final want = hours.clamp(1, 48);
    final params = <String, String>{
      'latitude': lat.toStringAsFixed(6),
      'longitude': lng.toStringAsFixed(6),
      'hourly': [
        'weathercode',
        'precipitation_probability',
        'windspeed_10m',
        'cloudcover',
        'temperature_2m',
        'precipitation',
      ].join(','),
      'timezone': 'auto',
    };
    if (day != null) {
      final y = day.year.toString().padLeft(4, '0');
      final m = day.month.toString().padLeft(2, '0');
      final d = day.day.toString().padLeft(2, '0');
      final dateStr = '$y-$m-$d';
      params['start_date'] = dateStr;
      params['end_date'] = dateStr;
    } else {
      params['forecast_days'] = '2';
    }
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', params);

    try {
      final res = await http.get(uri).timeout(httpTimeout);
      if (res.statusCode != 200) {
        return _stubHourly(lat, lng, hours: want, day: day);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final hourly = body['hourly'] as Map<String, dynamic>?;
      if (hourly == null) return _stubHourly(lat, lng, hours: want, day: day);

      List<T?> listOf<T>(String key) {
        final v = hourly[key];
        if (v is List) return v.map<T?>((e) => e as T?).toList();
        return const [];
      }

      final times = listOf<String>('time');
      final wcode = listOf<num>('weathercode');
      final pop = listOf<num>('precipitation_probability');
      final windKmh = listOf<num>('windspeed_10m');
      final cloud = listOf<num>('cloudcover');
      final temp = listOf<num>('temperature_2m');
      final precip = listOf<num>('precipitation');
      final rain = listOf<num>('rain');
      final snowfall = listOf<num>('snowfall');

      final len = [
        times.length,
        wcode.length,
        pop.length,
        windKmh.length,
        cloud.length,
        temp.length,
        precip.length,
        rain.length,
        snowfall.length,
      ]
          .where((e) => e > 0)
          .fold<int>(0, (p, e) => p == 0 ? e : (e < p ? e : p));
      if (len == 0) return _stubHourly(lat, lng, hours: want, day: day);

      final list = List.generate(len, (i) {
        final dateStr = times[i] ?? DateTime.now().toIso8601String();
        final dt = DateTime.tryParse(dateStr) ?? DateTime.now();
        final kmh = (windKmh[i] ?? 0).toDouble();
        final ms = kmh / 3.6;
        final double precipMm = (precip[i] ?? 0).toDouble();
        final double rainMm = (i < rain.length && rain[i] != null)
            ? (rain[i] ?? 0).toDouble()
            : 0.0;
        final double snowMm = (i < snowfall.length && snowfall[i] != null)
            ? (snowfall[i] ?? 0).toDouble()
            : 0.0;
        final double combinedPrecip =
            _mergePrecipSources(precipMm, rainMm, snowMm);
        final num? rawPop = (i < pop.length) ? pop[i] : null;
        final double probability =
            _normalizeProbability(rawPop, combinedPrecip, fallbackFactor: 32.0);
        return {
          'time': dt,
          'weathercode': (wcode[i] ?? 0).toInt(),
          'cloud_pct': (cloud[i] ?? 0).toDouble(),
          'wind_m_s': ms,
          'pop': probability,
          'temp_c': (temp[i] ?? 0).toDouble(),
          'precip_mm': combinedPrecip,
        };
      });
      // If a specific day was requested, API already returns that day. Still trim to want.
      return list.take(want).toList();
    } catch (_) {
      return _stubHourly(lat, lng, hours: want, day: day);
    }
  }

  static double _mergePrecipSources(
      double precipMm, double rainMm, double snowMm) {
    final components =
        [precipMm, rainMm, snowMm].where((v) => v.isFinite && v > 0).toList();
    if (components.isEmpty) {
      return 0.0;
    }
    // Open-Meteo sometimes folds rain/snow into precipitation, so prefer the largest bucket
    return components.reduce((a, b) => a > b ? a : b);
  }

  static double _normalizeProbability(num? rawPercent, double precipMm,
      {double fallbackFactor = 25.0, double maxPercent = 90.0}) {
    if (rawPercent != null) {
      final double fraction = (rawPercent.toDouble().clamp(0.0, 100.0)) / 100.0;
      return fraction.clamp(0.0, 1.0);
    }
    if (precipMm <= 0) {
      return 0.0;
    }
    final double approx = min(precipMm * fallbackFactor, maxPercent);
    return (approx / 100.0).clamp(0.0, 1.0);
  }

  // ---- Internal stub ----
  static List<Map<String, dynamic>> _stubDaily(double lat, double lng,
      {int days = 7}) {
    final now = DateTime.now();
    final rnd = Random(lat.hashCode ^ lng.hashCode);
    return List.generate(days, (i) {
      final date =
          DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final weathercode = rnd.nextInt(4) * 10;
      final cloud = rnd.nextInt(60) + 10; // 10-70%
      final wind = (rnd.nextDouble() * 6) + 1; // 1-7 m/s
      final pop = (rnd.nextDouble() * 0.6); // 0-0.6
      final temp = 12 + rnd.nextInt(14); // 12-25°C
      final precip = pop > 0.4 ? rnd.nextDouble() * 5.0 : 0.0;
      return {
        'date': date,
        'weathercode': weathercode,
        'cloud_pct': cloud.toDouble(),
        'wind_m_s': wind,
        'pop': pop,
        'temp_c': temp.toDouble(),
        'precip_mm': precip,
      };
    });
  }

  static List<Map<String, dynamic>> _stubHourly(double lat, double lng,
      {int hours = 24, DateTime? day}) {
    final base = day ?? DateTime.now();
    final start = DateTime(base.year, base.month, base.day, 0);
    final rnd = Random(lat.hashCode ^ lng.hashCode ^ start.day);
    return List.generate(hours, (i) {
      final dt = start.add(Duration(hours: i));
      final weathercode = rnd.nextInt(4) * 10;
      final cloud = rnd.nextInt(60) + 10;
      final wind = (rnd.nextDouble() * 6) + 1;
      final pop = (rnd.nextDouble() * 0.6);
      final temp = 10 + rnd.nextInt(15);
      final precip = pop > 0.5 ? rnd.nextDouble() * 2.0 : 0.0;
      return {
        'time': dt,
        'weathercode': weathercode,
        'cloud_pct': cloud.toDouble(),
        'wind_m_s': wind,
        'pop': pop,
        'temp_c': temp.toDouble(),
        'precip_mm': precip,
      };
    });
  }
}
