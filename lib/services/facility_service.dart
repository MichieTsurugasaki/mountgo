import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/facility.dart';

class FacilityService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'facilities';

  /// 特定の山に紐づく施設を全て取得
  static Future<List<Facility>> getFacilitiesByMountainId(
      String mountainId) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('mountainId', isEqualTo: mountainId)
          .orderBy('distanceKm', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => Facility.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Error fetching facilities for mountain $mountainId: $e');
      return [];
    }
  }

  /// 施設を新規作成
  static Future<String?> createFacility(Facility facility) async {
    try {
      final docRef = await _firestore
          .collection(_collectionName)
          .add(facility.toFirestore());
      return docRef.id;
    } catch (e) {
      print('Error creating facility: $e');
      return null;
    }
  }

  /// 施設を更新
  static Future<bool> updateFacility(Facility facility) async {
    try {
      await _firestore
          .collection(_collectionName)
          .doc(facility.id)
          .update(facility.copyWith(updatedAt: DateTime.now()).toFirestore());
      return true;
    } catch (e) {
      print('Error updating facility ${facility.id}: $e');
      return false;
    }
  }

  /// 施設を削除
  static Future<bool> deleteFacility(String facilityId) async {
    try {
      await _firestore.collection(_collectionName).doc(facilityId).delete();
      return true;
    } catch (e) {
      print('Error deleting facility $facilityId: $e');
      return false;
    }
  }

  /// リアルタイム更新を監視（Stream）
  static Stream<List<Facility>> streamFacilitiesByMountainId(
      String mountainId) {
    return _firestore
        .collection(_collectionName)
        .where('mountainId', isEqualTo: mountainId)
        .orderBy('distanceKm', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Facility.fromFirestore(doc.data(), doc.id))
            .toList());
  }
}
