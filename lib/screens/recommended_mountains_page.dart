import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class RecommendedMountainsPage extends StatefulWidget {
  const RecommendedMountainsPage({super.key});

  @override
  State<RecommendedMountainsPage> createState() =>
      _RecommendedMountainsPageState();
}

class _RecommendedMountainsPageState extends State<RecommendedMountainsPage> {
  List<dynamic> mountains = [];
  bool isLoading = true;
  String errorMessage = "";

  // ✅ ここにあなたのFirebase FunctionsのURLを入れてください
  final String apiUrl =
      "https://api-ladf53uzuq-uc.a.run.app/getRecommendedMountains";

  @override
  void initState() {
    super.initState();
    fetchRecommendedMountains();
  }

  Future<void> fetchRecommendedMountains() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          mountains = data["recommended"] ?? [];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = "サーバーエラー: ${response.statusCode}";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "通信エラー: $e";
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("☀ 晴れた山リスト"),
        backgroundColor: Colors.green.shade700,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
              ? Center(
                  child: Text(errorMessage,
                      style: const TextStyle(color: Colors.red)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: mountains.length,
                  itemBuilder: (context, index) {
                    final mountain = mountains[index];
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: mountain["icon"] != null
                            ? Image.network(
                                mountain["icon"],
                                width: 50,
                                height: 50,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.terrain, size: 40),
                              )
                            : const Icon(Icons.terrain, size: 40),
                        title: Text(
                          mountain["name"] ?? "不明な山",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        subtitle: Text(
                          "${mountain["weather"] ?? "天気情報なし"} / ${mountain["temp"]?.toStringAsFixed(1) ?? "?"}℃",
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
