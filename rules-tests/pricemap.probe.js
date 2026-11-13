// المرحلة 4: نموذج priceMap التجريبي — قياس + اختبارات اختراق منطقي + سلامة التحديث. Emulator فقط (demo-*).
// مفيش تعديل في firestore.rules ولا Flutter ولا Firestore الإنتاج. النموذج بيتبني في الذاكرة (pricemap-model.js).
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, deleteField } = require('firebase/firestore');
const { real, VARIANTS, buildModelRules, injectExtra } = require('./pricemap-model');

const out = [];
const md = (s = '') => { out.push(s); console.log(s); };

function classify(e) {
  const msg = String((e && (e.message || e.code)) || e).replace(/\s+/g, ' ');
  if (/expressions to evaluate/i.test(msg)) return 'EXPR_LIMIT';
  if (/Service call error/i.test(msg)) return 'READ_LIMIT';
  if (/PERMISSION_DENIED|permission-denied|insufficient permissions/i.test(msg)) {
    if (/evaluation error|Unable to evaluate|is undefined|Property|not a (map|list)|Invalid|Error/i.test(msg) && !/^.{0,40}false for/i.test(msg)) return 'DENY_EVAL_ERROR';
    return 'DENY';
  }
  return 'OTHER:' + msg.slice(0, 200);
}
async function attempt(fn) { try { await fn(); return 'ALLOWED'; } catch (e) { return classify(e); } }
const short = (r) => ({ ALLOWED: 'OK', EXPR_LIMIT: 'EXPR', READ_LIMIT: 'READ', DENY: 'DENY', DENY_EVAL_ERROR: 'DENY(err)', DENY_CTL_OK: 'DENY(ctl✓)' }[r] || r.slice(0, 40));

// ───────────── بيانات ─────────────
const IDS15 = Array.from({ length: 15 }, (_, i) => 'p' + (i + 1));
async function seed(env, { flag = true } = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'app_info/security'), { enforcePrices: flag });
    await setDoc(doc(db, 'app_info/delivery_areas'), { areas: [{ name: 'Zone A', fee: 25 }], fees: [25] });
    await setDoc(doc(db, 'promos/SAVE10'), { percent: 10, active: true, note: '' });
    await setDoc(doc(db, 'promos/OLD'), { percent: 10, active: false, note: '' });
    await setDoc(doc(db, 'admins/admin1'), { name: 'A' });
    await setDoc(doc(db, 'storeOwners/owner1'), { name: 'O1', storeId: 'shop1', active: true });
    await setDoc(doc(db, 'storeOwners/owner2'), { name: 'O2', storeId: 'shop2', active: true });
    const pm = Object.fromEntries(IDS15.map((id) => [id, 10]));
    await setDoc(doc(db, 'stores/shop1'), { name: 'S1', active: true, time: '20-30', order: 1, rating: 4, priceMap: pm });
    await setDoc(doc(db, 'stores/shop2'), { name: 'S2', active: true, time: '20-30', order: 2, rating: 4, priceMap: { q1: 10 } });
    await setDoc(doc(db, 'stores/shopL'), { name: 'Legacy', active: true, time: '20-30', order: 3, rating: 4 });
    await setDoc(doc(db, 'stores/closed'), { name: 'Closed', active: false, time: '20-30', order: 4, rating: 4, priceMap: { p1: 10 } });
    for (const id of IDS15) {
      await setDoc(doc(db, `stores/shop1/products/${id}`), { name: id, price: 10, available: true });
      await setDoc(doc(db, `stores/shopL/products/${id}`), { name: id, price: 10, available: true });
    }
    await setDoc(doc(db, 'stores/shop1/products/p16'), { name: 'p16', price: 10, available: false }); // غير متاح: مش في priceMap
    await setDoc(doc(db, 'stores/shop2/products/q1'), { name: 'q1', price: 10, available: true });
    await setDoc(doc(db, 'stores/closed/products/p1'), { name: 'p1', price: 10, available: true });
    await setDoc(doc(db, 'orders/o1'), { ...ord(1), createdAt: new Date() });
  });
}
const as = (env, uid) => env.authenticatedContext(uid, { email: 'a@x.com' }).firestore();

function ord(n, o = {}) {
  const ids = o.ids || IDS15.slice(0, n);
  const items = o.items || ids.map((id) => ({ name: 'n' + id, price: o.price ?? 10, qty: o.qty ?? 1, productId: id }));
  const subtotal = o.subtotal ?? items.reduce((a, l) => a + (typeof l.price === 'number' && typeof l.qty === 'number' ? l.price * l.qty : 0), 0);
  const fee = o.fee ?? 20;
  const discount = o.discount ?? 0;
  const d = {
    userId: o.uid || 'cust1', userName: 'Ali', userEmail: 'a@x.com', phone: '01012345678', address: 'عنوان تجريبي 1', notes: '',
    storeId: o.storeId || 'shop1', storeName: 'S', items, subtotal, deliveryFee: fee, total: o.total ?? (subtotal + fee - discount),
    paymentMethod: 'cash', status: o.status || 'new', createdAt: serverTimestamp(),
  };
  if (o.area) d.area = o.area;
  if (o.promoCode !== undefined) d.promoCode = o.promoCode;
  if (discount !== 0) d.discount = discount;
  return Object.assign(d, o.extra || {});
}
// طلب كامل الشروط: منطقة + كوبون SAVE10 (10%)
function ordFull(n, o = {}) {
  const subtotal = n * 10;
  const discount = Math.floor(subtotal * 10) / 100;
  return ord(n, { area: 'Zone A', fee: 25, promoCode: 'SAVE10', discount, ...o });
}

