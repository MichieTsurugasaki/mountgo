import admin from 'firebase-admin';
import fs from 'fs';

function resolveServiceAccount() {
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
    const fallback = './gen-lang-client-0636793764-796b85572dd7.json';
    if (!fs.existsSync(fallback)) throw new Error('サービスアカウントが見つかりません');
    return JSON.parse(fs.readFileSync(fallback, 'utf8'));
  } catch (e) {
    console.error('サービスアカウント読み込み失敗', e);
    process.exit(1);
  }
}

const serviceAccount = resolveServiceAccount();
if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const updates = [
    { id: 'FAt31dGbFMIQGUNLIaXY', lat: 35.3606, lng: 138.7274 },
    { id: 'Y6B2Wq7SZxR5C7i9BU3J', lat: 35.625, lng: 139.24361 }
  ];

  let ok = 0, fail = 0;
  for (const u of updates) {
    try {
      await db.collection('mountains').doc(u.id).update({ lat: u.lat, lng: u.lng, needs_location: false, updated_at: admin.firestore.FieldValue.serverTimestamp() });
      console.log(`✅ 更新: ${u.id} -> lat:${u.lat} lng:${u.lng}`);
      ok++;
    } catch (e) {
      console.error(`❌ 更新失敗: ${u.id}`, e.message || e);
      fail++;
    }
  }

  console.log(`\n完了: 成功 ${ok} 件, 失敗 ${fail} 件`);
  process.exit(fail ? 1 : 0);
}

main();
