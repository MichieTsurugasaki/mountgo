/**
 * CSVから山データを一括インポートするスクリプト
 * 日本百名山/二百名山など、CSVで用意したデータを一括登録
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import path from 'node:path';
import { parse } from 'csv-parse/sync';
import crypto from 'node:crypto';

// Firebase Admin 初期化（環境変数優先、なければローカルのJSONにフォールバック）
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

const serviceAccount = resolveServiceAccount();
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}
const db = admin.firestore();

/**
 * 必須カラム定義
 */
const REQUIRED_COLUMNS = [
  'name','pref','elevation','lat','lng','level'
];

/**
 * CSVのヘッダー検証
 */
function validateHeaders(header) {
  const missing = REQUIRED_COLUMNS.filter((h) => !header.includes(h));
  if (missing.length > 0) {
    const msg = `必須カラムが不足しています: ${missing.join(', ')}\n`+
      `ヘッダー例: ${REQUIRED_COLUMNS.join(', ')}, elevation, course_time_total, time_car, time_public, ...`;
    throw new Error(msg);
  }
}

/**
 * CSVファイルを読み込んでFirestoreに登録
 * 
 * CSV形式（例）:
 * name,pref,elevation,lat,lng,level,course_time_total,time_car,time_public,description
 * 富士山,静岡県,3776,35.3606,138.7274,上級,600,180,240,日本最高峰...
 */