let seq = 0;
let lastData = null;
const createOrder = (db, data) => { lastData = data; return setDoc(doc(db, `orders/o_${++seq}`), data); };

// ───────────── 1) القياس: السعة ─────────────
const NS = [1, 3, 5, 8, 10, 12, 15];
const PAD = `function Ppad(d) { return d.status == 'new' && d.paymentMethod == 'cash' && d.userId == request.auth.uid && d.items is list && d.storeId is string; }`;
const rep = (s, k) => Array.from({ length: k }, () => s).join(' && ');
function extraBlocks(lv) {
  const { KS, REPS, PADREPS } = lv;
  let x = PAD + '\n';
  const D = 'request.resource.data';
  for (const k of KS) x += `match /pad_${k}/{id} { allow create: if validNewOrder(${D})${k ? ' && ' + rep(`Ppad(${D})`, k) : ''}; }\n`;
  for (const k of REPS) x += `match /rep_${k}/{id} { allow create: if ${rep(`validNewOrder(${D})`, k)}; }\n`;
  for (const r of PADREPS) x += `match /padonly_${r}/{id} { allow create: if ${rep(`Ppad(${D})`, r)}; }\n`;
  return x;
}

const capacity = {}; // variant -> {maxPmFlagOn: n}
async function perfFor(label, rules) {
  const env = await initializeTestEnvironment({ projectId: `demo-pm-${label.replace(/[^a-z0-9]/gi, '').toLowerCase()}-${rules.length}`, firestore: { rules } });
  const rows = [];
  const states = [
    ['store بـ priceMap + enforcePrices مفتوح', 'shop1', true],
    ['store بـ priceMap + enforcePrices مقفول', 'shop1', false],
    ['store قديم (من غير priceMap) + enforcePrices مفتوح', 'shopL', true],
    ['store قديم (من غير priceMap) + enforcePrices مقفول', 'shopL', false],
  ];
  for (const [name, storeId, flag] of states) {
    await seed(env, { flag });
    const db = as(env, 'cust1');
    const cells = [];
    for (const n of NS) cells.push(short(await attempt(() => createOrder(db, ordFull(n, { storeId })))));
    rows.push([name, ...cells]);
  }
  await env.cleanup();
  return { rows };
}

// قياس الاستهلاك في Emulator منفصل (قواعد فيها تكرار كتير؛ لو المترجم رفضها نجرب مستوى أخف من غير ما نبوّظ باقي النتائج)
const LEVELS = [
  { KS: [...Array.from({ length: 31 }, (_, i) => i), 35, 40], REPS: [1, 2, 3, 4, 5, 6, 8], PADREPS: [1, 2, 4, 8, 16, 24, 32, 48, 64] },
  { KS: [0, 2, 4, 8, 12, 20, 30], REPS: [1, 2, 3, 4], PADREPS: [1, 4, 16, 32, 64] },
  { KS: [0, 4, 12, 30], REPS: [1, 2], PADREPS: [4, 32] },
];
async function meterFor(label, buildRules) {
  let lastErr;
  for (const lv of LEVELS) {
    let env;
    try {
      const rules = buildRules(extraBlocks(lv));
      env = await initializeTestEnvironment({ projectId: `demo-pmm-${label.replace(/[^a-z0-9]/gi, '').toLowerCase()}-${rules.length}`, firestore: { rules } });
      await seed(env, { flag: true });
      const db = as(env, 'cust1');
      const pad = {};
      for (const n of [1, 8, 15]) {
        let kmax = -1, why = '-';
        for (const k of lv.KS) {
          const r = await attempt(() => setDoc(doc(db, `pad_${k}/o${n}_${k}`), ordFull(n)));
          if (r === 'ALLOWED') kmax = k; else { why = r; break; }
        }
        pad[n] = { kmax, why };
      }
      let padOnlyMax = 0, padOnlyFail = '-';
      for (const r of lv.PADREPS) {
        const res = await attempt(() => setDoc(doc(db, `padonly_${r}/x${r}`), ordFull(1)));
        if (res === 'ALLOWED') padOnlyMax = r; else { padOnlyFail = r; break; }
      }
      const rep8 = {};
      for (const n of [1, 8, 15]) {
        let ok = 0, fail = '-', why = '-';
        for (const k of lv.REPS) {
          const res = await attempt(() => setDoc(doc(db, `rep_${k}/r${n}_${k}`), ordFull(n)));
          if (res === 'ALLOWED') ok = k; else { fail = k; why = res; break; }
        }
        rep8[n] = { ok, fail, why };
      }
      await env.cleanup();
      return { pad, padOnlyMax, padOnlyFail, rep8 };
    } catch (e) {
      lastErr = e;
      try { if (env) await env.cleanup(); } catch (_) { /* ignore */ }
    }
  }
  throw lastErr;
}

