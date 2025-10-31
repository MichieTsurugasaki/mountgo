import admin from 'firebase-admin';
import fs from 'node:fs';

const SERVICE_ACCOUNT_PATH = './gen-lang-client-0636793764-796b85572dd7.json';

function initFirebase() {
  if (admin.apps.length === 0) {
    const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }
  return admin.firestore();
}

function toInt(v) { const n = parseInt(v, 10); return Number.isFinite(n) ? n : undefined; }

async function main() {
  const db = initFirebase();
  const snap = await db.collection('mountains').get();

  const total = snap.size;
  let withTrailheads = 0;
  let withOsm = 0;
  let withFallback = 0;
  let withCapacity = 0;
  let withToilet = 0;
  let emptyLatLng = 0;

  for (const d of snap.docs) {
    const m = d.data() || {};
    if (!Number.isFinite(Number(m.lat)) || !Number.isFinite(Number(m.lng))) emptyLatLng++;
    const ths = Array.isArray(m.trailheads) ? m.trailheads : [];
    if (ths.length > 0) withTrailheads++;
    let osm = false, fallback = false, cap = false, toilet = false;
    for (const t of ths) {
      if (t?.source === 'osm') osm = true;
      if (t?.source === 'osm-fallback') fallback = true;
      if (t?.capacity != null) cap = true;
      if (t?.hasToilet === true) toilet = true;
    }
    if (osm) withOsm++;
    if (fallback) withFallback++;
    if (cap) withCapacity++;
    if (toilet) withToilet++;
  }

  const pct = (a) => (total ? Math.round((a / total) * 100) : 0);
  console.log('Trailheads coverage');
  console.log('-------------------');
  console.log(`mountains total         : ${total}`);
  console.log(`with trailheads         : ${withTrailheads} (${pct(withTrailheads)}%)`);
  console.log(`with OSM trailheads     : ${withOsm} (${pct(withOsm)}%)`);
  console.log(`with fallback trailheads: ${withFallback} (${pct(withFallback)}%)`);
  console.log(`with capacity           : ${withCapacity} (${pct(withCapacity)}%)`);
  console.log(`with hasToilet          : ${withToilet} (${pct(withToilet)}%)`);
  console.log(`mountains missing lat/lng: ${emptyLatLng}`);
}

main().catch((e) => { console.error('fatal:', e); process.exit(1); });