function parseList(v) {
  if (!v) return [];
  if (Array.isArray(v)) return v;
  return String(v)
    .split('|')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

// --- 日本の都道府県名リスト（簡易） ---
const PREFS = [
  '北海道','青森県','岩手県','宮城県','秋田県','山形県','福島県',
  '茨城県','栃木県','群馬県','埼玉県','千葉県','東京都','神奈川県',
  '新潟県','富山県','石川県','福井県','山梨県','長野県','岐阜県','静岡県','愛知県',
  '三重県','滋賀県','京都府','大阪府','兵庫県','奈良県','和歌山県',
  '鳥取県','島根県','岡山県','広島県','山口県',
  '徳島県','香川県','愛媛県','高知県',
  '福岡県','佐賀県','長崎県','熊本県','大分県','宮崎県','鹿児島県','沖縄県'
];

function extractPrefFromLocation(loc = '') {
  const s = String(loc);
  // 1) フル名称での一致
  let hit = PREFS.filter((p) => s.includes(p));
  // 2) ベース名称（県/府/都/道を省いた形）でも試す（例: "岩手/秋田…"）
  if (hit.length === 0) {
    const baseMap = new Map([
      ['北海道','北海道'],
      ['青森','青森県'],['岩手','岩手県'],['宮城','宮城県'],['秋田','秋田県'],['山形','山形県'],['福島','福島県'],
      ['茨城','茨城県'],['栃木','栃木県'],['群馬','群馬県'],['埼玉','埼玉県'],['千葉','千葉県'],['東京','東京都'],['神奈川','神奈川県'],
      ['新潟','新潟県'],['富山','富山県'],['石川','石川県'],['福井','福井県'],['山梨','山梨県'],['長野','長野県'],['岐阜','岐阜県'],['静岡','静岡県'],['愛知','愛知県'],
      ['三重','三重県'],['滋賀','滋賀県'],['京都','京都府'],['大阪','大阪府'],['兵庫','兵庫県'],['奈良','奈良県'],['和歌山','和歌山県'],
      ['鳥取','鳥取県'],['島根','島根県'],['岡山','岡山県'],['広島','広島県'],['山口','山口県'],
      ['徳島','徳島県'],['香川','香川県'],['愛媛','愛媛県'],['高知','高知県'],
      ['福岡','福岡県'],['佐賀','佐賀県'],['長崎','長崎県'],['熊本','熊本県'],['大分','大分県'],['宮崎','宮崎県'],['鹿児島','鹿児島県'],['沖縄','沖縄県']
    ]);
    const parts = s.split(/[\／/・\s]/).map((t) => t.trim()).filter(Boolean);
    const found = new Set();
    for (const part of parts) {
      for (const [base, full] of baseMap.entries()) {
        if (part.startsWith(base)) {
          found.add(full);
        }
      }
    }
    hit = Array.from(found);
  }
  return hit.length ? Array.from(new Set(hit)).join('・') : '';
}

async function validateCSV200(csvFilePath) {
  const text = fs.readFileSync(csvFilePath, 'utf8');
  const parsed = parse(text, { columns: true, skip_empty_lines: true, trim: true });
  const header = Object.keys(parsed[0] || {});
  const required = ['番号','山名','よみがな','所在地'];
  const missing = required.filter((h) => !header.includes(h));
  if (missing.length) {
    throw new Error(`二百名山フォーマットの必須カラムが不足: ${missing.join(', ')}`);
  }
  let ok = 0, bad = 0, i = 1;
  for (const r of parsed) {
    const errs = [];
    if (!String(r['山名'] || '').trim()) errs.push('山名');
    const pref = extractPrefFromLocation(r['所在地']);
    if (!pref) errs.push('所在地→都道府県抽出');
    if (errs.length) {
      console.error(`❌ 行${i}: ${errs.join(', ')}`);
      bad++;
    } else {
      ok++;
    }
    i++;
  }
  console.log(`\n検証結果(200): OK ${ok} / NG ${bad} / 合計 ${ok+bad}`);
  if (bad > 0) process.exit(1);
}

async function importFromCSV200(csvFilePath, options = {}) {
  const { appendTag, match: matchMode = 'name', normalizeName, docId: docIdMode } = options;
  console.log(`📄 [200] CSVファイルを読み込みます: ${csvFilePath}\n`);
  const text = fs.readFileSync(csvFilePath, 'utf8');
  const parsed = parse(text, { columns: true, skip_empty_lines: true, trim: true });
  const header = Object.keys(parsed[0] || {});
  const required = ['番号','山名','よみがな','所在地'];
  const missing = required.filter((h) => !header.includes(h));
  if (missing.length) {
    throw new Error(`二百名山フォーマットの必須カラムが不足: ${missing.join(', ')}`);
  }
  console.log(`📊 ${parsed.length}件のデータを処理します\n`);
  const mountainsRef = db.collection('mountains');
  let successCount = 0, errorCount = 0, i = 1;
  for (const r of parsed) {
    try {
      const name = String(r['山名'] || '').trim();
      const nameKana = String(r['よみがな'] || '').trim();
      const pref = extractPrefFromLocation(r['所在地']);
      if (!name || !pref) {
        console.error(`❌ 行${i}: 必須不足 name/pref`);
        errorCount++; i++; continue;
      }
      // 正規化: 都道府県プレフィックスを名前へ付与（追加時を推奨）
      function basePref(prefFull) {
        const map = new Map([
          ['北海道','北海道'],
          ['青森県','青森'],['岩手県','岩手'],['宮城県','宮城'],['秋田県','秋田'],['山形県','山形'],['福島県','福島'],
          ['茨城県','茨城'],['栃木県','栃木'],['群馬県','群馬'],['埼玉県','埼玉'],['千葉県','千葉'],['東京都','東京'],['神奈川県','神奈川'],
          ['新潟県','新潟'],['富山県','富山'],['石川県','石川'],['福井県','福井'],['山梨県','山梨'],['長野県','長野'],['岐阜県','岐阜'],['静岡県','静岡'],['愛知県','愛知'],
          ['三重県','三重'],['滋賀県','滋賀'],['京都府','京都'],['大阪府','大阪'],['兵庫県','兵庫'],['奈良県','奈良'],['和歌山県','和歌山'],
          ['鳥取県','鳥取'],['島根県','島根'],['岡山県','岡山'],['広島県','広島'],['山口県','山口'],
          ['徳島県','徳島'],['香川県','香川'],['愛媛県','愛媛'],['高知県','高知'],
          ['福岡県','福岡'],['佐賀県','佐賀'],['長崎県','長崎'],['熊本県','熊本'],['大分県','大分'],['宮崎県','宮崎'],['鹿児島県','鹿児島'],['沖縄県','沖縄']
        ]);
        // 複数都道府県は先頭のみ採用
        const first = String(prefFull).split('・')[0];
        return map.get(first) || first.replace(/[都道府県]$/,'');
      }
      const normalizedName = (() => {
        if (!normalizeName) return name;
        const bp = basePref(pref);
        if (normalizeName === 'pref') return `${bp}${name}`; // 例: 秋田駒ヶ岳
        if (normalizeName === 'pref-full') return `${pref}${name}`; // 例: 秋田県駒ヶ岳
        return name;
      })();

      // 安定ID: name+pref のハッシュ
      function stableIdFor(nm, pf) {
        const key = `${nm}__${pf}`;
        return crypto.createHash('sha1').update(key).digest('hex');
      }
      // 追加フィールド（任意）を解釈
      const levelVal = (r.level || '').toString().trim();
      const level = ['初級','中級','上級'].includes(levelVal) ? levelVal : '中級';
      const elevation = Number.isFinite(parseInt(r.elevation)) ? parseInt(r.elevation) : undefined;
      const lat = Number.isFinite(parseFloat(r.lat)) ? parseFloat(r.lat) : undefined;
      const lng = Number.isFinite(parseFloat(r.lng)) ? parseFloat(r.lng) : undefined;
      const course_time_total = Number.isFinite(parseInt(r.course_time_total)) ? parseInt(r.course_time_total) : undefined;
      const course_time_up = Number.isFinite(parseInt(r.course_time_up)) ? parseInt(r.course_time_up) : undefined;
      const course_time_down = Number.isFinite(parseInt(r.course_time_down)) ? parseInt(r.course_time_down) : undefined;
      const time_car = Number.isFinite(parseInt(r.time_car)) ? parseInt(r.time_car) : undefined;
      const time_public = Number.isFinite(parseInt(r.time_public)) ? parseInt(r.time_public) : undefined;
      const time = (r.time || '').toString();
      const trailhead_name = (r.trailhead_name || '').toString();
      const styles = parseList(r.styles);
      const purposes = parseList(r.purposes);
      const access = parseList(r.access);
      const tags = parseList(r.tags);
      if (appendTag && !tags.includes(appendTag)) tags.push(appendTag);
      const description = (r.description || '').toString();
      const difficulty_score = Number.isFinite(parseInt(r.difficulty_score)) ? parseInt(r.difficulty_score) : undefined;
      const has_ropeway = r.has_ropeway === 'true' || r.has_ropeway === '1' ? true : undefined;
      const has_cablecar = r.has_cablecar === 'true' || r.has_cablecar === '1' ? true : undefined;
      const has_hut = r.has_hut === 'true' || r.has_hut === '1' ? true : undefined;
      const has_tent = r.has_tent === 'true' || r.has_tent === '1' ? true : undefined;
      const has_onsen = r.has_onsen === 'true' || r.has_onsen === '1' ? true : undefined;
      const has_local_food = r.has_local_food === 'true' || r.has_local_food === '1' ? true : undefined;

      // 既存照合: デフォルトは name、--match=name+pref 指定時は name + pref 一致を採用
      let docIdToUpdate = null;
      let existing = null;
      if (matchMode === 'name+pref') {
        const q = await mountainsRef.where('name', '==', name).get();
        const hit = q.docs.find(d => (d.data().pref || '') === pref);
        if (hit) {
          docIdToUpdate = hit.id;
          existing = hit.data();
        }
      } else {
        const q = await mountainsRef.where('name', '==', name).limit(1).get();
        if (!q.empty) {
          docIdToUpdate = q.docs[0].id;
          existing = q.docs[0].data();
        }
      }

      if (docIdToUpdate) {
        // 既存データは破壊的に上書きしない。必要最小限のみ更新・マージ。
        const mergedTags = Array.from(new Set([...(existing.tags || []), ...tags]));
        const updateData = {
          name, // 既存は原則維持（正規化は新規追加時推奨）
          name_kana: nameKana || existing.name_kana || undefined,
          pref: existing.pref || pref, // 既存優先
          tags: mergedTags,
          // level は既存がなければ設定
          ...(existing.level ? {} : { level }),
          // styles/purposes/access/description は既存がなければ設定
          ...(existing.styles && existing.styles.length ? {} : (styles.length ? { styles } : {})),
          ...(existing.purposes && existing.purposes.length ? {} : (purposes.length ? { purposes } : {})),
          ...(existing.access && existing.access.length ? {} : (access.length ? { access } : {})),
          ...(existing.description ? {} : (description ? { description } : {})),
          // 数値は既存が未設定/0のときにのみ反映（提供があれば）
          ...((!Number.isFinite(existing.elevation) || existing.elevation === 0) && Number.isFinite(elevation) ? { elevation } : {}),
          ...((!Number.isFinite(existing.course_time_total) || existing.course_time_total === 0) && Number.isFinite(course_time_total) ? { course_time_total } : {}),
          ...((!Number.isFinite(existing.course_time_up) || existing.course_time_up === 0) && Number.isFinite(course_time_up) ? { course_time_up } : {}),
          ...((!Number.isFinite(existing.course_time_down) || existing.course_time_down === 0) && Number.isFinite(course_time_down) ? { course_time_down } : {}),
          ...((!Number.isFinite(existing.time_car) || existing.time_car === 0) && Number.isFinite(time_car) ? { time_car } : {}),
          ...((!Number.isFinite(existing.time_public) || existing.time_public === 0) && Number.isFinite(time_public) ? { time_public } : {}),
          ...(existing.time ? {} : (time ? { time } : {})),
          ...(existing.trailhead_name ? {} : (trailhead_name ? { trailhead_name } : {})),
          ...(Number.isFinite(existing.difficulty_score) ? {} : (Number.isFinite(difficulty_score) ? { difficulty_score } : {})),
          ...(typeof existing.has_ropeway === 'boolean' ? {} : (typeof has_ropeway === 'boolean' ? { has_ropeway } : {})),
          ...(typeof existing.has_cablecar === 'boolean' ? {} : (typeof has_cablecar === 'boolean' ? { has_cablecar } : {})),
          ...(typeof existing.has_hut === 'boolean' ? {} : (typeof has_hut === 'boolean' ? { has_hut } : {})),
          ...(typeof existing.has_tent === 'boolean' ? {} : (typeof has_tent === 'boolean' ? { has_tent } : {})),
          ...(typeof existing.has_onsen === 'boolean' ? {} : (typeof has_onsen === 'boolean' ? { has_onsen } : {})),
          ...(typeof existing.has_local_food === 'boolean' ? {} : (typeof has_local_food === 'boolean' ? { has_local_food } : {})),
          // 座標は既存がなければ設定
          ...((!Number.isFinite(existing.lat) && Number.isFinite(lat)) ? { lat } : {}),
          ...((!Number.isFinite(existing.lng) && Number.isFinite(lng)) ? { lng } : {}),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        };
        await mountainsRef.doc(docIdToUpdate).update(updateData);
        console.log(`✅ 更新(200): ${name}`);
      } else {
        // 最小限のデータで新規追加（座標・標高は未設定）。必要なら後で補完。
        const mountainData = {
          name: normalizedName,
          name_kana: nameKana,
          pref,
          level,
          styles,
          purposes,
          tags,
          access,
          description,
          ...(Number.isFinite(elevation) ? { elevation } : {}),
          ...(Number.isFinite(lat) ? { lat } : {}),
          ...(Number.isFinite(lng) ? { lng } : {}),
          ...(Number.isFinite(course_time_total) ? { course_time_total } : {}),
          ...(Number.isFinite(course_time_up) ? { course_time_up } : {}),
          ...(Number.isFinite(course_time_down) ? { course_time_down } : {}),
          ...(Number.isFinite(time_car) ? { time_car } : {}),
          ...(Number.isFinite(time_public) ? { time_public } : {}),
          ...(time ? { time } : {}),
          ...(trailhead_name ? { trailhead_name } : {}),
          ...(Number.isFinite(difficulty_score) ? { difficulty_score } : {}),
          ...(typeof has_ropeway === 'boolean' ? { has_ropeway } : {}),
          ...(typeof has_cablecar === 'boolean' ? { has_cablecar } : {}),
          ...(typeof has_hut === 'boolean' ? { has_hut } : {}),
          ...(typeof has_tent === 'boolean' ? { has_tent } : {}),
          ...(typeof has_onsen === 'boolean' ? { has_onsen } : {}),
          ...(typeof has_local_food === 'boolean' ? { has_local_food } : {}),
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        };
        if (docIdMode === 'name+pref-hash') {
          const id = stableIdFor(name, pref);
          await mountainsRef.doc(id).set(mountainData, { merge: true });
          console.log(`✅ 追加(200-ID): ${normalizedName} [${id}]`);
        } else {
          await mountainsRef.add(mountainData);
          console.log(`✅ 追加(200): ${normalizedName}`);
        }
      }
      successCount++;
    } catch (e) {
      console.error(`❌ 行${i} (${r['山名'] || '-'}) でエラー: ${e.message}`);
      errorCount++;
    }
    i++;
  }
  console.log('\n=== [200] 処理完了 ===');
  console.log(`✅ 成功: ${successCount}件`);
  console.log(`❌ エラー: ${errorCount}件`);
  console.log(`📊 合計: ${parsed.length}件\n`);
}

async function importFromCSV(csvFilePath, options = {}) {
  const { appendTag, match: matchMode = 'name', normalizeName, docId: docIdMode } = options; // 例: '日本二百名山'
  console.log(`📄 CSVファイルを読み込みます: ${csvFilePath}\n`);
  
  try {
    // CSVファイルを読み込み
    const fileContent = fs.readFileSync(csvFilePath, 'utf-8');
    const parsed = parse(fileContent, {
      columns: true,
      skip_empty_lines: true,
      trim: true,
      relax_column_count: true,
      relax_quotes: true
    });
    const header = Object.keys(parsed[0] || {});
    validateHeaders(header);
    const records = parsed;
    
    console.log(`📊 ${records.length}件のデータを処理します\n`);
    
  const mountainsRef = db.collection('mountains');
    let successCount = 0;
    let errorCount = 0;
    
    let rowIndex = 1; // 1-based for readability (excluding header)
    for (const record of records) {
      try {
        // 行バリデーション
        const errs = [];
        const name = (record.name || '').toString().trim();
        const pref = (record.pref || '').toString().trim();
        const latVal = parseFloat(record.lat);
        const lngVal = parseFloat(record.lng);
        const levelVal = (record.level || '').toString().trim();
        if (!name) errs.push('name');
        if (!pref) errs.push('pref');
        if (!Number.isFinite(latVal)) errs.push('lat');
        if (!Number.isFinite(lngVal)) errs.push('lng');
  if (!['初級','中級','上級'].includes(levelVal)) errs.push('level(初級/中級/上級)');
  const elev = parseInt(record.elevation);
  if (!Number.isFinite(elev)) errs.push('elevation(整数)');
        if (errs.length) {
          console.error(`❌ 行${rowIndex}: 必須/形式エラー -> ${errs.join(', ')}`);
          errorCount++;
          rowIndex++;
          continue; // スキップ
        }
        // 数値フィールドを変換
        // tags/access を配列に正規化
        const tags = parseList(record.tags);
        if (appendTag && !tags.includes(appendTag)) tags.push(appendTag);
        const access = parseList(record.access);

        // 正規化名（追加時推奨）
        function basePref2(prefFull) {
          const map = new Map([
            ['北海道','北海道'],
            ['青森県','青森'],['岩手県','岩手'],['宮城県','宮城'],['秋田県','秋田'],['山形県','山形'],['福島県','福島'],
            ['茨城県','茨城'],['栃木県','栃木'],['群馬県','群馬'],['埼玉県','埼玉'],['千葉県','千葉'],['東京都','東京'],['神奈川県','神奈川'],
            ['新潟県','新潟'],['富山県','富山'],['石川県','石川'],['福井県','福井'],['山梨県','山梨'],['長野県','長野'],['岐阜県','岐阜'],['静岡県','静岡'],['愛知県','愛知'],
            ['三重県','三重'],['滋賀県','滋賀'],['京都府','京都'],['大阪府','大阪'],['兵庫県','兵庫'],['奈良県','奈良'],['和歌山県','和歌山'],
            ['鳥取県','鳥取'],['島根県','島根'],['岡山県','岡山'],['広島県','広島'],['山口県','山口'],
            ['徳島県','徳島'],['香川県','香川'],['愛媛県','愛媛'],['高知県','高知'],
            ['福岡県','福岡'],['佐賀県','佐賀'],['長崎県','長崎'],['熊本県','熊本'],['大分県','大分'],['宮崎県','宮崎'],['鹿児島県','鹿児島'],['沖縄県','沖縄']
          ]);
          return map.get(prefFull) || prefFull.replace(/[都道府県]$/,'');
        }
        const normalizedName = (() => {
          if (!normalizeName) return name;
          if (normalizeName === 'pref') return `${basePref2(pref)}${name}`;
          if (normalizeName === 'pref-full') return `${pref}${name}`;
          return name;
        })();

        const mountainData = {
          name: normalizedName,
          pref,
          elevation: elev,
          lat: latVal,
          lng: lngVal,
          level: levelVal || '中級',
          
          // コース情報
          course_time_total: parseInt(record.course_time_total) || 0,
          course_time_up: parseInt(record.course_time_up) || 0,
          course_time_down: parseInt(record.course_time_down) || 0,
          
          // アクセス情報
          time_car: parseInt(record.time_car) || 0,
          time_public: parseInt(record.time_public) || 0,
          time: record.time || '',
          trailhead_name: record.trailhead_name || '',
          
          // 特徴・設備
          styles: parseList(record.styles),
          purposes: parseList(record.purposes),
          tags,
          access,
          has_ropeway: record.has_ropeway === 'true' || record.has_ropeway === '1',
          has_cablecar: record.has_cablecar === 'true' || record.has_cablecar === '1',
          has_hut: record.has_hut === 'true' || record.has_hut === '1',
          has_tent: record.has_tent === 'true' || record.has_tent === '1',
          has_onsen: record.has_onsen === 'true' || record.has_onsen === '1',
          has_local_food: record.has_local_food === 'true' || record.has_local_food === '1',
          
          // その他
          difficulty_score: parseInt(record.difficulty_score) || 5,
          description: record.description || '',
          
          // タイムスタンプ
          created_at: admin.firestore.FieldValue.serverTimestamp(),
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        };
        
        // 同じ名前の山が既に存在するかチェック
        // 既存照合
        let docIdToUpdate = null;
        if (matchMode === 'name+pref') {
          const q = await mountainsRef.where('name', '==', name).get();
          const hit = q.docs.find(d => (d.data().pref || '') === pref);
          if (hit) docIdToUpdate = hit.id;
        } else {
          const q = await mountainsRef.where('name', '==', name).limit(1).get();
          if (!q.empty) docIdToUpdate = q.docs[0].id;
        }

        if (docIdToUpdate) {
          await mountainsRef.doc(docIdToUpdate).update({
            ...mountainData,
            created_at: (await mountainsRef.doc(docIdToUpdate).get()).data()?.created_at,
          });
          console.log(`✅ 更新: ${name}`);
        } else {
          if (docIdMode === 'name+pref-hash') {
            const id = crypto.createHash('sha1').update(`${name}__${pref}`).digest('hex');
            await mountainsRef.doc(id).set(mountainData, { merge: true });
            console.log(`✅ 追加(ID): ${normalizedName} [${id}]`);
          } else {
            await mountainsRef.add(mountainData);
            console.log(`✅ 追加: ${normalizedName}`);
          }
        }
        
        successCount++;
        
      } catch (error) {
        console.error(`❌ 行${rowIndex} (${record.name || '-'}) でエラー: ${error.message}`);
        errorCount++;
      }
      rowIndex++;
    }
    
    console.log('\n=== 処理完了 ===');
    console.log(`✅ 成功: ${successCount}件`);
    console.log(`❌ エラー: ${errorCount}件`);
    console.log(`📊 合計: ${records.length}件\n`);
    
  } catch (error) {
    console.error('❌ CSVファイルの読み込みエラー:', error);
    throw error;
  }
}

/**
 * サンプルCSVを生成
 */
function generateSampleCSV() {
  const sampleData = `name,pref,elevation,lat,lng,level,course_time_total,course_time_up,course_time_down,time_car,time_public,time,trailhead_name,styles,purposes,tags,access,has_ropeway,has_cablecar,has_hut,has_tent,has_onsen,has_local_food,difficulty_score,description
高尾山,東京都,599,35.6250,139.2430,初級,130,60,50,60,70,60分（車）/ 70分（公共交通機関）,高尾山口駅,ハイキング|自然,癒し|デート|家族旅行,自然,車|公共交通機関,0,1,0,0,1,1,2,都心から1時間、標高599mの身近な名山。ケーブルカーやリフトもあり、初心者から楽しめる。
塔ノ岳,神奈川県,1491,35.4503,139.1595,中級,330,210,120,150,180,150分（車）/ 180分（公共交通機関）,大倉バス停,絶景|稜線,冒険|リフレッシュ,温泉,車|公共交通機関,0,0,1,0,1,1,5,丹沢の名峰、標高1491m。大倉尾根は「バカ尾根」と呼ばれる急登だが、山頂からの富士山と相模湾の眺望は絶景。
富士山,静岡県,3776,35.3606,138.7274,上級,600,360,240,180,240,180分（車）/ 240分（公共交通機関）,富士宮口五合目,絶景,冒険,日本百名山|世界遺産,車|公共交通機関,0,0,1,0,1,1,8,標高3776m、日本最高峰。7月〜9月の夏山シーズンのみ登山可能。高山病対策と防寒具が必須。`;

  const outPath = path.resolve('../../firestore-seed/mountains_template.csv');
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, sampleData, 'utf-8');
  console.log('✅ サンプルCSVを生成しました: firestore-seed/mountains_template.csv\n');
  console.log('このファイルを編集して、実際のデータを入力してください。');
  console.log('その後、以下のコマンドで実行:');
  console.log('  node import_from_csv.mjs import ../../firestore-seed/mountains_data.csv\n');
}

