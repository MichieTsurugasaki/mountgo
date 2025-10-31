import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  static const String _apiUrl =
      "http://localhost:57966"; // ★ここは wrangler dev のURLに合わせる

  static Future<String> callAI(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"prompt": prompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Cloudflare AI のレスポンス構造に合わせて修正
        if (data["response"] != null) {
          // Cloudflare の Llama モデルは JSON配列で返す場合あり
          if (data["response"] is Map && data["response"]["response"] != null) {
            return data["response"]["response"].toString();
          }
          return data["response"].toString();
        } else if (data["error"] != null) {
          return "⚠️ エラー: ${data["error"]}";
        } else {
          return "⚠️ 不明なレスポンス形式: ${response.body}";
        }
      } else {
        return "⚠️ サーバーエラー: ${response.statusCode}";
      }
    } catch (e) {
      return "⚠️ 通信エラー: $e";
    }
  }
}
