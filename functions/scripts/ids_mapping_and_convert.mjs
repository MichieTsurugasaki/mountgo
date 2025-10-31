/**
 * 安定ID（name+pref の SHA1）マッピング出力＆CSV置換ツール
 *
 * 使い方:
 *   # 1) マッピングCSVを出力（タグで対象を絞る）
 *   node scripts/ids_mapping_and_convert.mjs mapping --tag=日本二百名山
 *     -> 出力: firestore-seed/mountains_ids_mapping_日本二百名山.csv
 *
 *   # 2) 既存のテンプレートCSVの mountain_id を安定IDに置換
 *   node scripts/ids_mapping_and_convert.mjs convert --in=../firestore-seed/trailheads_日本二百名山_with_ids.csv \
 *       --out=../firestore-seed/trailheads_日本二百名山_with_ids_stable.csv --by=name+pref
 *     --by=name+pref: CSV中の mountain_name + pref から安定IDを算出して置換
 *     --by=id       : CSVの mountain_id を現行IDとみなし、Firestoreから name/pref を取得して算出
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { parse } from 'csv-parse/sync';

function resolveServiceAccount() {
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    }
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
      return JSON.parse(fs.readFileSync(p, 'utf8'));
    }
    const fallback = './gen-lang-client-0636793764-796b85572dd7.json';
    if (!fs.existsSync(fallback)) {
      throw new Error('サービスアカウント情報が見つかりません。FIREBASE_SERVICE_ACCOUNT_JSON または GOOGLE_APPLICATION_CREDENTIALS を設定してください。');
    }
    return JSON.parse(fs.readFileSync(fallback, 'utf8'));
  } catch (e) {
    console.error('❌ サービスアカウントJSONの読み込みに失敗:', e);
    process.exit(1);
  }
}

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(resolveServiceAccount()) });
}
const db = admin.firestore();

function stableIdFor(name, pref) {
  const key = `${name}__${pref}`;
  return crypto.createHash('sha1').update(key).digest('hex');
}

function csvEscape(value) {
  const s = value == null ? '' : String(value);
  if (s.includes('"') || s.includes(',') || s.includes('\n')) {
    return '"' + s.replaceAll('"', '""') + '"';
  }
  return s;
}

async function exportMapping(tag) {
  // ワークスペース直下の firestore-seed に出力
  const outDir = path.resolve('../firestore-seed');
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `mountains_ids_mapping_${tag}.csv`.replaceAll('/', '_'));
  console.log(`🔎 マッピングを作成中（タグ: ${tag}）...`);
  const qs = db.collection('mountains').where('tags', 'array-contains', tag);
  const snap = await qs.get();
  const items = snap.docs.map(d => ({ id: d.id, ...d.data() }));
  items.sort((a,b) => (a.pref||'').localeCompare(b.pref||'', 'ja') || (a.name||'').localeCompare(b.name||'', 'ja'));
  const lines = [];
  lines.push('current_id,stable_id,name,pref');
  for (const m of items) {
    const st = stableIdFor(m.name || '', m.pref || '');
    lines.push([
      csvEscape(m.id),
      csvEscape(st),
      csvEscape(m.name || ''),
      csvEscape(m.pref || ''),
    ].join(','));
  }
  fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
  console.log(`✅ 出力: ${path.relative(path.resolve('..'), outPath)}`);
}

async function convertCsv(inPath, outPath, mode) {
  console.log(`🔄 置換: ${inPath} → ${outPath} （by=${mode}）`);
  const raw = fs.readFileSync(inPath, 'utf8');
  // 先頭にログ等が混在する可能性に配慮して、ヘッダー行を探す
  const headerLine = raw.split(/\r?\n/).find(l => l.startsWith('mountain_id,'));
  if (!headerLine) throw new Error('ヘッダー（mountain_id, ...）が見つかりません');
  const idx = raw.indexOf(headerLine);
  const text = raw.slice(idx);
  const records = parse(text, { columns: true, skip_empty_lines: true, trim: true });

  if (mode === 'id') {
    // 現行IDから name/pref を取得して stable を算出
    const out = [];
    for (const r of records) {
      const id = r.mountain_id;
      if (!id) { out.push(r); continue; }
      const doc = await db.collection('mountains').doc(id).get();
      const d = doc.data() || {};
      r.mountain_id = stableIdFor(d.name || '', d.pref || '');
      out.push(r);
    }
    // 書き出し
    const headers = Object.keys(out[0] || {});
    const lines = [headers.join(',')];
    for (const r of out) {
      lines.push(headers.map(h => csvEscape(r[h])).join(','));
    }
    fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
    console.log(`✅ 書き出し完了: ${outPath}`);
    return;
  }

  // name+pref から安定IDを算出
  const out = records.map(r => ({ ...r, mountain_id: stableIdFor(r.mountain_name || '', r.pref || '') }));
  const headers = Object.keys(out[0] || {});
  const lines = [headers.join(',')];
  for (const r of out) lines.push(headers.map(h => csvEscape(r[h])).join(','));
  fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
  console.log(`✅ 書き出し完了: ${outPath}`);
}

async function main() {
  const args = process.argv.slice(2);
  const sub = args[0];
  const opts = args.slice(1).reduce((acc, cur) => {
    if (cur.startsWith('--tag=')) acc.tag = cur.substring(6);
    if (cur.startsWith('--in=')) acc.in = cur.substring(5);
    if (cur.startsWith('--out=')) acc.out = cur.substring(6);
    if (cur.startsWith('--by=')) acc.by = cur.substring(5);
    return acc;
  }, { tag: '日本二百名山', by: 'name+pref' });

  if (sub === 'mapping') {
    await exportMapping(opts.tag);
    return;
  }
  if (sub === 'convert') {
    if (!opts.in || !opts.out) throw new Error('convert には --in と --out が必要です');
    await convertCsv(path.resolve(opts.in), path.resolve(opts.out), opts.by);
    return;
  }

  console.log('使用方法:');
  console.log('  node scripts/ids_mapping_and_convert.mjs mapping --tag=日本二百名山');
  console.log('  node scripts/ids_mapping_and_convert.mjs convert --in=<in.csv> --out=<out.csv> [--by=name+pref|id]');
}

main().catch(e => { console.error('❌ エラー:', e); process.exit(1); });
