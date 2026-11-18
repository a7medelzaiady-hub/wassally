// يجهّز Firebase Emulators (Auth + Firestore) ببيانات تجريبية لرحلات Maestro.
// بيشتغل على emulators فقط (demo-wasally). Authorization: Bearer owner بيتخطى قواعد الأمان في الـ Emulator.
const PROJECT = 'demo-wasally';
const FS = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
const AUTH = `http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchCreate`;
const headers = { 'Content-Type': 'application/json', Authorization: 'Bearer owner' };

const enc = (v) => {
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) } };
};

async function put(path, data) {
  const res = await fetch(`${FS}/${path}`, {
    method: 'PATCH',
    headers,
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, enc(v)])) }),
  });
  if (!res.ok) throw new Error(`Firestore ${path}: ${res.status} ${await res.text()}`);
}

const roles = ['customer', 'owner', 'courier'];
const authRes = await fetch(AUTH, {
  method: 'POST',
  headers,
  body: JSON.stringify({
    users: roles.map((r) => ({
      localId: `e2e-${r}`,
      email: `${r}@e2e.test`,
      emailVerified: true,
      providerUserInfo: [
        { providerId: 'google.com', rawId: `sub-${r}`, federatedId: `sub-${r}`, email: `${r}@e2e.test` },
      ],
    })),
  }),
});
if (!authRes.ok) throw new Error(`Auth batchCreate: ${authRes.status} ${await authRes.text()}`);

await put('app_info/delivery_areas', { areas: [{ name: 'منطقة الاختبار', fee: 10 }], fees: [10] });
await put('stores/e2e-shop', {
  name: 'متجر الاختبار', category: 'مطاعم', icon: 'store', active: true,
  time: '20-30', order: 1, rating: 4.5,
});
await put('stores/e2e-shop/products/p1', { name: 'منتج تجريبي', price: 50, isAvailable: true, available: true });
await put('storeOwners/e2e-owner', { name: 'صاحب اختبار', storeId: 'e2e-shop', active: true });
await put('couriers/e2e-courier', { name: 'مندوب اختبار', active: true });
await put('users/e2e-customer', { name: 'عميل اختبار', phone: '01012345678', address: 'عنوان اختبار، شارع 1' });
console.log('E2E seed complete');
