import 'package:flutter/foundation.dart';

/// リモート重み設定取得（互換スタブ）
/// weight_config.dart が `show RemoteWeightSource` で参照する想定のAPIに合わせる
class RemoteWeightSource {
  /// 直近どのソースを使ったか（asset / firestore など）
  static String? lastSource;

  /// 将来的に Firestore/Remote Config 等から取得する想定のスタブ
  static Future<Map<String, dynamic>?> fetchRemoteWeights() async {
    debugPrint('📝 RemoteWeightSource.fetchRemoteWeights(): no-op (stub)');
    return null;
  }
}

/// 既存の参照に備えた別名（必要に応じて使用）
class RemoteWeightConfig {
  static Future<Map<String, dynamic>?> fetch() =>
      RemoteWeightSource.fetchRemoteWeights();
}
