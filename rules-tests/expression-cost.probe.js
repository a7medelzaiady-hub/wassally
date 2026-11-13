// المرحلة 3: مصدر استهلاك "حد التعبيرات" (1000 تعبير في الطلب الواحد) — قياس فقط.
// ما بيعدّلش firestore.rules ولا Flutter ولا بيانات إنتاج. كل التجارب على Emulator (مشاريع demo-*).
// الدوال بتتسحب من firestore.rules الحالية (HEAD) بنصها، وبتتركّب في قواعد تجريبية في الذاكرة.
//
// مفيش Emulator بيرجّع "عدد التعبيرات" المستهلك، فبنقيس بطريقتين:
//  1) السعة: أكبر عدد أصناف (1..15) يعدّي عند كل جزء/تركيبة.
//  2) التكلفة التقريبية: بنكرر الجزء r مرة في AND واحد (كله true) ونشوف أكبر r يعدّي؛ التكلفة ≈ 1000 / r.
// وبنفصل بين: EXPR_LIMIT (حد التعبيرات) | READ_LIMIT (حد القراءات) | SECURITY_OR_DATA (false عادي) | OTHER.
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, serverTimestamp } = require('firebase/firestore');

const real = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
const out = []; // سطور markdown
const md = (s = '') => { out.push(s); console.log(s); };

function classify(e) {
  const msg = String((e && (e.message || e.code)) || e).replace(/\s+/g, ' ');
  if (/expressions to evaluate/i.test(msg)) return 'EXPR_LIMIT';
  if (/Service call error/i.test(msg)) return 'READ_LIMIT';
  if (/PERMISSION_DENIED/i.test(msg) && /false for/i.test(msg) && !/evaluation error|Unable to evaluate/i.test(msg)) return 'SECURITY_OR_DATA';
  return 'OTHER:' + msg.slice(0, 160);
}

function extractFn(src, name) {
  const m = new RegExp(`function\\s+${name}\\s*\\(`).exec(src);
  if (!m) throw new Error('function not found: ' + name);
  let j = src.indexOf('{', m.index), depth = 0;
  for (; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (depth === 0) { j++; break; } }
  }
  return src.slice(m.index, j);
}

function order(n, { area = true, promo = true } = {}) {
  const items = Array.from({ length: n }, (_, i) => ({ name: 'p' + (i + 1), price: 10, qty: 1, productId: 'p' + (i + 1) }));
  const subtotal = n * 10;
  const fee = area ? 25 : 20;
  const discount = promo ? Math.floor(subtotal * 10) / 100 : 0;
  const o = {
    userId: 'cust1', userName: 'Ali', userEmail: 'a@x.com', phone: '01012345678', address: 'عنوان تجريبي 1',
    notes: '', storeId: 'shop1', storeName: 'S', items, subtotal, deliveryFee: fee,
    total: subtotal + fee - discount, paymentMethod: 'cash', status: 'new', createdAt: serverTimestamp(),
  };
  if (area) o.area = 'Zone A';
  if (promo) { o.promoCode = 'SAVE10'; o.discount = discount; }
  return o;
}

async function seed(env, enforce) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'app_info/security'), { enforcePrices: enforce });
    await setDoc(doc(db, 'app_info/delivery_areas'), { areas: [{ name: 'Zone A', fee: 25 }], fees: [25] });
    await setDoc(doc(db, 'promos/SAVE10'), { percent: 10, active: true, note: '' });
    await setDoc(doc(db, 'stores/shop1'), { name: 'S', active: true, time: '20-30', order: 1, rating: 4 });
    await setDoc(doc(db, 'stores/shop2'), { name: 'Closed', active: false, time: '20-30', order: 2, rating: 4 });
    for (let i = 1; i <= 15; i++) await setDoc(doc(db, `stores/shop1/products/p${i}`), { name: 'p' + i, price: 10, available: true });
  });
}
const dbOf = (env) => env.authenticatedContext('cust1', { email: 'a@x.com' }).firestore();

async function tryCreate(db, col, id, data) {
  try { await setDoc(doc(db, `${col}/${id}`), data); return 'ALLOWED'; } catch (e) { return classify(e); }
}

// ───────────── 1) سعة القواعد الحقيقية (من غير منطقة/كوبون) ─────────────
async function part1() {
  md('## 1) القواعد الحالية كما هي — أقصى عدد أصناف (طلب عادي من غير منطقة/كوبون)');
  md('');
  md('| enforcePrices | الأصناف | النتيجة |');
  md('|---|---|---|');
  for (const enforce of [false, true]) {
    const env = await initializeTestEnvironment({ projectId: `demo-x3-real-${enforce}`, firestore: { rules: real } });
    await seed(env, enforce);
    const db = dbOf(env);
    for (const n of [1, 2, 3, 4, 5, 6, 7, 8]) {
      const r = await tryCreate(db, 'orders', `o${n}`, order(n, { area: false, promo: false }));
      md(`| ${enforce} | ${n} | ${r} |`);
    }
    await env.cleanup();
  }
  md('');
}

