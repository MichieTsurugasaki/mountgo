import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'remote_weight_config.dart' show RemoteWeightSource;

/// スコアリング時に利用する重み定義
class Weights {
  final int bonusPreferTag; // 温泉/山小屋/テント/郷土料理/ロープウェイ/ケーブルカーなどのタグ加点
  final int bonusPreferPT; // 公共交通機関の加点
  final int bonusStyleStrong; // スタイル（稜線/岩場/鎖場など）強い加点
  final int bonusStyleSoft; // スタイル（自然/絶景など）緩やかな加点

  const Weights({
    required this.bonusPreferTag,
    required this.bonusPreferPT,
    required this.bonusStyleStrong,
    required this.bonusStyleSoft,
  });

  static const Weights _defaults = Weights(
    bonusPreferTag: 10,
    bonusPreferPT: 8,
    bonusStyleStrong: 12,
    bonusStyleSoft: 6,
  );

  static Weights defaults() => _defaults;

  factory Weights.fromMap(Map<String, dynamic> m) {
    int parseInt(String k, int d) {
      final v = m[k];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? d;
      return d;
    }

    return Weights(
      bonusPreferTag: parseInt('bonusPreferTag', _defaults.bonusPreferTag),
      bonusPreferPT: parseInt('bonusPreferPT', _defaults.bonusPreferPT),
      bonusStyleStrong:
          parseInt('bonusStyleStrong', _defaults.bonusStyleStrong),
      bonusStyleSoft: parseInt('bonusStyleSoft', _defaults.bonusStyleSoft),
    );
  }

  Map<String, dynamic> toJson() => {
        'bonusPreferTag': bonusPreferTag,
        'bonusPreferPT': bonusPreferPT,
        'bonusStyleStrong': bonusStyleStrong,
        'bonusStyleSoft': bonusStyleSoft,
      };
}

/// 重み設定のロード
class WeightConfig {
  static Weights? _cached;

  /// ロード順序：
  /// 1) RemoteWeightSource.fetchRemoteWeights()（存在すれば）
  /// 2) assets/config/weights.json（存在すれば）
  /// 3) Weights.defaults()
  static Future<Weights> load() async {
    if (_cached != null) return _cached!;

    try {
      final remote = await RemoteWeightSource.fetchRemoteWeights();
      if (remote != null) {
        _cached = Weights.fromMap(remote);
        RemoteWeightSource.lastSource = 'remote';
        return _cached!;
      }
    } catch (e) {
      debugPrint('⚠️ Remote weights not available: $e');
    }

    try {
      final bytes = await rootBundle.load('assets/config/weights.json');
      final jsonStr = utf8.decode(bytes.buffer.asUint8List());
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      _cached = Weights.fromMap(map);
      RemoteWeightSource.lastSource = 'asset';
      return _cached!;
    } catch (e) {
      debugPrint('⚠️ Asset weights not available: $e');
    }

    _cached = Weights.defaults();
    RemoteWeightSource.lastSource = 'default';
    return _cached!;
  }
}
