// قياس مقارن لنسختين من firestore.rules على نفس الطلب ونفس البيانات (مرحلة قياس فقط).
// ما بيعدّلش firestore.rules ولا Flutter ولا بيانات إنتاج. كله على Emulator بمشروع تجريبي.
// النسخ بتتجاب من تاريخ git (git show <sha>:firestore.rules) — لازم checkout بـ fetch-depth: 0.
//
// بدون منطقة ولا كوبون (عشان نعزل تأثيرهم): 1 و5 و8 و15 صنف × enforcePrices مقفول/شغّال.
// التصنيف:
//   ALLOWED              نجح
//   EXPR_LIMIT           تجاوز حد التعبيرات (maximum of N expressions to evaluate)
//   READ_LIMIT           تجاوز حد قراءات المستندات (Service call error في get/exists)
//   SECURITY_OR_DATA     رفض عادي (false) من شرط في القواعد. بيتميز عن "عدم توافق البيانات"
//                        بسيناريو التحكّم: لو طلب الصنف الواحد مع enforce مقفول نجح، يبقى شكل الطلب سليم.
//   OTHER                أي رسالة غير متوقعة (بتتطبع كاملة)
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { doc, setDoc, serverTimestamp } = require('firebase/firestore');

const ROOT = path.join(__dirname, '..');
const VERSIONS = [
  ['04e1e65', 'القديمة (قبل المناطق/الكوبونات/المشرف)'],
  ['6908ef0', 'الحالية (أول commit فيه المناطق والكوبونات والمشرف)'],
];
const COUNTS = [1, 5, 8, 15];

const results = [];
function classify(e) {
  const msg = String((e && (e.message || e.code)) || e).replace(/\s+/g, ' ');
  if (/expressions to evaluate/i.test(msg)) return ['EXPR_LIMIT', msg];
  if (/Service call error/i.test(msg)) return ['READ_LIMIT', msg];
  if (/PERMISSION_DENIED/i.test(msg) && /false for/i.test(msg) && !/evaluation error|Unable to evaluate/i.test(msg)) {
    return ['SECURITY_OR_DATA', msg];
  }
  return ['OTHER', msg];
}

function order(n) {
  const items = Array.from({ length: n }, (_, i) => ({ name: 'p' + (i + 1), price: 10, qty: 1, productId: 'p' + (i + 1) }));
  const subtotal = n * 10;
  return {
    userId: 'cust1', userName: 'Ali', userEmail: 'a@x.com', phone: '01012345678', address: 'عنوان تجريبي 1',
    notes: '', storeId: 'shop1', storeName: 'S', items, subtotal, deliveryFee: 20,
    total: subtotal + 20, paymentMethod: 'cash', status: 'new', createdAt: serverTimestamp(),
  };
}

async function makeEnv(projectId, rules, enforce) {
  const env = await initializeTestEnvironment({ projectId, firestore: { rules } });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'app_info/security'), { enforcePrices: enforce });
    await setDoc(doc(db, 'stores/shop1'), { name: 'S', active: true, time: '20-30', order: 1, rating: 4 });
    for (let i = 1; i <= 15; i++) await setDoc(doc(db, `stores/shop1/products/p${i}`), { name: 'p' + i, price: 10, available: true });
  });
  return env;
}

function rulesAt(sha) {
  return execFileSync('git', ['show', `${sha}:firestore.rules`], { cwd: ROOT, encoding: 'utf8' });
}

(async () => {
  try {
    for (const [sha, label] of VERSIONS) {
      let rules;
      try { rules = rulesAt(sha); } catch (e) {
        results.push({ version: `${sha} ${label}`, enforce: '-', items: '-', outcome: 'MISSING', detail: 'ما لقيتش الـ commit (محتاج fetch-depth: 0)' });
        continue;
      }
      for (const enforce of [false, true]) {
        const env = await makeEnv(`demo-cmp-${sha}-${enforce}`, rules, enforce);
        const db = env.authenticatedContext('cust1', { email: 'a@x.com' }).firestore();
        let k = 0;
        for (const n of COUNTS) {
          let outcome = 'ALLOWED', detail = '';
          try { await setDoc(doc(db, `orders/o${++k}`), order(n)); } catch (e) { [outcome, detail] = classify(e); }
          results.push({ version: `${sha} ${label}`, enforce, items: n, outcome, detail: detail.slice(0, 420) });
          console.log(`[${sha}] enforcePrices=${enforce} items=${n} => ${outcome}${detail ? ' :: ' + detail.slice(0, 300) : ''}`);
        }
        await env.cleanup();
      }
    }
  } catch (e) {
    console.error('COMPARE SETUP ERROR', e);
    results.push({ version: '-', enforce: '-', items: '-', outcome: 'ERROR', detail: String(e && e.message).slice(0, 300) });
    process.exitCode = 1;
  } finally {
    const rows = results.map((r) => `| ${r.version} | ${r.enforce} | ${r.items} | **${r.outcome}** | ${String(r.detail).replace(/\|/g, '/')} |`);
    const md = ['## مقارنة نسختين من القواعد (من غير منطقة/كوبون)', '',
      '| النسخة | enforcePrices | الأصناف | النتيجة | الرسالة |', '|---|---|---|---|---|', ...rows, ''].join('\n');
    fs.writeFileSync(path.join(__dirname, 'compare-results.md'), md);
    if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, md + '\n');
  }
})();
