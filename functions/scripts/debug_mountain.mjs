#!/usr/bin/env node
/**
 * 特定の山のFirestoreデータを詳細表示
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const serviceAccount = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../gen-lang-client-0636793764-796b85572dd7.json'), 'utf8')
);

initializeApp({
  credential: cert(serviceAccount),
});

const db = getFirestore();

const mountainName = process.argv[2] || '富士山';

async function getMountainData() {
  console.log(`🔍 検索: ${mountainName}\n`);

  const snapshot = await db.collection('mountains').where('name', '==', mountainName).limit(1).get();

  if (snapshot.empty) {
    console.log('❌ 見つかりませんでした');
    return;
  }

  snapshot.forEach((doc) => {
    const data = doc.data();
    console.log(`📄 Document ID: ${doc.id}`);
    console.log(`\n📊 データ:`);
    console.log(JSON.stringify(data, null, 2));
    
    console.log(`\n🗺 位置情報:`);
    console.log(`  lat: ${data.lat} (type: ${typeof data.lat})`);
    console.log(`  lng: ${data.lng} (type: ${typeof data.lng})`);
    
    console.log(`\n🏷 タグ:`);
    console.log(`  tags: ${data.tags || 'なし'}`);
  });
}

getMountainData().catch((err) => {
  console.error('❌ エラー:', err);
  process.exit(1);
});
