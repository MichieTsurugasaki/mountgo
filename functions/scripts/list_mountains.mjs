#!/usr/bin/env node
/**
 * Firestore mountains コレクションのドキュメントIDとname/prefを一覧表示
 * 
 * YAMAP リンク更新用の doc_id を調べる際に使用
 * 
 * Usage:
 *   node scripts/list_mountains.mjs
 *   node scripts/list_mountains.mjs --query 富士山
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// サービスアカウントキーを読み込み
const serviceAccount = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../gen-lang-client-0636793764-796b85572dd7.json'), 'utf8')
);

initializeApp({
  credential: cert(serviceAccount),
});

const db = getFirestore();

// コマンドライン引数からクエリを取得
const args = process.argv.slice(2);
let queryText = '';
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--query' && i + 1 < args.length) {
    queryText = args[i + 1];
    break;
  }
}

async function listMountains() {
  console.log('🔎 Firestore mountains コレクションを取得中...\n');

  const snapshot = await db.collection('mountains').get();
  const mountains = [];

  snapshot.forEach((doc) => {
    const data = doc.data();
    const name = data.name || '';
    const pref = data.pref || '';
    
    // クエリフィルタリング
    if (queryText && !name.includes(queryText) && !pref.includes(queryText)) {
      return;
    }

    mountains.push({
      id: doc.id,
      name: name,
      pref: pref,
    });
  });

  console.log(`📊 取得件数: ${mountains.length}\n`);

  // アルファベット順（ID順）でソート
  mountains.sort((a, b) => a.name.localeCompare(b.name, 'ja'));

  // 結果を表示（CSV形式）
  console.log('doc_id,name,pref');
  mountains.forEach((m) => {
    console.log(`${m.id},${m.name},${m.pref}`);
  });
}

listMountains().catch((err) => {
  console.error('❌ エラー:', err);
  process.exit(1);
});
