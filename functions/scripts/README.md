# 山データ管理スクリプト

検索機能に必要な山のデータをFirestoreに登録・更新するためのスクリプト集です。

## 📋 必要なデータ項目

### 必須項目
- `name`: 山名
- `pref`: 都道府県
- `elevation`: 標高（m）
- `lat`, `lng`: 緯度経度
- `level`: レベル（初級/中級/上級）
- `description`: 山の説明（200-300文字）

### 検索機能で使用する項目
- `course_time_total`: 総コースタイム（分）
- `course_time_up`: 登り時間（分）
- `course_time_down`: 下り時間（分）
- `time_car`: 車でのアクセス時間（分）
- `time_public`: 公共交通機関でのアクセス時間（分）
- `time`: アクセス時間の表示用文字列
- `trailhead_name`: 登山口名

### スタイル・特徴
- `styles`: ["ハイキング", "絶景", "自然", "稜線", "岩場", "鎖場"]
- `purposes`: ["冒険", "癒し", "リフレッシュ", "デート", "家族旅行"]

### 設備情報（boolean）
- `has_ropeway`: ロープウェイ
- `has_cablecar`: ケーブルカー
- `has_hut`: 山小屋
- `has_tent`: テント泊
- `has_onsen`: 近隣温泉
- `has_local_food`: 郷土料理

### その他
- `difficulty_score`: 難易度スコア（1-10）
- `created_at`, `updated_at`: タイムスタンプ

## 🚀 使い方

### 1. 既存データの拡張

既にFirestoreに登録されている日本百名山のデータに、検索機能用のフィールドを追加します。

```bash
cd functions/scripts
node enhance_mountain_data.mjs enhance
```

**含まれる山データ（一部）:**
- 高尾山、塔ノ岳、丹沢山
- 富士山
- 木曽駒ヶ岳
- 赤岳
- 槍ヶ岳、穂高岳、立山
- 岩手山、月山
- 大峰山
- 阿蘇山、霧島山、屋久島

### 2. 新規データの追加

スクリプトに含まれていない山を追加します。

```bash
node enhance_mountain_data.mjs add
```

### 3. 両方実行

```bash
node enhance_mountain_data.mjs all
```

### 4. Firestoreスキーマの正規化（フィールドの補完）

Flutterアプリが期待するフィールド（`level`, `courseTime`, `styles`, `purposes`, `tags`, `access`, `accessCar/accessPublic` など）を揃えるための補完スクリプトです。

```
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
node functions/scripts/normalize_mountains_schema.mjs
```

このスクリプトは次を行います：
- 欠けているキーに安全な初期値をセット（既存値は上書きしません）
- いくつかの値を文字列型に正規化
- 20件ごとに進捗を表示

### 空港メタをCSVから生成する（airports_meta.json）

空港メタ（主要/地方と便数など）をCSVから生成できます。

```
node functions/scripts/csv_to_airports_meta.mjs path/to/airports_meta.csv assets/config/airports_meta.json
```

CSVヘッダー例:

```
code,category,type,dailyFlights
HND,major,major,1200
MMJ,regional,regional,20
```

category/type は片方でもOK（後方互換）。dailyFlights は1日の便数の目安（整数）。

## 📊 CSVから一括インポート

大量の山データを一括で登録する場合は、CSVファイルを使用します。

### ステップ1: サンプルCSVを生成

```bash
node import_from_csv.mjs template
```

これで `firestore-seed/mountains_template.csv` が生成されます。

### ステップ2: CSVファイルを編集

生成されたCSVファイルを編集して、実際の山データを入力します。

**CSVフォーマット:**
```csv
name,pref,elevation,lat,lng,level,course_time_total,time_car,time_public,styles,purposes,has_ropeway,has_cablecar,has_hut,has_tent,has_onsen,has_local_food,difficulty_score,description
高尾山,東京都,599,35.6250,139.2430,初級,130,60,70,ハイキング|自然,癒し|デート,0,1,0,0,1,1,2,都心から1時間...
```

**注意:**
- `styles`と`purposes`は`|`区切りで複数指定
- boolean項目は`0`(false)または`1`(true)
- 文字列にカンマが含まれる場合はダブルクォートで囲む

### ステップ3: CSVの事前検証（推奨）

インポート前に形式チェックを行うと、エラーのある行を早期に発見できます。

```bash
node import_from_csv.mjs validate ../../firestore-seed/mountains_data.csv
```

検証では次を確認します。
- 必須カラムが揃っているか: name, pref, elevation, lat, lng, level
- 各行の必須値が正しいか: name/pref が空でない、lat/lng が数値、elevation が整数、level が 初級/中級/上級 のいずれか

問題があれば NG として行番号と項目を表示し、終了コード 1 で終了します。

### ステップ4: CSVをインポート

