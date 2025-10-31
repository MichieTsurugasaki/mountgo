const admin = require('firebase-admin');
const serviceAccount = require('./functions/gen-lang-client-0636793764-796b85572dd7.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function removeDuplicates() {
  console.log('🔍 重複をチェック中...');
  
  const snapshot = await db.collection('mountains').get();
  const mountains = {};
  const toDelete = [];
  
  snapshot.forEach(doc => {
    const data = doc.data();
    const key = `${data.name}_${data.pref}`;
    
    if (mountains[key]) {
      // 重複が見つかった
      console.log(`⚠️  重複発見: ${data.name} (${data.pref})`);
      console.log(`   保持: ${mountains[key].id}`);
      console.log(`   削除: ${doc.id}`);
      toDelete.push({ id: doc.id, name: data.name, pref: data.pref });
    } else {
      mountains[key] = { id: doc.id, name: data.name, pref: data.pref };
    }
  });
  
  if (toDelete.length === 0) {
    console.log('✅ 重複なし');
    process.exit(0);
  }
  
  console.log(`\n🗑️  ${toDelete.length}件の重複を削除します...`);
  
  for (const item of toDelete) {
    await db.collection('mountains').doc(item.id).delete();
    console.log(`✅ 削除完了: ${item.name} (${item.pref}) - ID: ${item.id}`);
  }
  
  console.log('\n✅ すべての重複を削除しました');
  process.exit(0);
}

removeDuplicates().catch(err => {
  console.error('❌ エラー:', err);
  process.exit(1);
});
