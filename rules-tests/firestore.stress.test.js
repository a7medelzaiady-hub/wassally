const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
  writeBatch,
  serverTimestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-wasally';
const STORE_ID = 'stress-test-store';
const STAGES = [2, 10, 25, 50, 100, 250, 500];
const envMax = Number.parseInt(process.env.WASALLY_STRESS_MAX_CLIENTS || '500', 10);
const MAX_CLIENTS = Number.isFinite(envMax)
  ? Math.max(2, Math.min(envMax, 1000))
  : 500;

let testEnv;

before(async () => {
  // Fail closed: never run this suite against the real Wasally Firebase project.
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST ? true : false, true,
    'Firestore Emulator is required. Run with npm test; cloud Firestore is forbidden.');
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID,
    'The test project must be demo-wasally, never wasally-12259.');

  const rules = await readFile(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'stores', STORE_ID), {
      name: 'متجر اختبار الضغط',
      active: true,
    });
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

function orderBatch(context, uid, orderId) {
  const db = context.firestore();
  const batch = writeBatch(db);
  const orderRef = doc(db, 'orders', orderId);
  batch.set(orderRef, {
    userId: uid,
    customerName: 'عميل اختبار',
    notes: '',
    storeId: STORE_ID,
    storeName: 'متجر اختبار الضغط',
    items: [{ name: 'منتج اختبار', price: 100, qty: 1 }],
    subtotal: 100,
    deliveryFee: 10,
    total: 110,
    paymentMethod: 'cash',
    status: 'new',
    createdAt: serverTimestamp(),
  });
  batch.set(doc(db, 'orders', orderId, 'private', 'contact'), {
    userName: 'عميل اختبار',
    phone: '01012345678',
    address: 'شارع الاختبار، كفر الشيخ',
  });
  return batch.commit();
}

function percentile(values, p) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * p) - 1)];
}

test('staged concurrent order creation: 2 → 500 independent customers', {
  timeout: 180_000,
}, async () => {
  const stages = STAGES.filter((n) => n <= MAX_CLIENTS);
  if (stages[stages.length - 1] !== MAX_CLIENTS && MAX_CLIENTS > stages[stages.length - 1]) {
    stages.push(MAX_CLIENTS);
  }

  const summary = [];
  let sequence = 0;
  for (const count of stages) {
    const timings = [];
    const started = Date.now();
    const attempts = Array.from({ length: count }, async (_, index) => {
      const uid = `stress-customer-${sequence + index}`;
      const context = testEnv.authenticatedContext(uid);
      const orderId = `stress-order-${sequence + index}`;
      const t0 = performance.now();
      try {
        await assertSucceeds(orderBatch(context, uid, orderId));
        timings.push(performance.now() - t0);
        return { ok: true };
      } catch (error) {
        return { ok: false, error: String(error && error.message || error) };
      }
    });

    const results = await Promise.all(attempts);
    sequence += count;
    const succeeded = results.filter((r) => r.ok).length;
    const failed = results.length - succeeded;
    const row = {
      concurrentCustomers: count,
      succeeded,
      failed,
      wallClockMs: Date.now() - started,
      p50Ms: timings.length ? Math.round(percentile(timings, 0.50)) : null,
      p95Ms: timings.length ? Math.round(percentile(timings, 0.95)) : null,
    };
    summary.push(row);
    console.log('WASALLY_STRESS_STAGE ' + JSON.stringify(row));

    assert.equal(failed, 0,
      `Stage ${count} had failures: ${JSON.stringify(results.filter((r) => !r.ok).slice(0, 5))}`);
  }

  console.log('WASALLY_STRESS_SUMMARY ' + JSON.stringify(summary));
});

test('same idempotency order ID cannot be created twice; a new checkout may use a new ID', async () => {
  const uid = 'duplicate-submit-customer';
  const context = testEnv.authenticatedContext(uid);

  // Two overlapping retries for the same checkout share one stable order ID.
  const duplicateResults = await Promise.allSettled([
    orderBatch(context, uid, 'duplicate-checkout-stable-id'),
    orderBatch(context, uid, 'duplicate-checkout-stable-id'),
  ]);
  assert.equal(
    duplicateResults.filter((r) => r.status === 'fulfilled').length,
    1,
    'only one batch may create the order and its private contact document',
  );
  assert.equal(
    duplicateResults.filter((r) => r.status === 'rejected').length,
    1,
  );

  // A deliberately new checkout has a different persisted idempotency token.
  await assertSucceeds(orderBatch(context, uid, 'intentional-second-checkout'));
});

test('anonymous users cannot create orders', async () => {
  const context = testEnv.unauthenticatedContext();
  await assertFails(orderBatch(context, 'anonymous', 'anonymous-order'));
});
