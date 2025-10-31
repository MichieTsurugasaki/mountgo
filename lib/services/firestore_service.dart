import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 🗻 FirestoreService
/// - AIプラン・履歴・その他データ管理を担当
class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  /// 💾 登山プランを保存
  /// - mountainName, departure, timestamp などを含む Map を渡す
  static Future<void> savePlan(Map<String, dynamic> planData) async {
    try {
      await _db.collection('plans').add({
        ...planData,
        "createdAt": FieldValue.serverTimestamp(),
      });
      debugPrint("✅ FirestoreService.savePlan(): 登山プランを保存しました");
    } catch (e) {
      debugPrint("🔥 FirestoreService.savePlan() エラー: $e");
    }
  }

  /// 📖 特定ユーザーの保存済みプランを取得（降順）
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamUserPlans(
      String userId) {
    return _db
        .collection('plans')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// 📦 履歴削除
  static Future<void> deletePlan(String planId) async {
    try {
      await _db.collection('plans').doc(planId).delete();
      debugPrint("🗑 FirestoreService.deletePlan(): $planId を削除しました");
    } catch (e) {
      debugPrint("🔥 FirestoreService.deletePlan() エラー: $e");
    }
  }

  /// 🏔 mountains コレクションから候補を取得
  static Future<List<Map<String, dynamic>>> listMountains(
      {int limit = 50}) async {
    try {
      final qs = await _db.collection('mountains').limit(limit).get();
      return qs.docs
          .map((d) => {
                'id': d.id,
                ...d.data(),
              })
          .toList();
    } catch (e) {
      debugPrint("🔥 FirestoreService.listMountains() エラー: $e");
      return [];
    }
  }

  /// 🏷 指定タグ（tags 配列に含まれる）の山を取得
  /// - 例: tag = '日本二百名山'
  static Future<List<Map<String, dynamic>>> listMountainsByTag(
      {required String tag, int limit = 200}) async {
    try {
      final qs = await _db
          .collection('mountains')
          .where('tags', arrayContains: tag)
          .limit(limit)
          .get();
      return qs.docs
          .map((d) => {
                'id': d.id,
                ...d.data(),
              })
          .toList();
    } catch (e) {
      debugPrint("🔥 FirestoreService.listMountainsByTag($tag) エラー: $e");
      return [];
    }
  }

  /// Save a user-added spot under a mountain document.
  /// mountainId can be the document id or the mountain name; if an id-like value is provided it will be used as doc id.
  static Future<void> saveUserSpot(
      {required String mountainId, required Map<String, dynamic> spot}) async {
    try {
      final coll =
          _db.collection('mountains').doc(mountainId).collection('user_spots');
      await coll.add({
        ...spot,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
          '✅ FirestoreService.saveUserSpot(): saved spot for $mountainId');
    } catch (e) {
      debugPrint('🔥 FirestoreService.saveUserSpot() error: $e');
    }
  }
}
