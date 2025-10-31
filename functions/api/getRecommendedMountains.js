import axios from "axios";
import admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

const owmApiKey = process.env.OWM_API_KEY || process.env.owm_key;

export const getRecommendedMountains = async (req, res) => {
  try {
    const snapshot = await db.collection("mountains").get();
    console.log(`📘 Firestore: ${snapshot.size} 件の山を取得`);

    if (snapshot.empty) {
      return res.status(404).json({ error: "No mountains found in Firestore" });
    }

    const recommended = [];

    const promises = snapshot.docs.map(async (doc) => {
      const mountain = doc.data();
      const { name, lat } = mountain;
      const lng = mountain.lng || mountain.lon; // lon対応

      // ✅ lat/lon が欠けていたらスキップ
      if (lat === undefined || lng === undefined) {
        console.warn(`⚠️ Skipped ${name}: lat/lon missing`);
        return;
      }

      // ✅ 数値変換
      const latNum = Number(lat);
      const lonNum = Number(lng);

      if (isNaN(latNum) || isNaN(lonNum)) {
        console.warn(`⚠️ Skipped ${name}: lat/lon not numeric`);
        return;
      }

      try {
        const url = `https://api.openweathermap.org/data/2.5/weather?lat=${latNum}&lon=${lonNum}&appid=${owmApiKey}&lang=ja&units=metric`;
        const response = await axios.get(url);

        if (!response.data.weather || !response.data.weather[0]) {
          console.warn(`⚠️ No weather info for ${name}`);
          return;
        }

        const weather = response.data.weather[0].description || "不明";
        const temp = response.data.main?.temp ?? null;
        const icon = response.data.weather[0]?.icon ?? "01d";

        if (weather.includes("晴") || weather.includes("曇")) {
          recommended.push({
            name,
            weather,
            temp,
            icon: `https://openweathermap.org/img/wn/${icon}@2x.png`,
          });
        }
      } catch (err) {
        console.error(`❌ ${name} の天気取得エラー: ${err.message}`);
      }
    });

    await Promise.all(promises);

    console.log(`✅ 晴れ・曇りの山: ${recommended.length} 件`);
    return res.json({ recommended });
  } catch (error) {
    console.error("🔥 getRecommendedMountains error:", error);
    return res.status(500).json({ error: error.message });
  }
};