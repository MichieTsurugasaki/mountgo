import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'api_service.dart';

/// 🏔 ChatService
/// - Firestore にチャット履歴を保存
/// - Gemini（またはAPI）からAI応答を取得（ストリーミング対応）
/// - 山ごと（mountainId単位）に履歴を管理
class ChatService {
  /// 🧭 メッセージをリアルタイム購読（DetailPageで使用）
  static Stream<QuerySnapshot<Map<String, dynamic>>> getMessages(
      String mountainId) {
    return FirebaseFirestore.instance
        .collection("mountain_chats")
        .doc(mountainId)
        .collection("messages")
        .orderBy("createdAt", descending: false)
        .snapshots();
  }

  /// 💾 Firestore にメッセージを単独保存
  /// （AI応答やユーザー発言の両方で使用可能）
  static Future<void> saveMessage({
    required String mountainId,
    required String role,
    required String text,
  }) async {
    await FirebaseFirestore.instance
        .collection("mountain_chats")
        .doc(mountainId)
        .collection("messages")
        .add({
      "role": role,
      "text": text,
      "createdAt": FieldValue.serverTimestamp(),
    });

    debugPrint("💬 ChatService.saveMessage(): $role / $text");
  }

  /// 🤖 ユーザー発言 → AI応答まで自動処理（ストリーミング付き）
  static Future<void> sendAndReply({
    required String mountainId,
    required String userText,
    required String departureLabel,
    Map<String, dynamic>? searchContext,
    void Function(String delta)? onStream, // ストリーミング差分
  }) async {
    // ① Firestoreにユーザー発言を保存
    await saveMessage(
      mountainId: mountainId,
      role: "user",
      text: userText,
    );

    // ② AI用プロンプトを構築（強化版）
    final mountain = searchContext?['mountain'] as Map<String, dynamic>?;
    final mountainName = mountain?['name'] ?? '';
    final mountainPref = mountain?['pref'] ?? '';
    final plannedDate = searchContext?['plannedDate'] as String?;
    final weather = searchContext?['weather'] as Map<String, dynamic>?;

    final systemPrompt = '''
あなたは「晴れ山SEARCH AIマウンテンコンシェルジュ」です。
安全第一で、季節・天候・難易度・アクセスを考慮した山旅満喫プランを日本語で提案します。

【選択された山】
${mountainName.isNotEmpty ? '・山名: $mountainName' : ''}
${mountainPref.isNotEmpty ? '・都道府県: $mountainPref' : ''}

【条件】
- 出発地: $departureLabel
${plannedDate != null ? '- 登山予定日: $plannedDate' : ''}
${weather != null ? '- 天気予報: 降水確率${weather['rain_am'] ?? '不明'}(午前), ${weather['rain_pm'] ?? '不明'}(午後), 気温${weather['temp_c'] ?? '不明'}°C' : ''}

【検索条件】
${_formatSearchContext(searchContext)}

【回答スタイル】
- タイムライン形式で具体的に（例：05:30 出発 → 08:00 登山口到着 → ...）
- 箇条書き中心で読みやすく
- 安全上の注意点を必ず含める
- 絵文字を適度に使用して親しみやすく
''';

    // ③ Gemini（またはAPI）呼び出し（ストリーミング対応）
    final buffer = StringBuffer();
    try {
      await for (final delta in ApiService.streamGemini(
        systemPrompt: systemPrompt,
        userMessage: userText,
        context: searchContext,
      )) {
        buffer.write(delta);
        if (onStream != null) onStream(delta);
      }
    } catch (e) {
      buffer.write('\n⚠️ エラー: ${e.toString()}');
    }

    // ④ AI応答を Firestore に保存
    final aiText = buffer.toString().trim();
    if (aiText.isEmpty) return;

    await saveMessage(
      mountainId: mountainId,
      role: "assistant",
      text: aiText,
    );

    debugPrint("✅ ChatService.sendAndReply 完了: $mountainId");
  }

  /// 検索条件をフォーマットして文字列に変換
  static String _formatSearchContext(Map<String, dynamic>? context) {
    if (context == null) return '指定なし';

    final parts = <String>[];

    if (context['selectedLevel'] != null) {
      parts.add('難易度: ${context['selectedLevel']}');
    }
    if (context['selectedAccessTime'] != null) {
      parts.add('アクセス時間: ${context['selectedAccessTime']}');
    }
    if (context['selectedCourseTime'] != null) {
      parts.add('コースタイム: ${context['selectedCourseTime']}');
    }
    if (context['selectedStyles'] != null &&
        context['selectedStyles'] is List) {
      final styles = (context['selectedStyles'] as List).join('、');
      if (styles.isNotEmpty) parts.add('スタイル: $styles');
    }
    if (context['selectedPurposes'] != null &&
        context['selectedPurposes'] is List) {
      final purposes = (context['selectedPurposes'] as List).join('、');
      if (purposes.isNotEmpty) parts.add('目的: $purposes');
    }

    return parts.isEmpty ? '指定なし' : parts.map((p) => '・$p').join('\n');
  }
}
