#!/usr/bin/env node
/**
 * mountains_standard_template.csv からFirestoreへ山データをインポート
 * 
 * Usage:
 *   node scripts/import_standard_mountains.mjs
 *   node scripts/import_standard_mountains.mjs --write
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { parse } from 'csv-parse/sync';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const serviceAccount = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '../gen-lang-client-0636793764-796b85572dd7.json'), 'utf8')
);

initializeApp({
  credential: cert(serviceAccount),
});

const db = getFirestore();

const writeMode = process.argv.includes('--write');

async function importMountains() {
  const csvPath = path.resolve(__dirname, '../../firestore-seed/mountains_standard_template.csv');
  const csvContent = fs.readFileSync(csvPath, 'utf8');
  
  const records = parse(csvContent, {
    columns: true,
    skip_empty_lines: true,
  });

  console.log(`📄 入力: ${csvPath}`);
  console.log(`🔎 処理件数: ${records.length}（モード: ${writeMode ? '書き込み' : 'dry-run'}）\n`);

  const batch = db.batch();
  let count = 0;

  for (const row of records) {
    const name = row.name?.trim();
    if (!name) continue;

    // 既存チェック
    const existing = await db.collection('mountains').where('name', '==', name).limit(1).get();
    
    if (!existing.empty) {
      console.log(`⏭  スキップ: ${name} (既に存在)`);
      continue;
    }

    // データ変換
    const data = {
      name: name,
      pref: row.pref?.trim() || '',
      elevation: parseInt(row.elevation) || 0,
      lat: parseFloat(row.lat) || 0,
      lng: parseFloat(row.lng) || 0,
      level: row.level?.trim() || '初級',
      courseTime: row.time || '',
      description: row.description?.trim() || `${name}は${row.pref}に位置する人気の山です。`,
      tags: row.tags?.split('|').map(t => t.trim()).filter(t => t) || [],
      styles: row.styles?.split('|').map(s => s.trim()).filter(s => s) || [],
      purposes: row.purposes?.split('|').map(p => p.trim()).filter(p => p) || [],
      time_car: row.time_car?.toString() || '',
      time_public: row.time_public?.toString() || '',
      trailheads: row.trailhead_name ? [{
        name: row.trailhead_name,
        lat: parseFloat(row.lat) || 0,
        lng: parseFloat(row.lng) || 0,
        source: 'csv-import'
      }] : [],
      created_at: new Date(),
      updated_at: new Date(),
    };

    if (writeMode) {
      const docRef = db.collection('mountains').doc();
      batch.set(docRef, data);
      console.log(`✓ ${name} を登録予定`);
    } else {
      console.log(`✓ ${name} :: lat=${data.lat}, lng=${data.lng}, tags=${data.tags.join(', ')}`);
    }

    count++;

    // Batch limit (500)
    if (count % 450 === 0 && writeMode) {
      await batch.commit();
      console.log(`  📦 ${count}件 commit完了`);
    }
  }

  if (writeMode && count > 0) {
    await batch.commit();
    console.log(`\n✅ 完了: ${count}件をFirestoreに登録しました`);
  } else {
    console.log(`\n✅ Dry-run完了: ${count}件が登録可能です`);
    console.log(`\n💡 実際に登録するには --write オプションを付けてください:`);
    console.log(`   node scripts/import_standard_mountains.mjs --write`);
  }
}

importMountains().catch((err) => {
  console.error('❌ エラー:', err);
  process.exit(1);
});
