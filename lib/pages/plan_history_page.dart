import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

/// 📜 PlanHistoryPage
/// Firestoreに保存されたAI登山プランを一覧表示するページ
class PlanHistoryPage extends StatelessWidget {
  final String userId;

  const PlanHistoryPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFB),
      appBar: AppBar(
        title: const Text("保存したAIプラン履歴"),
        backgroundColor: const Color(0xFF267365),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.streamUserPlans(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("まだ保存されたプランはありません 🌿",
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            );
          }

          final plans = snapshot.data!.docs;

          return ListView.builder(
            itemCount: plans.length,
            itemBuilder: (context, i) {
              final plan = plans[i].data();
              final id = plans[i].id;

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 3,
                child: ListTile(
                  leading: const Icon(Icons.terrain, color: Color(0xFF267365)),
                  title: Text(plan["mountainName"] ?? "名称未設定",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("出発地：${plan["departure"] ?? "不明"}"),
                      const SizedBox(height: 4),
                      Text(
                        plan["timestamp"] != null
                            ? plan["timestamp"].toString().substring(0, 19)
                            : "日時不明",
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () async {
                      await FirestoreService.deletePlan(id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("プランを削除しました")),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
