#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { parse } from 'csv-parse/sync';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

function norm(s) {
  if (!s) return '';
  return s.toString().replace(/（.*?）|\(.*?\)/g, '').replace(/[\s\u3000]/g, '').replace(/ヶ/g,'ケ').replace(/[・\-‐−ー]/g,'').replace(/[、,。．]/g,'').replace(/(岳|山|峰|嶺|嶽|連峰|連山)$/g,'').trim();
}

const possibleSAPaths = [path.resolve(process.cwd(), 'gen-lang-client-0636793764-796b85572dd7.json'), path.resolve(process.cwd(), '../gen-lang-client-0636793764-796b85572dd7.json')];
let saPath = possibleSAPaths.find(p=>fs.existsSync(p));
if (!saPath) { console.error('service account not found'); process.exit(1); }
const sa = JSON.parse(fs.readFileSync(saPath,'utf8'));
initializeApp({ credential: cert(sa) });
const db = getFirestore();

if (process.argv.length < 3) { console.error('usage: node nihon200_match_report.mjs <csv_path>'); process.exit(1); }
const csvPath = process.argv[2];
const raw = fs.readFileSync(csvPath,'utf8');
const records = parse(raw, { columns: true, skip_empty_lines: true });

(async()=>{
  const snap = await db.collection('mountains').get();
  const dbList = snap.docs.map(d=>({ id:d.id, name: d.data().name, name_kana: d.data().name_kana, tags: d.data().tags || [] }));
  const dbNorm = dbList.map(d=>({ ...d, n: norm(d.name), nk: d.name_kana?d.name_kana.replace(/\s+/g,'') : '' }));
  const notFound = [];
  const ambiguous = [];
  const matched = [];
  for (const r of records) {
    const rawName = r['山名'] || Object.values(r)[1];
    const kana = r['よみがな'] || Object.values(r)[2] || '';
    const n = norm(rawName);
    const nk = kana.replace(/\s+/g,'');
    let candidates = [];
    if (nk) candidates = dbNorm.filter(d=>d.nk && d.nk.includes(nk));
    if (candidates.length===0) candidates = dbNorm.filter(d=>d.n && (d.n===n || d.n.includes(n) || n.includes(d.n)));
    if (candidates.length===0) {
      const short = n.slice(0,3);
      candidates = dbNorm.filter(d=>d.n && d.n.includes(short));
    }
    if (candidates.length===0) {
      notFound.push({ name: rawName, kana });
      continue;
    }
    if (candidates.length>1) {
      const exact = candidates.filter(c=>c.name===rawName);
      if (exact.length===1) { matched.push({ name: rawName, match: exact[0]}); continue; }
      ambiguous.push({ name: rawName, kana, candidates: candidates.map(c=>c.name) });
      continue;
    }
    matched.push({ name: rawName, match: candidates[0] });
  }
  fs.writeFileSync('nihon200_matched.json', JSON.stringify(matched, null, 2));
  fs.writeFileSync('nihon200_notfound.csv', 'name,kana\n' + notFound.map(r=>`"${r.name}","${r.kana}"`).join('\n'));
  fs.writeFileSync('nihon200_ambiguous.csv', 'name,kana,candidates\n' + ambiguous.map(a=>`"${a.name}","${a.kana}","${a.candidates.join('|')}"`).join('\n'));
  console.log('report written: nihon200_matched.json (%d), nihon200_notfound.csv (%d), nihon200_ambiguous.csv (%d)', matched.length, notFound.length, ambiguous.length);
  process.exit(0);
})();
