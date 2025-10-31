import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// 位置情報ユーティリティ（非推奨APIを使用しない実装）
class LocationService {
  /// 位置情報の権限を確認し、必要ならリクエスト
  static Future<bool> ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('📍 Location permission denied forever.');
      return false;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('📍 Location service disabled.');
      return false;
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// 現在地を取得（LocationSettings を使用）
  static Future<Position> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration? timeLimit,
  }) async {
    final ok = await ensurePermission();
    if (!ok) {
      throw Exception('Location permission not granted or service disabled');
    }

    final settings = LocationSettings(
      accuracy: accuracy,
      timeLimit: timeLimit,
    );
    return Geolocator.getCurrentPosition(locationSettings: settings);
  }
}
