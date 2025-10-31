#!/usr/bin/env node
/**
 * CSVから山データをインポート（重複チェック付き）
 * 
 * 機能:
 * - 既存の山は更新（タグ追加、name_kana追加など）
 * - 新規の山は追加
 * - 日本百名山と日本二百名山の重複を正しく処理
 * 
 * Usage:
 *   node scripts/import_mountains_with_dedup.mjs <csv_path> [--write]
 *   
 * Example:
 *   node scripts/import_mountains_with_dedup.mjs ../firestore-seed/nihon_200_meizan_latest.csv --dry-run
 *   node scripts/import_mountains_with_dedup.mjs ../firestore-seed/nihon_200_meizan_latest.csv --write
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

// 山名の別名マッピング
const NAME_ALIASES = {
  '利尻山': '利尻岳',
  '朝日岳': '朝日連峰',
  '飯豊山': '飯豊連峰',
  '大朝日岳': '朝日連峰',
  '飯豊本山': '飯豊連峰'
};

// 山名の正規化
function normalizeName(name) {
  const normalized = name.replace(/[（(].*?[）)]/g, '').trim();
  return NAME_ALIASES[normalized] || normalized;
}

// 都道府県の正規化
function normalizePref(pref) {
  return pref.replace(/[・･、]/g, ' ')
    .split(/\s+/)
    .map(p => p.replace(/県|府|都|道/g, ''))
    .join(' ');
}

// タグをパイプ区切り文字列から配列に変換
function parseTags(tagStr) {
  if (!tagStr) return [];
  return tagStr.split('|').map(t => t.trim()).filter(t => t);
}

// CSVのlevelを正規化
function normalizeLevel(level) {
  const mapping = {
    '初級': '初級',
    '中級': '中級', 
    '上級': '上級',
    '初心者': '初級',
    '中級者': '中級',
    '上級者': '上級'
  };
  return mapping[level] || level;
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
  
  // 3. 部分一致で検索（より厳密に）
  const allSnapshot = await db.collection('mountains').get();
  for (const doc of allSnapshot.docs) {
    const docName = doc.data().name || '';
    // 短い方の名前が長い方に完全に含まれる場合のみマッチ
    // ただし、両方が5文字以上の場合のみ（誤マッチを避ける）
    if (docName.length >= 5 && normalizedName.length >= 5) {
      if (docName.includes(normalizedName) || normalizedName.includes(docName)) {
        return doc;
      }
    }
  }
  
  return null;
}

async function importWithDedup(csvPath, writeMode = false) {
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
  
  const stats = {
    total: records.length,
    existing: 0,
    new: 0,
    updated: 0,
    skipped: 0,
    tagUpdates: 0,
    errors: []
  };
  
  for (const row of records) {
    const csvName = row['山名'] || row.name;
    const csvKana = row['よみがな'] || row.name_kana;
    const csvPref = row['所在地'] || row.pref;
    const csvLat = parseFloat(row.lat);
    const csvLng = parseFloat(row.lng);
    const csvElevation = parseInt(row.elevation || row.elevation_m);
    const csvLevel = normalizeLevel(row.level);
    const csvTags = parseTags(row.tags);
    const csvStyles = parseTags(row.styles);
    const csvPurposes = parseTags(row.purposes);
    const csvAccess = row.access;
    const csvDescription = row.description;
    
    if (!csvName) {
      console.log(`⚠️  スキップ: 山名なし`);
      stats.skipped++;
      continue;
    }
    
    console.log(`\n🔍 処理中: ${csvName} (${csvPref})`);
    
    try {
      const doc = await findMountainDoc(csvName, csvPref);
      
      if (doc) {
        // 既存の山を更新
        stats.existing++;
        const data = doc.data();
        const updates = {};
        
        console.log(`  ℹ️  既存: ${doc.id} (${data.name})`);
        
        // name_kana の追加
        if (csvKana && !data.name_kana) {
          updates.name_kana = csvKana;
          console.log(`  ✅ name_kana: 追加 "${csvKana}"`);
        }
        
        // タグの追加（既存タグを保持）
        const existingTags = data.tags || [];
        const newTags = [...new Set([...existingTags, ...csvTags])];
        
        if (newTags.length > existingTags.length) {
          updates.tags = newTags;
          const addedTags = newTags.filter(t => !existingTags.includes(t));
          console.log(`  ✅ tags: 追加 [${addedTags.join(', ')}]`);
          stats.tagUpdates++;
        }
        
        // lat/lngの精度向上
        if (!isNaN(csvLat) && !isNaN(csvLng)) {
          const existingLat = data.lat;
          const existingLng = data.lng;
          
          if (typeof existingLat !== 'number' || typeof existingLng !== 'number') {
            updates.lat = csvLat;
            updates.lng = csvLng;
            console.log(`  ✅ lat/lng: 数値型に変換`);
          } else {
            const latDiff = Math.abs(existingLat - csvLat);
            const lngDiff = Math.abs(existingLng - csvLng);
            
            if (latDiff > 0.0001 || lngDiff > 0.0001) {
              updates.lat = csvLat;
              updates.lng = csvLng;
              console.log(`  ✅ lat/lng: 精度向上`);
            }
          }
        }
        
        // その他のフィールド更新
        if (csvStyles && csvStyles.length > 0 && !data.styles) {
          updates.styles = csvStyles;
          console.log(`  ✅ styles: 追加`);
        }
        
        if (csvPurposes && csvPurposes.length > 0 && !data.purposes) {
          updates.purposes = csvPurposes;
          console.log(`  ✅ purposes: 追加`);
        }
        
        // 更新実行
        if (Object.keys(updates).length > 0) {
          if (writeMode) {
            await doc.ref.update(updates);
            console.log(`  💾 更新完了`);
            stats.updated++;
          } else {
            console.log(`  🔧 更新予定 (--write で実行)`);
            stats.updated++;
          }
        } else {
          console.log(`  ✓ 更新不要`);
        }
        
      } else {
        // 新規の山を追加
        stats.new++;
        console.log(`  ✨ 新規追加`);
        
        const newData = {
          name: normalizeName(csvName),
          name_kana: csvKana || '',
          pref: csvPref || '',
          elevation: csvElevation || 0,
          lat: csvLat,
          lng: csvLng,
          level: csvLevel || '中級',
          tags: csvTags,
          styles: csvStyles,
          purposes: csvPurposes,
          access: csvAccess || '車|公共交通機関',
          description: csvDescription || '',
          has_hut: parseInt(row.has_hut) || 0,
          has_onsen: parseInt(row.has_onsen) || 0,
          has_ropeway: parseInt(row.has_ropeway) || 0,
          has_cablecar: parseInt(row.has_cablecar) || 0,
          has_tent: parseInt(row.has_tent) || 0,
          difficulty_score: parseInt(row.difficulty_score) || 5,
          time_car: row.time_car || null,
          time_public: row.time_public || null,
          course_time_total: parseInt(row.course_time_total) || null,
          trailhead_name: row.trailhead_name || null
        };
        
        if (writeMode) {
          await db.collection('mountains').add(newData);
          console.log(`  💾 追加完了`);
        } else {
          console.log(`  🔧 追加予定 (--write で実行)`);
        }
      }
      
    } catch (err) {
      console.log(`  ❌ エラー: ${err.message}`);
      stats.errors.push({ name: csvName, error: err.message });
    }
  }
  
  console.log(`\n\n========== 実行結果 ==========`);
  console.log(`CSVレコード: ${stats.total}`);
  console.log(`既存の山: ${stats.existing}`);
  console.log(`新規の山: ${stats.new}`);
  console.log(`更新対象: ${stats.updated}`);
  console.log(`タグ更新: ${stats.tagUpdates}`);
  console.log(`スキップ: ${stats.skipped}`);
  console.log(`エラー: ${stats.errors.length}`);
  console.log(`==============================\n`);
  
  if (stats.errors.length > 0) {
    console.log(`\n⚠️  エラー詳細:`);
    stats.errors.forEach(e => {
      console.log(`  - ${e.name}: ${e.error}`);
    });
  }
}

// メイン処理
const args = process.argv.slice(2);
const csvPath = args[0];
const writeMode = args.includes('--write');

if (!csvPath) {
  console.error('Usage: node import_mountains_with_dedup.mjs <csv_path> [--write]');
  process.exit(1);
}

const resolvedPath = path.isAbsolute(csvPath) ? csvPath : path.resolve(__dirname, csvPath);

if (!fs.existsSync(resolvedPath)) {
  console.error(`❌ ファイルが見つかりません: ${resolvedPath}`);
  process.exit(1);
}

importWithDedup(resolvedPath, writeMode)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