```bash
node import_from_csv.mjs import ../../firestore-seed/mountains_data.csv

### 日本二百名山などデータセットの取り込み

CSVに `tags` 列がある場合は `|` 区切りでタグを指定できます（例: `日本二百名山|自然`）。
CSVにまだタグを入れていなくても、インポート時に全件へタグを一括付与できます。

```bash
# 例: 二百名山のCSVを取り込みつつ、全行に「日本二百名山」タグを追加
node import_from_csv.mjs import ../csv/japan-200mountains.csv --format=200 --append-tag=日本二百名山
```

2パターンの取り込みに対応しています。

1) 標準フォーマット（推奨）
   - 列: `name, pref, elevation, lat, lng, level`（必須）
   - 任意: `course_time_total, time_car, time_public, description, styles, purposes, tags, access`
   - 備考: `styles/purposes/tags/access` は `|` 区切りで複数指定

2) 日本二百名山の簡易フォーマット
   - 列: `番号, 山名, よみがな, 所在地`
   - 実行時に `--format=200` を付けると、この形式を受け付けます
   - `所在地` から都道府県を自動抽出（例: "岩手/秋田…" にも簡易対応）
   - 座標・標高などは未設定で登録（後で正規化/補完可能）
   - 例: `--append-tag=日本二百名山` を併用すると全行にタグを付与
```

## 🧭 既存CSV（百名山集約）からの取り込み（クイック）

提供いただいた `mountains_master_with_yamap_all_v2.csv` と `trailheads_master.csv` をそのまま取り込むためのスクリプトも用意しています。

### 山の基本情報（座標・標高など）

```bash
# 例: functions ディレクトリで実行
npm run import-mountains -- \
   "/absolute/path/to/mountains_master_with_yamap_all_v2.csv"
```

- 取り込む主な項目: name, lat, lng, elevation_m → elevation, prefectures → 先頭だけ pref, difficulty → level（初級/中級/上級）, median_time_h → courseTime（X時間Y分）
- 既存ドキュメントは name 一致で更新、なければ新規作成

### 登山口（trailheads）の取り込み

```bash
npm run import-trailheads -- \
   "/absolute/path/to/trailheads_master.csv"
```

- 取り込む主な項目: name, lat, lng, address, parking, toiletSeason, notes
- mountains.name == mountainName のドキュメントを探し、`trailheads` 配列にマージ（重複はスキップ）

取り込み後はアプリをリロードしてください。`lat/lng` が入っていれば、出発地からの実ルート計算によりアクセスタイム（「（実ルート）」表示）がカード/詳細に出るようになります。

## � YAMAPリンクの一括付与/更新（山ページ/コースURL）

各山ドキュメントに `yamap_mountain_id`（数値）や `yamap_url`、`itinerary_yamap`（コースURL）をまとめて付与します。詳細ページの「YAMAPで…」ボタンは以下の優先順でリンク先を決定します。

1) `itinerary_yamap` がURLならそのコースへ
2) `yamap_url` がURLなら山ページへ
3) `yamap_mountain_id` が数値なら `https://yamap.com/mountains/{id}` へ
4) なければ Google検索へフォールバック

テンプレートCSVは `firestore-seed/yamap_links_template.csv` を利用してください。

実行例（dry-run→本書き込みの順に推奨）:

```bash
cd functions

# 乾燥実行（書き込みなし）
npm run yamap:update-links -- --in=../firestore-seed/yamap_links.csv

# 問題なければ書き込み
npm run yamap:update-links -- --in=../firestore-seed/yamap_links.csv --write
```

CSVカラム例:

```
doc_id,name,pref,yamap_mountain_id,yamap_url,itinerary_yamap
```

特定方法の優先度:
- `doc_id` があればそれを使用（最優先）
- なければ `name` と（可能なら）`pref` の一致で1件に特定
- 複数一致や未一致はスキップし、警告を表示します

### 既存CSVからの抽出（ヘルパー）

既存の集約CSV（例: `mountains_master_with_yamap_all_v2.csv`）から、YAMAP URL/IDをテンプレ形式に変換するヘルパーを用意しています。

実行例:

```bash
cd functions

# 既存CSVから yamap_url などを抽出してテンプレ形式に変換
npm run yamap:extract -- --in=/path/to/mountains_master.csv --out=../firestore-seed/yamap_links.csv

# 出力を省略すると同じフォルダに yamap_links_extracted.csv が生成されます
npm run yamap:extract -- --in=/path/to/mountains_master.csv
```

抽出ポリシー:
- 列名が `yamap_url` / `YAMAP_URL` / `yamapLink` など明確ならそれを使用
- そうでなければ全列を走査し、`http` かつ `yamap.com` を含む値をURL候補として採用
- `itinerary_yamap`（コースURL）があれば併記
- `/mountains/{id}` が含まれるURLからは `yamap_mountain_id` を自動抽出

この生成CSVを手直し（必要に応じて `doc_id` を追記・確認）した上で、`yamap:update-links` をdry-run→writeの順に実行してください。

## 📝 データ入力のヒント

### アクセス時間の目安
- **~1時間**: 都心から近い山（高尾山など）
- **1〜2時間**: 関東近郊（塔ノ岳、大菩薩嶺など）
- **2〜3時間**: 中距離（丹沢山、富士山など）
- **3〜5時間**: 遠距離（八ヶ岳、北アルプスなど）
- **5時間以上**: 超遠距離（屋久島など）

