// Diagnostic-only runtime expression-budget positive control. Never merge into main.
const { initializeTestEnvironment, assertFails } = require('@firebase/rules-unit-testing');
const { getDoc, doc } = require('firebase/firestore');

async function main() {
  // Small individual expressions avoid the compiler's 'too complex' rejection.
  // A chain of helper functions forces repeated evaluations at request time.
  const functions = Array.from({ length: 16 }, (_, i) => {
    const terms = Array.from({ length: 75 }, (_, j) => `request.auth.uid != 'blocked_${i}_${j}'`).join(' && ');
    return `function check${i}() { return ${terms}${i < 15 ? ` && check${i + 1}()` : ''}; }`;
  }).join('\n');
  const rules = `rules_version = '2'; service cloud.firestore { match /databases/{database}/documents { ${functions} match /positive_control/{id} { allow read: if request.auth != null && check0(); } } }`;
  const env = await initializeTestEnvironment({ projectId: 'demo-wasally', firestore: { rules } });
  try {
    const db = env.authenticatedContext('positive-control-user').firestore();
    let denial;
    try { denial = await assertFails(getDoc(doc(db, 'positive_control/test'))); }
    catch (error) { console.log('POSITIVE_CONTROL_ASSERT_FAIL=' + String(error)); process.exitCode = 1; return; }
    const message = [denial?.message, denial?.details, denial?.toString?.()].filter(Boolean).join(' ');
    console.log('POSITIVE_CONTROL_ERROR=' + message);
    console.log('POSITIVE_CONTROL_DETECTOR=' + (/maximum of 1000 expressions/i.test(message) ? 'HIT' : 'MISS'));
    if (!/maximum of 1000 expressions/i.test(message)) process.exitCode = 1;
  } finally { await env.cleanup(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
