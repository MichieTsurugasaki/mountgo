/**
 * mountains_master_with_yamap_all_v2.csv を Firestore の mountains へ反映
 * - 必須: name, lat, lng（elevation_m があれば elevation として保存）
 * - pref は prefectures から先頭の都道府県を抽出
 * - level は difficulty を 初級/中級/上級 に粗くマップ
 * - courseTime は median_time_h を「X時間Y分」に整形（あれば）
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

function firstPref(s) {
	if (!s) return '';
	const raw = s.toString();
	const parts = raw.split(/[,、，・\s]+/).map((x) => x.trim()).filter(Boolean);
	return parts[0] || raw.trim();
}

function levelFromDifficulty(d) {
	const n = Number(d);
	if (!Number.isFinite(n)) return '中級';
	if (n <= 2) return '初級';
	if (n <= 3) return '中級';
	return '上級';
}

function courseTimeFromHours(h) {
	const n = Number(h);
	if (!Number.isFinite(n) || n <= 0) return null;
	const hours = Math.floor(n);
	const minutes = Math.round((n - hours) * 60);
	const mm = minutes.toString().padStart(1, '0');
	return `${hours}時間${mm}分`;
}

async function importMountains(csvPath) {
	const db = initFirebase();
	const rows = loadCsvRecords(csvPath);
	let up = 0, add = 0, bad = 0;

	for (const r of rows) {
		try {
			const name = (r.name || '').toString().trim();
			const lat = parseFloat(r.lat);
			const lng = parseFloat(r.lng);
			if (!name || !Number.isFinite(lat) || !Number.isFinite(lng)) {
				bad++;
				console.error(`❌ 不正/不足: name="${name}", lat=${r.lat}, lng=${r.lng}`);
				continue;
			}
			const elevation = Number.isFinite(parseInt(r.elevation_m)) ? parseInt(r.elevation_m) : undefined;
			const pref = firstPref(r.prefectures);
			const level = levelFromDifficulty(r.difficulty);
			const courseTime = courseTimeFromHours(r.median_time_h);

			const payload = {
				name,
				lat,
				lng,
				...(pref ? { pref } : {}),
				...(elevation ? { elevation } : {}),
				...(level ? { level } : {}),
				...(courseTime ? { courseTime } : {}),
				updated_at: admin.firestore.FieldValue.serverTimestamp(),
			};

			// 既存（name 一致）を検索
			const qs = await db.collection('mountains').where('name', '==', name).limit(1).get();
			if (qs.empty) {
				await db.collection('mountains').add({
					...payload,
					created_at: admin.firestore.FieldValue.serverTimestamp(),
				});
				add++;
			} else {
				await qs.docs[0].ref.set(payload, { merge: true });
				up++;
			}
		} catch (e) {
			bad++;
			console.error(`🔥 行エラー: ${e.message}`);
		}
	}

	console.log(`\n結果: 追加 ${add}, 更新 ${up}, 不正 ${bad}, 合計 ${rows.length}`);
}

async function main() {
	const csvPath = process.argv[2];
	if (!csvPath) {
		console.log('使用方法:');
		console.log('  node scripts/import_mountains.mjs <mountains_csv_path>');
		console.log('\n想定CSV: mountains_master_with_yamap_all_v2.csv（ヘッダー: name, lat, lng, elevation_m, prefectures, difficulty, median_time_h など）');
		process.exit(1);
	}
	const abs = path.resolve(csvPath);
	await importMountains(abs);
}

main().catch((e) => {
	console.error('致命的エラー:', e);
	process.exit(1);
});

