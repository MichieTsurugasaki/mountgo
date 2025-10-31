/**
 * trailheads_master.csv を Firestore の mountains ドキュメントへ取り込む
 * - mountains.[docId or (name+pref) or name] を検索して trailheads 配列にマージ
 * - 既存 trailheads と重複しないよう name または lat/lng 近似で判定
 *
 * サポートするCSVヘッダー（いずれか/複数可）:
 * - mountain_id: 山ドキュメントID（安定ID or 既存ID）
 * - mountain_name または mountainName: 山名
 * - pref: 都道府県（name+pref 照合用）
 * - trailhead_name または name: 登山口名
 * - trailhead_lat または lat
 * - trailhead_lng または lng
 * - access_notes/address/parking/toiletSeason/notes などは任意
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import path from 'node:path';
import { parse } from 'csv-parse/sync';

const SERVICE_ACCOUNT_PATH = './gen-lang-client-0636793764-796b85572dd7.json';

function initFirebase() {
	if (admin.apps.length === 0) {
		const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
		admin.initializeApp({
			credential: admin.credential.cert(serviceAccount),
		});
	}
	return admin.firestore();
}

function loadCsvRecords(csvPath) {
	const text = fs.readFileSync(csvPath, 'utf8');
	return parse(text, { columns: true, skip_empty_lines: true, trim: true });
}

function nearlyEqual(a, b, eps = 1e-5) {
	return Math.abs((a ?? 0) - (b ?? 0)) <= eps;
}

function mergeTrailhead(existingList, newTh) {
	const list = Array.isArray(existingList) ? [...existingList] : [];
	const hasDup = list.some((t) => {
		if (!t) return false;
		const sameName = (t.name || '').toString().trim() === (newTh.name || '').toString().trim();
		const sameCoord = nearlyEqual(Number(t.lat), Number(newTh.lat)) && nearlyEqual(Number(t.lng), Number(newTh.lng));
		return sameName || sameCoord;
	});
	if (!hasDup) list.push(newTh);
	return list;
}

async function findMountainDoc(db, { mountainId, name, pref }) {
	// 1) ID指定があれば最優先
	if (mountainId) {
		const ref = db.collection('mountains').doc(mountainId);
		const snap = await ref.get();
		if (snap.exists) return { ref, snap };
	}
	// 2) name+pref マッチ
	if (name && pref) {
		const qs = await db.collection('mountains').where('name', '==', name).get();
		const hit = qs.docs.find((d) => (d.data().pref || '') === pref);
		if (hit) return { ref: hit.ref, snap: hit };
	}
	// 3) name のみ（最後の手段）
	if (name) {
		const qs = await db.collection('mountains').where('name', '==', name).limit(1).get();
		if (!qs.empty) return { ref: qs.docs[0].ref, snap: qs.docs[0] };
	}
	return null;
}

async function importTrailheads(csvPath) {
	const db = initFirebase();
	const rows = loadCsvRecords(csvPath);

	let ok = 0, skip = 0, miss = 0, bad = 0;
	for (const r of rows) {
		try {
			const mountainId = (r.mountain_id || '').toString().trim();
			const mountainName = (r.mountain_name || r.mountainName || r.mountain || r.name_ja || '').toString().trim();
			const pref = (r.pref || '').toString().trim();
			const thName = (r.trailhead_name || r.name || '').toString().trim();
			const lat = parseFloat(r.trailhead_lat ?? r.lat);
			const lng = parseFloat(r.trailhead_lng ?? r.lng);

			if ((!mountainName && !mountainId) || !thName || !Number.isFinite(lat) || !Number.isFinite(lng)) {
				console.error(`❌ 不正データ: id="${mountainId}" name="${mountainName}" th="${thName}" lat=${r.trailhead_lat ?? r.lat} lng=${r.trailhead_lng ?? r.lng}`);
				bad++;
				continue;
			}

			const th = {
				name: thName,
				lat,
				lng,
				address: (r.address || '').toString().trim(),
				parking: (r.parking || '').toString().trim(),
				toiletSeason: (r.toiletSeason || '').toString().trim(),
				// 追加フィールド（任意／テンプレ互換）
				...(r.access_notes ? { access_notes: r.access_notes.toString().trim() } : {}),
				...(r.parking_spaces ? { parking_spaces: Number.parseInt(r.parking_spaces) || r.parking_spaces.toString().trim() } : {}),
				...(r.public_transport ? { public_transport: r.public_transport.toString().trim() } : {}),
				...(r.elevation_m ? { elevation_m: Number.parseInt(r.elevation_m) || r.elevation_m.toString().trim() } : {}),
				...(r.description ? { description: r.description.toString().trim() } : {}),
				...(r.source_url ? { source_url: r.source_url.toString().trim() } : {}),
				// 旧フィールドとの互換
				notes: (r.notes || '').toString().trim(),
			};

			const found = await findMountainDoc(db, { mountainId, name: mountainName, pref });
			if (!found) {
				console.warn(`⚠️ 未登録の山: id="${mountainId}" name="${mountainName}" pref="${pref}" — trailhead をスキップ`);
				miss++;
				continue;
			}

			const data = found.snap.data() || {};
			const merged = mergeTrailhead(data.trailheads, th);
			if (merged.length === (Array.isArray(data.trailheads) ? data.trailheads.length : 0)) {
				// 変化なし
				skip++;
				continue;
			}
			await found.ref.set({ trailheads: merged }, { merge: true });
			ok++;
		} catch (e) {
			console.error(`🔥 行エラー: ${e.message}`);
			bad++;
		}
	}

	console.log(`\n結果: 追加/更新 ${ok}, スキップ(重複) ${skip}, 山未登録 ${miss}, 不正 ${bad}, 合計 ${rows.length}`);
}

async function main() {
	const csvPath = process.argv[2];
	if (!csvPath) {
		console.log('使用方法:');
		console.log('  node scripts/import_trailheads.mjs <trailheads_csv_path>');
		console.log('\nCSVヘッダー例: mountain_id,mountain_name,pref,trailhead_name,trailhead_lat,trailhead_lng,...');
		process.exit(1);
	}
	const abs = path.resolve(csvPath);
	await importTrailheads(abs);
}

main().catch((e) => {
	console.error('致命的エラー:', e);
	process.exit(1);
});

