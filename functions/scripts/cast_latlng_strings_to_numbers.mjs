import admin from 'firebase-admin';
import fs from 'node:fs';

// Firebase Admin 初期化（import_from_csv.mjs と同様の解決を利用）
function resolveServiceAccount() {
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    }
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
      return JSON.parse(fs.readFileSync(p, 'utf8'));
    }
    const fallback = './gen-lang-client-0636793764-796b85572dd7.json';
    if (!fs.existsSync(fallback)) {
      throw new Error('サービスアカウント情報が見つかりません。FIREBASE_SERVICE_ACCOUNT_JSON または GOOGLE_APPLICATION_CREDENTIALS を設定してください。');
    }
    return JSON.parse(fs.readFileSync(fallback, 'utf8'));
  } catch (e) {
    console.error('❌ サービスアカウントJSONの読み込みに失敗:', e);
    process.exit(1);
  }
}

const serviceAccount = resolveServiceAccount();
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}
const db = admin.firestore();

async function main() {
  console.log('🔧 lat/lng 文字列→数値 変換スクリプトを実行します');
  const mountainsRef = db.collection('mountains');

  // 全件取得してクライアント側で型チェック（総数は小さい想定: 数百件）
  const snapshot = await mountainsRef.get();
  console.log(`🔎 mountains コレクションの総件数: ${snapshot.size} 件`);
  const docsMap = new Map();
  for (const d of snapshot.docs) docsMap.set(d.id, d);

  let updated = 0;
  let skipped = 0;
  let failed = 0;

  for (const [id, docSnap] of docsMap.entries()) {
    try {
      const data = docSnap.data();
      const update = {};
      if (data && Object.prototype.hasOwnProperty.call(data, 'lat')) {
        const latVal = data.lat;
        if (typeof latVal === 'string' && latVal.trim().length > 0) {
          const parsed = parseFloat(latVal);
          if (Number.isFinite(parsed)) update.lat = parsed;
        }
      }
      if (data && Object.prototype.hasOwnProperty.call(data, 'lng')) {
        const lngVal = data.lng;
        if (typeof lngVal === 'string' && lngVal.trim().length > 0) {
          const parsed = parseFloat(lngVal);
          if (Number.isFinite(parsed)) update.lng = parsed;
        }
      }

      if (Object.keys(update).length === 0) {
        skipped++;
        continue;
      }

      update.updated_at = admin.firestore.FieldValue.serverTimestamp();
      await mountainsRef.doc(id).update(update);
      console.log(`✅ 更新: ${data.name || id} -> ${JSON.stringify(update)}`);
      updated++;
    } catch (e) {
      console.error(`❌ 更新失敗: ${id}`, e);
      failed++;
    }
  }

  console.log('\n=== 完了 ===');
  console.log(`✅ 更新完了: ${updated} 件`);
  console.log(`⚠️ スキップ: ${skipped} 件 (変換不要または非数値)`);
  console.log(`❌ 失敗: ${failed} 件`);
  process.exit(0);
}

main();
