# 日本二百名山・三百名山 データベース CSV フォーマット仕様

## 概要
このドキュメントでは、日本二百名山・三百名山の山情報と登山口情報を収集・管理するためのCSVフォーマットを定義します。

## 共通ルール

### ファイル形式
- **文字コード**: UTF-8（BOMなし）
- **改行コード**: LF（Unix形式）
- **区切り文字**: カンマ（,）
- **複数値の区切り**: パイプ（|）
- **日付形式**: ISO 8601（例: 2025-10-28T00:00:00Z）

### データ品質
- 座標はWGS84、小数点6桁以上推奨（精度約0.11m）
- 必須フィールドは空欄不可
- 出典・ライセンス情報は必ず記載
- URLは検証済みのものを使用

---

## 1. mountains.csv - 山の基本情報

### 目的
山単位の基本マスタデータ（峰名・読み・標高・座標・所属都道府県など）

### フィールド定義

| カラム名 | 必須 | 型 | 説明 | 例 |
|---------|------|-----|------|-----|
| mountain_id | ★ | string | ユニークID | JPN200-001 |
| name | ★ | string | 正式名称 | 富士山 |
| name_kana | | string | ふりがな | ふじさん |
| alt_name | | string | 別名（複数は\|区切り） | 白根三山 |
| elevation_m | ★ | integer | 標高（メートル） | 3776 |
| lat | ★ | decimal | 緯度（WGS84） | 35.360625 |
| lng | ★ | decimal | 経度（WGS84） | 138.727363 |
| prefectures | ★ | string | 都道府県（複数は\|区切り） | 静岡県\|山梨県 |
| range | | string | 山域／山系 | 富士山地 |
| difficulty | | string | 総合難易度 | 初級/中級/上級 |
| prominence_m | | integer | 独立峰高（メートル） | 3776 |
| geom_source | | string | 座標の出典 | GSI/OpenStreetMap/GPS実測 |
| description | | text | 短い説明（300文字以内） | 日本最高峰の独立峰... |
| listings | | string | 収録リスト（\|区切り） | 二百名山\|日本百名山 |
| tags | | string | タグ（\|区切り） | 日本百名山\|温泉\|山小屋\|縦走 |
| source_url | ★ | string | 出典URL | https://example.org |
| license | ★ | string | ライセンス | CC-BY-4.0 |
| created_at | | datetime | 作成日時 | 2025-10-28T00:00:00Z |
| updated_at | | datetime | 更新日時 | 2025-10-28T00:00:00Z |

### サンプル
```csv
mountain_id,name,name_kana,alt_name,elevation_m,lat,lng,prefectures,range,difficulty,prominence_m,geom_source,description,listings,tags,source_url,license,created_at,updated_at
JPN200-001,富士山,ふじさん,,3776,35.360625,138.727363,山梨県|静岡県,富士山地,中級,,GSI,日本最高峰の独立峰。夏季は多くの登山者で賑わう。,二百名山|日本百名山,日本百名山,https://example.org/fuji,CC-BY-4.0,2025-10-28T00:00:00Z,2025-10-28T00:00:00Z
```

### タグ一覧
使用可能なタグ（複数はパイプ区切り）:
- **日本百名山**: 日本百名山に選定されている
- **二百名山**: 日本二百名山に選定されている
- **三百名山**: 日本三百名山に選定されている
- **温泉**: 近隣に温泉施設あり
- **山小屋**: ルート上に山小屋あり
- **テント泊**: テント泊可能
- **縦走**: 縦走ルートあり
- **ロープウェイ**: ロープウェイでアクセス可能
- **ケーブルカー**: ケーブルカーでアクセス可能
- **郷土料理**: 周辺で郷土料理が楽しめる
- **公共交通機関**: 公共交通でアクセス可能

---

## 2. trailheads.csv - 登山口情報

### 目的
登山口・登山道入口ごとの詳細（アクセス情報や駐車場など）

### フィールド定義

| カラム名 | 必須 | 型 | 説明 | 例 |
|---------|------|-----|------|-----|
| trailhead_id | ★ | string | ユニークID | JPN200-001-A |
| mountain_id | ★ | string | 山ID（mountains.csvの外部キー） | JPN200-001 |
| name | ★ | string | 登山口名 | 吉田口登山道・富士山スバルライン五合目 |
| name_kana | | string | ふりがな | ふじさんよしだぐちごごうめ |
| alt_name | | string | 別名 | |
| lat | ★ | decimal | 緯度 | 35.404 |
| lng | ★ | decimal | 経度 | 138.791 |
| elevation_m | | integer | 登山口標高 | 2305 |
| access_summary | | text | アクセス概要 | 車:中央道河口湖ICから40分\|バス:河口湖駅から路線バスあり |
| nearest_station | | string | 最寄り駅 | 河口湖駅 |
| nearest_station_dist_km | | decimal | 駅からの距離（km） | 30 |
| bus_routes | | string | バス路線（複数は\|区切り） | 河口湖駅→五合目バス |
| parking | | string | 駐車場情報 | 有(200台) |
| parking_fee | | string | 駐車料金 | 有料（1000円/日） |
| opening_season | | string | 開設時期 | 4-10 / 通年 |
| trail_type | | string | ルート種別 | 登山道/林道/ロープウェイ |
| estimated_time_up_h | | decimal | 登り所要時間（時間） | 6.5 |
| estimated_time_down_h | | decimal | 下り所要時間（時間） | 4.5 |
| difficulty | | string | 難易度 | 初級/中級/上級 |
| trail_condition_note | | text | 危険箇所メモ | 鎖場あり/岩場注意 |
| official_url | | string | 公式サイト | https://... |
| source_url | ★ | string | 出典URL | https://example.org |
| license | ★ | string | ライセンス | CC-BY-4.0 |
| created_at | | datetime | 作成日時 | 2025-10-28T00:00:00Z |
| updated_at | | datetime | 更新日時 | 2025-10-28T00:00:00Z |