/**
 * メイン実行
 */
async function main() {
  const args = process.argv.slice(2);
  const command = args[0];
  const filePath = args[1];
  // 追加オプション（例: --append-tag=日本二百名山）
  const extraOpts = args.slice(2).reduce((acc, cur) => {
    if (cur.startsWith('--append-tag=')) {
      acc.appendTag = decodeURIComponent(cur.split('=')[1]);
    }
    if (cur.startsWith('--format=')) {
      acc.format = decodeURIComponent(cur.split('=')[1]);
    }
    if (cur.startsWith('--match=')) {
      acc.match = decodeURIComponent(cur.split('=')[1]); // name | name+pref
    }
    if (cur.startsWith('--normalize-name=')) {
      acc.normalizeName = decodeURIComponent(cur.split('=')[1]); // pref | pref-full
    }
    if (cur.startsWith('--doc-id=')) {
      acc.docId = decodeURIComponent(cur.split('=')[1]); // name+pref-hash
    }
    return acc;
  }, {});
  
  try {
    if (command === 'import' && filePath) {
      if (extraOpts.format === '200') {
        await importFromCSV200(filePath, extraOpts);
      } else {
        await importFromCSV(filePath, extraOpts);
      }
    } else if (command === 'template') {
      generateSampleCSV();
    } else if (command === 'validate' && filePath) {
      // 形式検査のみ（書き込みなし）
      if (extraOpts.format === '200') {
        await validateCSV200(filePath);
      } else {
        const text = fs.readFileSync(filePath, 'utf8');
        const parsed = parse(text, { columns: true, skip_empty_lines: true, trim: true });
        const header = Object.keys(parsed[0] || {});
        validateHeaders(header);
        let ok = 0, bad = 0, i = 1;
        for (const r of parsed) {
          const errs = [];
          const name = (r.name || '').toString().trim();
          const pref = (r.pref || '').toString().trim();
          const latVal = parseFloat(r.lat);
          const lngVal = parseFloat(r.lng);
          const levelVal = (r.level || '').toString().trim();
          if (!name) errs.push('name');
          if (!pref) errs.push('pref');
          if (!Number.isFinite(latVal)) errs.push('lat');
          if (!Number.isFinite(lngVal)) errs.push('lng');
          if (!['初級','中級','上級'].includes(levelVal)) errs.push('level(初級/中級/上級)');
          const elev2 = parseInt(r.elevation);
          if (!Number.isFinite(elev2)) errs.push('elevation(整数)');
          if (errs.length) {
            console.error(`❌ 行${i}: ${errs.join(', ')}`);
            bad++;
          } else {
            ok++;
          }
          i++;
        }
        console.log(`\n検証結果: OK ${ok} / NG ${bad} / 合計 ${ok+bad}`);
        if (bad > 0) process.exit(1);
      }
    } else {
      console.log('使用方法:');
      console.log('  node import_from_csv.mjs template                    # サンプルCSVを生成');
      console.log('  node import_from_csv.mjs validate <csvファイルパス>  # CSVの検証のみ');
      console.log('  node import_from_csv.mjs import <csvファイルパス>    # CSVからインポート');
      console.log('  オプション: --append-tag=<タグ名> 例) --append-tag=日本二百名山');
      console.log('           : --format=200         例) 二百名山フォーマット（番号,山名,よみがな,所在地）');
      console.log('           : --match=name+pref    例) 既存照合を name+pref で行う（同名の重複を適切に分離）');
      console.log('           : --normalize-name=pref|pref-full  例) 新規追加時に "秋田駒ヶ岳" / "秋田県駒ヶ岳" で保存');
      console.log('           : --doc-id=name+pref-hash          例) 追加時に安定ID（name+prefのSHA1）で保存');
      console.log('\n例:');
      console.log('  node import_from_csv.mjs import ../csv/japan-200mountains.csv --format=200 --append-tag=日本二百名山 --match=name+pref');
      console.log('  node import_from_csv.mjs import ../csv/japan-200mountains.csv --format=200 --append-tag=日本二百名山 --match=name+pref --normalize-name=pref');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('処理中にエラーが発生しました:', error);
    process.exit(1);
  }
}

main();
