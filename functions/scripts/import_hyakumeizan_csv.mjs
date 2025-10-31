#!/usr/bin/env node

/**
 * 日本百名山CSVをFirestoreにインポートするスクリプト
 * 
 * 使用方法:
 * node import_hyakumeizan_csv.mjs <CSVファイル>
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import { parse } from 'csv-parse/sync';

// Firebase Admin初期化
const serviceAccount = JSON.parse(
  fs.readFileSync('./gen-lang-client-0636793764-796b85572dd7.json', 'utf8')
);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'yamabiyori'
});

const db = admin.firestore();

async function importHyakumeizanCSV(csvFilePath) {
  console.log(`📄 CSVファイルを読み込みます: ${csvFilePath}\n`);
  
  try {
    // CSVファイルを読み込み
    const fileContent = fs.readFileSync(csvFilePath, 'utf-8');
    const records = parse(fileContent, {
      columns: true,
      skip_empty_lines: true,
      trim: true,
      relax_column_count: true,
      relax_quotes: true
    });
    
    console.log(`📊 ${records.length}件のデータを処理します\n`);
    
    const mountainsRef = db.collection('mountains');
    let successCount = 0;
    let errorCount = 0;
    
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      const rowNum = i + 2; // ヘッダー + 0-indexed
      
      try {
        const docId = record.doc_id || `mountain_${i + 1}`;
        const name = (record.name || '').trim();
        
        if (!name) {
          console.warn(`⚠️  行 ${rowNum}: 名前が空です。スキップします。`);
          errorCount++;
          continue;
        }
        
        // Firestoreドキュメントを作成
        const mountainData = {
          name: name,
          name_kana: (record.reading || '').trim(),
          pref: (record.prefectures || record.area || '').trim(),
          area: (record.area || '').trim(),
          lat: parseFloat(record.lat) || 0,
          lng: parseFloat(record.lng) || 0,
          elevation: parseInt(record.elevation_m) || 0,
          median_time_h: parseFloat(record.median_time_h) || 0,
          min_time_h: parseFloat(record.min_time_h) || 0,
          max_time_h: parseFloat(record.max_time_h) || 0,
          difficulty: parseInt(record.difficulty) || 0,
          season: (record.season || '').trim(),
          notes: (record.notes || '').trim().replace(/\n/g, ' '),
          huts: (record.huts || '').trim(),
          huts_url: (record.huts_url || '').trim(),
          photo_url: (record.photo_url || '').trim(),
          tairyoku_yamap: (record.tairyoku_yamap || '').trim(),
          itinerary_yamap: (record.itinerary_yamap || '').trim().replace(/\n/g, ' '),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        };
        
        // tagsをパイプ区切りから配列に変換
        const tagsStr = (record.tags || '').trim();
        if (tagsStr) {
          mountainData.tags = tagsStr.split('|').map(t => t.trim()).filter(t => t);
        } else {
          mountainData.tags = [];
        }
        
        // Firestoreに保存
        await mountainsRef.doc(docId).set(mountainData, { merge: true });
        
        successCount++;
        if (successCount % 10 === 0) {
          console.log(`   処理中... ${successCount}/${records.length}`);
        }
        
      } catch (error) {
        console.error(`❌ 行 ${rowNum} (${record.name || 'unknown'}): ${error.message}`);
        errorCount++;
      }
    }
    
    console.log('\n✅ インポート完了!');
    console.log(`📊 統計:`);
    console.log(`   - 成功: ${successCount}件`);
    console.log(`   - エラー: ${errorCount}件`);
    console.log(`   - 合計: ${records.length}件`);
    
  } catch (error) {
    console.error('❌ CSVファイルの読み込みエラー:', error);
    throw error;
  }
}

// コマンドライン引数をチェック
if (process.argv.length < 3) {
  console.error('使用方法: node import_hyakumeizan_csv.mjs <CSVファイル>');
  console.error('');
  console.error('例:');
  console.error('  node import_hyakumeizan_csv.mjs ~/Documents/日本百名山/CSV/mountains_master_updated.csv');
  process.exit(1);
}

const csvFilePath = process.argv[2];

// ファイルの存在確認
if (!fs.existsSync(csvFilePath)) {
  console.error(`❌ エラー: ファイルが見つかりません: ${csvFilePath}`);
  process.exit(1);
}

// 実行
try {
  await importHyakumeizanCSV(csvFilePath);
  console.log('\n🎉 すべての処理が完了しました!');
  process.exit(0);
} catch (error) {
  console.error('\n💥 処理中にエラーが発生しました:', error.message);
  process.exit(1);
}
