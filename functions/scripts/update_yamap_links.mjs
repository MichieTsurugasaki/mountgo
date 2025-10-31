#!/usr/bin/env node

/**
 * YAMAPリンク/IDを Firestore の mountains コレクションに一括付与・更新します。
 *
 * 入力CSVの想定カラム（いずれかで特定できればOK）:
 * - target_doc_id | doc_id | id: FirestoreのドキュメントID（最優先）
 * - name: 山名
 * - pref | prefectures: 都道府県（nameとセットで曖昧性解消に使用）
 * - yamap_mountain_id: 数値のYAMAP山ID（例: 108）
 * - yamap_url: 直接の山ページURL（例: https://yamap.com/mountains/108）
 * - itinerary_yamap: コースURL（任意、あれば優先的にボタンで使用）
 *
 * 使い方:
 *   node scripts/update_yamap_links.mjs --in=../firestore-seed/yamap_links.csv --write
 * オプション:
 *   --in=<path>   入力CSV
 *   --write       実際にFirestoreへ書き込み（省略時はdry-run）
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import path from 'node:path';
import { parse } from 'csv-parse/sync';

const SERVICE_ACCOUNT_PATH = './gen-lang-client-0636793764-796b85572dd7.json';

function parseArgs() {
  const args = process.argv.slice(2);
  const out = { in: null, write: false };
  for (const a of args) {
    if (a.startsWith('--in=')) out.in = a.substring(5);
    if (a === '--write') out.write = true;
  }
  if (!out.in && args[0] && !args[0].startsWith('--')) {
    out.in = args[0];
  }
  return out;
}

function initFirebase() {
  if (admin.apps.length === 0) {
    const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }
  return admin.firestore();
}

function loadCsv(csvPath) {
  const text = fs.readFileSync(csvPath, 'utf8');
  return parse(text, { columns: true, skip_empty_lines: true, trim: true });
}

function nOrNull(v) {
  const s = (v ?? '').toString().trim();
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

async function findMountainDoc(db, { docId, name, pref }) {
  if (docId) {
    const ref = db.collection('mountains').doc(docId);
    const snap = await ref.get();
    if (snap.exists) return ref;
    return null;
  }
  if (!name) return null;
  let q = db.collection('mountains').where('name', '==', name);
  if (pref) q = q.where('pref', '==', pref);
  const qs = await q.get();
  if (qs.empty) return null;
  if (qs.size > 1) {
    console.warn(`⚠️  複数一致: name="${name}"${pref ? `, pref="${pref}"` : ''} → ${qs.size}件。スキップします。`);
    return null;
  }
  return qs.docs[0].ref;
}

async function main() {
  const opts = parseArgs();
  if (!opts.in) {
    console.log('使用方法:');
    console.log('  node scripts/update_yamap_links.mjs --in=../firestore-seed/yamap_links.csv [--write]');
    console.log('\nCSVカラム例:');
    console.log('  doc_id,name,pref,yamap_mountain_id,yamap_url,itinerary_yamap');
    process.exit(1);
  }
  const csvPath = path.resolve(opts.in);
  if (!fs.existsSync(csvPath)) {
    console.error(`❌ 入力CSVが見つかりません: ${csvPath}`);
    process.exit(1);
  }

  const db = initFirebase();
  const rows = loadCsv(csvPath);
  let ok = 0, skip = 0, notfound = 0, errs = 0;

  console.log(`📄 入力: ${csvPath}`);
  console.log(`🔎 処理件数: ${rows.length}（モード: ${opts.write ? '書き込み' : 'dry-run'}）\n`);

  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    try {
      const docId = (r.target_doc_id || r.doc_id || r.id || '').toString().trim();
      const name = (r.name || '').toString().trim();
      const pref = (r.pref || r.prefectures || '').toString().trim();
  let yamapIdNum = nOrNull(r.yamap_mountain_id);
  const yamapUrl = (r.yamap_url || '').toString().trim();
      const itineraryUrl = (r.itinerary_yamap || '').toString().trim();

      if (!docId && !name) {
        skip++;
        console.warn(`⚠️  行${i + 2}: doc_id か name のいずれかが必要です。スキップします。`);
        continue;
      }

      const ref = await findMountainDoc(db, { docId, name, pref });
      if (!ref) {
        notfound++;
        console.warn(`⚠️  行${i + 2}: 対象ドキュメントが見つかりませんでした（doc_id=${docId || '-'}, name=${name || '-'}, pref=${pref || '-'}）`);
        continue;
      }

      // yamap_url から ID を推測
      if (!yamapIdNum && yamapUrl) {
        const m = yamapUrl.match(/\/mountains\/(\d+)/);
        if (m && m[1]) {
          const guessed = Number(m[1]);
          if (Number.isFinite(guessed)) yamapIdNum = guessed;
        }
      }

      const payload = {};
      if (yamapIdNum !== null) payload.yamap_mountain_id = yamapIdNum;
      if (yamapUrl) payload.yamap_url = yamapUrl;
      if (itineraryUrl) payload.itinerary_yamap = itineraryUrl;

      if (Object.keys(payload).length === 0) {
        skip++;
        console.warn(`⚠️  行${i + 2}: 更新対象フィールドが空です。スキップします。`);
        continue;
      }

      if (opts.write) {
        await ref.set(payload, { merge: true });
      }
      ok++;
      console.log(`✓ 行${i + 2}: 更新${opts.write ? '完了' : '予定'} → ${ref.path} :: ${JSON.stringify(payload)}`);
    } catch (e) {
      errs++;
      console.error(`❌ 行${i + 2}: ${e.message}`);
    }
  }

  console.log('\n✅ 完了');
  console.log(`  - 更新${opts.write ? '' : '予定'}: ${ok}`);
  console.log(`  - スキップ: ${skip}`);
  console.log(`  - 見つからず: ${notfound}`);
  console.log(`  - エラー: ${errs}`);
}

main().catch((e) => {
  console.error('致命的エラー:', e);
  process.exit(1);
});