// ───────────── 2/3) الأجزاء والتركيبات ─────────────
const FN_NAMES = ['securityFlag', 'orderKeys', 'lineOk', 'lineOkAt', 'priceOkAt', 'pricesMatch', 'lineTotalAt',
  'allLinesOk', 'linesSum', 'feeOk', 'promoOk', 'validNewOrder'];

const SCALARS = `d.keys().hasOnly(orderKeys().concat(['area', 'promoCode', 'discount'])) &&
  d.keys().hasAll(orderKeys()) && d.get('area', '') is string && d.get('area', '').size() <= 60 &&
  d.userId == request.auth.uid && d.status == 'new' && d.paymentMethod == 'cash' &&
  d.createdAt == request.time && d.userEmail == request.auth.token.get('email', '') &&
  d.userName is string && d.userName.size() >= 1 && d.userName.size() <= 80 &&
  d.phone is string && d.phone.matches('^01[0125][0-9]{8}$') &&
  d.address is string && d.address.size() >= 5 && d.address.size() <= 300 &&
  d.notes is string && d.notes.size() <= 500 &&
  d.storeId is string && d.storeId.size() <= 100 && d.storeName is string && d.storeName.size() <= 100`;
const LINES = `d.items is list && d.items.size() >= 1 && d.items.size() <= 15 && allLinesOk(d.items)`;
const LINESUM = `d.subtotal is number && d.subtotal >= 0 && d.subtotal <= 100000 && math.abs(d.subtotal - linesSum(d.items)) < 0.01`;
const TOTAL = `d.total is number && d.total > 0 && d.total <= 100000 && math.abs(d.total - (d.subtotal + d.deliveryFee - d.get('discount', 0))) < 0.01`;
const STORE = `get(/databases/$(database)/documents/stores/$(d.storeId)).data.get('active', true) == true`;
const PRICES = `(!securityFlag('enforcePrices') || pricesMatch(d.items, d.storeId))`;

// تجربة في الذاكرة فقط (مش إصلاح): نفس lineOk لكن بتخزين الحقول في let عشان ما تتعادش dereference كتير.
const LINEOK_LET = `
function lineOkL(l) {
  let k = l.keys();
  let nm = l.name;
  let pr = l.price;
  let q = l.qty;
  return l is map &&
    k.hasOnly(['name', 'price', 'qty', 'productId']) && k.hasAll(['name', 'price', 'qty']) &&
    (!('productId' in k) || (l.productId is string && l.productId.size() > 0 && l.productId.size() <= 100)) &&
    nm is string && nm.size() > 0 && nm.size() <= 120 &&
    pr is number && pr >= 0 && pr <= 20000 && q is number && q >= 1 && q <= 50;
}
function lineOkAtL(items, i) { return items.size() <= i || lineOkL(items[i]); }
function allLinesOkL(items) {
  return ${Array.from({ length: 15 }, (_, i) => `lineOkAtL(items, ${i})`).join(' && ')};
}`;
const LINES_L = `d.items is list && d.items.size() >= 1 && d.items.size() <= 15 && allLinesOkL(d.items)`;

// كل جزء بيتعرّف مرة واحدة كدالة P_<اسم>(d) (عشان ما نكرّرش regex في القواعد — المترجم بيرفض "Expression is too complex"
// لو نفس النص اتكرر في أماكن كتير). التركيبات والتكرار بينادوا على الدوال دي.
const PIECES = {
  scalars: SCALARS,
  lines: LINES,
  linesum_only: LINESUM,
  total_only: TOTAL,
  area: 'feeOk(d)',
  promo: 'promoOk(d)',
  store: STORE,
  prices: PRICES,
};
const call = (n) => `P_${n}(request.resource.data)`;
const COMPONENTS = Object.fromEntries(Object.keys(PIECES).map((n) => [n, [n]]));
const COMBOS = {
  'lines+linesum+total': ['lines', 'linesum_only', 'total_only'],
  'lines+area': ['lines', 'area'],
  'lines+promo': ['lines', 'promo'],
  'lines+area+promo': ['lines', 'area', 'promo'],
  'lines+linesum+total+area+promo': ['lines', 'linesum_only', 'total_only', 'area', 'promo'],
  'scalars+lines+linesum+total+area+promo (بدون الأسعار)': ['scalars', 'lines', 'linesum_only', 'total_only', 'area', 'promo'],
  'validNewOrder الحقيقية (كل الشروط، بدون فحص المحل)': ['REAL'],
  'validNewOrder الحقيقية + فحص المحل': ['REAL', 'store'],
};
const REPS = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]; // 96+ بيرفضها مترجم القواعد (Expression is too complex)
const REP_NS = [1, 4];

