#!/usr/bin/env node

/**
 * CSVファイルの全山に「日本百名山」タグを追加するスクリプト
 * 
 * 使用方法:
 * node update_hyakumeizan_tags.mjs <入力CSVファイル> <出力CSVファイル>
 * 
 * 例:
 * node update_hyakumeizan_tags.mjs ~/Documents/日本百名山/CSV/mountains_master_with_yamap_all_v2.csv ~/Documents/日本百名山/CSV/mountains_master_updated.csv
 */

import fs from 'fs';
import path from 'path';

const TAG_NAME = '日本百名山';

function updateCsvTags(inputPath, outputPath) {
  console.log(`📖 読み込み中: ${inputPath}`);
  
  // CSVファイルを読み込む
  const content = fs.readFileSync(inputPath, 'utf-8');
  const lines = content.split('\n');
  
  if (lines.length === 0) {
    console.error('❌ エラー: 空のファイルです');
    process.exit(1);
  }
  
  // ヘッダー行を取得
  const header = lines[0];
  const columns = header.split(',');
  
  // tagsカラムのインデックスを探す
  const tagsIndex = columns.findIndex(col => col.trim() === 'tags');
  
  if (tagsIndex === -1) {
    console.error('❌ エラー: tagsカラムが見つかりません');
    console.log('利用可能なカラム:', columns);
    process.exit(1);
  }
  
  console.log(`✓ tagsカラムを検出: インデックス ${tagsIndex}`);
  
  // 更新された行を格納
  const updatedLines = [header]; // ヘッダーはそのまま
  let updatedCount = 0;
  let alreadyHasTag = 0;
  
  // データ行を処理
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    
    // 空行はスキップ
    if (!line) {
      continue;
    }
    
    // CSV行をパース（簡易版 - パイプ区切りを考慮）
    const cells = line.split(',');
    
    if (cells.length <= tagsIndex) {
      console.warn(`⚠️  警告: 行 ${i + 1} のカラム数が不足しています。スキップします。`);
      updatedLines.push(line);
      continue;
    }
    
    // 現在のtagsの値を取得
    let currentTags = cells[tagsIndex].trim();
    
    // タグがすでに含まれているかチェック
    if (currentTags.includes(TAG_NAME)) {
      alreadyHasTag++;
      updatedLines.push(line);
      continue;
    }
    
    // タグを追加
    if (currentTags === '' || currentTags === '""' || currentTags === "''") {
      // タグが空の場合は新規追加
      cells[tagsIndex] = TAG_NAME;
    } else {
      // 既存のタグがある場合はパイプ区切りで追加
      // 引用符を除去してから処理
      currentTags = currentTags.replace(/^["']|["']$/g, '');
      cells[tagsIndex] = `${currentTags}|${TAG_NAME}`;
    }
    
    // 改行を含むフィールドを正規化（スペースに置換）
    const updatedLine = cells.map(cell => cell.replace(/\n|\r/g, ' ')).join(',');
    updatedLines.push(updatedLine);
    updatedCount++;
  }
  
  // 結果をファイルに書き込む
  fs.writeFileSync(outputPath, updatedLines.join('\n'), 'utf-8');
  
  console.log('\n✅ 完了!');
  console.log(`📊 統計:`);
  console.log(`   - 処理した行数: ${lines.length - 1}`);
  console.log(`   - 更新した行数: ${updatedCount}`);
  console.log(`   - すでにタグがある行数: ${alreadyHasTag}`);
  console.log(`💾 出力ファイル: ${outputPath}`);
}

// コマンドライン引数をチェック
if (process.argv.length < 4) {
  console.error('使用方法: node update_hyakumeizan_tags.mjs <入力CSV> <出力CSV>');
  console.error('');
  console.error('例:');
  console.error('  node update_hyakumeizan_tags.mjs input.csv output.csv');
  console.error('  node update_hyakumeizan_tags.mjs ~/Documents/日本百名山/CSV/mountains.csv ~/Documents/日本百名山/CSV/mountains_updated.csv');
  process.exit(1);
}

const inputPath = path.resolve(process.argv[2]);
const outputPath = path.resolve(process.argv[3]);

// ファイルの存在確認
if (!fs.existsSync(inputPath)) {
  console.error(`❌ エラー: 入力ファイルが見つかりません: ${inputPath}`);
  process.exit(1);
}

// 実行
try {
  updateCsvTags(inputPath, outputPath);
} catch (error) {
  console.error('❌ エラーが発生しました:', error.message);
  console.error(error.stack);
  process.exit(1);
}
