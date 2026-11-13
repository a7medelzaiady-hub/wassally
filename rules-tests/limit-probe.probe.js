// قياس حد قراءات قواعد Firestore (get/exists/getAfter) — مرحلة قياس فقط.
// ما بيعدّلش firestore.rules ولا أي بيانات إنتاج: كله على Emulator (projectId تجريبي).
// التشغيل: firebase emulators:exec --only firestore --project demo-wasally "node limit-probe.probe.js"
//
// الاتنين اللي بنقيسهم:
//  A) سلوك الحد نفسه بقواعد اصطناعية صغيرة (كل الشروط فيها true، فأي فشل = تجاوز الحد مش صلاحيات):
//     - مستندات مختلفة (1..21) في عملية واحدة
//     - نفس المستند مكرر (1..21 مرة) وexists+get على نفس المستند
//     - batch: هل الحد 10 بيفضل ساري على كل عملية جوه الـ batch؟
//  B) إنشاء طلب بقواعد المشروع الفعلية (من firestore.rules كما هي) بـ 1/5/8 أصناف، مع المنطقة والكوبون
//     وenforcePrices، وكمان نسخة في الذاكرة فيها فحص المحل (تعديل نصي داخل الاختبار فقط، مش في الملف).
//     فيه سيناريو تحكّم (enforcePrices مقفول) عشان نتأكد إن شكل الطلب نفسه سليم.
//
// التصنيف: ALLOWED = نجح | LIMIT = رسالة تجاوز الحد | DENIED = شرط أمني/قاعدة رجّعت false.
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, writeBatch, serverTimestamp } = require('firebase/firestore');

const results = [];
const log = (section, name, outcome, detail = '') => {
  results.push({ section, name, outcome, detail });
  console.log(`[${section}] ${name} => ${outcome}${detail ? ' :: ' + detail : ''}`);
};

const LIMIT_RE = /exceed|maximum|too many|limit|quota|access call/i;
function classify(e) {
  const msg = String((e && (e.message || e.code)) || e).replace(/\s+/g, ' ');
  return { outcome: LIMIT_RE.test(msg) ? 'LIMIT' : 'DENIED', detail: msg.slice(0, 260) };
}
async function attempt(fn) {
  try {
    await fn();
    return { outcome: 'ALLOWED', detail: '' };
  } catch (e) {
    return classify(e);
  }
}

// ───────────── A) قواعد اصطناعية ─────────────
const P = (n) => `/databases/$(database)/documents/probe/d${n}`;
const DISTINCT = [1, 5, 9, 10, 11, 12, 20, 21];
const REPEAT = [1, 10, 11, 21];

function syntheticRules() {
  let r = "rules_version = '2';\nservice cloud.firestore { match /databases/{database}/documents {\n";
  r += 'match /probe/{id} { allow read, write: if false; }\n';
  for (const k of DISTINCT) {
    const calls = Array.from({ length: k }, (_, i) => `get(${P(i + 1)}).data.v == 1`).join(' && ');
    r += `match /distinct${k}/{id} { allow create: if ${calls}; }\n`;
  }
  for (const m of REPEAT) {
    const calls = Array.from({ length: m }, () => `get(${P(1)}).data.v == 1`).join(' && ');
    r += `match /repeat${m}/{id} { allow create: if ${calls}; }\n`;
  }
  // exists + get على نفس المستند (زي securityFlag): 5 مرات من كل واحد = 10 استدعاء نصي، مستند واحد.
  const eg = Array.from({ length: 5 }, () => `exists(${P(1)}) && get(${P(1)}).data.v == 1`).join(' && ');
  r += `match /existsget/{id} { allow create: if ${eg}; }\n`;
  // أزواج: كل مستند من 6 مستندات متكرر مرتين = 12 استدعاء نصي على 6 مستندات.
  const pairs = Array.from({ length: 6 }, (_, i) => `get(${P(i + 1)}).data.v == 1 && get(${P(i + 1)}).data.v == 1`).join(' && ');
  r += `match /pairs6/{id} { allow create: if ${pairs}; }\n`;
  // لأجل الـ batch: نصف أول (d1..d6) ونصف تاني (d7..d12).
  const half = (from) => Array.from({ length: 6 }, (_, i) => `get(${P(from + i)}).data.v == 1`).join(' && ');
  r += `match /halfA/{id} { allow create: if ${half(1)}; }\n`;
  r += `match /halfB/{id} { allow create: if ${half(7)}; }\n`;
  r += '}}\n';
  return r;
}

