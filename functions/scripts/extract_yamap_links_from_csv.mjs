#!/usr/bin/env node

/**
 * 既存のCSVから YAMAP の山ページURL/コースURLを抽出し、
 * update_yamap_links.mjs で読み込めるテンプレ形式に変換します。
 *
 * 使い方:
 *   node scripts/extract_yamap_links_from_csv.mjs --in=<入力CSV> [--out=<出力CSV>]
 *
 * 入力CSVの想定（柔軟に対応）
 * - name | 山名
 * - pref | prefectures | 所在地 | area
 * - yamap_url 系の列（例: yamap_url, yamap_link, YAMAP_URL など）
 *   → 値が http を含み yamap.com を含むものを URL とみなす
 * - itinerary_yamap（任意）: コースURL
 */

import fs from 'node:fs';
import path from 'node:path';
import { parse } from 'csv-parse/sync';

function parseArgs() {
  const args = process.argv.slice(2);
  const out = { in: null, out: null };
  for (const a of args) {
    if (a.startsWith('--in=')) out.in = a.substring(5);
    if (a.startsWith('--out=')) out.out = a.substring(6);
  }
  if (!out.in && args[0] && !args[0].startsWith('--')) out.in = args[0];
  return out;
}

function loadCsv(p) {
  const text = fs.readFileSync(p, 'utf8');
  return parse(text, { columns: true, skip_empty_lines: true, trim: true, relax_column_count: true });
}

function csvEscape(v) {
  const s = (v ?? '').toString();
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

function pickField(obj, keys) {
  for (const k of keys) {
    if (obj[k] != null && obj[k] !== '') return obj[k];
  }
  return '';
}

function extractYamapUrlFromRow(row) {
  // 優先: 明示列
  const direct = pickField(row, ['yamap_url', 'YAMAP_URL', 'yamapLink', 'yamap_link']);
  if (typeof direct === 'string' && direct.includes('http') && direct.includes('yamap.com')) {
    return direct.trim();
  }
  // スキャン: すべての列の中から yamap.com を含むURLを探す（tairyoku_yamap など文字列は除外）
  for (const [k, vRaw] of Object.entries(row)) {
    const v = (vRaw ?? '').toString();
    if (!v) continue;
    if (v.includes('http') && v.includes('yamap.com')) {
      // 文字列スコア（URLらしさ）: スラッシュ含む or https:// で始まる
      if (/^https?:\/\//.test(v) || v.includes('/')) return v.trim();
    }
  }
  return '';
}

function extractIdFromYamapUrl(url) {
  if (!url) return '';
  const m = url.match(/\/mountains\/(\d+)/);
  return m && m[1] ? m[1] : '';
}

async function main() {
  const opts = parseArgs();
  if (!opts.in) {
    console.log('使用方法: node scripts/extract_yamap_links_from_csv.mjs --in=<入力CSV> [--out=<出力CSV>]');
    process.exit(1);
  }
  const inPath = path.resolve(opts.in);
  if (!fs.existsSync(inPath)) {
    console.error(`❌ 入力CSVが見つかりません: ${inPath}`);
    process.exit(1);
  }
  const outPath = path.resolve(opts.out || path.join(path.dirname(inPath), 'yamap_links_extracted.csv'));

  const rows = loadCsv(inPath);
  console.log(`📄 入力: ${inPath} / 件数: ${rows.length}`);

  const header = 'doc_id,name,pref,yamap_mountain_id,yamap_url,itinerary_yamap';
  const outLines = [header];

  let withUrl = 0;
  for (const row of rows) {
    const name = pickField(row, ['name', '山名']).toString().trim();
    const pref = pickField(row, ['pref', 'prefectures', '所在地', 'area']).toString().trim();
    const yamapUrl = extractYamapUrlFromRow(row);
    const yamapMountainId = extractIdFromYamapUrl(yamapUrl);
    const itinerary = pickField(row, ['itinerary_yamap', 'コースURL']).toString().trim();

    if (yamapUrl) withUrl++;

    const line = [
      '', // doc_id は空（後続の update で name+pref で特定 or 手動で埋める）
      name,
      pref,
      yamapMountainId,
      yamapUrl,
      itinerary,
    ].map(csvEscape).join(',');
    outLines.push(line);
  }

  fs.writeFileSync(outPath, outLines.join('\n'), 'utf8');
  console.log(`\n✅ 変換完了: ${outPath}`);
  console.log(`   - YAMAP URL 抽出: ${withUrl}/${rows.length}`);
}

main().catch(e => {
  console.error('致命的エラー:', e);
  process.exit(1);
});
