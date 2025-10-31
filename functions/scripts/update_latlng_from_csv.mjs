import admin from 'firebase-admin';
import fs from 'fs';
import { parse } from 'csv-parse/sync';

function resolveServiceAccount() {
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
    const fallback = './gen-lang-client-0636793764-796b85572dd7.json';
    if (!fs.existsSync(fallback)) throw new Error('サービスアカウントが見つかりません');
    return JSON.parse(fs.readFileSync(fallback, 'utf8'));
  } catch (e) {
    console.error('サービスアカウントの読み込み失敗', e);
    process.exit(1);
  }
}

const serviceAccount = resolveServiceAccount();
if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const args = process.argv.slice(2);
  const csvPath = args[0] || './reports/non_numeric_latlngs.csv';
  if (!fs.existsSync(csvPath)) {
    console.error('CSV ファイルが見つかりません:', csvPath);
    process.exit(1);
  }
  const text = fs.readFileSync(csvPath, 'utf8');
  const records = parse(text, { columns: true, skip_empty_lines: true, trim: true });
  console.log(`📥 読み込み: ${records.length} 行 from ${csvPath}`);

  let updated = 0, skipped = 0, failed = 0;
  for (const r of records) {
    const id = (r.id || '').trim();
    if (!id) { skipped++; continue; }
    const latRaw = (r.lat || '').toString().trim();
    const lngRaw = (r.lng || '').toString().trim();
    const lat = Number.isFinite(parseFloat(latRaw)) ? parseFloat(latRaw) : undefined;
    const lng = Number.isFinite(parseFloat(lngRaw)) ? parseFloat(lngRaw) : undefined;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      console.warn(`⚠️ スキップ (数値でない): ${id} ${r.name} lat='${latRaw}' lng='${lngRaw}'`);
      skipped++; continue;
    }
    try {
      await db.collection('mountains').doc(id).update({ lat, lng, needs_location: false, updated_at: admin.firestore.FieldValue.serverTimestamp() });
      console.log(`✅ 更新: ${id} ${r.name} -> lat:${lat} lng:${lng}`);
      updated++;
    } catch (e) {
      console.error(`❌ 更新失敗: ${id} ${r.name}`, e.message || e);
      failed++;
    }
  }

  console.log('\n=== 完了 ===');
  console.log(`✅ 更新: ${updated} 件`);
  console.log(`⚠️ スキップ: ${skipped} 件`);
  console.log(`❌ 失敗: ${failed} 件`);
  process.exit(0);
}

main();
