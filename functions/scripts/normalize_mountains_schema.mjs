#!/usr/bin/env node
import admin from 'firebase-admin';
import fs from 'fs';

// Usage:
//   export GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json
//   node functions/scripts/normalize_mountains_schema.mjs
// Notes:
//   This script backfills/normalizes fields on mountains documents so the app can rely on a stable schema.

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}

const db = admin.firestore();

function ensureArray(v) {
  if (Array.isArray(v)) return v.map(String);
  if (v == null) return [];
  return [String(v)];
}

function str(v, fallback = '') {
  if (v === undefined || v === null) return fallback;
  return String(v);
}

async function run() {
  const snap = await db.collection('mountains').get();
  console.log(`Found ${snap.size} mountains`);
  let updated = 0;

  for (const doc of snap.docs) {
    const m = doc.data();

    const patch = {};

    // Required: name, pref, lat, lng
    // Optional but expected by app: level, courseTime, accessCar/accessPublic or time_car/time_public, styles, purposes, access, tags, description, course

    if (!('level' in m)) patch.level = '';
    if (!('courseTime' in m)) patch.courseTime = '—';

    // Access fields: keep both app-friendly keys and legacy keys if present
  if (!('accessCar' in m) && !('time_car' in m)) patch.accessCar = '';
  if (!('accessPublic' in m) && !('time_public' in m)) patch.accessPublic = '';

  // Legacy → New mapping
  if (!('accessCar' in m) && ('time_car' in m)) patch.accessCar = String(m.time_car);
  if (!('accessPublic' in m) && ('time_public' in m)) patch.accessPublic = String(m.time_public);
  if (!('course' in m) && ('popularRoute' in m)) patch.course = String(m.popularRoute);

    // Arrays
    if (!('styles' in m)) patch.styles = [];
    if (!('purposes' in m)) patch.purposes = [];
    if (!('tags' in m)) patch.tags = [];

    // Derive tags from boolean flags if present
    const tags = Array.isArray(m.tags) ? [...m.tags] : [];
    if (m.has_hut === 1 || m.has_hut === true) tags.push('山小屋');
    if (m.has_tent === 1 || m.has_tent === true) tags.push('テント泊');
    if (m.has_onsen === 1 || m.has_onsen === true) tags.push('温泉');
    if (m.has_local_food === 1 || m.has_local_food === true) tags.push('郷土料理');
    if (m.has_cablecar === 1 || m.has_cablecar === true) tags.push('ケーブルカー');
    if (m.has_ropeway === 1 || m.has_ropeway === true) tags.push('ロープウェイ');
    if (tags.length > 0) patch.tags = [...new Set(tags.map(String))];

    // styles/purposes pipe-delimited strings → arrays
    if (!Array.isArray(m.styles) && typeof m.styles === 'string' && m.styles.includes('|')) {
      patch.styles = m.styles.split('|').map(s => String(s).trim()).filter(Boolean);
    }
    if (!Array.isArray(m.purposes) && typeof m.purposes === 'string' && m.purposes.includes('|')) {
      patch.purposes = m.purposes.split('|').map(s => String(s).trim()).filter(Boolean);
    }
    if (!('access' in m)) patch.access = [];

    // Normalize string fields if present but not string
    const toStringIfPresent = ['name','pref','course','description','level','courseTime','accessCar','accessPublic'];
    for (const k of toStringIfPresent) {
      if (k in m && typeof m[k] !== 'string') {
        patch[k] = String(m[k]);
      }
    }

    // Skip update if no changes
    if (Object.keys(patch).length === 0) continue;

    await doc.ref.set(patch, { merge: true });
    updated++;
    if (updated % 20 === 0) console.log(`Updated ${updated}`);
  }

  console.log(`Done. Updated ${updated} docs.`);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
