/**
 * 日本百名山リスト（name,pref）から Firestore の mountains に「日本百名山」タグを一括付与
 *
 * 使い方:
 *   node scripts/tag_hyakumeizan_from_list.mjs --in=../firestore-seed/nihon_100_meizan_template.csv
 * オプション:
 *   --dry-run  実際には書き込まず、ヒット件数のみ確認
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import path from 'node:path';
import { parse } from 'csv-parse/sync';
import crypto from 'node:crypto';

function resolveServiceAccount() {
  const fallback = './gen-lang-client-0636793764-796b85572dd7.json';
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
  if (!fs.existsSync(fallback)) throw new Error('サービスアカウントが見つかりません');
  return JSON.parse(fs.readFileSync(fallback, 'utf8'));
}

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(resolveServiceAccount()) });
}
const db = admin.firestore();

function stableIdFor(name, pref) {
  return crypto.createHash('sha1').update(`${name}__${pref}`).digest('hex');
}

function canonicalizePrefTokens(s) {
  if (!s) return [];
  // 区切りを正規化（・ | / 、 , ）
  const raw = String(s).replace(/[|,、/]/g, '・');
  const parts = raw.split('・').map(x => x.trim()).filter(Boolean);
  const mapShort = new Map([
    ['東京','東京都'], ['京都','京都府'], ['大阪','大阪府'],
    ['北海道','北海道'],
    ['青森','青森県'],['岩手','岩手県'],['宮城','宮城県'],['秋田','秋田県'],['山形','山形県'],['福島','福島県'],
    ['茨城','茨城県'],['栃木','栃木県'],['群馬','群馬県'],['埼玉','埼玉県'],['千葉','千葉県'],['神奈川','神奈川県'],
    ['新潟','新潟県'],['富山','富山県'],['石川','石川県'],['福井','福井県'],['山梨','山梨県'],['長野','長野県'],['岐阜','岐阜県'],['静岡','静岡県'],['愛知','愛知県'],
    ['三重','三重県'],['滋賀','滋賀県'],['兵庫','兵庫県'],['奈良','奈良県'],['和歌山','和歌山県'],
    ['鳥取','鳥取県'],['島根','島根県'],['岡山','岡山県'],['広島','広島県'],['山口','山口県'],
    ['徳島','徳島県'],['香川','香川県'],['愛媛','愛媛県'],['高知','高知県'],
    ['福岡','福岡県'],['佐賀','佐賀県'],['長崎','長崎県'],['熊本','熊本県'],['大分','大分県'],['宮崎','宮崎県'],['鹿児島','鹿児島県'],['沖縄','沖縄県']
  ]);
  return parts.map(p => {
    if (p.endsWith('都') || p.endsWith('道') || p.endsWith('府') || p.endsWith('県')) return p;
    return mapShort.get(p) || (p + (p==='東京'?'都': '県'));
  }).sort();
}

function prefBase(prefFull) {
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
  const first = (prefFull||'').toString().split('・')[0];
  if (!first) return '';
  if (first.endsWith('都')||first.endsWith('道')||first.endsWith('府')||first.endsWith('県')) {
    return map.get(first) || first.replace(/[都道府県]$/,'');
  }
  return first;
}

function canonicalPrefJoined(pref) {
  const arr = canonicalizePrefTokens(pref);
  return arr.length ? arr.join('・') : (pref || '');
}

function prefSetsMatch(listPref, docPref) {
  const a = canonicalizePrefTokens(listPref);
  const b = canonicalizePrefTokens(docPref);
  if (a.length === 0 || b.length === 0) return false;
  // 完全一致 or 片方が包含でもOK（例: リストが「長野県」, ドキュメントが「長野県・岐阜県」）
  const aSet = new Set(a), bSet = new Set(b);
  const aInB = a.every(x => bSet.has(x));
  const bInA = b.every(x => aSet.has(x));
  if (aInB || bInA) return true;
  // フォールバック: docPrefの生文字列に都道府県フル名が含まれていれば一致とみなす
  const raw = (docPref||'').toString();
  return a.some(full => raw.includes(full));
}

function charVariants(s) {
  const set = new Set();
  const push = (v) => { if (v) set.add(v); };
  push(s);
  // ヶ/ケ 換字
  push(s.replaceAll('ヶ', 'ケ'));
  push(s.replaceAll('ケ', 'ヶ'));
  // 嶽/岳 換字
  push(s.replaceAll('嶽', '岳'));
  push(s.replaceAll('岳', '嶽'));
  // 御岳山/御嶽山 代表的表記ゆれ
  push(s.replaceAll('御嶽山', '御岳山'));
  push(s.replaceAll('御岳山', '御嶽山'));
  return Array.from(set).filter(Boolean);
}

function stripParens(s) {
  return (s||'').toString().replace(/[（(].*?[）)]/g, '').trim();
}

function generateCandidateNames(name, pref) {
  const cand = new Set();
  // 元名称と文字バリアント
  for (const v of charVariants(name)) cand.add(v);
  // 県表記（フル/短縮）+ 名称（それぞれの文字バリアント）
  const fulls = canonicalizePrefTokens(pref);
  if (fulls.length > 0) {
    const full = fulls[0];
    const base = prefBase(full);
    for (const v of charVariants(name)) {
      if (base) cand.add(`${base}${v}`);
      cand.add(`${full}${v}`);
    }
  }
  return Array.from(cand).slice(0, 10); // in クエリ上限
}

let __allDocsCache = null;
async function loadAllMountains() {
  if (__allDocsCache) return __allDocsCache;
  const snap = await db.collection('mountains').get();
  __allDocsCache = snap.docs.map(d => ({ id: d.id, data: d.data() || {} }));
  return __allDocsCache;
}

async function addTagByNamePref(name, pref, tag, dryRun=false, nameKana=null, allowUnique=false) {
  // 1) 安定ID優先
  const sid = stableIdFor(name, pref);
  const stableRef = db.collection('mountains').doc(sid);
  const stableSnap = await stableRef.get();
  if (stableSnap.exists) {
    if (!dryRun) {
      const cur = stableSnap.data() || {};
      const next = Array.from(new Set([...(Array.isArray(cur.tags)?cur.tags:[]), tag]));
      const patch = { tags: next };
      if (nameKana && (!cur.name_kana || cur.name_kana !== nameKana)) {
        patch.name_kana = nameKana;
      }
      await stableRef.set(patch, { merge: true });
    }
    return { id: sid, type: 'stable' };
  }
  // 2) name+pref（拡張一致: 県名セットの包含も許容 + プレフィックス正規化名 + 表記ゆれ）
  const namesArr = generateCandidateNames(name, pref);
  let candidate = null;
  const qs = await db.collection('mountains').where('name', 'in', namesArr).get();
  if (!qs.empty) {
    const matches = [];
    for (const d of qs.docs) {
      const dp = (d.data().pref || '').toString();
      if (prefSetsMatch(pref, dp)) { matches.push(d); }
    }
    if (matches.length >= 1) {
      // 安全策: 複数一致する場合（legacy+stableの二重）には両方に付与
      if (!dryRun) {
        for (const m of matches) {
          const cur = m.data() || {};
          const next = Array.from(new Set([...(Array.isArray(cur.tags)?cur.tags:[]), tag]));
          const patch = { tags: next };
          if (nameKana && (!cur.name_kana || cur.name_kana !== nameKana)) patch.name_kana = nameKana;
          await m.ref.set(patch, { merge: true });
        }
      }
      candidate = matches[0];
    }
    // 県一致が見つからないが単一ヒットならそれを採用（安全のためdryRun時のみの判断は避ける）
    if (!candidate && qs.size === 1 && !dryRun) {
      candidate = qs.docs[0];
    }
  } else {
    // 旧ロジック（完全一致）も念のためフォールバック
    const q2 = await db.collection('mountains').where('name', '==', name).get();
    for (const d of q2.docs) {
      const dp = (d.data().pref || '').toString();
      if (prefSetsMatch(pref, dp)) { candidate = d; break; }
    }
  }

  // 2.5) 県不問・名称ユニーク一致を許可（オプション）
  if (!candidate && allowUnique && !dryRun) {
    let uniqueDoc = null;
    let total = 0;
    for (const v of namesArr) {
      const qx = await db.collection('mountains').where('name', '==', v).get();
      total += qx.size;
      if (qx.size === 1 && !uniqueDoc) {
        uniqueDoc = qx.docs[0];
      }
      if (total > 1 && !uniqueDoc) break; // ユニークでない
    }
    if (uniqueDoc) candidate = uniqueDoc;
  }
  if (candidate) {
    if (!dryRun) {
      const cur = candidate.data() || {};
      const next = Array.from(new Set([...(Array.isArray(cur.tags)?cur.tags:[]), tag]));
      const patch = { tags: next };
      if (nameKana && (!cur.name_kana || cur.name_kana !== nameKana)) {
        patch.name_kana = nameKana;
      }
      await candidate.ref.set(patch, { merge: true });
    }
    return { id: candidate.id, type: 'legacy' };
  }
  // 3) nameのみ（重複が無い場合のみ）
  if (!pref) {
    const q2 = await db.collection('mountains').where('name', '==', name).get();
    if (q2.size === 1) {
      const d = q2.docs[0];
      if (!dryRun) {
        const cur = d.data() || {};
        const next = Array.from(new Set([...(Array.isArray(cur.tags)?cur.tags:[]), tag]));
        const patch = { tags: next };
        if (nameKana && (!cur.name_kana || cur.name_kana !== nameKana)) {
          patch.name_kana = nameKana;
        }
        await d.ref.set(patch, { merge: true });
      }
      return { id: d.id, type: 'legacy' };
    }
  }
  return null;
}

async function main() {
  const args = process.argv.slice(2);
  const inArg = args.find(a => a.startsWith('--in='));
  const dryRun = args.includes('--dry-run');
  const reportArg = args.find(a => a.startsWith('--report-out='));
  const allowUnique = args.includes('--allow-unique-name-match');
  const mapInArg = args.find(a => a.startsWith('--map-in='));
  const mapOutArg = args.find(a => a.startsWith('--map-out='));
  const normalizePrefFlag = args.includes('--normalize-pref');
  const inPath = inArg ? inArg.substring(5) : '../firestore-seed/nihon_100_meizan_template.csv';
  const abs = path.resolve(inPath);
  if (!fs.existsSync(abs)) {
    console.error(`❌ 入力CSVが見つかりません: ${abs}`);
    process.exit(1);
  }

  const text = fs.readFileSync(abs, 'utf8');
  const rows = parse(text, { columns: true, skip_empty_lines: true, trim: true });
  // 手動マップの読み込み
  let manualMap = [];
  let manualMapPath = null;
  if (mapInArg) {
    manualMapPath = path.resolve(mapInArg.substring(9));
    if (fs.existsSync(manualMapPath)) {
      const mt = fs.readFileSync(manualMapPath, 'utf8');
      manualMap = parse(mt, { columns: true, skip_empty_lines: true, trim: true });
    } else {
      console.warn(`⚠️ --map-in 指定のファイルが見つかりません: ${manualMapPath}`);
    }
  }
  const keyOf = (n, p) => `${(n||'').toString().trim()}__${(p||'').toString().trim()}`;
  const mapByKey = new Map(manualMap.map(r => [keyOf(r.mountain_name || r.name, r.pref), r]));
  let ok=0, miss=0, legacy=0, stable=0;
  const missDetails = [];
  for (const r of rows) {
    const name = (r.mountain_name || r.name || '').toString().trim();
    const nameKana = (r.mountain_name_kana || r.name_kana || '').toString().trim();
    const pref = (r.pref || '').toString().trim();
    if (!name || !pref) { miss++; continue; }
    // 手動マッピング優先
    const mk = mapByKey.get(keyOf(name, pref));
    if (mk && (mk.target_doc_id || mk.target_docId || mk.doc_id)) {
      const targetId = (mk.target_doc_id || mk.target_docId || mk.doc_id).toString().trim();
      if (targetId) {
        if (!dryRun) {
          const ref = db.collection('mountains').doc(targetId);
          const snap = await ref.get();
          if (!snap.exists) {
            console.warn(`⚠️ map-in: 対象ドキュメントが見つかりません id=${targetId} (${name})`);
          } else {
            const cur = snap.data() || {};
            const nextTags = Array.from(new Set([...(Array.isArray(cur.tags)?cur.tags:[]), '日本百名山']));
            const patch = { tags: nextTags };
            if (nameKana && (!cur.name_kana || cur.name_kana !== nameKana)) patch.name_kana = nameKana;
            if (normalizePrefFlag) patch.pref = canonicalPrefJoined(pref);
            await ref.set(patch, { merge: true });
          }
        }
        ok++;
        continue;
      }
      // target_doc_id が空で suggested_target_name から推定を試みる
      const sName = (mk.suggested_target_name || mk.suggested || '').toString().trim();
      if (sName) {
        const vars = Array.from(new Set([
          ...generateCandidateNames(sName, pref),
          ...generateCandidateNames(stripParens(sName), pref)
        ]));
        const q = await db.collection('mountains').where('name', 'in', vars.slice(0, 10)).get();
        let chosen = null;
        for (const d of q.docs) {
          const dp = (d.data().pref || '').toString();
          if (prefSetsMatch(pref, dp)) { chosen = d; break; }
        }
        // フォールバック: 全件読み込みで部分一致検索
        if (!chosen) {
          const all = await loadAllMountains();
          const terms = Array.from(new Set([sName, stripParens(sName), ...charVariants(sName), ...charVariants(stripParens(sName))])).filter(Boolean);
          const candidates = [];
          for (const doc of all) {
            const nm = (doc.data.name || '').toString();
            const dp = (doc.data.pref || '').toString();
            if (!prefSetsMatch(pref, dp)) continue;
            if (terms.some(t => nm.includes(t))) candidates.push(doc);
          }
          if (candidates.length === 1) {
            chosen = { id: candidates[0].id, ref: db.collection('mountains').doc(candidates[0].id), data: () => candidates[0].data };
          }
        }
        if (chosen) {
          if (!dryRun) {
            const cur = chosen.data() || {};
            const nextTags = Array.from(new Set([...(Array.isArray(cur.tags)?cur.tags:[]), '日本百名山']))
            const patch = { tags: nextTags };
            if (nameKana && (!cur.name_kana || cur.name_kana !== nameKana)) patch.name_kana = nameKana;
            if (normalizePrefFlag) patch.pref = canonicalPrefJoined(pref);
            await chosen.ref.set(patch, { merge: true });
          }
          ok++;
          // map-outにdocIdを埋めるため、manualMapの行に付与
          mk.target_doc_id = chosen.id;
          continue;
        }
      }
      // ここまでで解決できなければ通常フローへフォールバック
    }
  const res = await addTagByNamePref(name, pref, '日本百名山', dryRun, nameKana || null, allowUnique);
    if (!res) {
      miss++;
      // レポート用候補探索（name variants のみ、prefは不問）
      const vars = generateCandidateNames(name, pref);
      const found = [];
      if (vars.length > 0) {
        const q = await db.collection('mountains').where('name', 'in', vars.slice(0, 10)).get();
        for (const d of q.docs) {
          const data = d.data() || {};
          found.push({ id: d.id, name: data.name || '', pref: data.pref || '' });
        }
      }
      missDetails.push({ name, nameKana, pref, variants: vars.join('|'), candidates: found.map(f => `${f.name}（${f.pref}）:${f.id}`).join(' | ') });
      continue;
    }
    ok++;
    if (res.type === 'stable') stable++; else legacy++;
  }
  console.log(`📊 結果: 付与 ${ok} (stable ${stable}, legacy ${legacy}) / 未ヒット ${miss} / 入力 ${rows.length}`);
  if (dryRun) console.log('※ dry-run モードのため書き込みは行っていません');

  // 未ヒットレポートの出力
  if (reportArg) {
    const outPath = path.resolve(reportArg.substring(13));
    const header = 'mountain_name,mountain_name_kana,pref,variants,candidates\n';
    const body = missDetails.map(m => [m.name, m.nameKana, m.pref, m.variants, m.candidates].map(v => {
      const s = (v||'').toString();
      return '"' + s.replaceAll('"','""') + '"';
    }).join(',')).join('\n');
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, header + body + '\n', 'utf8');
    console.log(`📝 未ヒットレポートを書き出しました: ${outPath}`);
  }

  // map-out の書き出し（解決した doc_id を反映）
  if (mapOutArg && manualMap.length) {
    const out = path.resolve(mapOutArg.substring(10));
    const cols = ['mountain_name','pref','suggested_target_name','target_doc_id','notes'];
    const lines = [cols.join(',')];
    for (const r of manualMap) {
      const row = cols.map(c => ('"' + ((r[c]||'').toString().replaceAll('"','""')) + '"'));
      lines.push(row.join(','));
    }
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, lines.join('\n') + '\n', 'utf8');
    console.log(`📝 manual_map を更新しました: ${out}`);
  }
}

main().catch(e => { console.error('❌ エラー:', e); process.exit(1); });
