// CSVのカラム数を29列に揃える補正スクリプト
// usage: node fix_csv_columns.js <input> <output>
import fs from 'fs';

const input = process.argv[2];
const output = process.argv[3];
const EXPECTED_COLS = 29;

const lines = fs.readFileSync(input, 'utf8').split(/\r?\n/);
const fixed = lines.map((line, i) => {
  if (!line.trim()) return '';
  const cols = line.split(',');
  if (cols.length < EXPECTED_COLS) {
    return cols.concat(Array(EXPECTED_COLS - cols.length).fill('')).join(',');
  } else if (cols.length > EXPECTED_COLS) {
    return cols.slice(0, EXPECTED_COLS).join(',');
  } else {
    return line;
  }
});
fs.writeFileSync(output, fixed.join('\n'));
console.log('done');
