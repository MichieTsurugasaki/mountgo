// nihon_200_meizan_only.csv をFirestoreインポート用に変換するスクリプト
// usage: node convert_nihon_200_meizan_only_to_import.js <input_csv> <output_csv>
import fs from 'fs';

const input = process.argv[2];
const output = process.argv[3];
const lines = fs.readFileSync(input, 'utf8').split(/\r?\n/);
if (lines.length < 2) throw new Error('CSVデータが不足しています');
const header = 'id,name,name_kana,pref,level,height,lat,lng,tags,category,activity,access,min_time,max_time,season,desc,notes,fee,fee_note,parking,parking_note,toilet,toilet_note,water,water_note,stay,stay_note,area,hyaku';
const result = [header];
for (let i = 1; i < lines.length; i++) {
  const row = lines[i];
  if (!row.trim()) continue;
  const cols = row.split(',');
  // 必要なカラムをマッピング
  const out = [
    cols[0], // id
    cols[1], // name
    cols[2], // name_kana
    cols[3], // pref
    cols[4], // level
    cols[5], // height
    cols[6], // lat
    cols[7], // lng
    cols[8], // tags
    cols[9], // category
    cols[10], // activity
    cols[11], // access
    cols[12], // min_time
    cols[13], // max_time
    '', // season
    cols[15], // desc
    '', // notes
    '', // fee
    '', // fee_note
    '', // parking
    '', // parking_note
    '', // toilet
    '', // toilet_note
    '', // water
    '', // water_note
    '', // stay
    '', // stay_note
    '', // area
    ''  // hyaku
  ];
  result.push(out.join(','));
}
fs.writeFileSync(output, result.join('\n'));
console.log('done');
