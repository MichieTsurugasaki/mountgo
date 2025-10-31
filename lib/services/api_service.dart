import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Gemini への問い合わせ統合クライアント
/// 1) Cloudflare Workers 中継があれば優先
/// 2) なければ直接 Google Gemini API（APIキー）
class ApiService {
  static String? get _workerUrl => dotenv.env['GEMINI_API_URL'];
  static String? get _workerStreamUrl => dotenv.env['GEMINI_STREAM_URL'];
  static String? get _apiKey => dotenv.env['GEMINI_API_KEY'];

  // Diagnostics for UI/debug
  static String _lastTransport =
      'none'; // worker | direct | local | stream-worker
  static String? _lastError;
  static String get lastTransport => _lastTransport;
  static String? get lastError => _lastError;

  /// 非ストリーミング
  static Future<String> askGemini({
    required String systemPrompt,
    required String userMessage,
    Map<String, dynamic>? context,
  }) async {
    // Workers があれば優先
    if (_workerUrl != null && _workerUrl!.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse(_workerUrl!),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'system': systemPrompt,
            'user': userMessage,
            'context': context ?? {},
          }),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          _lastTransport = 'worker';
          _lastError = null;
          final data = jsonDecode(res.body);
          return data['text'] ?? data.toString();
        }
        // ステータス異常時: APIキーがあれば直接Geminiへ、それも不可ならローカル生成
        if (_apiKey != null && _apiKey!.isNotEmpty) {
          final out = await _askGeminiDirect(
              systemPrompt: systemPrompt,
              userMessage: userMessage,
              context: context);
          _lastTransport = 'direct';
          _lastError = null;
          return out;
        }
        return _localConciergePlan(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            context: context);
      } catch (e) {
        _lastError = e.toString();
        // Flutter Webで CORS に起因する `ClientException: Failed to fetch` が発生しうる
        // まずは直接APIを試す → ダメならローカル
        if (_apiKey != null && _apiKey!.isNotEmpty) {
          try {
            final out = await _askGeminiDirect(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                context: context);
            _lastTransport = 'direct';
            _lastError = null;
            return out;
          } catch (_) {}
        }
        return _localConciergePlan(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            context: context,
            note: kIsWeb ? '（Web環境のため外部AIに接続できず、端末内で簡易プランを作成しました）' : null);
      }
    }

    // 直接API（簡易実装・開発用）
    if (_apiKey == null || _apiKey!.isEmpty) {
      // APIキーが無い場合もローカル生成へ
      final out = _localConciergePlan(
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          context: context,
          note: '（開発モード: APIキー未設定のため、端末内で簡易プランを作成しました）');
      _lastTransport = 'local';
      _lastError = 'API key not set';
      return out;
    }
    final out = await _askGeminiDirect(
        systemPrompt: systemPrompt, userMessage: userMessage, context: context);
    _lastTransport = 'direct';
    _lastError = null;
    return out;
  }

  /// ストリーミング（Server-Sent Events 形式を想定）
  /// Cloudflare Workers 側で text/event-stream を返す実装に対応
  static Stream<String> streamGemini({
    required String systemPrompt,
    required String userMessage,
    Map<String, dynamic>? context,
  }) async* {
    if (_workerStreamUrl == null || _workerStreamUrl!.isEmpty) {
      // ストリームURL未設定: 直接APIか、非ストリーミングにフォールバック
      if (_apiKey != null && _apiKey!.isNotEmpty) {
        // 直接API（非ストリーミング）
        final full = await _askGeminiDirect(
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          context: context,
        );
        _lastTransport = 'direct';
        _lastError = null;
        // 疑似ストリーミングで段階的に返す
        for (final chunk in _splitForStreaming(full)) {
          yield chunk;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
        return;
      }
      final full = await askGemini(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        context: context,
      );
      for (final chunk in _splitForStreaming(full)) {
        yield chunk;
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      return;
    }
    try {
      final req = http.Request('POST', Uri.parse(_workerStreamUrl!));
      req.headers['content-type'] = 'application/json';
      req.headers['accept'] = 'text/event-stream';
      req.body = jsonEncode({
        'system': systemPrompt,
        'user': userMessage,
        'context': context ?? {},
      });

      final res = await http.Client().send(req);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // 非ストリーミングでフォールバック（優先: 直接API）
        if (_apiKey != null && _apiKey!.isNotEmpty) {
          final full = await _askGeminiDirect(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            context: context,
          );
          _lastTransport = 'direct';
          _lastError = 'worker non-200';
          for (final chunk in _splitForStreaming(full)) {
            yield chunk;
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }
          return;
        }
        final full = await askGemini(
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          context: context,
        );
        for (final chunk in _splitForStreaming(full)) {
          yield chunk;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
        return;
      }

      // SSE: "data: {...}\n\n" をパース
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        for (final line in const LineSplitter().convert(chunk)) {
          final l = line.trim();
          if (l.startsWith('data:')) {
            final data = l.substring(5).trim();
            if (data == '[DONE]') return;
            try {
              final json = jsonDecode(data);
              final delta = (json['delta'] ?? json['text'] ?? '').toString();
              if (delta.isNotEmpty) yield delta;
              _lastTransport = 'stream-worker';
              _lastError = null;
            } catch (_) {
              // プレーン文字列でもOK
              yield data;
            }
          }
        }
      }
    } catch (_) {
      // ストリームが確立できない場合 → 非ストリーミングへフォールバック（優先: 直接API）
      if (_apiKey != null && _apiKey!.isNotEmpty) {
        final full = await _askGeminiDirect(
          systemPrompt: systemPrompt,
          userMessage: userMessage,
          context: context,
        );
        _lastTransport = 'direct';
        for (final chunk in _splitForStreaming(full)) {
          yield chunk;
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
        return;
      }
      final full = await askGemini(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        context: context,
      );
      _lastTransport = 'local';
      for (final chunk in _splitForStreaming(full)) {
        yield chunk;
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      return;
    }
  }

  /// テキストを概ね文単位で分割して、UI側で自然に流れるようにする
  static Iterable<String> _splitForStreaming(String text) sync* {
    final normalized = text.replaceAll('\r', '');
    final sentenceEnd = RegExp(r'(?<=[。！!？?\n])');
    final parts = normalized
        .split(sentenceEnd)
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (parts.length <= 1) {
      // 文として分割できない場合は固定幅で分割
      const chunkSize = 60;
      for (var i = 0; i < normalized.length; i += chunkSize) {
        yield normalized.substring(
            i,
            i + chunkSize > normalized.length
                ? normalized.length
                : i + chunkSize);
      }
      return;
    }
    for (final p in parts) {
      yield p;
    }
  }

  /// ネットワーク不通やCORS制約時の簡易ローカル生成
  static String _localConciergePlan({
    required String systemPrompt,
    required String userMessage,
    Map<String, dynamic>? context,
    String? note,
  }) {
    final m = (context?['mountain'] as Map<String, dynamic>?) ?? const {};
    final name = (m['name'] ?? '').toString();
    final pref = (m['pref'] ?? '').toString();
    final course = (m['course'] ?? '').toString();
    final departure = (context?['departure'] ?? '').toString();
    final plannedDate = (context?['plannedDate'] ?? '').toString();
    final search =
        (context?['searchConditions'] as List?)?.cast<String>() ?? const [];
    final weatherInfo =
        (context?['weatherInfo'] as List?)?.cast<String>() ?? const [];

    final b = StringBuffer();
    b.writeln('⛰️ 簡易プラン（オフライン）');
    if (note != null && note.isNotEmpty) b.writeln(note);
    if (name.isNotEmpty) b.writeln('・山名: $name');
    if (pref.isNotEmpty) b.writeln('・都道府県: $pref');
    if (course.isNotEmpty) b.writeln('・人気コース: $course');
    if (departure.isNotEmpty) b.writeln('・出発地: $departure');
    if (plannedDate.isNotEmpty) b.writeln('・登山予定日: $plannedDate');
    if (weatherInfo.isNotEmpty) {
      b.writeln('・天気:');
      for (final w in weatherInfo) b.writeln('  - $w');
    }
    if (search.isNotEmpty) {
      b.writeln('・条件:');
      for (final s in search) b.writeln('  - $s');
    }
    b.writeln('');
    b.writeln('【おすすめのタイムライン（例）】');
    b.writeln('05:30 自宅出発 🚗');
    b.writeln('08:00 登山口到着・準備');
    b.writeln('08:30 入山 → 休憩を挟みつつ安全第一で行動');
    b.writeln('11:30 山頂到着・展望/昼食');
    b.writeln('13:00 下山開始');
    b.writeln('15:30 下山・温泉/ご当地グルメ♨️');
    b.writeln('18:00 帰路へ');
    b.writeln('');
    b.writeln('【安全メモ】');
    b.writeln('・最新の天気/登山道情報を確認し、無理のない計画で');
    b.writeln('・水分/行動食/防寒/雨具を必携、時間に余裕を');
    b.writeln('・体調が優れない/天候悪化時は速やかに撤退');
    b.writeln('');
    b.writeln('質問: $userMessage');
    return b.toString();
  }

  // --- Direct Gemini (non-stream) helper ---
  static Future<String> _askGeminiDirect({
    required String systemPrompt,
    required String userMessage,
    Map<String, dynamic>? context,
  }) async {
    // Use Gemini 2.5 Flash (stable)
    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey';
    final payload = {
      "contents": [
        {
          "parts": [
            {"text": "$systemPrompt\n\nユーザー: $userMessage"}
          ]
        }
      ]
    };
    final res = await http.post(
      Uri.parse(url),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final json = jsonDecode(res.body);
      final text =
          (json['candidates']?[0]?['content']?['parts']?[0]?['text']) ?? '';
      return text.toString();
    }
    _lastError = 'direct non-200 ${res.statusCode}';
    throw Exception('Gemini(direct) error: ${res.statusCode} ${res.body}');
  }
}
