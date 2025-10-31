#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { parse } from 'csv-parse/sync';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const possibleSA = [
  path.resolve(process.cwd(), 'gen-lang-client-0636793764-796b85572dd7.json'),
  path.resolve(process.cwd(), '../gen-lang-client-0636793764-796b85572dd7.json')
];
let saPath = possibleSA.find(p=>fs.existsSync(p));
if (!saPath) { console.error('service account not found'); process.exit(1); }
const sa = JSON.parse(fs.readFileSync(saPath,'utf8'));
initializeApp({ credential: cert(sa) });
const db = getFirestore();

const csvPath = process.argv[2] || path.resolve(process.cwd(), 'nihon200_notfound.csv');
if (!fs.existsSync(csvPath)) { console.error('csv not found:', csvPath); process.exit(1); }
const raw = fs.readFileSync(csvPath,'utf8');
const records = parse(raw, { columns: true, skip_empty_lines: true });

function normalize(s) {
  if (!s) return '';
  return s.toString().replace(/（.*?）|\(.*?\)/g,'').replace(/[\s\u3000]/g,'').replace(/ヶ/g,'ケ').replace(/[・\-‐−ー]/g,'').replace(/[、,。．]/g,'').replace(/(岳|山|峰|嶺|嶽|連峰|連山)$/g,'').trim();
}

(async ()=>{
  let created = 0;
  for (const r of records) {
    const name = r['name'] || r['山名'] || Object.values(r)[0];
    const kana = r['kana'] || r['よみがな'] || Object.values(r)[1] || '';
    if (!name) continue;
    const n = normalize(name);
    // check existing by exact name or normalized
    let q = await db.collection('mountains').where('name', '==', name).get();
    if (!q.empty) { console.log('EXISTS exact:', name); continue; }
    // scan all and check normalized
    const all = await db.collection('mountains').get();
    let found = false;
    for (const doc of all.docs) {
      const dname = doc.data().name || '';
      const dn = normalize(dname);
      if (dn && (dn === n || dn.includes(n) || n.includes(dn))) { found = true; break; }
    }
    if (found) { console.log('EXISTS norm:', name); continue; }
    // create placeholder
    const docRef = await db.collection('mountains').add({
      name: name,
      name_kana: kana || null,
      pref: '',
      lat: null,
      lng: null,
      tags: ['日本二百名山'],
      created_from_csv: 'nihon200',
      needs_location: true,
      description: '',
      created_at: new Date().toISOString()
    });
    console.log('CREATED placeholder:', name, '->', docRef.id);
    created++;
  }
  console.log('Done. created=%d', created);
  process.exit(0);
})();
