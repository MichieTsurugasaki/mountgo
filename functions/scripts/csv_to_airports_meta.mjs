#!/usr/bin/env node
/**
 * CSV -> airports_meta.json converter
 * 
 * Usage:
 *   node functions/scripts/csv_to_airports_meta.mjs input.csv path/to/assets/config/airports_meta.json
 * 
 * CSV columns (header required):
 *   code,category,type,dailyFlights
 * - category: major|regional (optional)
 * - type: legacy field (optional)
 * - dailyFlights: integer approximation per day
 */

import fs from 'node:fs';
import path from 'node:path';

function parseCsv(text) {
  const lines = text.split(/\r?\n/).filter(l => l.trim().length > 0);
  if (lines.length === 0) return [];
  const header = lines[0].split(',').map(s => s.trim());
  const idx = (name) => header.findIndex(h => h.toLowerCase() === name.toLowerCase());
  const iCode = idx('code');
  const iCategory = idx('category');
  const iType = idx('type');
  const iDaily = idx('dailyFlights');
  const out = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(',');
    const code = (cols[iCode] || '').trim();
    if (!code) continue;
    const category = (iCategory >= 0 ? cols[iCategory] : '').trim();
    const type = (iType >= 0 ? cols[iType] : '').trim();
    const dailyFlights = parseInt((iDaily >= 0 ? cols[iDaily] : '0').trim(), 10) || 0;
    out.push({ code, category, type, dailyFlights });
  }
  return out;
}

function main() {
  const [, , inputCsv, outJson] = process.argv;
  if (!inputCsv || !outJson) {
    console.error('Usage: node functions/scripts/csv_to_airports_meta.mjs input.csv assets/config/airports_meta.json');
    process.exit(1);
  }
  const csv = fs.readFileSync(inputCsv, 'utf8');
  const list = parseCsv(csv);
  const json = JSON.stringify(list, null, 2) + '\n';
  fs.mkdirSync(path.dirname(outJson), { recursive: true });
  fs.writeFileSync(outJson, json, 'utf8');
  console.log(`Wrote ${list.length} entries to ${outJson}`);
}

main();
