// 百名山を除外した日本二百名山リストをCSVで出力するスクリプト
// usage: node export_nihon_200_meizan_only.js <input_csv> <output_csv>
import fs from 'fs';

const input = process.argv[2];
const output = process.argv[3];
const lines = fs.readFileSync(input, 'utf8').split(/\r?\n/);
if (lines.length < 2) throw new Error('CSVデータが不足しています');
const header = lines[0];
const rows = lines.slice(1).filter(Boolean);
const result = [header];
for (const row of rows) {
  const cols = row.split(',');
  // タグ列（9番目）に「日本百名山」が含まれていればスキップ
  if (cols[8] && cols[8].includes('日本百名山')) continue;
  // タグ列に「日本二百名山」が含まれていれば出力
  if (cols[8] && cols[8].includes('日本二百名山')) result.push(row);
}
fs.writeFileSync(output, result.join('\n'));
console.log('done');
