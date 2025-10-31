/**
 * Firestore 初期データ登録スクリプト
 * 登山アプリ用 山データ
 */

import { initializeApp } from "firebase/app";
import { getFirestore, collection, addDoc } from "firebase/firestore";
import { readFileSync } from "fs";

// === Firebase Config ===
// Flutterで自動生成されたファイルから値を取得して貼り付ける場合もあります。
// ここでは手動で記載します（yamabiyoriプロジェクト用）
const firebaseConfig = {
  apiKey: "AIzaSyC8bKkv67SXsdz_BDLK2AmQX5xsxssmqpg",
  authDomain: "yamabiyori.firebaseapp.com",
  projectId: "yamabiyori",
  storageBucket: "yamabiyori.firebasestorage.app",
  messagingSenderId: "458368304727",
  appId: "1:458368304727:web:b22117ac4ed0e6070c8512",
  measurementId: "G-WH7KXEC5PM"
};


// === Firestore初期化 ===
const app = initializeApp(firebaseConfig);
const db = getFirestore(app);

async function seedMountains() {
  const mountains = [
    {
      name: "富士山",
      elevation: 3776,
      location: "静岡県・山梨県",
      level: "上級",
      description: "日本一高い山。初心者にはややハードだが人気。",
      lat: 35.3606,
      lng: 138.7274,
    },
    {
      name: "高尾山",
      elevation: 599,
      location: "東京都八王子市",
      level: "初心者",
      description: "アクセス抜群で初心者向け、観光にも最適。",
      lat: 35.6250,
      lng: 139.2430,
    },
    {
      name: "阿蘇山",
      elevation: 1592,
      location: "熊本県阿蘇市",
      level: "中級",
      description: "雄大なカルデラを持つ活火山、絶景の名峰。",
      lat: 32.8842,
      lng: 131.1047,
    },
  ];

  for (const mountain of mountains) {
    await addDoc(collection(db, "mountains"), mountain);
    console.log(`✅ 登録完了: ${mountain.name}`);
  }

  console.log("🎉 すべての山データをFirestoreに登録しました！");
}

seedMountains().catch(console.error);
