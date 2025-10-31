#!/usr/bin/env node
/**
 * Firestore mountains コレクションをタグ付きでリスト
 */

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const serviceAccountPath = path.resolve(__dirname, '../gen-lang-client-0636793764-796b85572dd7.json');
const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

async function listWithTags() {
  const snapshot = await db.collection('mountains').get();
  
  const filterTag = process.argv[2]; // オプション: "日本二百名山" など
  
  snapshot.forEach(doc => {
    const data = doc.data();
    const tags = data.tags || [];
    
    if (filterTag && !tags.includes(filterTag)) return;
    
    console.log(`${doc.id}\t${data.name}\t${data.pref || ''}\t${tags.join('|')}`);
  });
}

listWithTags()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
