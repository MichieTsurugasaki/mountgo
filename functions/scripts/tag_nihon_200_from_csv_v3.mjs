#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { parse } from 'csv-parse/sync';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

function norm(s) {
  if (!s) return '';
  return s
    .toString()
    .replace(/（.*?）|\(.*?\)/g, '')
    .replace(/[\s\u3000]/g, '')
    .replace(/ヶ/g, 'ケ')
    .replace(/[・･·]/g, '')
    .replace(/[ー−‐]/g, '')
    .replace(/[、,。．]/g, '')
    .replace(/(岳|山|峰|嶺|嶽|連峰|連山|連峰)$/g, '')
    .trim();
}

const possibleSAPaths = [
  path.resolve(process.cwd(), 'gen-lang-client-0636793764-796b85572dd7.json'),
  path.resolve(process.cwd(), '../gen-lang-client-0636793764-796b85572dd7.json'),
];
let saPath = possibleSAPaths.find(p => fs.existsSync(p));
if (!saPath) { console.error('service account not found'); process.exit(1); }
const sa = JSON.parse(fs.readFileSync(saPath,'utf8'));
initializeApp({ credential: cert(sa) });
const db = getFirestore();

if (process.argv.length < 3) { console.error('usage: node tag_nihon_200_from_csv_v3.mjs <csv_path>'); process.exit(1); }
const csvPath = process.argv[2];
if (!fs.existsSync(csvPath)) { console.error('csv not found:', csvPath); process.exit(1); }
const raw = fs.readFileSync(csvPath,'utf8');
const records = parse(raw, { columns: true, skip_empty_lines: true });

(async () => {
  const snap = await db.collection('mountains').get();
  const dbList = snap.docs.map(d => ({ id: d.id, name: d.data().name, name_kana: d.data().name_kana, tags: d.data().tags || [] }));
  const dbNorm = dbList.map(d => ({ ...d, n: norm(d.name), nk: d.name_kana ? d.name_kana.replace(/\s+/g,'') : '' }));
  const TAG = '日本二百名山';
  const HYAKU = '日本百名山';
  let added=0, skippedHyaku=0, notFound=0, ambiguous=0;
  for (const r of records) {
    const rawName = r['山名'] || r['name'] || Object.values(r)[1];
    const kana = r['よみがな'] || r['name_kana'] || Object.values(r)[2];
    if (!rawName) continue;
    const n = norm(rawName);
    const nk = kana ? kana.replace(/\s+/g,'') : '';
    // prefer matching by kana if present
    let candidates = [];
    if (nk) candidates = dbNorm.filter(d => d.nk && d.nk.includes(nk));
    if (candidates.length === 0) candidates = dbNorm.filter(d => d.n && (d.n === n || d.n.includes(n) || n.includes(d.n)));
    if (candidates.length === 0) {
      // try includes first 3 chars
      const short = n.slice(0,3);
      candidates = dbNorm.filter(d => d.n && (d.n.includes(short)));
    }
    if (candidates.length === 0) {
      console.log('NOT FOUND:', rawName);
      notFound++;
      continue;
    }
    if (candidates.length > 1) {
      const exact = candidates.filter(c => c.name === rawName);
      if (exact.length === 1) candidates = exact;
    }
    if (candidates.length > 1) {
      console.log('AMBIGUOUS:', rawName, '->', candidates.map(c=>c.name).join(' | '));
      ambiguous++;
      continue;
    }
    const doc = candidates[0];
    const dref = db.collection('mountains').doc(doc.id);
    const dsnap = await dref.get();
    const data = dsnap.data();
    const tags = Array.isArray(data.tags) ? data.tags.slice() : (typeof data.tags === 'string' ? data.tags.split('|') : []);
    if (tags.includes(HYAKU)) { console.log('SKIP has hyaku:', rawName, '->', doc.name); skippedHyaku++; continue; }
    if (!tags.includes(TAG)) { tags.push(TAG); await dref.update({ tags }); console.log('ADDED:', rawName, '->', doc.name); added++; }
    else console.log('ALREADY:', rawName, '->', doc.name);
  }
  console.log('RESULT added=%d skippedHyaku=%d notFound=%d ambiguous=%d', added, skippedHyaku, notFound, ambiguous);
  process.exit(0);
})();
