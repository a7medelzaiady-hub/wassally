// بيكتب قواعد نموذج priceMap التجريبية في ملف مؤقت (للاختبار بس). الاستخدام: node build-model-rules.js <variant> <out>
const fs = require('node:fs');
const { VARIANTS, buildModelRules } = require('./pricemap-model');
const [variant, out] = process.argv.slice(2);
if (!VARIANTS[variant] || !out) { console.error('usage: node build-model-rules.js <variant> <out>; variants:', Object.keys(VARIANTS).join(', ')); process.exit(2); }
fs.writeFileSync(out, buildModelRules(VARIANTS[variant]));
console.log('wrote', out, 'for', variant);