// ───────────── 2) اختبارات الاختراق المنطقي ─────────────
const ATTACK_OK = new Set(['DENY', 'DENY_EVAL_ERROR', 'DENY_CTL_OK']);
async function runSuite(label, rules) {
  const env = await initializeTestEnvironment({ projectId: `demo-pms-${label.replace(/[^a-z0-9]/gi, '').toLowerCase()}-${rules.length}`, firestore: { rules } });
  const results = [];
  const T = (group, name, expect, fn, opts = {}) => results.push({ group, name, expect, fn, opts });
  const cust = (e) => as(e, 'cust1');
  const own1 = (e) => as(e, 'owner1');
  const batchOf = (db, ops) => async () => {
    const b = writeBatch(db);
    for (const [kind, ref, data] of ops) { if (kind === 'set') b.set(ref, data); else if (kind === 'update') b.update(ref, data); else b.delete(ref); }
    await b.commit();
  };
  const P = (db, p) => doc(db, p);

  // ضوابط (لازم تنجح، وإلا الاختبارات السلبية بدون معنى)
  T('ضابط', '1 صنف سليم', 'ALLOW', (e) => createOrder(cust(e), ord(1)));
  T('ضابط', '8 أصناف + منطقة + كوبون', 'ALLOW', (e) => createOrder(cust(e), ordFull(8)));
  T('ضابط', 'enforcePrices مقفول + store بـ priceMap: 8 أصناف سليمة', 'ALLOW', (e) => createOrder(cust(e), ordFull(8)), { flag: false });
  T('ضابط', 'store قديم (fallback): 1 صنف سليم', 'ALLOW', (e) => createOrder(cust(e), ord(1, { storeId: 'shopL' })));

  // أسعار
  T('سعر', 'تغيير سعر المنتج من التطبيق (1 بدل 10)', 'DENY', (e) => createOrder(cust(e), ord(1, { price: 1 })));
  T('سعر', 'سعر واحد مغلوط وسط 8 أصناف', 'DENY', (e) => {
    const o = ord(8); o.items[7].price = 1; o.subtotal = 71; o.total = 91; return createOrder(cust(e), o);
  });
  T('سعر', 'سعر أعلى من المعتمد (11)', 'DENY', (e) => createOrder(cust(e), ord(1, { price: 11 })));
  T('سعر', 'سعر مغلوط + enforcePrices مقفول (store بـ priceMap بيطبّق دايمًا)', 'DENY', (e) => createOrder(cust(e), ord(1, { price: 1 })), { flag: false });
  T('سعر', 'سعر صفر', 'DENY', (e) => createOrder(cust(e), ord(1, { price: 0, subtotal: 0, total: 20 })));
  T('سعر', 'سعر سالب', 'DENY', (e) => createOrder(cust(e), ord(1, { price: -5, subtotal: -5, total: 15 })));
  T('سعر', 'سعر نص بدل رقم', 'DENY', (e) => createOrder(cust(e), ord(1, { items: [{ name: 'n', price: '10', qty: 1, productId: 'p1' }], subtotal: 10, total: 30 })));
  // منتجات
  T('منتج', 'منتج غير موجود (p999)', 'DENY', (e) => createOrder(cust(e), ord(1, { ids: ['p999'] })));
  T('منتج', 'منتج تابع لمحل آخر (q1 على shop1)', 'DENY', (e) => createOrder(cust(e), ord(1, { ids: ['q1'] })));
  T('منتج', 'منتج shop1 على طلب لـ shop2', 'DENY', (e) => createOrder(cust(e), ord(1, { storeId: 'shop2', ids: ['p1'] })));
  T('منتج', 'منتج غير متاح (p16)', 'DENY', (e) => createOrder(cust(e), ord(1, { ids: ['p16'] })));
  T('منتج', 'صنف غير معتمد وسط 8 أصناف', 'DENY', (e) => createOrder(cust(e), ord(8, { ids: ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p999'] })));
  T('منتج', 'بدون productId', 'DENY', (e) => createOrder(cust(e), ord(1, { items: [{ name: 'n', price: 10, qty: 1 }], subtotal: 10, total: 30 })));
  T('منتج', 'productId رقم', 'DENY', (e) => createOrder(cust(e), ord(1, { items: [{ name: 'n', price: 10, qty: 1, productId: 5 }], subtotal: 10, total: 30 })));
  T('منتج', 'حقل زيادة في السطر', 'DENY', (e) => createOrder(cust(e), ord(1, { items: [{ name: 'n', price: 10, qty: 1, productId: 'p1', evil: 1 }], subtotal: 10, total: 30 })));
  T('منتج', 'اسم صنف فاضي', 'DENY', (e) => createOrder(cust(e), ord(1, { items: [{ name: '', price: 10, qty: 1, productId: 'p1' }], subtotal: 10, total: 30 })));
  T('منتج', 'سطر مش map', 'DENY', (e) => createOrder(cust(e), ord(1, { items: ['p1'], subtotal: 10, total: 30 })));
  T('منتج', 'items مش list', 'DENY', (e) => createOrder(cust(e), ord(1, { items: { a: 1 }, subtotal: 10, total: 30 })));
  T('منتج', 'items فاضية', 'DENY', (e) => createOrder(cust(e), ord(1, { items: [], subtotal: 0, total: 20 })));
  T('منتج', '16 صنف', 'DENY', (e) => createOrder(cust(e), ord(16, { ids: [...IDS15, 'p16'] })));
  // كميات وإجمالي
  T('كمية', 'كمية 0', 'DENY', (e) => createOrder(cust(e), ord(1, { qty: 0, subtotal: 0, total: 20 })));
  T('كمية', 'كمية 51', 'DENY', (e) => createOrder(cust(e), ord(1, { qty: 51, subtotal: 510, total: 530 })));
  T('كمية', 'كمية نص', 'DENY', (e) => createOrder(cust(e), ord(1, { items: [{ name: 'n', price: 10, qty: '2', productId: 'p1' }], subtotal: 20, total: 40 })));
  T('إجمالي', 'subtotal مخفّض', 'DENY', (e) => createOrder(cust(e), ord(2, { subtotal: 5, total: 25 })));
  T('إجمالي', 'total مخفّض', 'DENY', (e) => createOrder(cust(e), ord(2, { total: 1 })));
  T('إجمالي', 'رسوم توصيل مخفّضة (5)', 'DENY', (e) => createOrder(cust(e), ord(1, { fee: 5, total: 15 })));
  T('إجمالي', 'رسوم منطقة مش في القائمة (99)', 'DENY', (e) => createOrder(cust(e), ord(1, { fee: 99, total: 109 })));
  T('إجمالي', 'subtotal > 100000', 'DENY', (e) => createOrder(cust(e), ord(1, { qty: 50, price: 10, subtotal: 100001, total: 100021 })));
  // خصم وكوبون
  T('كوبون', 'خصم بدون promoCode', 'DENY', (e) => createOrder(cust(e), ord(2, { discount: 2, total: 38 })));
  T('كوبون', 'خصم أكبر من النسبة (50% بدل 10%)', 'DENY', (e) => createOrder(cust(e), ord(2, { promoCode: 'SAVE10', discount: 10, total: 30 })));
  T('كوبون', 'كوبون غير نشط', 'DENY', (e) => createOrder(cust(e), ord(2, { promoCode: 'OLD', discount: 2, total: 38 })));
  T('كوبون', 'كوبون غير موجود', 'DENY', (e) => createOrder(cust(e), ord(2, { promoCode: 'FAKE', discount: 2, total: 38 })));
  T('كوبون', 'خصم سالب', 'DENY', (e) => createOrder(cust(e), ord(2, { promoCode: 'SAVE10', discount: -5, total: 45 })));
  T('كوبون', 'خصم صحيح لكن total ما اتخصمش', 'DENY', (e) => createOrder(cust(e), ord(2, { promoCode: 'SAVE10', discount: 2, total: 40 })));
  T('كوبون', 'خصم صحيح كامل (ضابط)', 'ALLOW', (e) => createOrder(cust(e), ord(2, { promoCode: 'SAVE10', discount: 2, total: 38 })));
  // محل
  T('محل', 'محل مقفول (active=false)', 'DENY', (e) => createOrder(cust(e), ord(1, { storeId: 'closed' })));
  T('محل', 'محل غير موجود', 'DENY', (e) => createOrder(cust(e), ord(1, { storeId: 'nostore' })));
  T('محل', 'userId لشخص تاني', 'DENY', (e) => createOrder(cust(e), ord(1, { uid: 'other' })));
  T('محل', 'status مش new', 'DENY', (e) => createOrder(cust(e), ord(1, { status: 'delivered' })));
  // الحقول الأساسية (تبسيط القواعد لازم ما يضعفش حاجة)
  T('حقول', 'storeId فيه / (حقن مسار)', 'DENY', (e) => createOrder(cust(e), ord(1, { storeId: 'shop1/products/p1' })));
  T('حقول', 'notes وaddress فيهم سطور جديدة (مسموح زي الحالي)', 'ALLOW', (e) => createOrder(cust(e), ord(1, { extra: { notes: 'سطر1\nسطر2', address: 'شارع 1\nدور 2' } })));
  T('حقول', 'userName رقم', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { userName: 5 } })));
  T('حقول', 'userName فاضي', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { userName: '' } })));
  T('حقول', 'address قصير', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { address: 'abc' } })));
  T('حقول', 'notes أطول من 500', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { notes: 'x'.repeat(501) } })));
  T('حقول', 'phone غلط', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { phone: '123' } })));
  T('حقول', 'area أطول من 60', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { area: 'x'.repeat(61) } })));
  T('حقول', 'area مش نص', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { area: 5 } })));
  T('حقول', 'حقل غريب في الطلب', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { evil: 1 } })));
  T('حقول', 'email مختلف عن توكن العميل', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { userEmail: 'z@x.com' } })));
  T('حقول', 'createdAt مش وقت السيرفر', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { createdAt: new Date('2020-01-01') } })));
  T('حقول', 'paymentMethod غير cash', 'DENY', (e) => createOrder(cust(e), ord(1, { extra: { paymentMethod: 'card' } })));
  for (const k of ['userName', 'userEmail', 'phone', 'address', 'notes', 'storeName', 'subtotal', 'deliveryFee', 'total', 'paymentMethod', 'status', 'createdAt', 'items', 'storeId', 'userId']) {
    T('حقول ناقصة', `حذف الحقل ${k}`, 'DENY', (e) => { const o = ord(1); delete o[k]; return createOrder(cust(e), o); });
  }
  T('إجمالي', 'subtotal نص', 'DENY', (e) => createOrder(cust(e), ord(1, { subtotal: '10' })));
  T('إجمالي', 'total نص', 'DENY', (e) => createOrder(cust(e), ord(1, { total: '30' })));
  T('إجمالي', 'total = 0', 'DENY', (e) => createOrder(cust(e), ord(1, { total: 0 })));
  // تغيير الطلب بعد الإنشاء
  const upd = (uid, data) => (e) => updateDoc(P(as(e, uid), 'orders/o1'), data);
  T('تعديل طلب', 'العميل يغيّر storeId بعد الإنشاء', 'DENY', upd('cust1', { storeId: 'shop2' }));
  T('تعديل طلب', 'المدير يغيّر storeId', 'DENY', upd('admin1', { storeId: 'shop2' }));
  T('تعديل طلب', 'صاحب المحل يغيّر storeId', 'DENY', upd('owner1', { storeId: 'shop2' }));
  T('تعديل طلب', 'صاحب محل تاني يغيّر storeId', 'DENY', upd('owner2', { storeId: 'shop2' }));
  T('تعديل طلب', 'العميل يغيّر items/السعر', 'DENY', upd('cust1', { items: [{ name: 'n', price: 1, qty: 1, productId: 'p1' }], subtotal: 1, total: 21 }));
  T('تعديل طلب', 'المدير يغيّر items', 'DENY', upd('admin1', { items: [{ name: 'n', price: 1, qty: 1, productId: 'p1' }] }));
  // كتابة priceMap
  const st = (uid) => (e) => P(as(e, uid), 'stores/shop1');
  T('كتابة priceMap', 'عميل يعدّل priceMap', 'DENY', (e) => updateDoc(st('cust1')(e), { 'priceMap.p1': 1 }));
  T('كتابة priceMap', 'عميل يستبدل priceMap كله', 'DENY', (e) => setDoc(st('cust1')(e), { priceMap: { p1: 1 } }, { merge: true }));
  T('كتابة priceMap', 'عميل يحذف priceMap', 'DENY', (e) => updateDoc(st('cust1')(e), { priceMap: deleteField() }));
  T('كتابة priceMap', 'عميل يحذف مفتاح سعر', 'DENY', (e) => updateDoc(st('cust1')(e), { 'priceMap.p3': deleteField() }));
  T('كتابة priceMap', 'عميل يمرر priceMap مع حقول تقييم', 'DENY', (e) => updateDoc(st('cust1')(e), { ratingSum: 5, ratingCount: 1, lastReviewId: 'r1', 'priceMap.p1': 1 }));
  T('كتابة priceMap', 'عميل يعدّل سعر منتج في الكتالوج', 'DENY', (e) => updateDoc(P(cust(e), 'stores/shop1/products/p1'), { price: 1 }));
  T('كتابة priceMap', 'صاحب محل تاني يعدّل priceMap', 'DENY', (e) => updateDoc(st('owner2')(e), { 'priceMap.p1': 1, pmProductId: 'p1' }));
  T('كتابة priceMap', 'صاحب المحل: تغيير priceMap بدون تغيير الصنف', 'DENY', (e) => updateDoc(st('owner1')(e), { 'priceMap.p1': 1, pmProductId: 'p1' }));
  T('كتابة priceMap', 'صاحب المحل: إضافة مفتاح لصنف غير موجود', 'DENY', (e) => updateDoc(st('owner1')(e), { 'priceMap.p99': 5, pmProductId: 'p99' }));
  T('كتابة priceMap', 'صاحب المحل: حذف سعر من غير ما الصنف يبقى غير متاح', 'DENY', (e) => updateDoc(st('owner1')(e), { 'priceMap.p3': deleteField(), pmProductId: 'p3' }));
  T('كتابة priceMap', 'صاحب المحل: حذف priceMap كله', 'DENY', (e) => updateDoc(st('owner1')(e), { priceMap: deleteField(), pmProductId: 'p1' }));
  T('كتابة priceMap', 'صاحب المحل: priceMap مش map', 'DENY', (e) => updateDoc(st('owner1')(e), { priceMap: 5, pmProductId: 'p1' }));
  T('كتابة priceMap', 'صاحب المحل: تعديل مفتاحين مرة واحدة', 'DENY', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['update', P(db, 'stores/shop1/products/p1'), { price: 12 }],
      ['update', P(db, 'stores/shop1/products/p2'), { price: 12 }],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p1': 12, 'priceMap.p2': 12, pmProductId: 'p1' }],
    ])();
  });
  T('كتابة priceMap', 'صاحب المحل: pmProductId لا يطابق المفتاح المتغير', 'DENY', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['update', P(db, 'stores/shop1/products/p1'), { price: 12 }],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p1': 12, pmProductId: 'p2' }],
    ])();
  });
  T('كتابة priceMap', 'صاحب المحل: سعر الخريطة ≠ سعر الصنف', 'DENY', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['update', P(db, 'stores/shop1/products/p1'), { price: 12 }],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p1': 5, pmProductId: 'p1' }],
    ])();
  });
  T('كتابة priceMap', 'صاحب المحل: مفتاح لصنف غير متاح (p16)', 'DENY', (e) => {
    const db = own1(e);
    return batchOf(db, [['update', P(db, 'stores/shop1'), { 'priceMap.p16': 10, pmProductId: 'p16' }]])();
  });
  T('كتابة priceMap', 'صاحب المحل: تغيير سعر صنف بدون تحديث priceMap (drift)', 'DENY', (e) => updateDoc(P(own1(e), 'stores/shop1/products/p1'), { price: 5 }));
  T('كتابة priceMap', 'صاحب المحل: إخفاء صنف (available=false) بدون حذفه من priceMap', 'DENY', (e) => updateDoc(P(own1(e), 'stores/shop1/products/p1'), { available: false }));
  T('كتابة priceMap', 'صاحب المحل: حذف صنف بدون حذفه من priceMap', 'DENY', (e) => deleteDoc(P(own1(e), 'stores/shop1/products/p2')));
  T('كتابة priceMap', 'صاحب المحل: إضافة صنف جديد بدون priceMap', 'DENY', (e) => setDoc(P(own1(e), 'stores/shop1/products/p20'), { name: 'x', price: 7 }));
  T('كتابة priceMap', 'صاحب المحل: صنف جديد وسعر الخريطة مختلف', 'DENY', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['set', P(db, 'stores/shop1/products/p20'), { name: 'x', price: 7 }],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p20': 8, pmProductId: 'p20' }],
    ])();
  });
  // كتابة مشروعة
  T('كتابة مشروعة', 'صاحب المحل: تعديل سعر + priceMap في batch', 'ALLOW', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['update', P(db, 'stores/shop1/products/p1'), { price: 12 }],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p1': 12, pmProductId: 'p1' }],
    ])();
  });
  T('كتابة مشروعة', 'صاحب المحل: صنف جديد + priceMap', 'ALLOW', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['set', P(db, 'stores/shop1/products/p20'), { name: 'x', price: 7 }],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p20': 7, pmProductId: 'p20' }],
    ])();
  });
  T('كتابة مشروعة', 'صاحب المحل: إخفاء صنف + حذفه من priceMap', 'ALLOW', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['update', P(db, 'stores/shop1/products/p3'), { available: false }],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p3': deleteField(), pmProductId: 'p3' }],
    ])();
  });
  T('كتابة مشروعة', 'صاحب المحل: حذف صنف + حذفه من priceMap', 'ALLOW', (e) => {
    const db = own1(e);
    return batchOf(db, [
      ['delete', P(db, 'stores/shop1/products/p2')],
      ['update', P(db, 'stores/shop1'), { 'priceMap.p2': deleteField(), pmProductId: 'p2' }],
    ])();
  });
  T('كتابة مشروعة', 'صاحب المحل: تعديل اسم الصنف فقط (السعر ثابت)', 'ALLOW', (e) => updateDoc(P(own1(e), 'stores/shop1/products/p1'), { name: 'جديد' }));
  T('كتابة مشروعة', 'صاحب المحل: تحديث offerItems/active من غير لمس priceMap', 'ALLOW', (e) => updateDoc(st('owner1')(e), { active: true, offerItems: [], updatedAt: serverTimestamp() }));
  T('كتابة مشروعة', 'المدير: تعديل priceMap مباشرة (ثقة المدير)', 'ALLOW', (e) => updateDoc(st('admin1')(e), { 'priceMap.p1': 11 }));
  T('كتابة مشروعة', 'store قديم: صاحب محل يضيف صنف من غير priceMap (fallback)', 'ALLOW', async (e) => {
    await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'storeOwners/ownerL'), { name: 'L', storeId: 'shopL', active: true }));
    return setDoc(P(as(e, 'ownerL'), 'stores/shopL/products/p30'), { name: 'x', price: 9 });
  });
  T('سعة', '8 أصناف: 30 منطقة في delivery_areas + priceMap فيها 300 صنف', 'ALLOW', async (e) => {
    await env.withSecurityRulesDisabled(async (c) => {
      const db = c.firestore();
      const fees = Array.from({ length: 30 }, (_, i) => 100 + i); fees.push(25);
      await setDoc(doc(db, 'app_info/delivery_areas'), { areas: [{ name: 'Zone A', fee: 25 }], fees });
      const pm = Object.fromEntries(Array.from({ length: 300 }, (_, i) => ['x' + i, 10]));
      for (const id of IDS15) pm[id] = 10;
      await updateDoc(doc(db, 'stores/shop1'), { priceMap: pm });
    });
    return createOrder(cust(e), ordFull(8));
  });
  // fallback للمحل القديم (نفس السلوك الحالي)
  T('fallback', 'store قديم + سعر مغلوط + enforcePrices مفتوح', 'DENY', (e) => createOrder(cust(e), ord(1, { storeId: 'shopL', price: 1 })));
  T('fallback', 'store قديم + سعر مغلوط + enforcePrices مقفول (سلوك قديم: مسموح)', 'ALLOW', (e) => createOrder(cust(e), ord(1, { storeId: 'shopL', price: 1 })), { flag: false });

  // سلامة التصميم: تحديث سعر أثناء وجود طلب
  T('تحديث أثناء الطلب', 'طلب قبل تحديث السعر (سعر 10) ينجح', 'ALLOW', (e) => createOrder(cust(e), ord(1)));
  results.push({ group: 'تحديث أثناء الطلب', name: 'تسلسل: تحديث 10→12 ثم طلب بالقديم (10) يُرفض، بالجديد (12) ينجح، الطلب القديم ما يتغيرش', expect: 'SEQ', opts: {}, fn: async (e) => {
    const steps = [];
    const c = cust(e), o = own1(e);
    steps.push(['طلب قبل التحديث بسعر 10', 'ALLOWED', await attempt(() => createOrder(c, ord(1, { storeId: 'shop1' })))]);
    await batchOf(o, [
      ['update', P(o, 'stores/shop1/products/p1'), { price: 12 }],
      ['update', P(o, 'stores/shop1'), { 'priceMap.p1': 12, pmProductId: 'p1' }],
    ])();
    const okCtl = () => createOrder(c, ord(1, { ids: ['p5'] })); // صنف ما اتلمسش = طلب سليم في نفس الحالة
    steps.push(['طلب متأخر بسعر قديم 10 بعد التحديث', 'DENY', await attempt(() => createOrder(c, ord(1, { price: 10 }))), okCtl]);
    steps.push(['طلب بسعر جديد 12', 'ALLOWED', await attempt(() => createOrder(c, ord(1, { price: 12 })))]);
    steps.push(['طلب يخلط جديد (p1=12) وقديم (p2=10)', 'ALLOWED', await attempt(() => createOrder(c, { ...ord(2), items: [{ name: 'a', price: 12, qty: 1, productId: 'p1' }, { name: 'b', price: 10, qty: 1, productId: 'p2' }], subtotal: 22, total: 42 }))]);
    steps.push(['تعديل items في الطلب القديم من المدير', 'DENY', await attempt(() => updateDoc(P(as(e, 'admin1'), 'orders/o1'), { items: [{ name: 'n', price: 12, qty: 1, productId: 'p1' }] })), () => updateDoc(P(as(e, 'admin1'), 'orders/o1'), { status: 'preparing' })]);
    // إخفاء الصنف أثناء التحضير
    await batchOf(o, [
      ['update', P(o, 'stores/shop1/products/p2'), { available: false }],
      ['update', P(o, 'stores/shop1'), { 'priceMap.p2': deleteField(), pmProductId: 'p2' }],
    ])();
    steps.push(['طلب بصنف اتخفى (p2) بعد الإخفاء', 'DENY', await attempt(() => createOrder(c, ord(1, { ids: ['p2'] }))), okCtl]);
    // المدير بيغيّر سعر الصنف بدون priceMap (drift): fail-closed
    await updateDoc(P(as(e, 'admin1'), 'stores/shop1/products/p4'), { price: 15 });
    steps.push(['drift من المدير: السعر الجديد 15 (priceMap لسه 10) → يُرفض (fail-closed)', 'DENY', await attempt(() => createOrder(c, ord(1, { ids: ['p4'], price: 15 }))), okCtl]);
    steps.push(['drift من المدير: السعر المعتمد القديم 10 → ينجح (السعر المعتمد هو priceMap)', 'ALLOWED', await attempt(() => createOrder(c, ord(1, { ids: ['p4'], price: 10 })))]);
    return steps;
  } });

  // رسالة الرفض في الـ Emulator ممكن تحتوي نص "حد التعبيرات" حتى لو الرفض أمني (تتبّع كل الفروع). فالحكم بالتحكّم:
  // لو الرفض ظهر بنص EXPR/READ نجرب طلب سليم بنفس الحجم (منطقة+كوبون)؛ لو نجح يبقى الرفض أمني فعلًا.
  async function verdict(got, ctlFn) {
    if (got === 'ALLOWED' || !/LIMIT/.test(got)) return got;
    const n = lastData && Array.isArray(lastData.items) ? Math.max(1, Math.min(lastData.items.length, 8)) : 1;
    const ctl = await attempt(ctlFn || (() => createOrder(as(env, 'cust1'), ordFull(n))));
    return ctl === 'ALLOWED' ? 'DENY_CTL_OK' : 'INCONCLUSIVE';
  }
  const rows = [];
  let pass = 0, failN = 0, limitHits = 0;
  for (const t of results) {
    await seed(env, { flag: t.opts.flag !== undefined ? t.opts.flag : true });
    if (t.expect === 'SEQ') {
      let steps;
      try { steps = await t.fn(env); } catch (e) { steps = [['خطأ غير متوقع في التسلسل', 'ALLOWED', classify(e)]]; }
      for (let [nm, ex, got, cf] of steps) {
        got = await verdict(got, cf);
        const ok = ex === 'ALLOWED' ? got === 'ALLOWED' : ATTACK_OK.has(got);
        if (/LIMIT/.test(got)) limitHits++;
        ok ? pass++ : failN++;
        rows.push([t.group, nm, ex === 'ALLOWED' ? 'ALLOW' : 'DENY', short(got), ok ? 'PASS' : 'FAIL']);
      }
      continue;
    }
    let got = await attempt(() => t.fn(env));
    got = await verdict(got);
    const ok = t.expect === 'ALLOW' ? got === 'ALLOWED' : ATTACK_OK.has(got);
    if (/LIMIT/.test(got)) limitHits++;
    ok ? pass++ : failN++;
    rows.push([t.group, t.name, t.expect, short(got), ok ? 'PASS' : 'FAIL']);
  }
  await env.cleanup();
  return { rows, pass, failN, limitHits };
}

