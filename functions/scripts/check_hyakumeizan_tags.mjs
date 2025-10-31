#!/usr/bin/env node

import admin from 'firebase-admin';
import fs from 'node:fs';

// 設定（環境変数で上書き可能）
const REQUIRED_TAG = process.env.REQUIRED_TAG || '日本百名山';
const ENFORCE_HYAKUMEIZAN_FOR_ALL = process.env.ENFORCE_HYAKUMEIZAN_FOR_ALL === 'true';
// STRICT=true の場合、重大な不整合があれば終了コード1で終了（CI向け）
const STRICT = process.env.STRICT !== 'false';

// 認証情報の解決優先度:
// 1) FIREBASE_SERVICE_ACCOUNT_JSON (JSON文字列)
// 2) GOOGLE_APPLICATION_CREDENTIALS (ファイルパス)
// 3) リポジトリ同梱のデフォルトパス（ローカル用）
let serviceAccount;
try {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
    serviceAccount = JSON.parse(fs.readFileSync(p, 'utf8'));
  } else {
    const fallbackPath = './gen-lang-client-0636793764-796b85572dd7.json';
    if (!fs.existsSync(fallbackPath)) {
      console.error('❌ サービスアカウント情報が見つかりません。環境変数 FIREBASE_SERVICE_ACCOUNT_JSON か GOOGLE_APPLICATION_CREDENTIALS を設定してください。');
      process.exit(1);
    }
    serviceAccount = JSON.parse(fs.readFileSync(fallbackPath, 'utf8'));
  }
} catch (e) {
  console.error('❌ サービスアカウントJSONの読み込み/解析に失敗しました:', e);
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

async function main() {
  console.log('🔎 Firestoreのmountainsコレクションを確認します...');
  const snapshot = await db.collection('mountains').get();
  console.log(`📦 総ドキュメント数: ${snapshot.size}`);

  // 各種カウント
  let requiredTagPresent = 0;
  let requiredTagMissing = 0;
  let missingTagsField = 0;
  let nonArrayTags = 0;
  let emptyTags = 0;
  let invalidTagItems = 0; // 非文字列や空文字

  const missingRequiredSamples = [];
  const malformedSamples = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const name = data.name || '(名前未設定)';

    const hasTagsField = Object.prototype.hasOwnProperty.call(data, 'tags');
    const rawTags = data.tags;
    let tags = [];

    if (!hasTagsField) {
      missingTagsField++;
      malformedSamples.push({ id: doc.id, name, reason: 'tagsフィールド欠落' });
    } else if (!Array.isArray(rawTags)) {
      nonArrayTags++;
      malformedSamples.push({ id: doc.id, name, reason: `tagsが配列ではない: ${typeof rawTags}` });
    } else {
      tags = rawTags;
      if (tags.length === 0) {
        emptyTags++;
        malformedSamples.push({ id: doc.id, name, reason: 'tagsが空配列' });
      }
      // アイテムの妥当性
      for (const t of tags) {
        if (typeof t !== 'string' || t.trim().length === 0) {
          invalidTagItems++;
          malformedSamples.push({ id: doc.id, name, reason: `無効なタグ値: ${JSON.stringify(t)}` });
          break; // 同一ドキュメントからは1回のみ記録
        }
      }
    }

    // 必須タグ（日本百名山）の有無
    if (Array.isArray(rawTags) && rawTags.includes(REQUIRED_TAG)) {
      requiredTagPresent++;
    } else {
      requiredTagMissing++;
      if (missingRequiredSamples.length < 20) {
        missingRequiredSamples.push({ id: doc.id, name });
      }
    }
  }

  // レポート出力
  console.log('\n📊 タグ健全性レポート:');
  console.log(`   - 必須タグ「${REQUIRED_TAG}」あり: ${requiredTagPresent}件`);
  console.log(`   - 必須タグなし: ${requiredTagMissing}件`);
  console.log(`   - tagsフィールド欠落: ${missingTagsField}件`);
  console.log(`   - tagsが配列でない: ${nonArrayTags}件`);
  console.log(`   - tagsが空配列: ${emptyTags}件`);
  console.log(`   - 無効なタグ要素: ${invalidTagItems}件`);

  if (missingRequiredSamples.length > 0) {
    console.log('\n⚠️ 必須タグがないドキュメント（最大20件）:');
    for (const { id, name } of missingRequiredSamples) {
      console.log(`   - ${name} (docId: ${id})`);
    }
  }

  if (malformedSamples.length > 0) {
    console.log('\n🚧 タグフィールドの不整合（サンプル最大20件）:');
    for (const s of malformedSamples.slice(0, 20)) {
      console.log(`   - ${s.name} (docId: ${s.id}) → ${s.reason}`);
    }
    if (malformedSamples.length > 20) {
      console.log(`   ...他 ${malformedSamples.length - 20} 件`);
    }
  }

  // 退出コード判定
  let issues = 0;
  if (missingTagsField > 0) issues++;
  if (nonArrayTags > 0) issues++;
  if (invalidTagItems > 0) issues++;
  if (ENFORCE_HYAKUMEIZAN_FOR_ALL && requiredTagMissing > 0) issues++;

  if (STRICT && issues > 0) {
    console.error('\n❌ 健全性チェックに失敗しました（STRICTモード）');
    process.exit(1);
  }

  console.log('\n✅ 健全性チェック完了');
}

main().catch((err) => {
  console.error('💥 確認中にエラーが発生しました:', err);
  process.exit(1);
});
