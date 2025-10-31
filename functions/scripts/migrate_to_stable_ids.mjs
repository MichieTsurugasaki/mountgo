/**
 * mountains コレクションを「安定ID(docId=name+prefのSHA1)」へ段階移行
 * - 対象はタグで絞り込み（既定: 日本百名山, 日本二百名山）
 * - 既存docを残しつつ、新doc(安定ID)を作成/マージ（安全な片側コピー）
 * - オプションで削除(--delete-legacy)も可だがデフォルトは保持
 *
 * 使い方例:
 *   node scripts/migrate_to_stable_ids.mjs                 # 既定タグ2種を対象
 *   node scripts/migrate_to_stable_ids.mjs --tag=日本百名山 --tag=日本二百名山
 *   node scripts/migrate_to_stable_ids.mjs --delete-legacy=false --dry-run
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import crypto from 'node:crypto';

function resolveServiceAccount() {
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    }
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
      return JSON.parse(fs.readFileSync(p, 'utf8'));
    }
    const fallback = './gen-lang-client-0636793764-796b85572dd7.json';
    if (!fs.existsSync(fallback)) {
      throw new Error('サービスアカウント情報が見つかりません。FIREBASE_SERVICE_ACCOUNT_JSON または GOOGLE_APPLICATION_CREDENTIALS を設定してください。');
    }
    return JSON.parse(fs.readFileSync(fallback, 'utf8'));
  } catch (e) {
    console.error('❌ サービスアカウントJSONの読み込みに失敗:', e);
    process.exit(1);
  }
}

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(resolveServiceAccount()) });
}
const db = admin.firestore();

function stableIdFor(name, pref) {
  const key = `${name}__${pref}`;
  return crypto.createHash('sha1').update(key).digest('hex');
}

function deepMerge(base, newer) {
  // 配列はユニオン、オブジェクトは再帰マージ、プリミティブは newer 優先
  if (Array.isArray(base) && Array.isArray(newer)) {
    const set = new Set([...(base||[]), ...(newer||[])]);
    return Array.from(set);
  }
  if (base && typeof base === 'object' && newer && typeof newer === 'object') {
    const out = { ...base };
    for (const [k, v] of Object.entries(newer)) {
      if (out[k] === undefined) out[k] = v;
      else out[k] = deepMerge(out[k], v);
    }
    return out;
  }
  return newer ?? base;
}

async function migrateForTag(tag, opts) {
  const qs = db.collection('mountains').where('tags', 'array-contains', tag);
  const snap = await qs.get();
  const docs = snap.docs;
  let created = 0;
  let merged = 0;
  let skipped = 0;
  let legacyDeleted = 0;
  let missingKey = 0;
  let conflicts = 0;

  for (const d of docs) {
    const data = d.data() || {};
    const name = data.name || '';
    const pref = data.pref || '';
    if (!name || !pref) {
      missingKey++;
      if (opts.verbose) console.warn(`⚠️ name/pref 不足のためスキップ: id=${d.id}, name=${name}, pref=${pref}`);
      continue;
    }
    const sid = stableIdFor(name, pref);
    if (d.id === sid) { skipped++; continue; }

    const stableRef = db.collection('mountains').doc(sid);
    const stableSnap = await stableRef.get();
    const stableData = stableSnap.exists ? (stableSnap.data() || {}) : null;

    const mergedData = stableData ? deepMerge(stableData, data) : data;
    // タグは最低限ユニオン
    const baseTags = Array.isArray(stableData?.tags) ? stableData.tags : [];
    const newTags = Array.isArray(data.tags) ? data.tags : [];
    mergedData.tags = Array.from(new Set([...baseTags, ...newTags]));
    // レガシーIDの追記
    const legacySet = new Set([...(Array.isArray(stableData?.legacy_ids) ? stableData.legacy_ids : []), d.id]);
    mergedData.legacy_ids = Array.from(legacySet);

    if (opts.dryRun) {
      if (!stableSnap.exists) created++; else merged++;
      continue; // ドライラン
    }

    await stableRef.set(mergedData, { merge: true });
    if (!stableSnap.exists) created++; else merged++;

    if (opts.deleteLegacy) {
      try {
        await d.ref.delete();
        legacyDeleted++;
      } catch (e) {
        conflicts++;
        if (opts.verbose) console.warn(`⚠️ 旧ドキュメント削除失敗 id=${d.id}:`, e.message);
      }
    }
  }

  return { total: docs.length, created, merged, skipped, legacyDeleted, missingKey, conflicts };
}

async function verify(tag) {
  const qs = db.collection('mountains').where('tags', 'array-contains', tag);
  const snap = await qs.get();
  let total = 0, stable = 0;
  for (const d of snap.docs) {
    total++;
    const data = d.data() || {};
    const sid = stableIdFor(data.name || '', data.pref || '');
    if (d.id === sid) stable++;
  }
  return { total, stable };
}

async function main() {
  const args = process.argv.slice(2);
  const opts = { tags: ['日本百名山', '日本二百名山'], dryRun: false, deleteLegacy: false, verbose: true };
  for (const a of args) {
    if (a.startsWith('--tag=')) opts.tags.push(a.substring(6));
    if (a === '--dry-run') opts.dryRun = true;
    if (a.startsWith('--delete-legacy=')) opts.deleteLegacy = a.endsWith('true');
    if (a.startsWith('--delete-legacy')) opts.deleteLegacy = true;
    if (a.startsWith('--verbose=')) opts.verbose = a.endsWith('true');
  }
  // 明示指定がある場合は既定を置き換え
  if (args.some(a => a.startsWith('--tag='))) {
    opts.tags = args.filter(a => a.startsWith('--tag=')).map(a => a.substring(6));
  }

  console.log('🚀 安定ID移行を開始');
  console.log('対象タグ:', opts.tags.join(', '));
  console.log('dryRun:', opts.dryRun, ' deleteLegacy:', opts.deleteLegacy);

  const results = [];
  for (const tag of opts.tags) {
    console.log(`\n=== タグ: ${tag} ===`);
    const r = await migrateForTag(tag, opts);
    console.log(`合計: ${r.total}, 作成: ${r.created}, マージ: ${r.merged}, スキップ(既に安定ID): ${r.skipped}, 欠落(name/pref): ${r.missingKey}, 旧削除: ${r.legacyDeleted}, 衝突: ${r.conflicts}`);
    const v = await verify(tag);
    console.log(`検証: total=${v.total}, stableId一致=${v.stable}`);
    results.push({ tag, ...r, verify: v });
  }

  console.log('\n✅ 完了');
}

main().catch(e => { console.error('❌ エラー:', e); process.exit(1); });