async function sectionA() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-probe-synthetic',
    firestore: { rules: syntheticRules() },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (let i = 1; i <= 21; i++) await setDoc(doc(db, `probe/d${i}`), { v: 1 });
  });
  const db = env.unauthenticatedContext().firestore();
  let n = 0;
  const create = (col) => setDoc(doc(db, `${col}/x${++n}`), { a: 1 });

  for (const k of DISTINCT) {
    const r = await attempt(() => create(`distinct${k}`));
    log('A', `${k} مستند مختلف في عملية واحدة`, r.outcome, r.detail);
  }
  for (const m of REPEAT) {
    const r = await attempt(() => create(`repeat${m}`));
    log('A', `نفس المستند ${m} مرة (get مكرر)`, r.outcome, r.detail);
  }
  let r = await attempt(() => create('existsget'));
  log('A', 'exists+get ×5 على نفس المستند (10 استدعاء نصي)', r.outcome, r.detail);
  r = await attempt(() => create('pairs6'));
  log('A', '6 مستندات كل واحد مرتين (12 استدعاء نصي)', r.outcome, r.detail);

  // batch: عمليتين، كل واحدة 6 مستندات مختلفة (المجموع 12 مختلف) — الحد الكلي للـ batch 20؟
  r = await attempt(async () => {
    const b = writeBatch(db);
    b.set(doc(db, `halfA/b${++n}`), { a: 1 });
    b.set(doc(db, `halfB/b${++n}`), { a: 1 });
    await b.commit();
  });
  log('A', 'batch: عمليتين × 6 مستندات مختلفة (12 إجمالي)', r.outcome, r.detail);

  // batch: عملية واحدة فيها 11 مستند مختلف + عملية تانية بسيطة — هل الحد 10 بيفضل على العملية؟
  r = await attempt(async () => {
    const b = writeBatch(db);
    b.set(doc(db, `distinct11/b${++n}`), { a: 1 });
    b.set(doc(db, `distinct1/b${++n}`), { a: 1 });
    await b.commit();
  });
  log('A', 'batch: عملية بـ 11 مستند مختلف + عملية بمستند واحد', r.outcome, r.detail);

  r = await attempt(async () => {
    const b = writeBatch(db);
    b.set(doc(db, `distinct10/b${++n}`), { a: 1 });
    b.set(doc(db, `distinct10/b${++n}`), { a: 1 });
    await b.commit();
  });
  log('A', 'batch: عمليتين × 10 مستندات (نفس الـ 10 مستندات في الاتنين)', r.outcome, r.detail);

  await env.cleanup();
}

// ───────────── B) طلب بقواعد المشروع الفعلية ─────────────
const STORE_CHECK_OLD = "(!securityFlag('enforcePrices') || pricesMatch(d.items, d.storeId));";
const STORE_CHECK_NEW =
  "(!securityFlag('enforcePrices') || pricesMatch(d.items, d.storeId)) &&\n" +
  "        get(/databases/$(database)/documents/stores/$(d.storeId)).data.get('active', true) == true;";

function order(n, { area = false, promo = false } = {}) {
  const items = Array.from({ length: n }, (_, i) => ({ name: 'p' + (i + 1), price: 10, qty: 1, productId: 'p' + (i + 1) }));
  const subtotal = n * 10;
  const fee = area ? 25 : 20;
  const discount = promo ? Math.floor(subtotal * 10) / 100 : 0; // 10%
  const o = {
    userId: 'cust1', userName: 'Ali', userEmail: 'a@x.com', phone: '01012345678', address: 'عنوان تجريبي 1',
    notes: '', storeId: 'shop1', storeName: 'S', items, subtotal, deliveryFee: fee,
    total: subtotal + fee - discount, paymentMethod: 'cash', status: 'new', createdAt: serverTimestamp(),
  };
  if (area) o.area = 'Zone A';
  if (promo) { o.promoCode = 'SAVE10'; o.discount = discount; }
  return o;
}

