/**
 * Enrich trailheads with OpenStreetMap (Overpass API):
 *  - Find tourism=information + information=trailhead near each mountain/trailhead
 *  - For each trailhead, find nearby amenity=toilets and amenity=parking and extract capacity
 * Writes back to Firestore mountains.trailheads merging entries.
 *
 * Usage:
 *   node scripts/enrich_trailheads_osm.mjs [--limit 50] [--radius 2000]
 */

import admin from 'firebase-admin';
import fs from 'node:fs';
import https from 'node:https';
import { URL } from 'node:url';

const SERVICE_ACCOUNT_PATH = './gen-lang-client-0636793764-796b85572dd7.json';
// Multiple Overpass mirrors (round-robin on retry). You can override with env:
// OVERPASS_URLS (comma-separated) or OVERPASS_URL (single)
const OVERPASS_ENDPOINTS = (
  process.env.OVERPASS_URLS
    ? process.env.OVERPASS_URLS.split(',')
    : [
        process.env.OVERPASS_URL || 'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://z.overpass-api.de/api/interpreter',
      ]
).map((s) => s.trim()).filter(Boolean);

function initFirebase() {
  if (admin.apps.length === 0) {
    const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  }
  return admin.firestore();
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function overpassQuery(q, attempt = 1, startIndex) {
  const MAX_RETRY = 4;
  const endpoints = OVERPASS_ENDPOINTS.length > 0 ? OVERPASS_ENDPOINTS : ['https://overpass-api.de/api/interpreter'];
  const baseIndex = Number.isInteger(startIndex) ? startIndex : Math.floor(Math.random() * endpoints.length);
  const endpoint = endpoints[(baseIndex + (attempt - 1)) % endpoints.length];
  const url = new URL(endpoint);
  const body = new URLSearchParams({ data: q }).toString();
  return new Promise((resolve, reject) => {
    const req = https.request({
      method: 'POST',
      hostname: url.hostname,
      path: url.pathname + url.search,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    }, async (res) => {
      let data = '';
      res.on('data', (c) => data += c);
      res.on('end', async () => {
        const ct = res.headers['content-type'] || '';
        const looksHtml = data.trim().startsWith('<');
        const notOk = res.statusCode && res.statusCode >= 400;
        if (notOk || looksHtml || !ct.includes('application/json')) {
          if (attempt < MAX_RETRY) {
            const backoff = 1500 * Math.pow(2, attempt - 1);
            await sleep(backoff);
            try {
              const r = await overpassQuery(q, attempt + 1, baseIndex);
              resolve(r);
              return;
            } catch (e) {
              reject(e);
              return;
            }
          }
          reject(new Error(`Overpass HTTP ${res.statusCode} endpoint=${endpoint} content-type=${ct} body=${data.slice(0,200)}`));
          return;
        }
        try {
          const json = JSON.parse(data);
          resolve(json);
        } catch (e) {
          if (attempt < MAX_RETRY) {
            const backoff = 1500 * Math.pow(2, attempt - 1);
            await sleep(backoff);
            try {
              const r = await overpassQuery(q, attempt + 1, baseIndex);
              resolve(r);
              return;
            } catch (ee) {
              reject(ee);
              return;
            }
          }
          reject(new Error(`Overpass parse error: ${e.message} body=${data.slice(0,200)}`));
        }
      });
    });
    req.on('error', async (err) => {
      if (attempt < MAX_RETRY) {
        const backoff = 1500 * Math.pow(2, attempt - 1);
        await sleep(backoff);
        try {
          const r = await overpassQuery(q, attempt + 1, baseIndex);
          resolve(r);
          return;
        } catch (e) {
          reject(e);
          return;
        }
      }
      reject(err);
    });
    req.write(body);
    req.end();
  });
}

function nearlyEqual(a, b, eps = 1e-4) { return Math.abs((a ?? 0) - (b ?? 0)) <= eps; }

function mergeTrailhead(existingList, th) {
  const list = Array.isArray(existingList) ? [...existingList] : [];
  const dup = list.findIndex((t) => {
    if (!t) return false;
    const sameName = (t.name || '').toString().trim() === (th.name || '').toString().trim();
    const sameCoord = nearlyEqual(Number(t.lat), Number(th.lat)) && nearlyEqual(Number(t.lng), Number(th.lng));
    return sameName || sameCoord;
  });
  if (dup >= 0) {
    // merge fields
    list[dup] = { ...list[dup], ...th };
  } else {
    list.push(th);
  }
  return list;
}

function pick(obj, keys) { const o = {}; keys.forEach(k => { if (obj[k] != null) o[k] = obj[k]; }); return o; }

function extractCapacity(tags) {
  if (!tags) return undefined;
  const raw = tags['capacity:car'] || tags.capacity;
  if (!raw) return undefined;
  const n = parseInt(String(raw).replace(/[^0-9]/g, ''), 10);
  return Number.isFinite(n) && n > 0 ? n : String(raw);
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2)**2 + Math.cos(toRad(lat1))*Math.cos(toRad(lat2))*Math.sin(dLon/2)**2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

async function fetchAmenitiesAround(lat, lng, rrToilet, rrParking) {
  const q = `[
    out:json][timeout:25];
    (
      node["amenity"="toilets"](around:${rrToilet},${lat},${lng});
      node["amenity"="parking"](around:${rrParking},${lat},${lng});
    );
    out body;`;
  const am = await overpassQuery(q);
  const els = Array.isArray(am.elements) ? am.elements : [];
  const toilets = els.filter((x) => x.tags && x.tags.amenity === 'toilets');
  const parkings = els.filter((x) => x.tags && x.tags.amenity === 'parking');
  return { toilets, parkings };
}

async function enrichOneMountain(db, doc) {
  const data = doc.data() || {};
  let lat = Number(data.lat);
  let lng = Number(data.lng);
  const ths = Array.isArray(data.trailheads) ? data.trailheads : [];
  if ((!Number.isFinite(lat) || !Number.isFinite(lng)) && ths.length) {
    const t = ths[0];
    lat = Number(t.lat); lng = Number(t.lng);
  }
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return { skipped: true };

  const radius = Number(process.env.RADIUS_METERS || process.argv.find(a=>a.startsWith('--radius='))?.split('=')[1] || 2000);
  const qTrailheads = `[
    out:json][timeout:25];
    (
      node["tourism"="information"]["information"="trailhead"](around:${radius},${lat},${lng});
      way["tourism"="information"]["information"="trailhead"](around:${radius},${lat},${lng});
      rel["tourism"="information"]["information"="trailhead"](around:${radius},${lat},${lng});
    );
    out center;`;

  let osm;
  try {
    osm = await overpassQuery(qTrailheads);
  } catch (e) {
    console.warn(`Overpass trailhead error @${lat},${lng}: ${e.message}`);
    return { error: e.message };
  }

  const elements = Array.isArray(osm.elements) ? osm.elements : [];
  if (elements.length === 0) {
    // Fallback:探せなかった場合は駐車場/トイレから仮の登山口を生成
    const radiusSteps = [radius, Math.min(4000, radius*2), Math.min(6000, radius*3)];
    for (const rr of radiusSteps) {
      try {
        const { toilets, parkings } = await fetchAmenitiesAround(lat, lng, Math.max(600, Math.round(rr*0.3)), rr);
        if (parkings.length === 0 && toilets.length === 0) {
          // 次の半径で再試行
          await sleep(600);
          continue;
        }
        // 最寄りの駐車場を採用（無ければトイレ位置を仮の登山口）
        let node = null;
        let nodeType = '';
        if (parkings.length > 0) {
          nodeType = 'parking';
          node = parkings.map(p => ({...p, _d: haversineKm(lat, lng, p.lat, p.lon)})).sort((a,b)=>a._d-b._d)[0];
        } else if (toilets.length > 0) {
          nodeType = 'toilets';
          node = toilets.map(t => ({...t, _d: haversineKm(lat, lng, t.lat, t.lon)})).sort((a,b)=>a._d-b._d)[0];
        }
        if (!node) break;
        const nlat = node.lat, nlng = node.lon;
        const tname = (node.tags?.name || '').toString();
        const th = { name: tname || `${data.name} 登山口（${nodeType === 'parking' ? '駐車場' : '目印'}）`, lat: nlat, lng: nlng, source: 'osm-fallback' };
        // 収容台数とトイレ有無
        if (nodeType === 'parking') {
          const capacity = extractCapacity(node.tags);
          if (capacity != null) th.capacity = capacity;
        }
        const hasToiletNearby = toilets.some((t) => haversineKm(nlat, nlng, t.lat, t.lon) <= 0.6);
        if (hasToiletNearby) th.hasToilet = true;

        const merged = mergeTrailhead(ths, th);
        await doc.ref.set({ trailheads: merged }, { merge: true });
        return { updated: true, count: 1, fallback: true };
      } catch (e) {
        console.warn(`Fallback amenities query error @${lat},${lng}: ${e.message}`);
      }
    }
    return { updated: false };
  }

  let merged = ths.map((t) => ({ ...t }));
  for (const el of elements) {
    const tlat = (el.lat != null) ? el.lat : el.center?.lat; // node or way/rel center
    const tlng = (el.lon != null) ? el.lon : el.center?.lon;
    if (!Number.isFinite(tlat) || !Number.isFinite(tlng)) continue;
    const tname = (el.tags?.name || '').toString();
    const th = { name: tname || `${data.name} 登山口`, lat: tlat, lng: tlng, source: 'osm' };

    // For each trailhead, fetch toilets and parking nearby (smaller radius)
    const rrToilet = 500, rrParking = 800;
    try {
      const { toilets: elsToilet, parkings } = await fetchAmenitiesAround(tlat, tlng, rrToilet, rrParking);
      const hasToilet = elsToilet.length > 0;
      const capacity = parkings.map((p) => extractCapacity(p.tags)).find((c) => c != null);
      if (hasToilet) th.hasToilet = true;
      if (capacity != null) th.capacity = capacity;
      if (parkings.length > 0 && !th.parking) {
        th.parking = (parkings[0].tags?.name || '').toString();
      }
    } catch (e) {
      console.warn(`Overpass amenities error @${tlat},${tlng}: ${e.message}`);
    }

    merged = mergeTrailhead(merged, th);
    // Courtesy delay to avoid hammering Overpass
    await sleep(1200);
  }

  await doc.ref.set({ trailheads: merged }, { merge: true });
  return { updated: true, count: elements.length };
}

async function main() {
  const db = initFirebase();
  const limitArg = process.argv.find((a) => a.startsWith('--limit='));
  const limit = limitArg ? parseInt(limitArg.split('=')[1], 10) : undefined;

  const snap = await db.collection('mountains').get();
  let n = 0, updated = 0, skipped = 0, errors = 0;
  for (const d of snap.docs) {
    if (limit && n >= limit) break;
    n++;
    try {
      const r = await enrichOneMountain(db, d);
      if (r.skipped) skipped++; else if (r.error) errors++; else if (r.updated) updated++;
    } catch (e) {
      errors++;
      console.error('enrich mountain error:', e.message);
    }
    // Global courtesy delay
    await sleep(800);
  }
  console.log(`\nOSM enrich finished: total ${n}, updated ${updated}, skipped ${skipped}, errors ${errors}`);
}

main().catch((e) => { console.error('fatal:', e); process.exit(1); });
