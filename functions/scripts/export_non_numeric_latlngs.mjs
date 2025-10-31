import admin from 'firebase-admin';
import fs from 'node:fs';

function resolveServiceAccount() {
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
      return JSON.parse(fs.readFileSync(p, 'utf8'));
    }
    const fallback = './gen-lang-client-0636793764-796b85572dd7.json';
    if (!fs.existsSync(fallback)) throw new Error('サービスアカウントが見つかりません');
    return JSON.parse(fs.readFileSync(fallback, 'utf8'));
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}

const serviceAccount = resolveServiceAccount();
if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const snapshot = await db.collection('mountains').get();
  const rows = [];
  snapshot.forEach(doc => {
    const d = doc.data();
    const lat = d.lat;
    const lng = d.lng;
    if (typeof lat !== 'number' || typeof lng !== 'number') {
      rows.push({ id: doc.id, name: d.name || '', pref: d.pref || '', lat: lat === undefined ? '' : String(lat), lng: lng === undefined ? '' : String(lng), tags: (d.tags||[]).join('|'), created_from_csv: d.created_from_csv || '', needs_location: d.needs_location || '' });
    }
  });

  const outDir = './reports';
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);
  const outPath = `${outDir}/non_numeric_latlngs.csv`;
  const header = 'id,name,pref,lat,lng,tags,created_from_csv,needs_location\n';
  const body = rows.map(r => `${r.id},"${r.name.replace(/"/g,'""')}","${r.pref}","${r.lat}","${r.lng}","${r.tags}","${r.created_from_csv}","${r.needs_location}"`).join('\n');
  fs.writeFileSync(outPath, header + body, 'utf8');
  console.log(`✅ Exported ${rows.length} rows to ${outPath}`);
}

main().then(()=>process.exit(0)).catch(e=>{ console.error(e); process.exit(1); });
