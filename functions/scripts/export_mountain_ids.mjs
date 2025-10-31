/**
 * 指定タグ（既定: 日本二百名山）の山ドキュメントIDを含むテンプレートCSVを出力
 * 出力先: firestore-seed/trailheads_200_with_ids.csv
 * 使い方:
 *   node scripts/export_mountain_ids.mjs          # タグ=日本二百名山（既定）
 *   node scripts/export_mountain_ids.mjs 日本百名山  # 任意タグ
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import path from 'node:path';

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

const serviceAccount = resolveServiceAccount();
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

function csvEscape(value) {
  const s = value == null ? '' : String(value);
  if (s.includes('"') || s.includes(',') || s.includes('\n')) {
    return '"' + s.replaceAll('"', '""') + '"';
  }
  return s;
}

async function main() {
  // 引数: [TAG] または --tag=XXX / --stdout
  const args = process.argv.slice(2);
  let TAG = '日本二百名山';
  let toStdout = false;
  for (const a of args) {
    if (a === '--stdout') toStdout = true;
    else if (a.startsWith('--tag=')) TAG = a.substring(6);
    else if (!a.startsWith('--')) TAG = a; // 後方互換: 第1引数にタグ
  }
  console.log(`🔎 タグ「${TAG}」の山をエクスポートします...`);

  const snap = await db.collection('mountains').where('tags', 'array-contains', TAG).get();
  const items = snap.docs.map(d => ({ id: d.id, ...d.data() }));
  items.sort((a, b) => (a.pref || '').localeCompare(b.pref || '', 'ja') || (a.name || '').localeCompare(b.name || '', 'ja'));

  // ワークスペース直下の firestore-seed に出力
  const outDir = path.resolve('../firestore-seed');
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, `trailheads_${TAG}_with_ids.csv`.replaceAll('/', '_'));

  const headers = [
    'mountain_id',
    'mountain_name',
    'pref',
    'mountain_name_kana',
    'mountain_lat',
    'mountain_lng',
    // 以下は登山口用の入力カラム（空で出力）。1山に複数行OK。
    'trailhead_name',
    'trailhead_lat',
    'trailhead_lng',
    'access_notes',
    'parking_spaces',
    'public_transport',
    'elevation_m',
    'description',
    'notes',
    'source_url'
  ];

  const lines = [];
  lines.push(headers.join(','));
  for (const m of items) {
    const row = [
      csvEscape(m.id),
      csvEscape(m.name || ''),
      csvEscape(m.pref || ''),
      csvEscape(m.name_kana || ''),
      csvEscape(Number.isFinite(m.lat) ? m.lat : ''),
      csvEscape(Number.isFinite(m.lng) ? m.lng : ''),
      // 以下、テンプレート空欄
      '', // trailhead_name
      '', // trailhead_lat
      '', // trailhead_lng
      '', // access_notes
      '', // parking_spaces
      '', // public_transport
      '', // elevation_m
      '', // description
      '', // notes
      ''  // source_url
    ].join(',');
    lines.push(row);
  }

  const content = lines.join('\n');
  if (toStdout) {
    // そのまま標準出力
    console.log(content);
  } else {
    fs.writeFileSync(outPath, content, 'utf8');
  console.log(`✅ 出力完了: ${path.relative(path.resolve('..'), outPath)}`);
    console.log('列の意味:');
    console.log('  - mountain_id: mountainsコレクションのドキュメントID（ユニーク）');
    console.log('  - mountain_name/pref/...: 参照用（編集不要）');
    console.log('  - trailhead_*: 登山口情報を入力。1つのmountain_idに対して複数行追加可');
  }
}

main().catch((e) => {
  console.error('❌ エクスポートに失敗:', e);
  process.exit(1);
});
