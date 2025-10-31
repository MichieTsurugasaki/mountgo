/**
 * csv/japan-200mountains.csv をユーティリティ用途に変換
 * 1) name+pref の軽量リスト → firestore-seed/nihon_200_meizan_from_csv_name_pref.csv
 * 2) 安定ID付き trailheads テンプレ → firestore-seed/trailheads_日本二百名山_from_csv_stable.csv
 */

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { parse } from 'csv-parse/sync';

const SRC = path.resolve('../csv/japan-200mountains.csv');
const OUT_DIR = path.resolve('../firestore-seed');

function ensureOutDir() { fs.mkdirSync(OUT_DIR, { recursive: true }); }

const PREFS_FULL = [
  '北海道','青森県','岩手県','宮城県','秋田県','山形県','福島県','茨城県','栃木県','群馬県','埼玉県','千葉県','東京都','神奈川県','新潟県','富山県','石川県','福井県','山梨県','長野県','岐阜県','静岡県','愛知県','三重県','滋賀県','京都府','大阪府','兵庫県','奈良県','和歌山県','鳥取県','島根県','岡山県','広島県','山口県','徳島県','香川県','愛媛県','高知県','福岡県','佐賀県','長崎県','熊本県','大分県','宮崎県','鹿児島県','沖縄県'
];
const PREF_SHORT = new Map([
  ['北海道','北海道'],['青森','青森県'],['岩手','岩手県'],['宮城','宮城県'],['秋田','秋田県'],['山形','山形県'],['福島','福島県'],
  ['茨城','茨城県'],['栃木','栃木県'],['群馬','群馬県'],['埼玉','埼玉県'],['千葉','千葉県'],['東京','東京都'],['神奈川','神奈川県'],
  ['新潟','新潟県'],['富山','富山県'],['石川','石川県'],['福井','福井県'],['山梨','山梨県'],['長野','長野県'],['岐阜','岐阜県'],['静岡','静岡県'],['愛知','愛知県'],
  ['三重','三重県'],['滋賀','滋賀県'],['京都','京都府'],['大阪','大阪府'],['兵庫','兵庫県'],['奈良','奈良県'],['和歌山','和歌山県'],
  ['鳥取','鳥取県'],['島根','島根県'],['岡山','岡山県'],['広島','広島県'],['山口','山口県'],
  ['徳島','徳島県'],['香川','香川県'],['愛媛','愛媛県'],['高知','高知県'],
  ['福岡','福岡県'],['佐賀','佐賀県'],['長崎','長崎県'],['熊本','熊本県'],['大分','大分県'],['宮崎','宮崎県'],['鹿児島','鹿児島県'],['沖縄','沖縄県'],
]);

function extractPrefList(src) {
  const s = (src || '').toString();
  // 区切り表記の統一
  const norm = s.replace(/[|,、/]/g, '・');
  const set = new Set();
  // フル表記優先
  for (const p of PREFS_FULL) {
    if (norm.includes(p)) set.add(p);
  }
  // 短縮表記も拾う
  for (const [short, full] of PREF_SHORT.entries()) {
    if (norm.includes(short)) set.add(full);
  }
  return Array.from(set).sort();
}

function stableId(name, prefStr) {
  return crypto.createHash('sha1').update(`${name}__${prefStr}`).digest('hex');
}

function csvEsc(v) {
  const s = v == null ? '' : String(v);
  if (s.includes('"') || s.includes(',') || s.includes('\n')) return `"${s.replaceAll('"','""')}"`;
  return s;
}

function toNamePrefCsv(rows) {
  const out = [];
  out.push('mountain_name,pref');
  for (const r of rows) {
    const name = r['山名'];
    const prefs = extractPrefList(r['所在地']);
    const prefStr = prefs.join('・');
    out.push(`${csvEsc(name)},${csvEsc(prefStr)}`);
  }
  return out.join('\n');
}

function toTrailheadsStableCsv(rows) {
  const headers = [
    'mountain_id','mountain_name','pref','mountain_name_kana','mountain_lat','mountain_lng',
    'trailhead_name','trailhead_lat','trailhead_lng','access_notes','parking_spaces','public_transport','elevation_m','description','notes','source_url'
  ];
  const out = [];
  out.push(headers.join(','));
  for (const r of rows) {
    const name = r['山名'];
    const kana = r['よみがな'] || '';
    const prefs = extractPrefList(r['所在地']);
    const prefStr = prefs.join('・');
    const id = stableId(name, prefStr);
    out.push([
      csvEsc(id), csvEsc(name), csvEsc(prefStr), csvEsc(kana), '', '',
      '', '', '', '', '', '', '', '', '', ''
    ].join(','));
  }
  return out.join('\n');
}

function main() {
  if (!fs.existsSync(SRC)) {
    console.error(`❌ 入力CSVが見つかりません: ${SRC}`);
    process.exit(1);
  }
  const text = fs.readFileSync(SRC, 'utf8');
  const rows = parse(text, { columns: true, skip_empty_lines: true, trim: true });
  ensureOutDir();
  const out1 = path.join(OUT_DIR, 'nihon_200_meizan_from_csv_name_pref.csv');
  const out2 = path.join(OUT_DIR, 'trailheads_日本二百名山_from_csv_stable.csv');
  fs.writeFileSync(out1, toNamePrefCsv(rows), 'utf8');
  fs.writeFileSync(out2, toTrailheadsStableCsv(rows), 'utf8');
  console.log(`✅ 出力1: ${path.relative(path.resolve('..'), out1)}`);
  console.log(`✅ 出力2: ${path.relative(path.resolve('..'), out2)}`);
}

main();
