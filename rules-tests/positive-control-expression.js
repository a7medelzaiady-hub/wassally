// Diagnostic-only positive control: deliberately exceed Firestore's 1000-expression budget.
// This is not a production rule and must never be merged to main.
const { initializeTestEnvironment, assertFails } = require('@firebase/rules-unit-testing');
const { getDoc, doc } = require('firebase/firestore');

async function main() {
  const comparisons = Array.from({ length: 1100 }, (_, i) => `request.auth.uid != 'blocked_${i}'`).join(' && ');
  const rules = `rules_version = '2'; service cloud.firestore { match /databases/{database}/documents { match /positive_control/{id} { allow read: if request.auth != null && (${comparisons}); } } }`;
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
