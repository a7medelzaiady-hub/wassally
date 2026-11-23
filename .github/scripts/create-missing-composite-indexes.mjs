// بينشئ الفهارس المركبة اللي في firestore.indexes.json واحد واحد عن طريق Firestore Admin API.
// الفهرس الموجود بيرجع 409 (ALREADY_EXISTS) وبنعدّيه. مفيش مسح لأي فهرس أبدًا.
// الاستخدام: ACCESS_TOKEN=... node create-missing-composite-indexes.mjs <project> <indexes.json>
import { readFileSync } from "node:fs";

const [project, file] = process.argv.slice(2);
const token = process.env.ACCESS_TOKEN;
if (!project || !file || !token) { console.error("usage error"); process.exit(2); }
const { indexes = [] } = JSON.parse(readFileSync(file, "utf8"));
let created = 0, existing = 0, failed = 0;
for (const ix of indexes) {
  const fields = (ix.fields ?? []).map((f) => {
    const out = { fieldPath: f.fieldPath };
    if (f.order) out.order = f.order;
    if (f.arrayConfig) out.arrayConfig = f.arrayConfig;
    return out;
  });
  const url = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/${encodeURIComponent(ix.collectionGroup)}/indexes`;
  const res = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ queryScope: ix.queryScope ?? "COLLECTION", fields }),
  });
  if (res.ok) { created++; console.log(`created: ${ix.collectionGroup} ${fields.map((f) => f.fieldPath).join(",")}`); }
  else if (res.status === 409) existing++;
  else { failed++; console.error(`failed (${res.status}): ${ix.collectionGroup} ${fields.map((f) => f.fieldPath).join(",")}`); }
}
console.log(`composite indexes: created=${created} already-existing=${existing} failed=${failed}`);
if (failed) process.exit(1);