function buildRules(COMPONENTS, COMBOS, extra = '', pieces = PIECES) {
  const fns = FN_NAMES.map((n) => extractFn(real, n)).join('\n');
  let r = `rules_version = '2';\nservice cloud.firestore { match /databases/{database}/documents {\n${fns}\n${extra}\n`;
  for (const [n, expr] of Object.entries(pieces)) r += `function P_${n}(d) { return ${expr}; }\n`;
  r += 'function P_REAL(d) { return validNewOrder(d); }\n';
  const expand = (list) => list.map((n) => call(n)).join(' && ');
  const all = { ...COMPONENTS, ...COMBOS };
  Object.values(all).forEach((list, i) => {
    r += `match /sc${i}/{id} { allow create: if ${expand(list)}; }\n`;
  });
  Object.entries(COMPONENTS).forEach(([name, list], i) => {
    if (name === 'scalars') return; // فيه regex: مش بنكرره
    for (const k of REPS) {
      r += `match /rep_${i}_${k}/{id} { allow create: if ${Array.from({ length: k }, () => expand(list)).join(' && ')}; }\n`;
    }
  });
  r += '}}\n';
  return r;
}

async function part23(title, COMPONENTS, COMBOS, extra, pieces = PIECES) {
  const rules = buildRules(COMPONENTS, COMBOS, extra, pieces);
  console.log(`rules size: ${rules.length} bytes`);
  const env = await initializeTestEnvironment({ projectId: 'demo-x3-comp-' + Math.abs(rules.length), firestore: { rules } });
  await seed(env, true);
  const db = dbOf(env);
  const names = Object.keys({ ...COMPONENTS, ...COMBOS });

  md(`## ${title}: سعة كل جزء وتركيبة (نفس بيانات الطلب في الكل: منطقة + كوبون + محل شغّال، enforcePrices مفتوح)`);
  md('');
  md('| السيناريو | أقصى أصناف نجحت | أول فشل عند | سبب أول فشل | ملحوظة |');
  md('|---|---|---|---|---|');
  for (let i = 0; i < names.length; i++) {
    let maxOk = 0, firstFail = '-', why = '-';
    for (let n = 1; n <= 15; n++) {
      const r = await tryCreate(db, `sc${i}`, `o${n}`, order(n));
      if (r === 'ALLOWED') { if (firstFail === '-') maxOk = n; }
      else if (firstFail === '-') { firstFail = n; why = r; }
    }
    const note = (names[i] === 'prices' || /validNewOrder/.test(names[i])) && firstFail === 9 ? 'فشل عند 9 متوقع: حد القواعد 8 أصناف للأسعار' : '';
    md(`| ${names[i]} | ${maxOk} | ${firstFail} | ${why} | ${note} |`);
  }
  md('');

  md(`## ${title}: التكلفة التقريبية لكل جزء (تكرار الجزء r مرة في شرط واحد؛ التكلفة ≈ 1000 ÷ أكبر r عدّى)`);
  md('');
  md('| الجزء | الأصناف | أكبر تكرار نجح | أول تكرار فشل | سبب الفشل | تكلفة تقريبية (تعبير) |');
  md('|---|---|---|---|---|---|');
  const compNames = Object.keys(COMPONENTS);
  for (let ci = 0; ci < compNames.length; ci++) {
    if (compNames[ci] === 'scalars') continue;
    for (const n of REP_NS) {
      let maxOk = 0, firstFail = '-', why = '-';
      for (const k of REPS) {
        const r = await tryCreate(db, `rep_${ci}_${k}`, `o${n}_${k}`, order(n));
        if (r === 'ALLOWED') { if (firstFail === '-') maxOk = k; }
        else { firstFail = k; why = r; break; }
      }
      let est = '-';
      if (firstFail === '-') est = `< ${(1000 / maxOk).toFixed(1)} (اتكرر ${maxOk} مرة وعدّى)`;
      else if (maxOk === 0) est = `> 1000 (مرة واحدة فشلت)`;
      else est = `بين ${(1000 / firstFail).toFixed(0)} و ${(1000 / maxOk).toFixed(0)}`;
      md(`| ${compNames[ci]} | ${n} | ${maxOk} | ${firstFail} | ${why} | ${est} |`);
    }
  }
  md('');
  await env.cleanup();
}

(async () => {
  try {
    await part1();
    await part23('2+3+4) القواعد الحالية', COMPONENTS, COMBOS, '');
    try {
      // تجربة في الذاكرة فقط (مش إصلاح): هل تخزين الحقول في let بيقلل الاستهلاك؟
      await part23('5) تجربة (lineOk بـ let) — مش إصلاح', { lines_الحالية: ['lines'], lines_بـlet: ['lines_L'] }, {}, LINEOK_LET, { lines: LINES, lines_L: LINES_L });
    } catch (e) {
      md(`**تجربة let فشلت في التركيب/التشغيل:** ${String(e && e.message).slice(0, 300)}`);
    }
  } catch (e) {
    console.error('X3 SETUP ERROR', e);
    md(`**خطأ في إعداد القياس:** ${String(e && e.message).slice(0, 300)}`);
    process.exitCode = 1;
  } finally {
    const text = out.join('\n') + '\n';
    fs.writeFileSync(path.join(__dirname, 'expression-cost-results.md'), text);
    if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, text);
  }
})();
