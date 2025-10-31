import 'api_service.dart';

class MountainInfoAIService {
  /// DBに説明がなければAIで簡潔な紹介文を生成する（200〜400字程度）
  static Future<String?> getOrGenerateDescription(
      Map<String, dynamic> m) async {
    try {
      final existing = (m['description'] ?? '').toString().trim();
      if (existing.isNotEmpty) return existing;

      final name = (m['name'] ?? '').toString();
      final pref = (m['pref'] ?? '').toString();
      final height = (m['height'] ?? m['altitude'] ?? '').toString();
      final course = (m['course'] ?? m['popularRoute'] ?? '').toString();

      final system = 'あなたは山の紹介文を書くアシスタントです。日本語で、200〜400字、前向きで安全配慮のある文体でまとめます。'
          '見どころ、季節の魅力、一般的な難易度や注意点を簡潔に含めてください。';
      final user = [
        if (name.isNotEmpty) '・名称: $name',
        if (pref.isNotEmpty) '・都道府県: $pref',
        if (height.isNotEmpty) '・標高: $height m',
        if (course.isNotEmpty) '・代表ルート: $course',
        '上記情報をもとに初心者にも分かりやすい紹介文を作成してください。',
      ].join('\n');

      final text = await ApiService.askGemini(
        systemPrompt: system,
        userMessage: user,
        context: {'mountain': m},
      );
      return text.trim();
    } catch (_) {
      return null;
    }
  }
}
