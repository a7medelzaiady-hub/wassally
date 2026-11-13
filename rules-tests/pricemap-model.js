// المرحلة 4: نموذج "priceMap" تجريبي — بيتبني في الذاكرة من firestore.rules الحالية (HEAD) بتبديل نصّي.
// مفيش ملف إنتاج بيتعدّل: الناتج نص قواعد بيتحط في Emulator (مشاريع demo-*) أو في ملف مؤقت للاختبار بس.
//
// فكرة التصميم:
//  - stores/{id}.priceMap = { productId: السعر المعتمد } للأصناف المتاحة فقط (وجود المفتاح = الصنف تابع للمحل ومتاح).
//  - الطلب بيقرأ مستند المحل مرة واحدة (فحص المحل active + priceMap) بدل get لكل صنف.
//  - لو المحل ما اتحوّلش لسه (مفيش priceMap): نفس سلوك القواعد الحالية بالظبط (fallback) = أمان الترحيل.
//  - الكتابة على priceMap: المدير حر، وصاحب المحل مقيّد: مفتاح واحد في الكتابة، لازم يطابق الصنف بعد الكتابة
//    (getAfter) في نفس الـ batch، والعكس: كتابة صنف بسعر/توافر لازم تكون متسقة مع priceMap بعد الكتابة.
const fs = require('node:fs');
const path = require('node:path');

const real = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');

