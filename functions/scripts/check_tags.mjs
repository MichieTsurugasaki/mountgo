import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// サービスアカウントキーを読み込み
const serviceAccountPath = path.resolve(__dirname, '../gen-lang-client-0636793764-796b85572dd7.json');
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

async function checkTags() {
  const snapshot = await db.collection('mountains').get();
  console.log(`総山数: ${snapshot.size}`);
  
  const stats = {
    total: snapshot.size,
    with百名山: 0,
    with二百名山: 0,
    noTags: 0,
    missingLocation: [],
    zeroLocation: [],
    stringLocation: []
  };
  
  snapshot.forEach(doc => {
    const data = doc.data();
    const tags = data.tags || [];
    
    if (tags.includes('日本百名山')) stats.with百名山++;
    if (tags.includes('日本二百名山')) stats.with二百名山++;
    if (tags.length === 0) stats.noTags++;
    
    const lat = data.lat;
    const lng = data.lng;
    
    if (lat === undefined || lng === undefined) {
      stats.missingLocation.push(`${doc.id} (${data.name})`);
    } else if (lat === 0 || lng === 0) {
      stats.zeroLocation.push(`${doc.id} (${data.name})`);
    } else if (typeof lat !== 'number' || typeof lng !== 'number') {
      stats.stringLocation.push(`${doc.id} (${data.name}) lat=${typeof lat} lng=${typeof lng}`);
    }
  });
  
  console.log(`\n【タグ統計】`);
  console.log(`日本百名山タグあり: ${stats.with百名山}`);
  console.log(`日本二百名山タグあり: ${stats.with二百名山}`);
  console.log(`タグなし: ${stats.noTags}`);
  
  console.log(`\n【位置情報問題】`);
  console.log(`lat/lng未定義: ${stats.missingLocation.length}`);
  if (stats.missingLocation.length > 0 && stats.missingLocation.length <= 10) {
    stats.missingLocation.forEach(m => console.log(`  - ${m}`));
  }
  
  console.log(`lat/lngがゼロ: ${stats.zeroLocation.length}`);
  if (stats.zeroLocation.length > 0 && stats.zeroLocation.length <= 10) {
    stats.zeroLocation.forEach(m => console.log(`  - ${m}`));
  }
  
  console.log(`lat/lngが文字列: ${stats.stringLocation.length}`);
  if (stats.stringLocation.length > 0 && stats.stringLocation.length <= 10) {
    stats.stringLocation.forEach(m => console.log(`  - ${m}`));
  }
}

checkTags().then(() => process.exit(0)).catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
