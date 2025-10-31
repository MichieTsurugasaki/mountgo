#!/usr/bin/env node
/**
 * CSVから山データを読み込み、Firestoreの既存ドキュメントを更新
 * 
 * 機能:
 * - name_kana (よみがな) の追加
 * - lat/lng の更新 (より正確な座標がある場合)
 * - 不足しているメタデータの補完
 * 
 * Usage:
 *   node scripts/update_mountains_from_csv.mjs <csv_path> [--write]
 *   
 * Example:
 *   node scripts/update_mountains_from_csv.mjs ../firestore-seed/nihon_100_meizan_complete.csv --dry-run
 *   node scripts/update_mountains_from_csv.mjs ../firestore-seed/nihon_100_meizan_complete.csv --write
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { parse } from 'csv-parse/sync';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const serviceAccountPath = path.resolve(__dirname, '../gen-lang-client-0636793764-796b85572dd7.json');
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

// 山名の別名マッピング（CSV名 → Firestore名）
const NAME_ALIASES = {
  '利尻山': '利尻岳',
  '朝日岳': '朝日連峰',
  '飯豊山': '飯豊連峰',
  '大朝日岳': '朝日連峰',
  '飯豊本山': '飯豊連峰'
};

// 山名の正規化（括弧内の別名を除去）
function normalizeName(name) {
  const normalized = name.replace(/[（(].*?[）)]/g, '').trim();
  // 別名マッピングを適用
  return NAME_ALIASES[normalized] || normalized;
}

// 都道府県の正規化
function normalizePref(pref) {
  return pref.replace(/[・、]/g, ' ')
    .split(/\s+/)
    .map(p => p.replace(/県|府|都|道/g, ''))
    .join(' ');
}

async function findMountainDoc(name, pref) {
  const normalizedName = normalizeName(name);
  const normalizedPref = normalizePref(pref);
  
  // 1. 完全一致で検索
  let query = db.collection('mountains').where('name', '==', normalizedName);
  let snapshot = await query.get();
  
  if (!snapshot.empty) {
    return snapshot.docs[0];
  }
  
  // 2. 元の名前で検索
  query = db.collection('mountains').where('name', '==', name);
  snapshot = await query.get();
  
  if (!snapshot.empty) {
    return snapshot.docs[0];
  }
  
  // 3. 部分一致で検索
  const allSnapshot = await db.collection('mountains').get();
  for (const doc of allSnapshot.docs) {
    const docName = doc.data().name || '';
    if (docName.includes(normalizedName) || normalizedName.includes(docName)) {
      console.log(`  ℹ️  部分一致: CSV「${name}」→ Firestore「${docName}」`);
      return doc;
    }
  }
  
  return null;
}

async function updateFromCSV(csvPath, writeMode = false) {
  console.log(`\n📂 CSVファイル: ${csvPath}`);
  console.log(`🔧 モード: ${writeMode ? '書き込み (--write)' : 'ドライラン (--dry-run)'}\n`);
  
  const csvContent = fs.readFileSync(csvPath, 'utf8');
  const records = parse(csvContent, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
    bom: true
  });
  
  console.log(`📊 CSVレコード数: ${records.length}\n`);
  
  let matched = 0;
  let notFound = 0;
  let updated = 0;
  let skipped = 0;
  
  for (const row of records) {
    const csvName = row['山名'] || row.name;
    const csvKana = row['よみがな'] || row.name_kana;
    const csvPref = row['所在地'] || row.pref;
    const csvLat = parseFloat(row.lat);
    const csvLng = parseFloat(row.lng);
    
    if (!csvName) {
      console.log(`⚠️  スキップ: 山名なし`);
      skipped++;
      continue;
    }
    
    console.log(`\n🔍 処理中: ${csvName} (${csvPref})`);
    
    const doc = await findMountainDoc(csvName, csvPref);
    
    if (!doc) {
      console.log(`  ❌ 未発見: Firestoreに該当する山が見つかりません`);
      notFound++;
      continue;
    }
    
    matched++;
    const data = doc.data();
    const updates = {};
    
    // name_kana の追加
    if (csvKana && !data.name_kana) {
      updates.name_kana = csvKana;
      console.log(`  ✅ name_kana: 追加 "${csvKana}"`);
    } else if (csvKana && data.name_kana !== csvKana) {
      console.log(`  ℹ️  name_kana: 既存 "${data.name_kana}" (CSV: "${csvKana}")`);
    }
    
    // lat/lng の更新（既存値との差が大きい場合のみ）
    if (!isNaN(csvLat) && !isNaN(csvLng)) {
      const existingLat = data.lat;
      const existingLng = data.lng;
      
      if (typeof existingLat !== 'number' || typeof existingLng !== 'number') {
        updates.lat = csvLat;
        updates.lng = csvLng;
        console.log(`  ✅ lat/lng: 数値型に変換 ${csvLat}, ${csvLng}`);
      } else {
        const latDiff = Math.abs(existingLat - csvLat);
        const lngDiff = Math.abs(existingLng - csvLng);
        
        // 0.01度 (約1km) 以上の差がある場合は確認
        if (latDiff > 0.01 || lngDiff > 0.01) {
          console.log(`  ⚠️  座標差: lat差=${latDiff.toFixed(4)}, lng差=${lngDiff.toFixed(4)}`);
          console.log(`      既存: ${existingLat}, ${existingLng}`);
          console.log(`      CSV: ${csvLat}, ${csvLng}`);
          // 大きな差がある場合はスキップ（手動確認推奨）
          console.log(`  ⏸  座標更新スキップ（差が大きいため手動確認推奨）`);
        } else if (latDiff > 0.0001 || lngDiff > 0.0001) {
          // 小さな差は精度向上として更新
          updates.lat = csvLat;
          updates.lng = csvLng;
          console.log(`  ✅ lat/lng: 精度向上 ${csvLat}, ${csvLng}`);
        }
      }
    }
    
    // 更新実行
    if (Object.keys(updates).length > 0) {
      if (writeMode) {
        await doc.ref.update(updates);
        console.log(`  💾 更新完了: ${doc.id}`);
        updated++;
      } else {
        console.log(`  🔧 更新予定: ${doc.id} (--write で実行)`);
        updated++;
      }
    } else {
      console.log(`  ✓ 更新不要`);
    }
  }
  
  console.log(`\n\n========== 実行結果 ==========`);
  console.log(`CSVレコード: ${records.length}`);
  console.log(`マッチ成功: ${matched}`);
  console.log(`未発見: ${notFound}`);
  console.log(`更新対象: ${updated}`);
  console.log(`スキップ: ${skipped}`);
  console.log(`==============================\n`);
}

// メイン処理
const args = process.argv.slice(2);
const csvPath = args[0];
const writeMode = args.includes('--write');

if (!csvPath) {
  console.error('Usage: node update_mountains_from_csv.mjs <csv_path> [--write]');
  process.exit(1);
}

const resolvedPath = path.isAbsolute(csvPath) ? csvPath : path.resolve(__dirname, csvPath);

if (!fs.existsSync(resolvedPath)) {
  console.error(`❌ ファイルが見つかりません: ${resolvedPath}`);
  process.exit(1);
}

updateFromCSV(resolvedPath, writeMode)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