### コースタイムの目安
- **〜2時間**: 初心者向け軽登山
- **2〜4時間**: 半日コース
- **4〜6時間**: 日帰り標準コース
- **6〜9時間**: 日帰りロングコース
- **それ以上**: 縦走、山小屋泊推奨

### レベルの目安
- **初級**: 標高差500m以下、整備された登山道、半日程度
- **中級**: 標高差500-1000m、一般登山道、体力必要
- **上級**: 標高差1000m以上、岩場・鎖場あり、登山経験必須

### 難易度スコア（1-10）
- **1-2**: 観光気分で登れる（高尾山、阿蘇山）
- **3-4**: 軽登山（大菩薩嶺、木曽駒ヶ岳）
- **5-6**: 本格登山（塔ノ岳、丹沢山、月山）
- **7-8**: 技術が必要（赤岳、大峰山、富士山）
- **9-10**: エキスパート向け（槍ヶ岳、穂高岳）

## 🔍 データ確認

Firebaseコンソールで確認:
https://console.firebase.google.com/project/yamabiyori/firestore/data/mountains

または、Flutterアプリで検索してみてください！

## 🩺 タグ健全性チェック（定期実行対応）

Firestore の `mountains` コレクションにおける `tags` フィールドの健全性を自動チェックするスクリプトを用意しています。

### ローカル実行

```bash
cd functions
# 1) 環境変数にサービスアカウントJSON文字列を渡す場合（推奨）
export FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account", ... }'

# 2) もしくは GOOGLE_APPLICATION_CREDENTIALS でファイルパスを渡す
# export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/serviceAccount.json

# 実行（STRICTモードで不整合があれば終了コード1）
STRICT=true ENFORCE_HYAKUMEIZAN_FOR_ALL=true REQUIRED_TAG='日本百名山' npm run check:tags
```

チェック内容:
- `tags` フィールドの有無
- `tags` が配列型かどうか
- `tags` が空配列でないか
- 各要素が非空文字列か
- 必須タグ（デフォルト: `日本百名山`）の付与状況（サンプルを最大20件表示）

環境変数:
- `STRICT`（既定: `true`）: 不整合があれば失敗とする
- `ENFORCE_HYAKUMEIZAN_FOR_ALL`（既定: `false`）: すべての山に必須タグを要求
- `REQUIRED_TAG`（既定: `日本百名山`）: 必須タグ名

### GitHub Actions による定期実行

`.github/workflows/data-health-check.yml` を追加しました。毎日 06:00 JST に実行されます。

1. リポジトリの Settings → Secrets and variables → Actions → New repository secret から
   `FIREBASE_SERVICE_ACCOUNT_JSON` を作成し、サービスアカウントJSONの中身を貼り付けて保存します。
2. 以後、CI 上で自動的にスクリプトが実行され、重大な不整合があればジョブが失敗します。

必要に応じて `ENFORCE_HYAKUMEIZAN_FOR_ALL` を `false` に変更すれば、
「日本百名山」タグが未付与のドキュメントがあっても失敗させずにレポートのみ出力できます。

## ⚠️ 注意事項

1. **本番環境での実行時は十分注意してください**
   - テスト環境で動作確認後、本番実行を推奨
   - バックアップを取ってから実行

2. **API制限**
   - Firestoreの書き込み制限に注意
   - 大量データの場合はバッチ処理を検討

3. **データの精度**
   - アクセス時間は出発地により変動
   - コースタイムは個人差あり
   - 最新情報は各自治体・山小屋で確認

## 📚 データソース

以下のサイトを参考にデータを収集することをおすすめします:

- **ヤマレコ**: https://www.yamareco.com/
  - コースタイム、難易度、登山口情報
- **国土地理院**: https://www.gsi.go.jp/
  - 正確な標高、座標
- **山と高原地図**: https://www.yamakei.co.jp/
  - コースタイム、ルート情報
- **各自治体の観光協会サイト**
  - アクセス情報、駐車場情報

## 🆘 トラブルシューティング

### エラー: "Cannot find module 'csv-parse'"

```bash
cd functions
npm install csv-parse
```

### エラー: "Permission denied"

Firebase Admin SDKの認証情報を確認してください。
`gen-lang-client-0636793764-796b85572dd7.json`が正しい場所にあるか確認。

### 実行後にデータが表示されない

1. Firebaseコンソールでデータが登録されているか確認
2. Flutterアプリの検索条件を緩くして再検索
3. ブラウザのコンソールで`_loadCandidateMountains`のログを確認

## 💡 次のステップ

1. **優先度の高い山から登録**
   - 関東の人気の山20-30件
   - 北アルプスの主要な山10-15件
   - 各地方の代表的な山

2. **データの充実**
   - ヤマレコAPIでコースタイムを自動取得
   - 山小屋・温泉・郷土料理の詳細情報追加

3. **フィードバック収集**
   - ユーザーの検索結果を分析
   - データの精度を向上

---

質問や改善提案があれば、お気軽にご連絡ください！
