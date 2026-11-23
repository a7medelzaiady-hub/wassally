// يدمج فهارس Firestore الموجودة على الإنتاج مع firestore.indexes.json (اتحاد، من غير مسح).
// الاستخدام: node merge-firestore-indexes.mjs <live.json> <repo.json> <out.json> [--live-composites]
// --live-composites: الفهارس المركبة زي ما هي على الإنتاج بالظبط (من غير إنشاء جديد)،
// وإعدادات الحقول (fieldOverrides) = اتحاد. ده بيتجنب 409 "index already exists".
import { readFileSync, writeFileSync } from "node:fs";

const [livePath, repoPath, outPath, mode] = process.argv.slice(2);
const liveComposites = mode === "--live-composites";
const live = JSON.parse(readFileSync(livePath, "utf8"));
const repo = JSON.parse(readFileSync(repoPath, "utf8"));

const fieldKey = (f) => `${f.fieldPath}:${f.order ?? ""}:${f.arrayConfig ?? ""}:${f.vectorConfig ? JSON.stringify(f.vectorConfig) : ""}`;
const indexKey = (ix) => [
  ix.collectionGroup,
  ix.queryScope ?? "COLLECTION",
  (ix.fields ?? []).filter((f) => f.fieldPath !== "__name__").map(fieldKey).join("|"),
].join("#");

// الموجود على الإنتاج بشكله الحرفي الأول (عشان firebase ما يحاولش ينشئه تاني → 409)،
// وبعده فهارس الملف الجديدة فعلًا بس.
const indexes = new Map();
for (const ix of live.indexes ?? []) indexes.set(indexKey(ix), ix);
let added = 0;
if (!liveComposites) {
  for (const ix of repo.indexes ?? []) {
    const k = indexKey(ix);
    if (!indexes.has(k)) { indexes.set(k, ix); added++; }
  }
}

const overrides = new Map();
const ovKey = (o) => `${o.collectionGroup}#${o.fieldPath}`;
for (const o of repo.fieldOverrides ?? []) overrides.set(ovKey(o), o);
for (const o of live.fieldOverrides ?? []) if (!overrides.has(ovKey(o))) overrides.set(ovKey(o), o);

// أمان: الملف المدمج لازم يحتوي كل فهرس موجود على الإنتاج، وإلا نوقف قبل --force.
for (const ix of live.indexes ?? []) {
  if (!indexes.has(indexKey(ix))) { console.error("merge lost a live index"); process.exit(1); }
}
if ((live.indexes ?? []).length > 0 && indexes.size < (live.indexes ?? []).length) {
  console.error("merged index count is lower than live"); process.exit(1);
}
writeFileSync(outPath, JSON.stringify({ indexes: [...indexes.values()], fieldOverrides: [...overrides.values()] }, null, 2));
console.log(`indexes: repo=${(repo.indexes ?? []).length} live=${(live.indexes ?? []).length} new-from-repo=${added} total=${indexes.size}`);