async function makeEnv(projectId, rules, enforce) {
  const env = await initializeTestEnvironment({ projectId, firestore: { rules } });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'app_info/security'), { enforcePrices: enforce });
    await setDoc(doc(db, 'app_info/delivery_areas'), { areas: [{ name: 'Zone A', fee: 25 }], fees: [25] });
    await setDoc(doc(db, 'promos/SAVE10'), { percent: 10, active: true, note: '' });
    await setDoc(doc(db, 'stores/shop1'), { name: 'S', active: true, time: '20-30', order: 1, rating: 4 });
    await setDoc(doc(db, 'stores/shop2'), { name: 'Closed', active: false, time: '20-30', order: 2, rating: 4 });
    for (let i = 1; i <= 8; i++) await setDoc(doc(db, `stores/shop1/products/p${i}`), { name: 'p' + i, price: 10, available: true });
  });
  return env;
}

async function sectionB() {
  const realRules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
  const injectable = realRules.includes(STORE_CHECK_OLD);
  if (!injectable) log('B', 'حقن فحص المحل في نسخة الذاكرة', 'SKIPPED', 'ما لقيتش سطر pricesMatch بالصيغة المتوقعة');
  const variants = [
    ['القواعد الحالية كما هي', realRules, 'demo-probe-real'],
    ...(injectable ? [['الحالية + فحص المحل (نسخة في الذاكرة)', realRules.replace(STORE_CHECK_OLD, STORE_CHECK_NEW), 'demo-probe-store']] : []),
  ];
  const scenarios = [
    ['تحكّم: enforcePrices مقفول، 8 أصناف + منطقة + كوبون', false, 8, { area: true, promo: true }],
    ['enforcePrices شغّال، صنف واحد', true, 1, {}],
    ['enforcePrices شغّال، 5 أصناف', true, 5, {}],
    ['enforcePrices شغّال، 8 أصناف', true, 8, {}],
    ['enforcePrices شغّال، 1 صنف + منطقة + كوبون', true, 1, { area: true, promo: true }],
    ['enforcePrices شغّال، 5 أصناف + منطقة + كوبون', true, 5, { area: true, promo: true }],
    ['enforcePrices شغّال، 8 أصناف + منطقة', true, 8, { area: true }],
    ['enforcePrices شغّال، 8 أصناف + كوبون', true, 8, { promo: true }],
    ['enforcePrices شغّال، 8 أصناف + منطقة + كوبون (الحالة القصوى)', true, 8, { area: true, promo: true }],
  ];
  for (const [vname, rules, pid] of variants) {
    const envOn = await makeEnv(pid + '-on', rules, true);
    const envOff = await makeEnv(pid + '-off', rules, false);
    let n = 0;
    for (const [sname, enforce, items, opt] of scenarios) {
      const env = enforce ? envOn : envOff;
      const db = env.authenticatedContext('cust1', { email: 'a@x.com' }).firestore();
      const r = await attempt(() => setDoc(doc(db, `orders/o${++n}`), order(items, opt)));
      log('B', `${vname} | ${sname}`, r.outcome, r.detail);
    }
    if (pid === 'demo-probe-store') {
      const db = envOn.authenticatedContext('cust1', { email: 'a@x.com' }).firestore();
      const o = order(1, {});
      o.storeId = 'shop2';
      const r = await attempt(() => setDoc(doc(db, 'orders/closed1'), o));
      log('B', `${vname} | محل مقفول (متوقع DENIED: شرط أمني)`, r.outcome, r.detail);
      const o2 = order(1, {});
      o2.storeId = 'nope';
      const r2 = await attempt(() => setDoc(doc(db, 'orders/missing1'), o2));
      log('B', `${vname} | محل مش موجود (متوقع DENIED)`, r2.outcome, r2.detail);
    }
    await envOn.cleanup();
    await envOff.cleanup();
  }
}

function writeSummary() {
  const rows = results.map((r) => `| ${r.section} | ${r.name} | **${r.outcome}** | ${r.detail.replace(/\|/g, '/')} |`);
  const md = [
    '## نتائج قياس حد قراءات القواعد',
    '',
    'ALLOWED = نجح · LIMIT = تجاوز حد القراءات · DENIED = شرط أمني/قاعدة رجّعت false',
    '',
    '| القسم | الحالة | النتيجة | الرسالة |',
    '|---|---|---|---|',
    ...rows,
    '',
  ].join('\n');
  fs.writeFileSync(path.join(__dirname, 'probe-results.md'), md);
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, md + '\n');
}

(async () => {
  try {
    await sectionA();
    await sectionB();
  } catch (e) {
    console.error('PROBE SETUP ERROR', e);
    log('X', 'خطأ في إعداد القياس', 'ERROR', String(e && e.message).slice(0, 260));
    process.exitCode = 1;
  } finally {
    writeSummary();
  }
})();