function extractAt(src, from, braceFrom = from) {
  let j = src.indexOf('{', braceFrom), depth = 0;
  for (; j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (depth === 0) { j++; break; } }
  }
  return src.slice(from, j);
}
function extractFn(src, name) {
  const m = new RegExp(`function\\s+${name}\\s*\\(`).exec(src);
  if (!m) throw new Error('function not found: ' + name);
  return extractAt(src, m.index);
}
function extractStoresBlock(src) {
  const m = /match\s+\/stores\/\{storeId\}\s*\{/.exec(src);
  if (!m) throw new Error('stores block not found');
  return extractAt(src, m.index, m.index + m[0].length - 1);
}

const rng = (a, b) => Array.from({ length: b - a }, (_, i) => a + i);
const pmAtCalls = (n) => rng(0, n).map((i) => `pmAt(items, pm, ${i})`).join(' && ');
const sumCalls = (n) => rng(0, n).map((i) => `lineTotalAt(items, ${i})`).join(' + ');

// variants (المرحلة 4 — الجولة 2):
//  C = النموذج الأول (للمقارنة): تعديل نصي على القواعد الحالية + شرائح 4/8/15
//  E/F/G = الجولة 2: "شجرة" شرائح دقيقة (leaf لكل عدد أصناف بدون guards) + سطر خفيف (pm.get) + المجموع جوه الـ leaf
//     E: القواعد الأساسية مكتوبة بشكل خفيف (size) ، F: نفس E بس regex للنصوص، G: القواعد الأساسية الحالية كما هي + شجرة
const VARIANTS = {
  'C-slim-tier': { fixed: 'orig', lines: 'tier', line: 'slim' },
  'E-lean-size-tree': { fixed: 'lean', str: 'size', lines: 'tree' },
  'F-lean-regex-tree': { fixed: 'lean', str: 'regex', lines: 'tree' },
  'G-origfixed-tree': { fixed: 'orig', str: 'regex', lines: 'tree' },
  // H = F + تقليم تعبيرات زايدة (الاعتماد إن خطأ النوع = رفض، والاختبارات بتثبت ده): بدون is number للكمية والخصم، وحد الأصناف <=15 فقط.
  'H-lean-regex-trim': { fixed: 'lean', str: 'regex', lines: 'tree', trim: true },
};

function pmLineFn(kind) {
  if (kind === 'plain') {
    return `function pmLine(l, pm) {
  return l is map &&
    l.keys().hasOnly(['name', 'price', 'qty', 'productId']) &&
    l.keys().hasAll(['name', 'price', 'qty', 'productId']) &&
    l.name is string && l.name.size() > 0 && l.name.size() <= 120 &&
    l.qty is number && l.qty >= 1 && l.qty <= 50 &&
    l.productId is string && l.productId in pm &&
    l.price is number && math.abs(pm[l.productId] - l.price) < 0.01;
}`;
  }
  // slim: بدون l is map و hasAll (غياب حقل = خطأ تقييم = رفض). الاختبارات السلبية بتثبت إن الرفض بيحصل فعلًا.
  return `function pmLine(l, pm) {
  return l.keys().hasOnly(['name', 'price', 'qty', 'productId']) &&
    l.name is string && l.name.size() > 0 && l.name.size() <= 120 &&
    l.qty is number && l.qty >= 1 && l.qty <= 50 &&
    l.productId is string && l.productId in pm &&
    l.price is number && math.abs(pm[l.productId] - l.price) < 0.01;
}`;
}

const SYNC_HELPERS = `
    function pdoc(storeId, pid) { return /databases/$(database)/documents/stores/$(storeId)/products/$(pid); }
    function sAfter(storeId) { return getAfter(/databases/$(database)/documents/stores/$(storeId)).data; }
    // كتابة صنف (create/update) بعد التنفيذ: لازم يتسق مع priceMap بعد الكتابة (لو المحل محوّل).
    function pmLiveOk(storeId, pid) {
      return !('priceMap' in sAfter(storeId)) || (
        request.resource.data.get('available', true) == true
          ? (pid in sAfter(storeId).priceMap &&
             math.abs(sAfter(storeId).priceMap[pid] - request.resource.data.price) < 0.001)
          : !(pid in sAfter(storeId).priceMap));
    }
    function pmGoneOk(storeId, pid) {
      return !('priceMap' in sAfter(storeId)) || !(pid in sAfter(storeId).priceMap);
    }
    // تعديل priceMap من صاحب المحل: مفتاح واحد بالظبط = pmProductId، والصنف بعد الكتابة لازم يطابقه.
    function pmStoreSideOk(storeId, pid) {
      return (pid in request.resource.data.priceMap)
        ? (existsAfter(pdoc(storeId, pid)) &&
           getAfter(pdoc(storeId, pid)).data.get('available', true) == true &&
           math.abs(getAfter(pdoc(storeId, pid)).data.price - request.resource.data.priceMap[pid]) < 0.001)
        : (!existsAfter(pdoc(storeId, pid)) ||
           getAfter(pdoc(storeId, pid)).data.get('available', true) == false);
    }
    function pmChangeOk(storeId) {
      return !('priceMap' in changedKeys()) || (
        resource.data.get('priceMap', null) is map &&
        request.resource.data.priceMap is map &&
        request.resource.data.get('pmProductId', null) is string &&
        request.resource.data.priceMap.diff(resource.data.priceMap).affectedKeys().size() == 1 &&
        request.resource.data.priceMap.diff(resource.data.priceMap).affectedKeys()
          .hasOnly([request.resource.data.pmProductId]) &&
        pmStoreSideOk(storeId, request.resource.data.pmProductId));
    }
`;

function tierHelpers(v) {
  const pmAll = v.tier || v.lines === 'tier'
    ? `function pmAll(items, pm) {
  return items.size() <= 4 ? (${pmAtCalls(4)}) : (items.size() <= 8 ? (${pmAtCalls(8)}) : (${pmAtCalls(15)}));
}`
    : `function pmAll(items, pm) { return ${pmAtCalls(15)}; }`;
  const sumT = `function linesSumT(items) {
  return items.size() <= 4 ? (${sumCalls(4)}) : (items.size() <= 8 ? (${sumCalls(8)}) : (${sumCalls(15)}));
}`;
  return `
    // ───── نموذج priceMap (شرائح) ─────
    ${pmLineFn(v.line)}
    function pmAt(items, pm, i) { return items.size() <= i || pmLine(items[i], pm); }
    ${pmAll}
    ${sumT}
    // محل فيه priceMap = تحقق السعر من الخريطة (دايمًا، بغض النظر عن enforcePrices).
    // محل من غير priceMap = السلوك الحالي بالظبط.
    function linesChecked(d, s) {
      return ('priceMap' in s)
        ? pmAll(d.items, s.priceMap)
        : (securityFlag('enforcePrices')
            ? (allLinesOk(d.items) && pricesMatch(d.items, d.storeId))
            : allLinesOk(d.items));
    }
`;
}

// الجولة 2: leaf لكل عدد أصناف N (بدون guards)، شجرة ثنائية على n=items.size() بتختار الـ leaf.
// كل leaf: تحقق كل سطر + مجموع الأسطر = subtotal.
function treeHelpers(v) {
  const CAP = v.cap || 15;
  const nameCheck = v.str === 'regex'
    ? `l.name.matches('(?s).{1,120}')`
    : `l.name is string && l.name.size() >= 1 && l.name.size() <= 120`;
  const line = `function lnLean(l, pm) {
      return l.keys().hasOnly(['name', 'price', 'qty', 'productId']) &&
        ${nameCheck} &&
        ${v.trim ? 'l.qty >= 1 && l.qty <= 50' : 'l.qty is number && l.qty >= 1 && l.qty <= 50'} &&
        l.price > 0 && pm.get(l.productId, 0) == l.price;
    }`;
  const leaves = rng(1, CAP + 1).map((N) => `function leaf${N}(d, pm) {
      let it = d.items;
      return ${rng(0, N).map((i) => `lnLean(it[${i}], pm)`).join(' && ')} &&
        math.abs(d.subtotal - (${rng(0, N).map((i) => `it[${i}].price * it[${i}].qty`).join(' + ')})) < 0.01;
    }`).join('\n    ');
  const tree = (lo, hi) => {
    if (lo === hi) return `leaf${lo}(d, pm)`;
    const mid = Math.floor((lo + hi) / 2);
    return `(n <= ${mid} ? ${tree(lo, mid)} : ${tree(mid + 1, hi)})`;
  };
  return `
    // ───── نموذج priceMap (شجرة leaves) ─────
    ${line}
    ${leaves}
    function pmTree(d, pm) { let n = d.items.size(); return ${tree(1, CAP)}; }
    // محل فيه priceMap = تحقق السعر والمجموع من الخريطة (دايمًا). محل من غير priceMap = السلوك الحالي (+ المجموع).
    function linesChecked(d, s) {
      return ('priceMap' in s)
        ? pmTree(d, s.priceMap)
        : ((securityFlag('enforcePrices')
              ? (allLinesOk(d.items) && pricesMatch(d.items, d.storeId))
              : allLinesOk(d.items)) &&
           math.abs(d.subtotal - linesSum(d.items)) < 0.01);
    }
    function promoDisc(d, p) {
      return d.promoCode is string && ${v.trim ? '' : 'd.discount is number && '}d.discount > 0 && d.discount < d.subtotal &&
        p.active == true && d.discount <= d.subtotal * p.percent / 100 + 0.01;
    }
    function promoOkL(d) {
      return d.get('discount', 0) == 0 || promoDisc(d, get(/databases/$(database)/documents/promos/$(d.promoCode)).data);
    }
    function feeOkL(d) {
      return d.deliveryFee == 20 ||
        (d.deliveryFee in get(/databases/$(database)/documents/app_info/delivery_areas).data.get('fees', []));
    }
`;
}

function helpers(v) {
  return (v.lines === 'tree' ? treeHelpers(v) : tierHelpers(v)) + SYNC_HELPERS;
}

function leanValidNewOrder(v) {
  const strs = v.str === 'regex'
    ? `d.userName.matches('(?s).{1,80}') && d.phone.matches('^01[0125][0-9]{8}$') &&
      d.address.matches('(?s).{5,300}') && d.notes.matches('(?s).{0,500}') &&
      d.storeName.matches('(?s).{0,100}') && a.matches('(?s).{0,60}')`
    : `d.userName is string && d.userName.size() >= 1 && d.userName.size() <= 80 &&
      d.phone is string && d.phone.matches('^01[0125][0-9]{8}$') &&
      d.address is string && d.address.size() >= 5 && d.address.size() <= 300 &&
      d.notes is string && d.notes.size() <= 500 &&
      d.storeName is string && d.storeName.size() <= 100 &&
      a is string && a.size() <= 60`;
  return `function validNewOrder(d) {
      let s = get(/databases/$(database)/documents/stores/$(d.storeId)).data;
      let a = d.get('area', '');
      return d.keys().hasOnly(['userId', 'userName', 'userEmail', 'phone', 'address', 'notes',
              'storeId', 'storeName', 'items', 'subtotal', 'deliveryFee',
              'total', 'paymentMethod', 'status', 'createdAt', 'area', 'promoCode', 'discount']) &&
        d.userId == request.auth.uid &&
        d.status == 'new' &&
        d.paymentMethod == 'cash' &&
        d.createdAt == request.time &&
        d.userEmail == request.auth.token.get('email', '') &&
        ${strs} &&
        d.storeId.matches('[^/]{1,100}') &&
        s.get('active', true) == true &&
        promoOkL(d) &&
        ${v.trim ? 'd.items is list && d.items.size() <= 15 && d.subtotal <= 100000' : 'd.items is list && d.items.size() >= 1 && d.items.size() <= 15 &&\n        d.subtotal >= 0 && d.subtotal <= 100000'} &&
        linesChecked(d, s) &&
        feeOkL(d) &&
        d.total > 0 && d.total <= 100000 &&
        math.abs(d.total - (d.subtotal + d.deliveryFee - d.get('discount', 0))) < 0.01;
    }`;
}

function modelValidNewOrder(v) {
  if (v.fixed === 'lean') return leanValidNewOrder(v);
  let f = extractFn(real, 'validNewOrder');
  const must = (cond, msg) => { if (!cond) throw new Error('anchor missing in validNewOrder: ' + msg); };
  must(f.includes('allLinesOk(d.items) &&'), 'allLinesOk');
  must(f.includes('math.abs(d.subtotal - linesSum(d.items)) < 0.01 &&'), 'linesSum');
  must(/&&\s*\(!securityFlag\('enforcePrices'\) \|\| pricesMatch\(d\.items, d\.storeId\)\);/.test(f), 'pricesMatch');
  const tree = v.lines === 'tree';
  f = f.replace('allLinesOk(d.items) &&', () => `d.storeId.matches('[^/]{1,100}') && s.get('active', true) == true && linesChecked(d, s) &&`);
  f = f.replace('math.abs(d.subtotal - linesSum(d.items)) < 0.01 &&', () => (tree ? 'true &&' : 'math.abs(d.subtotal - linesSumT(d.items)) < 0.01 &&'));
  f = f.replace(/&&\s*\(!securityFlag\('enforcePrices'\) \|\| pricesMatch\(d\.items, d\.storeId\)\);/, () => ';');
  const head = 'function validNewOrder(d) {';
  must(f.startsWith(head), 'head');
  f = head + `\n      let s = get(/databases/$(database)/documents/stores/$(d.storeId)).data;` + f.slice(head.length);
  return f;
}

const STORES_BLOCK = `match /stores/{storeId} {
      allow read: if signedIn();
      allow create, delete: if isAdmin();
      allow update: if isAdmin() ||
        (isStoreOwner(storeId) &&
          changedKeys().hasOnly(['active', 'time', 'image', 'imageUrl',
                                 'productCount', 'offerItems', 'bestItems',
                                 'updatedAt', 'priceMap', 'pmProductId']) &&
          request.resource.data.get('active', true) is bool &&
          request.resource.data.get('time', '') is string &&
          request.resource.data.get('time', '').size() <= 60 &&
          request.resource.data.get('image', '') is string &&
          request.resource.data.get('imageUrl', '') is string &&
          pmChangeOk(storeId));

      allow update: if signedIn() &&
        changedKeys().hasOnly(['ratingSum', 'ratingCount', 'lastReviewId']) &&
        request.resource.data.lastReviewId is string &&
        !exists(/databases/$(database)/documents/reviews/$(request.resource.data.lastReviewId)) &&
        existsAfter(/databases/$(database)/documents/reviews/$(request.resource.data.lastReviewId)) &&
        getAfter(/databases/$(database)/documents/reviews/$(request.resource.data.lastReviewId)).data.storeId == storeId &&
        request.resource.data.ratingCount == resource.data.get('ratingCount', 0) + 1 &&
        request.resource.data.ratingSum ==
          resource.data.get('ratingSum', 0) +
          getAfter(/databases/$(database)/documents/reviews/$(request.resource.data.lastReviewId)).data.rating;

      match /products/{productId} {
        allow read: if signedIn();
        allow delete: if isAdmin() || (isStoreOwner(storeId) && pmGoneOk(storeId, productId));
        allow create, update: if isAdmin() ||
          (isStoreOwner(storeId) && validOwnerProduct(request.resource.data) &&
           pmLiveOk(storeId, productId));
      }
    }`;

// extra = قواعد إضافية للقياس (match blocks) بتتحط قبل قفلة الـ documents.
function buildModelRules(v, extra = '') {
  let r = real;
  const fn = extractFn(real, 'validNewOrder');
  r = r.replace(fn, () => helpers(v) + '\n    ' + modelValidNewOrder(v));
  const blk = extractStoresBlock(real);
  for (const anchor of ["'productCount', 'offerItems', 'bestItems'", 'lastReviewId', 'match /products/{productId}', 'allow create, delete: if isAdmin();']) {
    if (!blk.includes(anchor)) throw new Error('stores block changed, anchor missing: ' + anchor);
  }
  r = r.replace(blk, () => STORES_BLOCK);
  return injectExtra(r, extra);
}
function injectExtra(text, extra) {
  if (!extra) return text;
  const i = text.lastIndexOf('}');
  const j = text.lastIndexOf('}', i - 1);
  return text.slice(0, j) + extra + '\n' + text.slice(j);
}

module.exports = { real, VARIANTS, buildModelRules, injectExtra, extractFn };