### サンプル
```csv
trailhead_id,mountain_id,name,name_kana,lat,lng,elevation_m,access_summary,nearest_station,bus_routes,parking,parking_fee,opening_season,estimated_time_up_h,estimated_time_down_h,difficulty,source_url,license
JPN200-001-A,JPN200-001,富士山吉田口五合目,ふじさんよしだぐちごごうめ,35.404,138.791,2305,車:中央道河口湖ICから40分|バス:河口湖駅から路線バスあり,河口湖駅,河口湖駅→五合目バス,有(200台),有料,7-9,6.5,4.5,中級,https://example.org,CC-BY-4.0
```

---

## 3. facilities.csv - ルート沿い施設情報

### 目的
登山ルート上にあるトイレ・山小屋・お店などの施設情報

### フィールド定義

| カラム名 | 必須 | 型 | 説明 | 例 |
|---------|------|-----|------|-----|
| facility_id | ★ | string | ユニークID | FAC-001 |
| mountain_id | ★ | string | 山ID | JPN200-001 |
| trailhead_id | | string | 登山口ID（特定ルート上の場合） | JPN200-001-A |
| type | ★ | string | 施設種別 | トイレ/山小屋/お店 |
| name | ★ | string | 施設名 | 吉田口五合目公衆トイレ |
| distance_km | | decimal | 登山口からの距離（km） | 0 |
| elevation_m | | integer | 標高 | 2305 |
| lat | | decimal | 緯度 | 35.404 |
| lng | | decimal | 経度 | 138.791 |
| open_season | ★ | string | 開設時期 | 通年 / 4-11 / 7-9月 |
| winter_closed | | boolean | 冬季凍結閉鎖の可能性 | true/false |
| capacity | | integer | 収容人数（山小屋の場合） | 200 |
| facilities | | string | 設備（複数は\|区切り） | 宿泊\|食事\|売店 |
| water_available | | boolean | 水場あり | true/false |
| emergency_contact | | string | 緊急連絡先 | 090-xxxx-xxxx |
| notes | | text | 備考 | チップ制200円 |
| source_url | ★ | string | 出典URL | https://example.org |
| license | ★ | string | ライセンス | CC-BY-4.0 |
| created_at | | datetime | 作成日時 | 2025-10-28T00:00:00Z |
| updated_at | | datetime | 更新日時 | 2025-10-28T00:00:00Z |

### サンプル
```csv
facility_id,mountain_id,type,name,distance_km,elevation_m,open_season,winter_closed,notes,source_url,license
FAC-001,JPN200-001,トイレ,吉田口五合目公衆トイレ,0,2305,7-9月,true,チップ制200円,https://example.org,CC-BY-4.0
FAC-002,JPN200-001,山小屋,富士山ホテル,1.5,2700,7-9月,true,予約推奨。素泊まり8000円〜,https://example.org,CC-BY-4.0
```

---

## データ収集のヒント

### 信頼できる情報源
1. **公式サイト**: 各山域の観光協会・自治体サイト
2. **国土地理院**: 地図・標高データ
3. **登山情報サイト**: YAMAP、ヤマレコ、山と高原地図
4. **現地取材**: 実際に登山して確認（推奨）

### ID命名規則
- **山**: `JPN200-001`（日本二百名山）、`JPN300-001`（日本三百名山）
- **登山口**: `JPN200-001-A`（同一山の複数登山口はA/B/C...）
- **施設**: `FAC-001`（通し番号）

### 注意事項
- 座標は必ず現地確認またはGPS実測値を使用
- 駐車場・バス情報は季節変動があるため最新情報を確認
- トイレの冬季閉鎖情報は必ず記載（凍結リスク）
- 山小屋は営業期間・料金が毎年変わる可能性あり

---

## インポート手順

### 1. CSVファイル準備
```bash
# テンプレートをコピー
cp mountains_template.csv mountains.csv
cp trailheads_template.csv trailheads.csv
cp facilities_template.csv facilities.csv
```

### 2. データ入力
Excelやスプレッドシートで編集可能。保存時は必ずUTF-8、カンマ区切りで保存。

### 3. Firestoreへインポート
```bash
cd functions
node scripts/import_mountains.mjs
node scripts/import_trailheads.mjs
node scripts/import_facilities.mjs
```

---

## ライセンス情報

推奨ライセンス:
- **CC-BY-4.0**: 著作権表示付きで自由に利用可能
- **CC0**: パブリックドメイン（権利放棄）
- **独自ライセンス**: 出典元のライセンスに従う

必ず`source_url`と`license`を記載し、データの追跡可能性を確保してください。
