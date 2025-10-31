#!/usr/bin/env node

import admin from 'firebase-admin';
import fs from 'node:fs';

const TAG_NAME = '日本百名山';
const serviceAccountPath = './gen-lang-client-0636793764-796b85572dd7.json';

if (!fs.existsSync(serviceAccountPath)) {
  console.error(`❌ サービスアカウントファイルが見つかりません: ${serviceAccountPath}`);
  process.exit(1);
}

const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

function normalizeTags(raw) {
  if (Array.isArray(raw)) {
    return raw.map((t) => String(t).trim()).filter(Boolean);
  }
  if (typeof raw === 'string' && raw.length > 0) {
    return raw.split('|').map((t) => t.trim()).filter(Boolean);
  }
  return [];
}

async function main() {
  console.log('🏔️  mountainsコレクションのタグを更新します...');
  const snapshot = await db.collection('mountains').get();
  console.log(`📦 対象ドキュメント数: ${snapshot.size}`);

  let already = 0;
  let updated = 0;
  let missingName = 0;
  const errorDocs = [];

  for (const doc of snapshot.docs) {
    try {
      const data = doc.data();
      const name = data.name || '(名前未設定)';
      if (!data.name) missingName++;

      const tags = normalizeTags(data.tags);
      if (tags.includes(TAG_NAME)) {
        already++;
        continue;
      }

      const nextTags = [...tags, TAG_NAME];
      await doc.ref.set({ tags: nextTags }, { merge: true });
      updated++;
      console.log(`   ✅ 追加: ${name} (${doc.id})`);
    } catch (err) {
      errorDocs.push({ id: doc.id, error: err.message });
      console.error(`   ❌ エラー: ${doc.id} - ${err.message}`);
    }
  }

  console.log('\n📊 結果:');
  console.log(`   - 既にタグあり: ${already}件`);
  console.log(`   - 新規に追加: ${updated}件`);
  console.log(`   - name未設定: ${missingName}件`);
  console.log(`   - エラー: ${errorDocs.length}件`);

  if (errorDocs.length) {
    console.log('\n⚠️ エラー詳細 (最大10件):');
    for (const info of errorDocs.slice(0, 10)) {
      console.log(`   - ${info.id}: ${info.error}`);
    }
    if (errorDocs.length > 10) {
      console.log(`   ...他 ${errorDocs.length - 10} 件`);
    }
  }

  console.log('\n🎯 更新完了');
}

main().then(() => process.exit(0)).catch((err) => {
  console.error('💥 実行中にエラーが発生しました:', err);
  process.exit(1);
});
