import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AiConciergePage extends StatefulWidget {
  final String departureLabel;
  final String? level;
  final String? accessTime;
  final String? courseTime;
  final List<String>? styles;
  final List<String>? purposes;
  final List<String>? options;
  final List<String>? accessMethods;

  const AiConciergePage({
    super.key,
    required this.departureLabel,
    this.level,
    this.accessTime,
    this.courseTime,
    this.styles,
    this.purposes,
    this.options,
    this.accessMethods,
  });

  @override
  State<AiConciergePage> createState() => _AiConciergePageState();
}

class _AiConciergePageState extends State<AiConciergePage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, String>> messages = [];
  bool isLoading = false;

  // 🔥 Gemini Worker のURL
  final String workerUrl =
      "https://ai-test.tsurugasaki.workers.dev/gemini"; // 👈 あなたのWorker URL

  // 💬 初期プロンプト（AIへの導入文）
  String get initialPrompt => "あなたは登山計画をサポートする『AIマウンテンコンシェルジュ』です。"
      "出発地：${widget.departureLabel}、レベル：${widget.level ?? "未設定"}、"
      "移動時間：${widget.accessTime ?? "未設定"}、コースタイム：${widget.courseTime ?? "未設定"}。"
      "目的：${(widget.purposes ?? []).join("・")}。"
      "これらを考慮して、初心者にもわかりやすく、今日登るべきおすすめ登山プランを提案してください。"
      "回答は日本語で丁寧に、箇条書きで構成してください。";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendMessage(initialPrompt, isInitial: true);
    });
  }

  // ✉️ メッセージ送信
  Future<void> _sendMessage(String text, {bool isInitial = false}) async {
    if (text.trim().isEmpty) return;

    setState(() {
      messages.add({"role": "user", "text": text});
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse(workerUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"contents": text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data["reply"] ??
            data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ??
            "AIの返答が取得できませんでした。";

        setState(() {
          messages.add({"role": "assistant", "text": reply});
          isLoading = false;
        });

        _scrollToBottom();
      } else {
        setState(() {
          messages.add({
            "role": "assistant",
            "text": "⚠️ APIエラー: ${response.statusCode}\n${response.body}"
          });
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        messages.add({"role": "assistant", "text": "❌ 通信エラーが発生しました: $e"});
        isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFB),
      appBar: AppBar(
        title: const Text("AIマウンテンコンシェルジュ 💬"),
        backgroundColor: const Color(0xFF267365),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isUser = msg["role"] == "user";
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF267365) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        if (!isUser)
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Text(
                      msg["text"] ?? "",
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: CircularProgressIndicator(
                color: Color(0xFF267365),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border:
                  Border(top: BorderSide(color: Colors.black12, width: 0.8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: "AIに質問してみる（例：おすすめの山は？）",
                      border: InputBorder.none,
                    ),
                    onSubmitted: (text) {
                      _sendMessage(text);
                      _controller.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF267365)),
                  onPressed: () {
                    _sendMessage(_controller.text);
                    _controller.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
