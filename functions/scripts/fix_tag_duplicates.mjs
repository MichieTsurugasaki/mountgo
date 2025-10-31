#!/usr/bin/env node
/**
 * 日本百名山と日本二百名山の重複を解消
 * 日本百名山タグを持つ山から日本二百名山タグを削除
 * 
 * Usage:
 *   node scripts/fix_tag_duplicates.mjs [--write]
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const serviceAccountPath = path.resolve(__dirname, '../gen-lang-client-0636793764-796b85572dd7.json');
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const writeMode = process.argv.includes('--write');

async function fixDuplicates() {
  console.log(`\n🔧 モード: ${writeMode ? '書き込み (--write)' : 'ドライラン (--dry-run)'}\n`);
  
  const snapshot = await db.collection('mountains').get();
  
  console.log('【日本百名山と日本二百名山の重複チェック】\n');
  
  const duplicates = [];
  
  snapshot.forEach(doc => {
    const data = doc.data();
    const tags = data.tags || [];
    
    const has100 = tags.includes('日本百名山');
    const has200 = tags.includes('日本二百名山');
    
    if (has100 && has200) {
      duplicates.push({
        docRef: doc.ref,
        id: doc.id,
        name: data.name,
        pref: data.pref,
        tags: tags
      });
    }
  });
  
  if (duplicates.length === 0) {
    console.log('✓ 重複なし\n');
    return;
  }
  
  console.log(`⚠️  ${duplicates.length}件の重複を発見:\n`);
  
  for (const m of duplicates) {
    console.log(`\n🔍 処理中: ${m.name} (${m.pref})`);
    console.log(`  現在のタグ: ${m.tags.join(', ')}`);
    
    // 日本二百名山タグを削除
    const newTags = m.tags.filter(t => t !== '日本二百名山');
    console.log(`  新しいタグ: ${newTags.join(', ')}`);
    
    if (writeMode) {
      await m.docRef.update({ tags: newTags });
      console.log(`  💾 更新完了`);
    } else {
      console.log(`  🔧 更新予定 (--write で実行)`);
    }
  }
  
  console.log(`\n\n========== 実行結果 ==========`);
  console.log(`重複: ${duplicates.length}件`);
  console.log(`処理: ${duplicates.length}件`);
  console.log(`==============================\n`);
}

fixDuplicates()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
