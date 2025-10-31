const admin = require('firebase-admin');
const serviceAccount = require('./functions/gen-lang-client-0636793764-796b85572dd7.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkDuplicates() {
  console.log('🔍 データベースの重複チェックを開始...\n');
  
  const mountainsSnapshot = await db.collection('mountains').get();
  const mountains = mountainsSnapshot.docs.map(doc => ({
    id: doc.id,
    name: doc.data().name,
    pref: doc.data().pref,
    lat: doc.data().lat,
    lng: doc.data().lng,
  }));
  
  console.log(`📊 総山数: ${mountains.length}件\n`);
  
  // 名前と都道府県でグループ化
  const groups = {};
  mountains.forEach(m => {
    const key = `${m.name}_${m.pref}`;
    if (!groups[key]) {
      groups[key] = [];
    }
    groups[key].push(m);
  });
  
  // 重複を検出
  const duplicates = [];
  Object.entries(groups).forEach(([key, items]) => {
    if (items.length > 1) {
      duplicates.push({ key, items });
    }
  });
  
  if (duplicates.length === 0) {
    console.log('✅ 重複は見つかりませんでした');
  } else {
    console.log(`⚠️  重複が ${duplicates.length} 件見つかりました:\n`);
    duplicates.forEach(dup => {
      console.log(`【${dup.items[0].name}（${dup.items[0].pref}）】`);
      dup.items.forEach((item, idx) => {
        console.log(`  ${idx + 1}. ID: ${item.id}, 座標: (${item.lat}, ${item.lng})`);
      });
      console.log('');
    });
    
    // 削除スクリプトを生成
    console.log('\n📝 以下のコマンドで重複を削除できます:\n');
    duplicates.forEach(dup => {
      // 最初のドキュメントを残し、残りを削除
      for (let i = 1; i < dup.items.length; i++) {
        console.log(`// ${dup.items[i].name} の重複を削除`);
        console.log(`await db.collection('mountains').doc('${dup.items[i].id}').delete();`);
      }
    });
  }
  
  process.exit(0);
}

checkDuplicates().catch(error => {
  console.error('エラー:', error);
  process.exit(1);
});
