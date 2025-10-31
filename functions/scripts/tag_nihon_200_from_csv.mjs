#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { parse } from 'csv-parse/sync';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const serviceAccountPath = path.resolve(new URL(import.meta.url).pathname, '../gen-lang-client-0636793764-796b85572dd7.json');
// gen-lang path relative might not resolve; try sibling path
let saPath = serviceAccountPath;
if (!fs.existsSync(saPath)) {
  saPath = path.resolve(process.cwd(), 'gen-lang-client-0636793764-796b85572dd7.json');
}
if (!fs.existsSync(saPath)) {
  saPath = path.resolve(process.cwd(), '../gen-lang-client-0636793764-796b85572dd7.json');
}
if (!fs.existsSync(saPath)) {
  console.error('service account not found at expected paths.');
  process.exit(1);
}
const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

if (process.argv.length < 3) {
  console.error('usage: node tag_nihon_200_from_csv.mjs <csv_path>');
  process.exit(1);
}
const csvPath = process.argv[2];
if (!fs.existsSync(csvPath)) {
  console.error('CSV not found:', csvPath);
  process.exit(1);
}
const content = fs.readFileSync(csvPath, 'utf8');
const records = parse(content, { columns: true, skip_empty_lines: true });

const TAG = '日本二百名山';
const HYAKU_TAG = '日本百名山';

function normalizeName(n) {
  if (!n) return n;
  // remove fullwidth/trailing spaces
  return n.replace(/[（(].*?[）)]/g, '').trim();
}

(async () => {
  let added = 0;
  let skippedHyaku = 0;
  let notFound = 0;
  for (const r of records) {
    const rawName = r['山名'] || r['name'] || r['山名/名称'] || Object.values(r)[1];
    if (!rawName) continue;
    const name = rawName.trim();
    const candidates = [name, normalizeName(name)];
    let docs = [];
    for (const cand of candidates) {
      if (!cand) continue;
      const q = await db.collection('mountains').where('name', '==', cand).get();
      if (!q.empty) { docs = q.docs; break; }
    }
    // fallback: search by name contains
    if (docs.length === 0) {
      for (const cand of candidates) {
        if (!cand) continue;
        const q2 = await db.collection('mountains').where('name', '>=', cand).where('name', '<=', cand + '\uf8ff').get();
        if (!q2.empty) { docs = q2.docs; break; }
      }
    }
    if (docs.length === 0) {
      console.log('NOT FOUND:', name);
      notFound++;
      continue;
    }
    for (const doc of docs) {
      const data = doc.data();
      const tags = Array.isArray(data.tags) ? data.tags.slice() : (typeof data.tags === 'string' ? data.tags.split('|') : []);
      if (tags.includes(HYAKU_TAG)) {
        console.log('SKIP (has hyaku):', name, '->', doc.id);
        skippedHyaku++;
        continue;
      }
      if (!tags.includes(TAG)) {
        tags.push(TAG);
        await doc.ref.update({ tags });
        console.log('ADDED:', name, '->', doc.id);
        added++;
      } else {
        console.log('ALREADY:', name, '->', doc.id);
      }
    }
  }
  console.log('Finished. added=%d skippedHyaku=%d notFound=%d', added, skippedHyaku, notFound);
  process.exit(0);
})();
