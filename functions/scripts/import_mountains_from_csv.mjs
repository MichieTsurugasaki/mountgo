#!/usr/bin/env node
/**
 * CSVから山データをFirestoreへインポート
 * 
 * 機能:
 * - 新しい山のみを追加（既存の山はスキップ）
 * - lat/lng を数値型として保存
 * - tags を配列として保存
 * - name_kana (よみがな) をサポート
 * 
 * Usage:
 *   node scripts/import_mountains_from_csv.mjs <csv_path> [--write]
 *   
 * Example:
 *   node scripts/import_mountains_from_csv.mjs ../firestore-seed/nihon_200_meizan_data.csv --dry-run
 *   node scripts/import_mountains_from_csv.mjs ../firestore-seed/nihon_200_meizan_data.csv --write
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

// 山名の正規化（括弧内の別名を除去）
function normalizeName(name) {
  return name.replace(/[（(].*?[）)]/g, '').trim();
}

// 都道府県の正規化
function normalizePref(pref) {
  return pref
    .replace(/[・･、]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// 文字列をbooleanに変換
function parseBoolean(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    const lower = value.toLowerCase().trim();
    return lower === 'true' || lower === 'yes' || lower === '1';
  }
  return false;
}

async function checkExisting(name, pref) {
  const normalizedName = normalizeName(name);
  
  // 1. 正規化された名前で検索
  let snapshot = await db.collection('mountains')
    .where('name', '==', normalizedName)
    .limit(1)
    .get();
  
  if (!snapshot.empty) {
    return snapshot.docs[0];
  }
  
  // 2. 元の名前で検索
  snapshot = await db.collection('mountains')
    .where('name', '==', name)
    .limit(1)
    .get();
  
  if (!snapshot.empty) {
    return snapshot.docs[0];
  }
  
  return null;
}

async function importFromCSV(csvPath, writeMode = false) {
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
  
  let added = 0;
  let skipped = 0;
  let errors = 0;
  
  for (const row of records) {
    const csvName = row['山名'] || row.name;
    const csvKana = row['よみがな'] || row.name_kana;
    const csvPref = row['所在地'] || row.pref;
    
    if (!csvName) {
      console.log(`⚠️  スキップ: 山名なし`);
      skipped++;
      continue;
    }
    
    const normalizedName = normalizeName(csvName);
    console.log(`\n🔍 処理中: ${normalizedName} (${csvPref})`);
    
    // 既存チェック
    const existing = await checkExisting(csvName, csvPref);
    
    if (existing) {
      console.log(`  ⏭  既に存在: ${existing.id}`);
      skipped++;
      continue;
    }
    
    // データ作成
    try {
      const lat = parseFloat(row.lat);
      const lng = parseFloat(row.lng);
      const elevation = parseInt(row.elevation);
      
      if (isNaN(lat) || isNaN(lng)) {
        console.log(`  ❌ エラー: lat/lng が不正 (lat=${row.lat}, lng=${row.lng})`);
        errors++;
        continue;
      }
      
      const data = {
        name: normalizedName,
        name_kana: csvKana || '',
        pref: normalizePref(csvPref),
        elevation: !isNaN(elevation) ? elevation : 0,
        lat: lat,  // number型
        lng: lng,  // number型
        level: row.level || '初級',
        tags: (row.tags || '').split('|').map(t => t.trim()).filter(t => t),
        styles: (row.styles || '').split('|').map(s => s.trim()).filter(s => s),
        purposes: (row.purposes || '').split('|').map(p => p.trim()).filter(p => p),
        access: row.access || '',
        time_car: row.time_car || '',
        time_public: row.time_public || '',
        course_time_total: row.course_time_total || '',
        description: row.description || `${normalizedName}（標高${elevation || '不明'}m）は${csvPref}に位置する山です。`,
        trailhead_name: row.trailhead_name || '',
        has_hut: parseBoolean(row.has_hut),
        has_onsen: parseBoolean(row.has_onsen),
        has_ropeway: parseBoolean(row.has_ropeway),
        has_cablecar: parseBoolean(row.has_cablecar),
        has_tent: parseBoolean(row.has_tent),
        difficulty_score: parseInt(row.difficulty_score) || 0,
        created_at: new Date(),
        updated_at: new Date()
      };
      
      if (writeMode) {
        const docRef = await db.collection('mountains').add(data);
        console.log(`  ✅ 追加成功: ${docRef.id}`);
        added++;
      } else {
        console.log(`  🔧 追加予定 (--write で実行)`);
        added++;
      }
      
    } catch (err) {
      console.log(`  ❌ エラー: ${err.message}`);
      errors++;
    }
  }
  
  console.log(`\n\n========== 実行結果 ==========`);
  console.log(`CSVレコード: ${records.length}`);
  console.log(`追加: ${added}`);
  console.log(`スキップ(既存): ${skipped}`);
  console.log(`エラー: ${errors}`);
  console.log(`==============================\n`);
}

// メイン処理
const args = process.argv.slice(2);
const csvPath = args[0];
const writeMode = args.includes('--write');

if (!csvPath) {
  console.error('Usage: node import_mountains_from_csv.mjs <csv_path> [--write]');
  process.exit(1);
}

const resolvedPath = path.isAbsolute(csvPath) ? csvPath : path.resolve(__dirname, csvPath);

if (!fs.existsSync(resolvedPath)) {
  console.error(`❌ ファイルが見つかりません: ${resolvedPath}`);
  process.exit(1);
}

importFromCSV(resolvedPath, writeMode)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