// ───────────── التشغيل ─────────────
(async () => {
  try {
    md('# المرحلة 4 — نموذج priceMap التجريبي (قياس + اختبارات اختراق). Emulator فقط، مفيش تعديل في المشروع.');
    md('');
    // قاعدة المقارنة: القواعد الحالية (real) بنفس البيانات
    const results = {};
    md('## 1) السعة: أقصى عدد أصناف مع كل الشروط (منطقة + كوبون + فحص المحل + مجموع الأسطر + الإجمالي + الحقول الأساسية)');
    md('');
    md('الخلية = نتيجة إنشاء طلب بعدد الأصناف في العمود. OK نجح، EXPR حد التعبيرات، READ حد القراءات، DENY رفض قواعد.');
    md('');
    md(`| النسخة | الحالة | ${NS.join(' | ')} |`);
    md(`|---|---|${NS.map(() => '---').join('|')}|`);
    const all = { real: { label: 'الحالية (HEAD)', rules: real, build: (x) => injectExtra(real, x) } };
    for (const [vn, v] of Object.entries(VARIANTS)) {
      try { all[vn] = { label: vn, rules: buildModelRules(v), build: (x) => buildModelRules(v, x) }; } catch (e) { md(`| ${vn} | فشل بناء النسخة: ${String(e.message).slice(0, 120)} |`); }
    }
    for (const [vn, v] of Object.entries(all)) {
      try {
        results[vn] = await perfFor(vn, v.rules);
        for (const r of results[vn].rows) md(`| ${v.label} | ${r[0]} | ${r.slice(1).join(' | ')} |`);
      } catch (e) {
        md(`| ${v.label} | **فشل التشغيل/التركيب:** ${String(e && e.message).replace(/\|/g, '/').slice(0, 200)} |`);
      }
    }
    md('');
    for (const [vn, v] of Object.entries(all)) {
      try { Object.assign(results[vn] || (results[vn] = {}), await meterFor(vn, v.build)); }
      catch (e) { md(`> قياس الاستهلاك لـ ${v.label} فشل: ${String(e && e.message).replace(/\|/g, '/').slice(0, 200)}`); }
    }
    md('');
    md('## 2) الاستهلاك التقريبي للتعبيرات والهامش');
    md('');
    md('الطريقة: نكرر الدالة الكاملة r مرة في شرط واحد (التكلفة بين 1000/أول فشل و1000/آخر نجاح)، ونضيف "حشو" Ppad عدد K مرة لحد ما يفشل (الهامش = K × تكلفة Ppad).');
    md('');
    for (const [vn, r] of Object.entries(results)) {
      if (!r.pad) continue;
      const cLo = r.padOnlyFail === '-' ? 0 : 1000 / r.padOnlyFail, cHi = r.padOnlyMax ? 1000 / r.padOnlyMax : 1000;
      md(`**${all[vn].label}** — تكلفة Ppad≈ بين ${cLo.toFixed(0)} و${cHi.toFixed(0)} تعبير (اتكرر ${r.padOnlyMax} مرة ونجح، فشل عند ${r.padOnlyFail})`);
      md('');
      md('| الأصناف | أقصى تكرار كامل نجح | أول تكرار فشل | تكلفة الطلب الكامل (تقريبي) | أكبر K حشو نجح | هامش متبقي (تقريبي) | سبب الفشل |');
      md('|---|---|---|---|---|---|---|');
      for (const n of [1, 8, 15]) {
        const p = r.pad[n], q = r.rep8[n];
        const cost = q.ok === 0 ? '> 1000' : (q.fail === '-' ? `< ${(1000 / q.ok).toFixed(0)}` : `${(1000 / q.fail).toFixed(0)} – ${(1000 / q.ok).toFixed(0)}`);
        const margin = p.kmax < 0 ? 'لا يوجد (فشل بدون حشو)' : `≈ ${(p.kmax * cLo).toFixed(0)} – ${(p.kmax * cHi).toFixed(0)}`;
        md(`| ${n} | ${q.ok} | ${q.fail} | ${cost} | ${p.kmax} | ${margin} | ${p.why} |`);
      }
      md('');
    }
    md('## 3) اختبارات الاختراق المنطقي وسلامة التحديث');
    md('');
    md('الرفض لازم يكون رفض قواعد (DENY أو DENY(err) = خطأ تقييم = رفض)، ولو طلع EXPR/READ يتحسب فشل (الرفض بسبب الحد مش بسبب الأمان).');
    md('');
    const suiteSummary = [];
    for (const [vn, v] of Object.entries(all)) {
      if (vn === 'real') continue;
      const cap = results[vn] && results[vn].rows && results[vn].rows[0];
      const passes8 = cap && cap[4] === 'OK'; // العمود 0 الاسم، 1:n=1، 2:n=3، 3:n=5، 4:n=8
      if (!passes8) { md(`**${vn}**: اتخطّى (مش بينجح في 8 أصناف مع كل الشروط).`); md(''); suiteSummary.push([vn, '-', '-', '-']); continue; }
      let s;
      try { s = await runSuite(vn, v.rules); } catch (e) { md(`**${vn}**: فشل تشغيل الاختبارات: ${String(e.message).slice(0, 200)}`); continue; }
      suiteSummary.push([vn, s.pass, s.failN, s.limitHits]);
      md(`### ${vn}: نجح ${s.pass}، فشل ${s.failN}، حالات رفض بسبب الحدود ${s.limitHits}`);
      md('');
      md('| المجموعة | الاختبار | المتوقع | النتيجة | الحكم |');
      md('|---|---|---|---|---|');
      for (const r of s.rows) md(`| ${r.map((x) => String(x).replace(/\|/g, '/')).join(' | ')} |`);
      md('');
    }
    md('## 4) ملخص');
    md('');
    md('| النسخة | اختبارات نجحت | فشلت | رفض بسبب الحدود |');
    md('|---|---|---|---|');
    for (const r of suiteSummary) md(`| ${r.join(' | ')} |`);
    md('');
  } catch (e) {
    console.error('PM PROBE ERROR', e);
    md(`**خطأ في الإعداد:** ${String(e && e.message).slice(0, 400)}`);
    process.exitCode = 1;
  } finally {
    const text = out.join('\n') + '\n';
    fs.writeFileSync(path.join(__dirname, 'pricemap-results.md'), text);
    if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, text);
  }
})();
