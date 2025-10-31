/**
 * 山データ拡張スクリプト
 * 既存のFirestoreデータに検索機能用のフィールドを追加
 */

import admin from 'firebase-admin';
import { readFileSync } from 'fs';

// Firebase Admin初期化（ローカルで実行する場合）
const serviceAccount = JSON.parse(
  readFileSync('./gen-lang-client-0636793764-796b85572dd7.json', 'utf8')
);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'yamabiyori'
});

const db = admin.firestore();

/**
 * 検索機能に必要な拡張データ
 * 実際の山データに基づいて調整してください
 */
const mountainEnhancements = {
  // === 関東エリア ===
  "高尾山": {
    level: "初級",
    course_time_total: 130, // 2時間10分
    course_time_up: 60,
    course_time_down: 50,
    time_car: 60,
    time_public: 70,
    trailhead_name: "高尾山口駅",
    styles: ["ハイキング", "自然"],
    purposes: ["癒し", "デート", "家族旅行"],
    has_ropeway: false,
    has_cablecar: true,
    has_hut: false,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 2,
    description: "都心から1時間、標高599mの身近な名山。ケーブルカーやリフトもあり、初心者から楽しめる。山頂からは富士山や都心の眺望が素晴らしく、四季折々の自然と高尾山薬王院の歴史を感じられる。下山後は極楽湯で温泉、名物とろろそばも楽しめる。"
  },
  
  "塔ノ岳": {
    level: "中級",
    course_time_total: 330, // 5時間30分
    course_time_up: 210,
    course_time_down: 120,
    time_car: 150,
    time_public: 180,
    trailhead_name: "大倉バス停",
    styles: ["絶景", "稜線"],
    purposes: ["冒険", "リフレッシュ"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 5,
    description: "丹沢の名峰、標高1,491m。大倉尾根は「バカ尾根」と呼ばれる急登だが、山頂からの富士山と相模湾の眺望は絶景。山頂には尊仏山荘があり、丹沢表尾根の起点として人気。体力をつけたい中級者におすすめ。"
  },
  
  "丹沢山": {
    level: "中級",
    course_time_total: 405, // 6時間45分
    course_time_up: 255,
    course_time_down: 150,
    time_car: 125,
    time_public: 165,
    trailhead_name: "大倉バス停",
    styles: ["稜線", "絶景"],
    purposes: ["冒険", "リフレッシュ"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: true,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 6,
    description: "標高1,567m、丹沢山地の最高峰。塔ノ岳から稜線を縦走するルートが人気。ブナ林の美しい自然と展望の良い稜線歩きが魅力。みやま山荘でテント泊も可能。体力に自信のある中級者向け。"
  },

  // === 富士・南アルプス ===
  "富士山": {
    level: "上級",
    course_time_total: 600, // 10時間（往復）
    course_time_up: 360,
    course_time_down: 240,
    time_car: 180,
    time_public: 240,
    trailhead_name: "富士宮口五合目",
    styles: ["絶景"],
    purposes: ["冒険"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 8,
    description: "標高3,776m、日本最高峰。7月〜9月の夏山シーズンのみ登山可能。高山病対策と防寒具が必須。山頂からのご来光は一生の思い出に。登山経験を積んだ上級者向け。山小屋での一泊が推奨される。"
  },

  // === 中央アルプス ===
  "木曽駒ヶ岳": {
    level: "中級",
    course_time_total: 240, // 4時間（ロープウェイ利用）
    course_time_up: 120,
    course_time_down: 120,
    time_car: 240,
    time_public: 300,
    trailhead_name: "千畳敷駅",
    styles: ["絶景", "稜線"],
    purposes: ["癒し", "リフレッシュ"],
    has_ropeway: true,
    has_cablecar: false,
    has_hut: true,
    has_tent: true,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 4,
    description: "標高2,956m。駒ヶ岳ロープウェイで千畳敷カールまで一気に登れる、アクセス抜群のアルプス。高山植物の宝庫で、稜線からの眺望も素晴らしい。ロープウェイ利用で初心者でも3,000m級の山を体験できる。"
  },

  // === 八ヶ岳 ===
  "赤岳": {
    level: "上級",
    course_time_total: 540, // 9時間
    course_time_up: 330,
    course_time_down: 210,
    time_car: 210,
    time_public: 270,
    trailhead_name: "美濃戸口",
    styles: ["岩場", "鎖場", "絶景"],
    purposes: ["冒険"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: true,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 7,
    description: "標高2,899m、八ヶ岳連峰の最高峰。岩場と鎖場があり、登山技術が必要。文三郎尾根・地蔵尾根ルートが一般的。山頂からは南北アルプスや富士山の大パノラマ。赤岳鉱泉や行者小屋で一泊推奨。"
  },

  // === 北アルプス ===
  "槍ヶ岳": {
    level: "上級",
    course_time_total: 960, // 2日間コース（16時間）
    course_time_up: 600,
    course_time_down: 360,
    time_car: 300,
    time_public: 360,
    trailhead_name: "上高地",
    styles: ["岩場", "鎖場", "絶景"],
    purposes: ["冒険"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: true,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 9,
    description: "標高3,180m、日本のマッターホルンと称される名峰。山頂直下の梯子と鎖場は高度感抜群。槍ヶ岳山荘での一泊が必須。登山経験豊富な上級者向け。北アルプスの中心に位置し、360度の大展望が圧巻。"
  },

  "穂高岳": {
    level: "上級",
    course_time_total: 900, // 2日間コース
    course_time_up: 540,
    course_time_down: 360,
    time_car: 300,
    time_public: 360,
    trailhead_name: "上高地",
    styles: ["岩場", "鎖場", "絶景"],
    purposes: ["冒険"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: true,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 9,
    description: "標高3,190m、北アルプスの盟主。奥穂高岳、前穂高岳、北穂高岳など複数のピークからなる。岩稜帯の縦走は高度な技術が必要。穂高岳山荘や涸沢ヒュッテで宿泊。経験豊富な上級者のみ。"
  },

  "立山": {
    level: "中級",
    course_time_total: 300, // 5時間（ロープウェイ・バス利用）
    course_time_up: 180,
    course_time_down: 120,
    time_car: 180,
    time_public: 210,
    trailhead_name: "室堂",
    styles: ["絶景", "稜線"],
    purposes: ["癒し", "リフレッシュ"],
    has_ropeway: true,
    has_cablecar: true,
    has_hut: true,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 5,
    description: "標高3,015m、立山黒部アルペンルートでアクセス抜群。室堂から雄山へのルートは整備されており、中級者でも3,000m級を体験できる。みくりが池や地獄谷など見どころも多い。山小屋も充実。"
  },

  // === 東北 ===
  "岩手山": {
    level: "中級",
    course_time_total: 480, // 8時間
    course_time_up: 300,
    course_time_down: 180,
    time_car: 240,
    time_public: 300,
    trailhead_name: "馬返し登山口",
    styles: ["絶景", "自然"],
    purposes: ["冒険", "リフレッシュ"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 6,
    description: "標高2,038m、岩手県の最高峰。「南部片富士」と呼ばれる美しい山容。樹林帯から火山地形まで変化に富む登山道。山頂からは八幡平や鳥海山、晴れれば日本海まで望める。日帰り可能だが体力が必要。"
  },

  "月山": {
    level: "中級",
    course_time_total: 300, // 5時間
    course_time_up: 180,
    course_time_down: 120,
    time_car: 210,
    time_public: 270,
    trailhead_name: "姥沢登山口",
    styles: ["絶景", "自然"],
    purposes: ["癒し", "リフレッシュ"],
    has_ropeway: true,
    has_cablecar: false,
    has_hut: true,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 4,
    description: "標高1,984m、出羽三山の主峰。夏でも残雪があり、高山植物の宝庫。リフト利用で姥ヶ岳まで上がれば比較的楽に登れる。山頂には月山神社本宮。湯殿山、羽黒山とセットで訪れる修験の山。"
  },

  // === 関西・近畿 ===
  "大峰山": {
    level: "上級",
    course_time_total: 540, // 9時間
    course_time_up: 330,
    course_time_down: 210,
    time_car: 240,
    time_public: 300,
    trailhead_name: "行者還トンネル西口",
    styles: ["鎖場", "自然"],
    purposes: ["冒険"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: true,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 7,
    description: "標高1,915m（八経ヶ岳）、近畿最高峰。修験道の聖地で、弥山、八経ヶ岳へと続く稜線歩き。鎖場や岩場もあり登山技術が必要。原生林と苔の美しさは格別。弥山小屋で一泊推奨。"
  },

  // === 九州 ===
  "阿蘇山": {
    level: "初級",
    course_time_total: 120, // 2時間（ロープウェイ利用）
    course_time_up: 60,
    course_time_down: 60,
    time_car: 180,
    time_public: 240,
    trailhead_name: "阿蘇山西駅",
    styles: ["絶景", "自然"],
    purposes: ["癒し", "家族旅行"],
    has_ropeway: true,
    has_cablecar: false,
    has_hut: false,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 2,
    description: "標高1,592m（高岳）、世界最大級のカルデラを持つ活火山。ロープウェイで火口近くまで行ける。噴煙を上げる中岳火口は圧巻。草千里や米塚など見どころ満載。初心者でも楽しめる。"
  },

  "霧島山": {
    level: "中級",
    course_time_total: 240, // 4時間
    course_time_up: 150,
    course_time_down: 90,
    time_car: 240,
    time_public: 300,
    trailhead_name: "えびの高原",
    styles: ["絶景", "自然"],
    purposes: ["癒し", "リフレッシュ"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: false,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 5,
    description: "標高1,700m（韓国岳）、火山群からなる霊峰。韓国岳からは桜島や開聞岳を望む絶景。火口湖の大浪池も美しい。霧島温泉郷が近く、登山と温泉を楽しめる。高千穂峰への縦走も人気。"
  },

  "屋久島・宮之浦岳": {
    level: "上級",
    course_time_total: 660, // 11時間
    course_time_up: 420,
    course_time_down: 240,
    time_car: 60,
    time_public: 90,
    trailhead_name: "淀川登山口",
    styles: ["自然"],
    purposes: ["冒険", "癒し"],
    has_ropeway: false,
    has_cablecar: false,
    has_hut: true,
    has_tent: true,
    has_onsen: true,
    has_local_food: true,
    difficulty_score: 8,
    description: "標高1,936m、九州最高峰。世界自然遺産の原生林を抜けて登る。往復11時間と長丁場で体力が必要。縄文杉とセットで訪れる人も多い。新高塚小屋で一泊も可能。屋久島の大自然を満喫できる。"
  }
};

/**
 * アクセス時間の範囲を数値に変換（検索用）
 */
function getAccessTimeRange(timeString) {
  if (!timeString) return null;
  
  const ranges = {
    "~1時間": { min: 0, max: 60 },
    "1〜2時間": { min: 60, max: 120 },
    "2〜3時間": { min: 120, max: 180 },
    "3〜5時間": { min: 180, max: 300 },
    "5時間以上": { min: 300, max: 999 }
  };
  
  return ranges[timeString] || null;
}

/**
 * コースタイムの範囲を数値に変換
 */
function getCourseTimeRange(timeString) {
  if (!timeString) return null;
  
  const ranges = {
    "〜2時間": { min: 0, max: 120 },
    "2〜4時間": { min: 120, max: 240 },
    "4〜6時間": { min: 240, max: 360 },
    "6〜9時間": { min: 360, max: 540 },
    "それ以上（縦走を含む）": { min: 540, max: 9999 }
  };
  
  return ranges[timeString] || null;
}

/**
 * Firestoreのmountainsコレクションを更新
 */
async function enhanceMountainData() {
  console.log('🏔️  山データ拡張を開始します...\n');
  
  try {
    const mountainsRef = db.collection('mountains');
    const snapshot = await mountainsRef.get();
    
    let updatedCount = 0;
    let notFoundCount = 0;
    
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const mountainName = data.name;
      
      console.log(`処理中: ${mountainName}`);
      
      // 拡張データがあれば追加
      if (mountainEnhancements[mountainName]) {
        const enhancement = mountainEnhancements[mountainName];
        
        // 既存データとマージ
        const updateData = {
          ...enhancement,
          // アクセス時間の文字列表現も保存
          time: enhancement.time_car && enhancement.time_public 
            ? `${enhancement.time_car}分（車）/ ${enhancement.time_public}分（公共交通機関）`
            : enhancement.time_car 
              ? `${enhancement.time_car}分（車）`
              : enhancement.time_public 
                ? `${enhancement.time_public}分（公共交通機関）`
                : '',
          // 更新日時
          updated_at: admin.firestore.FieldValue.serverTimestamp()
        };
        
        await mountainsRef.doc(doc.id).update(updateData);
        console.log(`  ✅ ${mountainName} - 更新完了`);
        updatedCount++;
      } else {
        console.log(`  ⚠️  ${mountainName} - 拡張データなし（スキップ）`);
        notFoundCount++;
      }
    }
    
    console.log('\n=== 処理完了 ===');
    console.log(`✅ 更新: ${updatedCount}件`);
    console.log(`⚠️  スキップ: ${notFoundCount}件`);
    console.log(`📊 合計: ${snapshot.size}件\n`);
    
    console.log('🎉 山データの拡張が完了しました！');
    
  } catch (error) {
    console.error('❌ エラーが発生しました:', error);
    throw error;
  }
}

/**
 * 新しい山データを追加（サンプル）
 */
async function addNewMountains() {
  console.log('\n🏔️  新しい山データを追加します...\n');
  
  const newMountains = [
    {
      name: "大菩薩嶺",
      pref: "山梨県",
      elevation: 2057,
      lat: 35.7686,
      lng: 138.8342,
      level: "初級",
      course_time_total: 240,
      course_time_up: 150,
      course_time_down: 90,
      time_car: 150,
      time_public: 210,
      time: "150分（車）/ 210分（公共交通機関）",
      trailhead_name: "上日川峠",
      styles: ["絶景", "稜線"],
      purposes: ["癒し", "リフレッシュ"],
      has_ropeway: false,
      has_cablecar: false,
      has_hut: true,
      has_tent: false,
      has_onsen: true,
      has_local_food: true,
      difficulty_score: 3,
      description: "標高2,057m、初心者でも楽しめる稜線歩き。上日川峠から登れば、比較的楽に2,000m級の山を体験できる。大菩薩峠からの富士山の眺望は絶景。雷岩から介山荘のルートは展望抜群で人気。"
    }
  ];
  
  try {
    const mountainsRef = db.collection('mountains');
    
    for (const mountain of newMountains) {
      await mountainsRef.add({
        ...mountain,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`✅ ${mountain.name} を追加しました`);
    }
    
    console.log('\n🎉 新規データの追加が完了しました！');
  } catch (error) {
    console.error('❌ エラーが発生しました:', error);
    throw error;
  }
}

/**
 * メイン実行
 */
async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || 'enhance';
  
  try {
    if (command === 'enhance') {
      // 既存データの拡張
      await enhanceMountainData();
    } else if (command === 'add') {
      // 新規データ追加
      await addNewMountains();
    } else if (command === 'all') {
      // 両方実行
      await enhanceMountainData();
      await addNewMountains();
    } else {
      console.log('使用方法:');
      console.log('  node enhance_mountain_data.mjs enhance  # 既存データを拡張');
      console.log('  node enhance_mountain_data.mjs add      # 新規データを追加');
      console.log('  node enhance_mountain_data.mjs all      # 両方実行');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('処理中にエラーが発生しました:', error);
    process.exit(1);
  }
}

main();
