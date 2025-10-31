import admin from 'firebase-admin';
import fs from 'node:fs';

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
      throw new Error('サービスアカウント情報が見つかりません。');
    }
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
  const snapshot = await db.collection('mountains').get();
  const results = [];
  snapshot.forEach(doc => {
    const d = doc.data();
    const lat = d.lat;
    const lng = d.lng;
    if (typeof lat === 'string' || typeof lng === 'string') {
      results.push({ id: doc.id, name: d.name, lat, lng });
    }
  });
  console.log(`文字列型 lat/lng 件数: ${results.length}`);
  const show = results.slice(0, 60);
  for (const r of show) {
    console.log(`${r.id} | ${r.name} | lat=${JSON.stringify(r.lat)} (${typeof r.lat}) | lng=${JSON.stringify(r.lng)} (${typeof r.lng})`);
  }
  if (results.length > show.length) console.log(`... 他 ${results.length - show.length} 件`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
