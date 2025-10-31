import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple persistent cache for directions durations (in minutes)
/// Key format suggestion: "dircache:v1:<mode>:<origLat,origLng>><destLat,destLng>"
class DirectionsCache {
  static const _prefix = 'dircache:v1:';
  // Default decimals for coordinate rounding in cache keys (higher = more precise, lower = better hit rate)
  static int defaultCoordDecimals = 3; // ~110m precision

  static String _normalizeKey(String key) =>
      key.startsWith(_prefix) ? key : '$_prefix$key';

  static Future<int?> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_normalizeKey(key));
    if (raw == null) return null;
    try {
      // store either plain minutes or JSON {m:int}
      if (raw.startsWith('{')) {
        final map = json.decode(raw) as Map<String, dynamic>;
        final m = map['m'];
        if (m is num) return m.toInt();
        return null;
      }
      final val = int.tryParse(raw);
      return val;
    } catch (_) {
      return null;
    }
  }

  /// Get cached minutes if not expired by ttl.
  static Future<int?> getWithTTL(String key,
      {Duration ttl = const Duration(hours: 12)}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_normalizeKey(key));
    if (raw == null) return null;
    try {
      if (raw.startsWith('{')) {
        final map = json.decode(raw) as Map<String, dynamic>;
        final m = map['m'];
        final ts = map['ts'];
        if (m is num && ts is num) {
          final savedAt =
              DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: false);
          final isFresh = DateTime.now().difference(savedAt) <= ttl;
          if (isFresh) return m.toInt();
          return null; // expired
        }
      } else {
        // legacy plain data (no ts) -> treat as expired so it will refresh once
        return null;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<void> set(String key, int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    // Store JSON with timestamp for TTL handling
    final payload = json.encode({
      'm': minutes,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(_normalizeKey(key), payload);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  /// Helper to build a normalized cache key with coordinate rounding.
  /// mode: e.g., 'car', 'pt', 'ptdep', 'cardep', 'ptarr', 'cararr'
  static String keyFromCoords({
    required String mode,
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    int? decimals,
  }) {
    final d = decimals ?? defaultCoordDecimals;
    final oLat = originLat.toStringAsFixed(d);
    final oLng = originLng.toStringAsFixed(d);
    final dLat = destLat.toStringAsFixed(d);
    final dLng = destLng.toStringAsFixed(d);
    return '$mode:$oLat,$oLng>$dLat,$dLng';
  }
}
