// اختبارات قواعد Firestore (Emulator). لازم Node + firebase-tools. التشغيل من مجلد rules-tests:
//   npm install && npm test
// ملاحظة: اتكتبت من غير ما تتشغّل (البيئة اللي اتكتبت فيها مفيهاش Emulator). لو حصل فشل، راجع الاختبار
// والقاعدة الاتنين: ممكن الغلط في أي منهم.
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, getDoc, deleteDoc, writeBatch, serverTimestamp, increment, deleteField } = require('firebase/firestore');

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-wasally',
    firestore: { rules: fs.readFileSync(process.env.RULES_FILE || path.join(__dirname, '..', 'firestore.rules'), 'utf8') },
  });
});
after(async () => env && env.cleanup());

const store = 'shop1';
const baseOrder = (uid, over = {}) => ({
  userId: uid, customerName: 'Ali',
  notes: '', storeId: store, storeName: 'S', items: [{ name: 'p', price: 10, qty: 2, productId: 'p1' }],
  subtotal: 20, deliveryFee: 20, total: 40, paymentMethod: 'cash', status: 'new', createdAt: serverTimestamp(), ...over,
});

async function seed(extra = async () => {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins/admin1'), { name: 'A' });
    await setDoc(doc(db, 'couriers/cour1'), { name: 'C', active: true });
    await setDoc(doc(db, 'storeOwners/owner1'), { name: 'O', storeId: store, active: true });
    await setDoc(doc(db, 'storeOwners/owner2'), { name: 'O2', storeId: 'shop2', active: true });
    await setDoc(doc(db, 'stores/shop1'), { name: 'S', active: true, time: '20-30', order: 1, rating: 4 });
    await setDoc(doc(db, 'stores/shop2'), { name: 'S2', active: true, time: '20-30', order: 2, rating: 4 });
    await setDoc(doc(db, `stores/${store}/products/p1`), { name: 'p', price: 10 });
    await setDoc(doc(db, 'orders/o1'), { ...baseOrder('cust1'), createdAt: new Date() });
    await setDoc(doc(db, 'orders/o1/private/contact'), { userName: 'Ali Hassan', phone: '01012345678', address: 'عنوان تجريبي 1' });
    await extra(db);
  });
}
const as = (uid, claims = {}) => env.authenticatedContext(uid, { email: 'a@x.com', ...claims }).firestore();

beforeEach(() => seed());

test('users: whitelist يمنع حقول غريبة', async () => {
  const db = as('cust1');
  await assertSucceeds(setDoc(doc(db, 'users/cust1'), { name: 'Ali', phone: '010', address: 'x' }, { merge: true }));
  await assertFails(setDoc(doc(db, 'users/cust1'), { wallet: 999 }, { merge: true }));
  await assertFails(setDoc(doc(db, 'users/cust1'), { role: 'admin' }, { merge: true }));
});

test('orders: إنشاء عادي ينجح (الأسعار غير مفعّلة)', async () => {
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/new1'), baseOrder('cust1')));
});

test('orderLimits: العميل يكتب مستنده هو بس بوقت السيرفر، ومفيش قراءة ولا حذف', async () => {
  const db = as('cust1');
  await assertSucceeds(setDoc(doc(db, 'orderLimits/cust1'), { lastAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, 'orderLimits/cust2'), { lastAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, 'orderLimits/cust1'), { lastAt: new Date() }));
  await assertFails(setDoc(doc(db, 'orderLimits/cust1'), { lastAt: serverTimestamp(), x: 1 }));
  await assertFails(getDoc(doc(db, 'orderLimits/cust1')));
  await assertFails(deleteDoc(doc(db, 'orderLimits/cust1')));
});

test('orderRateLimit: مقفول افتراضيًا، ومفعّل يفرض فاصل 20 ثانية بين طلبين', async () => {
  const placeOrder = (db, id, withLimit = true) => {
    const b = writeBatch(db);
    b.set(doc(db, `orders/${id}`), baseOrder('cust1'));
    if (withLimit) b.set(doc(db, 'orderLimits/cust1'), { lastAt: serverTimestamp() });
    return b.commit();
  };
  const cust = as('cust1');

  // المفتاح مقفول: الطلب بدون مستند الحد ينجح (توافق مع النسخ القديمة).
  await assertSucceeds(placeOrder(cust, 'rl0', false));

  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'app_info/security'), { orderRateLimit: true });
  });

  // مفعّل: لازم يكتب مستند الحد مع الطلب.
  await assertFails(placeOrder(cust, 'rl1', false));
  await assertSucceeds(placeOrder(cust, 'rl1'));
  // طلب تاني فورًا يُرفض.
  await assertFails(placeOrder(cust, 'rl2'));

  // بعد انتهاء الفاصل (آخر طلب أقدم من 20 ثانية) ينجح.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'orderLimits/cust1'), { lastAt: new Date(Date.now() - 60_000) });
  });
  await assertSucceeds(placeOrder(cust, 'rl3'));

  // عميل تاني مستقل ما يتأثرش، وما ينفعش يكتب مستند الحد باسم غيره.
  const other = as('cust2');
  const b = writeBatch(other);
  b.set(doc(other, 'orders/rl4'), baseOrder('cust2'));
  b.set(doc(other, 'orderLimits/cust2'), { lastAt: serverTimestamp() });
  await assertSucceeds(b.commit());
  const evil = writeBatch(other);
  evil.set(doc(other, 'orders/rl5'), baseOrder('cust2'));
  evil.set(doc(other, 'orderLimits/cust1'), { lastAt: serverTimestamp() });
  await assertFails(evil.commit());
});

// المراجعة على أسعار الكتالوج بتتم عند الأدمن (verifiedTotal)، والقواعد بتتأكد من اتساق الأرقام بس:
// total = subtotal + deliveryFee - discount.
test('إجمالي الطلب: غير المتطابق حسابيًا يُرفض، والمتطابق ينجح', async () => {
  await assertFails(setDoc(doc(as('cust1'), 'orders/bad1'), baseOrder('cust1', { total: 41 })));
  await assertFails(setDoc(doc(as('cust1'), 'orders/bad2'), baseOrder('cust1', { total: 10 })));
  await assertFails(setDoc(doc(as('cust1'), 'orders/bad3'), baseOrder('cust1', { subtotal: 0.02, total: 10.02, deliveryFee: 20 })));
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/ok'), baseOrder('cust1')));
});

const actorUidOf = (role) => (role === 'admin' ? 'admin1' : role === 'courier' ? 'cour1' : role === 'owner' ? 'owner1' : 'cust1');
const changeStatus = (db, orderId, from, to, role) => {
  const b = writeBatch(db);
  b.update(doc(db, `orders/${orderId}`), {
    status: to,
    ...(to === 'on_the_way' ? { pickedUpAt: serverTimestamp() } : {}),
  });
  b.set(doc(db, `orders/${orderId}/statusHistory/${to}`), {
    from, to, actorUid: actorUidOf(role), actorRole: role, at: serverTimestamp(),
  });
  return b.commit();
};

test('statusHistory: الأدمن يغيّر الحالة مع سجل', async () => {
  await assertSucceeds(changeStatus(as('admin1'), 'o1', 'new', 'preparing', 'admin'));
});

test('statusHistory: عميل يدّعي دور admin يُرفض', async () => {
  await assertFails(changeStatus(as('cust1'), 'o1', 'new', 'cancelled', 'admin'));
});

test('statusHistory: لا تعديل ولا حذف', async () => {
  await changeStatus(as('admin1'), 'o1', 'new', 'preparing', 'admin');
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1/statusHistory/preparing'), { from: 'x' }));
});

test('order lifecycle: تغيير الحالة بلا سجل أو بتخطي مرحلة أو رجوع للخلف يُرفض افتراضيًا', async () => {
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1'), { status: 'preparing' }));
  await assertFails(changeStatus(as('admin1'), 'o1', 'new', 'on_the_way', 'admin'));
  await assertSucceeds(changeStatus(as('admin1'), 'o1', 'new', 'preparing', 'admin'));
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), { status: 'preparing' }));
  await assertFails(changeStatus(as('admin1'), 'o1', 'preparing', 'new', 'admin'));
});

test('order lifecycle: اعتماد الإجمالي دون تغيير الحالة يظل مسموحًا', async () => {
  await assertSucceeds(updateDoc(doc(as('admin1'), 'orders/o1'), { status: 'new', verifiedTotal: 30, verifiedAt: serverTimestamp() }));
});

test('customer: يقدر يعدّل الطلب وبيانات التواصل أثناء التجهيز قبل تعيين المندوب', async () => {
  await prepareOrderWithFeed();
  const db = as('cust1');
  await assertSucceeds(customerEditBatch(db, 'o1').commit());
  const feed = (await getDoc(doc(as('cour1'), 'courier_available_orders/o1'))).data();
  assert.equal(feed.total, 50);
  assert.equal(feed.items[0].qty, 3);
  await assertFails(deleteDoc(doc(db, 'orders/o1/private/contact')));
});

async function prepareOrderWithFeed(orderId = 'o1') {
  const db = as('owner1');
  const original = await getDoc(doc(db, `orders/${orderId}`));
  const createdAt = original.data().createdAt;
  const b = writeBatch(db);
  b.update(doc(db, `orders/${orderId}`), { status: 'preparing' });
  b.set(doc(db, `orders/${orderId}/statusHistory/preparing`), {
    from: 'new', to: 'preparing', actorUid: 'owner1', actorRole: 'owner', at: serverTimestamp(),
  });
  b.set(doc(db, `courier_available_orders/${orderId}`), {
    storeId: 'shop1', storeName: 'S', area: '', items: [{ name: 'p', price: 10, qty: 2, productId: 'p1' }],
    subtotal: 20, deliveryFee: 20, discount: 0, total: 40, status: 'preparing',
    createdAt,
  });
  await assertSucceeds(b.commit());
}

function customerEditBatch(db, orderId, { qty = 3, address = 'عنوان تجريبي 2' } = {}) {
  const b = writeBatch(db);
  b.update(doc(db, `orders/${orderId}`), {
    items: [{ name: 'p', price: 10, qty, productId: 'p1' }],
    subtotal: qty * 10, total: qty * 10 + 20, editedAt: serverTimestamp(),
  });
  b.update(doc(db, `orders/${orderId}/private/contact`), { address });
  b.update(doc(db, `courier_available_orders/${orderId}`), {
    items: [{ name: 'p', price: 10, qty, productId: 'p1' }],
    subtotal: qty * 10, total: qty * 10 + 20,
  });
  return b;
}

test('feed sync: تعديل العميل يحدّث الطلب والـ feed ذريًا دون PII', async () => {
  await prepareOrderWithFeed();
  const db = as('cust1');
  await assertSucceeds(customerEditBatch(db, 'o1').commit());
  const feed = (await getDoc(doc(as('cour1'), 'courier_available_orders/o1'))).data();
  assert.equal(feed.subtotal, 30);
  assert.equal(feed.total, 50);
  assert.equal(feed.items[0].qty, 3);
  for (const key of ['userId', 'userName', 'phone', 'address', 'courierPhone', 'customerName']) {
    assert.equal(Object.hasOwn(feed, key), false, `feed must not expose ${key}`);
  }
});

test('feed sync: يمنع تحديثًا غير مطابق أو كتابة feed من مستخدم آخر', async () => {
  await prepareOrderWithFeed();
  const db = as('cust1');
  const mismatch = writeBatch(db);
  mismatch.update(doc(db, 'orders/o1'), {
    items: [{ name: 'p', price: 10, qty: 4, productId: 'p1' }],
    subtotal: 40, total: 60, editedAt: serverTimestamp(),
  });
  mismatch.update(doc(db, 'orders/o1/private/contact'), { address: 'عنوان تجريبي 3' });
  mismatch.update(doc(db, 'courier_available_orders/o1'), { total: 999 });
  await assertFails(mismatch.commit());

  const strangerDb = as('cust2');
  const stranger = writeBatch(strangerDb);
  stranger.update(doc(strangerDb, 'courier_available_orders/o1'), { total: 60 });
  await assertFails(stranger.commit());
});

test('claim/edit race: التزامن الفعلي لا يترك feed قديمًا أو بيانات جزئية', async () => {
  const courierDb = as('cour1');
  for (let i = 0; i < 10; i++) {
    const orderId = `parallel-${i}`;
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const createdAt = new Date();
      await setDoc(doc(db, `orders/${orderId}`), {
        ...baseOrder('cust1', { status: 'preparing', createdAt }),
      });
      await setDoc(doc(db, `orders/${orderId}/private/contact`), {
        userName: 'Ali Hassan', phone: '01012345678', address: 'العنوان الأصلي',
      });
      await setDoc(doc(db, `courier_available_orders/${orderId}`), {
        storeId: 'shop1', storeName: 'S', area: '',
        items: [{ name: 'p', price: 10, qty: 2, productId: 'p1' }],
        subtotal: 20, deliveryFee: 20, discount: 0, total: 40,
        status: 'preparing', createdAt,
      });
    });
    const customerDb = as('cust1');
    const edit = customerEditBatch(customerDb, orderId);
    const claim = writeBatch(courierDb);
    claim.update(doc(courierDb, `orders/${orderId}`), {
      courierId: 'cour1', courierName: 'C', courierPhone: '01012345678', courierAt: serverTimestamp(),
    });
    claim.delete(doc(courierDb, `courier_available_orders/${orderId}`));
    const [editResult, claimResult] = await Promise.allSettled([edit.commit(), claim.commit()]);
    assert.equal(claimResult.status, 'fulfilled');
    const finalOrder = (await getDoc(doc(courierDb, `orders/${orderId}`))).data();
    const finalContact = (await getDoc(doc(courierDb, `orders/${orderId}/private/contact`))).data();
    assert.equal(finalOrder.courierId, 'cour1');
    assert.equal((await getDoc(doc(courierDb, `courier_available_orders/${orderId}`))).exists(), false);
    if (editResult.status === 'fulfilled') {
      assert.equal(finalOrder.total, 50);
      assert.equal(finalContact.address, 'عنوان تجريبي 2');
    } else {
      assert.equal(finalOrder.total, 40);
      assert.equal(finalContact.address, 'العنوان الأصلي');
    }
  }
});

test('claim/edit race: الاستلام أولًا يمنع التعديل بالكامل', async () => {
  await prepareOrderWithFeed();
  const courierDb = as('cour1');
  const claim = writeBatch(courierDb);
  claim.update(doc(courierDb, 'orders/o1'), {
    courierId: 'cour1', courierName: 'C', courierPhone: '01012345678', courierAt: serverTimestamp(),
  });
  claim.delete(doc(courierDb, 'courier_available_orders/o1'));
  await assertSucceeds(claim.commit());
  await assertFails(customerEditBatch(as('cust1'), 'o1').commit());
  const order = (await getDoc(doc(courierDb, 'orders/o1'))).data();
  assert.equal(order.courierId, 'cour1');
  assert.equal(order.total, 40);
  assert.equal((await getDoc(doc(courierDb, 'courier_available_orders/o1'))).exists(), false);
});

test('claim/edit race: التعديل أولًا يحدّث feed ثم الاستلام يزيله ذريًا', async () => {
  await prepareOrderWithFeed();
  const customerDb = as('cust1');
  await assertSucceeds(customerEditBatch(customerDb, 'o1').commit());
  const courierDb = as('cour1');
  const claim = writeBatch(courierDb);
  claim.update(doc(courierDb, 'orders/o1'), {
    courierId: 'cour1', courierName: 'C', courierPhone: '01012345678', courierAt: serverTimestamp(),
  });
  claim.delete(doc(courierDb, 'courier_available_orders/o1'));
  await assertSucceeds(claim.commit());
  const order = (await getDoc(doc(courierDb, 'orders/o1'))).data();
  assert.equal(order.courierId, 'cour1');
  assert.equal(order.total, 50);
  assert.equal((await getDoc(doc(courierDb, 'courier_available_orders/o1'))).exists(), false);
});


test('customer: تعديل الطلب وبيانات التواصل يُرفض بعد تعيين المندوب', async () => {
  await assertSucceeds(changeStatus(as('owner1'), 'o1', 'new', 'preparing', 'owner'));
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), {
      courierId: 'cour1', courierName: 'C', courierPhone: '01012345678',
    }));
  const db = as('cust1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), {
    items: [{ name: 'p', price: 10, qty: 3, productId: 'p1' }],
    subtotal: 30, total: 50, editedAt: serverTimestamp(),
  });
  b.update(doc(db, 'orders/o1/private/contact'), { address: 'عنوان تجريبي 3' });
  await assertFails(b.commit());
});

test('notifications: أدمن ينشئ، عميل يقرأ إشعاراته فقط', async () => {
  const n = { userId: 'cust1', title: 't', body: 'b', orderId: 'o1', read: false, createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as('admin1'), 'notifications/n1'), n));
  await assertFails(setDoc(doc(as('cust1'), 'notifications/n2'), n));
  await assertSucceeds(getDoc(doc(as('cust1'), 'notifications/n1')));
  await assertFails(getDoc(doc(as('cust2'), 'notifications/n1')));
});

async function deliveredWithCourier() {
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), { status: 'delivered', courierId: 'cour1', pickedUpAt: new Date() }));
}
const rate = (db, rating, orderId = 'o1') => {
  const b = writeBatch(db);
  const rid = `${orderId}_courier`;
  b.set(doc(db, `reviews/${rid}`), { orderId, courierId: 'cour1', userId: 'cust1', rating, comment: '', createdAt: serverTimestamp() });
  b.update(doc(db, 'couriers/cour1'), { ratingSum: increment(rating), ratingCount: increment(1), lastReviewId: rid });
  return b.commit();
};

test('reviews: تقييم طلب متسلَّم ينجح مرة واحدة فقط', async () => {
  await deliveredWithCourier();
  await assertSucceeds(rate(as('cust1'), 5));
  await assertFails(rate(as('cust1'), 5));
});

test('reviews: طلب غير متسلَّم أو تقييم 6 أو طلب شخص آخر يُرفض', async () => {
  await assertFails(rate(as('cust1'), 5)); // لسه new
  await deliveredWithCourier();
  await assertFails(rate(as('cust1'), 6));
  await assertFails(rate(as('cust2'), 5));
});

test('couriers: عميل لا يزوّد الإحصائية بدون تقييم', async () => {
  await assertFails(updateDoc(doc(as('cust1'), 'couriers/cour1'), { ratingSum: 50, ratingCount: 10, lastReviewId: 'fake' }));
});

const customerReview = (role, reviewerId, over = {}) => ({
  orderId: 'o1',
  customerId: 'cust1',
  reviewerId,
  reviewerRole: role,
  storeId: store,
  rating: 2,
  reason: 'unavailable',
  comment: 'لم يرد عند الوصول',
  createdAt: serverTimestamp(),
  ...over,
});

test('customer reviews: المندوب وصاحب المحل يقيّمان العميل بعد التسليم مرة واحدة', async () => {
  await setOrder({ status: 'delivered', courierId: 'cour1', deliveredBy: 'cour1' });
  await assertSucceeds(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1'),
  ));
  await assertFails(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1'),
  ));
  await assertSucceeds(setDoc(
    doc(as('owner1'), 'customer_reviews/o1_store_owner'),
    customerReview('store_owner', 'owner1', { reason: 'positive', rating: 5 }),
  ));
  await assertSucceeds(getDoc(doc(as('admin1'), 'customer_reviews/o1_courier')));
  await assertFails(getDoc(doc(as('cust1'), 'customer_reviews/o1_courier')));
});

test('customer reviews: يمنع التقييم المزور أو قبل التسليم أو من طرف غير مشارك', async () => {
  await assertFails(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1'),
  ));
  await setOrder({ status: 'delivered', courierId: 'cour1', deliveredBy: 'cour1' });
  await assertFails(setDoc(
    doc(as('cust1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cust1'),
  ));
  await assertFails(setDoc(
    doc(as('cour2'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour2'),
  ));
  await assertFails(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1', { rating: 6 }),
  ));
  await assertFails(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1', { reason: 'invented' }),
  ));
  await assertFails(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1', { rating: 2, reason: 'positive' }),
  ));
});

test('customer restrictions: الإدارة فقط تفرض تقييدًا مؤقتًا، والقواعد تمنع الطلب حتى رفعه', async () => {
  const restriction = {
    customerId: 'cust1',
    active: true,
    reason: 'تكرار رفض الاستلام بعد تأكيد الطلب',
    sourceOrderId: 'o1',
    createdAt: serverTimestamp(),
    createdBy: 'admin1',
    expiresAt: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000),
  };
  await assertFails(setDoc(doc(as('cust1'), 'customer_restrictions/cust1'), restriction));
  await assertSucceeds(setDoc(doc(as('admin1'), 'customer_restrictions/cust1'), restriction));
  await assertFails(setDoc(doc(as('cust1'), 'orders/restricted-order'), baseOrder('cust1')));
  await assertSucceeds(getDoc(doc(as('cust1'), 'customer_restrictions/cust1')));
  await assertFails(getDoc(doc(as('cust2'), 'customer_restrictions/cust1')));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'customer_restrictions/cust1'), {
    active: false,
    clearedAt: serverTimestamp(),
    clearedBy: 'admin1',
  }));
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/after-lift'), baseOrder('cust1')));
});

// ───────────── المرحلة 4: صاحب المحل ─────────────
test('owner: يقرأ طلبات محله فقط (بالاستعلام والقراءة المباشرة)', async () => {
  await env.withSecurityRulesDisabled((c) =>
    setDoc(doc(c.firestore(), 'orders/o2'), { ...baseOrder('cust1', { storeId: 'shop2' }), createdAt: new Date() }));
  await assertSucceeds(getDoc(doc(as('owner1'), 'orders/o1')));
  await assertFails(getDoc(doc(as('owner1'), 'orders/o2')));
  const { query, collection, where, getDocs } = require('firebase/firestore');
  await assertSucceeds(getDocs(query(collection(as('owner1'), 'orders'), where('storeId', '==', store))));
  await assertFails(getDocs(query(collection(as('owner1'), 'orders'), where('storeId', '==', 'shop2'))));
  await assertFails(getDocs(collection(as('owner1'), 'orders')));
});

test('owner: يبدأ التجهيز ويرفض طلبًا جديدًا مع سجل الحالة', async () => {
  await assertSucceeds(changeStatus(as('owner1'), 'o1', 'new', 'preparing', 'owner'));
  await seed();
  await assertSucceeds(changeStatus(as('owner1'), 'o1', 'new', 'cancelled', 'owner'));
});

test('صنف غير متاح: المحل يعلّم، والعميل يكمّل من غيره، وبعدها المحل يبدأ التجهيز', async () => {
  const owner = as('owner1');
  const cust = as('cust1');
  // المحل يعلّم الصنف. محل تاني أو العميل ما يقدروش.
  await assertFails(updateDoc(doc(as('owner2'), 'orders/o1'), { unavailableItems: ['p'] }));
  await assertFails(updateDoc(doc(cust, 'orders/o1'), { unavailableItems: ['p'] }));
  await assertFails(updateDoc(doc(owner, 'orders/o1'), { unavailableItems: [] }));
  await assertFails(updateDoc(doc(owner, 'orders/o1'), { unavailableItems: 'p' }));
  await assertSucceeds(updateDoc(doc(owner, 'orders/o1'), { unavailableItems: ['p'] }));
  // مينفعش يبدأ التجهيز وهو معلّم، لكن الرفض متاح.
  await assertFails(changeStatus(owner, 'o1', 'new', 'preparing', 'owner'));
  // العميل لازم يشيل العلامة في نفس التعديل.
  const edit = (db, over) => {
    const b = writeBatch(db);
    b.update(doc(db, 'orders/o1'), {
      items: [{ name: 'q', price: 10, qty: 1, productId: 'p2' }],
      subtotal: 10, total: 30, editedAt: serverTimestamp(), ...over,
    });
    b.update(doc(db, 'orders/o1/private/contact'), { address: 'عنوان تجريبي 3' });
    return b;
  };
  await assertFails(edit(cust, {}).commit());
  await assertSucceeds(edit(cust, { unavailableItems: deleteField() }).commit());
  const after = (await getDoc(doc(owner, 'orders/o1'))).data();
  assert.equal('unavailableItems' in after, false);
  await assertSucceeds(changeStatus(owner, 'o1', 'new', 'preparing', 'owner'));
});

test('صنف غير متاح: المحل يرفض الطلب المعلّم، ولا يعلّم طلبًا اتقبل', async () => {
  const owner = as('owner1');
  await assertSucceeds(updateDoc(doc(owner, 'orders/o1'), { unavailableItems: ['p'] }));
  await assertSucceeds(changeStatus(owner, 'o1', 'new', 'cancelled', 'owner'));
  await seed();
  await assertSucceeds(changeStatus(owner, 'o1', 'new', 'preparing', 'owner'));
  await assertFails(updateDoc(doc(owner, 'orders/o1'), { unavailableItems: ['p'] }));
});

test('owner: ما يقدرش يسلّم أو يرجّع للخلف أو يغيّر طلب محل تاني', async () => {
  await assertFails(changeStatus(as('owner1'), 'o1', 'new', 'delivered', 'owner'));
  await assertFails(changeStatus(as('owner1'), 'o1', 'new', 'on_the_way', 'owner'));
  await assertFails(changeStatus(as('owner2'), 'o1', 'new', 'preparing', 'owner'));
  await assertSucceeds(changeStatus(as('owner1'), 'o1', 'new', 'preparing', 'owner'));
  await assertFails(changeStatus(as('owner1'), 'o1', 'preparing', 'cancelled', 'owner'));
});

test('owner: ما يعيّنش مندوب ولا يعتمد إجمالي ولا يعدّل محتوى الطلب', async () => {
  const db = as('owner1');
  await assertFails(updateDoc(doc(db, 'orders/o1'), { courierId: 'cour1', courierName: 'C', courierPhone: '1' }));
  await assertFails(updateDoc(doc(db, 'orders/o1'), { status: 'new', verifiedTotal: 5, verifiedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'orders/o1'), { total: 1 }));
});

test('owner: سجل الحالة بدور owner لعميل أو لمحل تاني يُرفض', async () => {
  await assertFails(changeStatus(as('cust1'), 'o1', 'new', 'preparing', 'owner'));
  await assertFails(changeStatus(as('owner2'), 'o1', 'new', 'preparing', 'owner'));
});

test('owner: سجل الحالة إلزامي ومحل موقوف (active=false) يفقد الصلاحية', async () => {
  await assertFails(updateDoc(doc(as('owner1'), 'orders/o1'), { status: 'preparing' }));
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'storeOwners/owner1'), { active: false }));
  await assertFails(changeStatus(as('owner1'), 'o1', 'new', 'preparing', 'owner'));
  await assertFails(getDoc(doc(as('owner1'), 'orders/o1')));
});

test('owner: يعدّل حقول التشغيل في محله فقط', async () => {
  const db = as('owner1');
  await assertSucceeds(updateDoc(doc(db, 'stores/shop1'), { active: false, time: '30-40', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'stores/shop1'), { name: 'غيّرت الاسم' }));
  await assertFails(updateDoc(doc(db, 'stores/shop1'), { rating: 5 }));
  await assertFails(updateDoc(doc(db, 'stores/shop1'), { order: 0 }));
  await assertFails(updateDoc(doc(db, 'stores/shop2'), { active: false }));
  await assertFails(setDoc(doc(db, 'stores/newShop'), { name: 'x', active: true, time: '1' }));
});

test('owner: يضيف ويعدّل ويحذف أصناف محله فقط، وبحقول سليمة', async () => {
  const db = as('owner1');
  const p = { name: 'صنف', price: 25, image: '', isAvailable: true, available: true, createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(db, 'stores/shop1/products/p2'), p));
  await assertSucceeds(updateDoc(doc(db, 'stores/shop1/products/p2'), { price: 30, available: false, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, 'stores/shop1/products/p3'), { ...p, price: -1 }));
  await assertFails(setDoc(doc(db, 'stores/shop1/products/p4'), { ...p, price: 99999 }));
  await assertFails(setDoc(doc(db, 'stores/shop1/products/p5'), { ...p, owner: 'x' }));
  await assertFails(setDoc(doc(db, 'stores/shop2/products/p6'), p));
  await assertSucceeds(deleteDoc(doc(db, 'stores/shop1/products/p2')));
  await assertFails(deleteDoc(doc(db, 'stores/shop2/products/p1')));
});

test('owner: عروض الأصناف (سعر قبل الخصم، نص حر، تاريخ انتهاء) بقيم سليمة فقط', async () => {
  const db = as('owner1');
  const ref = (id) => doc(db, `stores/shop1/products/${id}`);
  const p = { name: 'صنف', price: 20, isAvailable: true, available: true, createdAt: serverTimestamp() };
  const ends = new Date(Date.now() + 86400000);
  await assertSucceeds(setDoc(ref('o1'), { ...p, oldPrice: 25, offerEndsAt: ends }));
  await assertSucceeds(setDoc(ref('o2'), { ...p, offerText: '2+1 مجانًا', offerEndsAt: ends }));
  await assertSucceeds(updateDoc(ref('o2'), { offerText: 'هدية مع الطلب', updatedAt: serverTimestamp() }));
  await assertFails(setDoc(ref('o3'), { ...p, oldPrice: 15 })); // السعر قبل الخصم لازم يكون أكبر
  await assertFails(setDoc(ref('o4'), { ...p, offerText: '' }));
  await assertFails(setDoc(ref('o5'), { ...p, offerText: 'x'.repeat(121) }));
  await assertFails(setDoc(ref('o6'), { ...p, offerText: 5 }));
  await assertFails(setDoc(ref('o7'), { ...p, offerEndsAt: 'غدًا' }));
  await assertFails(setDoc(doc(as('owner2'), 'stores/shop1/products/o8'), { ...p, offerText: 'x' }));
});

test('owner: عميل عادي ما يكتبش أصناف', async () => {
  await assertFails(setDoc(doc(as('cust1'), 'stores/shop1/products/px'), { name: 'x', price: 5 }));
});

test('owner: يرفع نسخة الكتالوج +1 فقط، والعميل لا', async () => {
  const v = { version: 1, updatedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as('owner1'), 'app_info/catalog'), v, { merge: true }));
  await assertFails(setDoc(doc(as('cust1'), 'app_info/catalog'), v, { merge: true }));
});

test('owner: يبعت إشعار للعميل، وما يكتبش في storeOwners أو admins', async () => {
  const n = { userId: 'cust1', title: 't', body: 'b', orderId: 'o1', read: false, createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as('owner1'), 'notifications/n9'), n));
  await assertFails(setDoc(doc(as('owner1'), 'storeOwners/owner1'), { name: 'x', storeId: 'shop2', active: true }));
  await assertFails(updateDoc(doc(as('owner1'), 'storeOwners/owner1'), { storeId: 'shop2' }));
  await assertFails(setDoc(doc(as('cust1'), 'storeOwners/cust1'), { name: 'x', storeId: store, active: true }));
  await assertSucceeds(getDoc(doc(as('owner1'), 'storeOwners/owner1')));
  await assertFails(getDoc(doc(as('owner2'), 'storeOwners/owner1')));
});

test('admin: يضيف صاحب محل ويقرأ القائمة، ويظل يتحكم في المحلات والأصناف', async () => {
  const db = as('admin1');
  await assertSucceeds(setDoc(doc(db, 'storeOwners/owner3'), { name: 'N', storeId: 'shop2', active: true }));
  await assertFails(setDoc(doc(db, 'storeOwners/owner4'), { name: 'N', storeId: 'shop2', active: true, role: 'admin' }));
  await assertSucceeds(updateDoc(doc(db, 'stores/shop1'), { name: 'اسم جديد', rating: 3 }));
  await assertSucceeds(setDoc(doc(db, 'stores/shop1/products/pa'), { name: 'x', price: 5, anything: 1 }));
});

test('courier lifecycle: لا يبدأ المندوب الرحلة قبل تجهيز المحل وتأكيد الجاهزية', async () => {
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), { courierId: 'cour1', pickedUpAt: new Date() }));
  // لا يمكن تخطي قبول المحل والتجهيز.
  await assertFails(changeStatus(as('cour1'), 'o1', 'new', 'on_the_way', 'courier'));
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), { status: 'preparing' }));
  // حتى بعد التجهيز، لا يبدأ قبل ready=true.
  await assertFails(changeStatus(as('cour1'), 'o1', 'preparing', 'on_the_way', 'courier'));
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), { ready: true }));
  await assertSucceeds(changeStatus(as('cour1'), 'o1', 'preparing', 'on_the_way', 'courier'));
});

// ───────────── إحصائيات المندوب، التقدّم على طلب، طلبات الانضمام، الشكاوى ─────────────
const { query, collection, where, getDocs } = require('firebase/firestore');
const setOrder = (patch) => env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'orders/o1'), patch));

const deliveryIssueData = (over = {}) => ({
  orderId: 'o1',
  courierId: 'cour1',
  customerId: 'cust1',
  storeId: store,
  reason: 'no_answer',
  note: 'وصلت واتصلت ولم يرد العميل',
  contactAttempted: true,
  status: 'open',
  createdBy: 'cour1',
  createdAt: serverTimestamp(),
  ...over,
});

test('delivery issue: الوصول والبلاغ يتسجلان ذريًا ولا يمكن التسليم مع بلاغ مفتوح', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date(), courierArrivedAt: new Date() });
  const courier = as('cour1');
  const orderRef = doc(courier, 'orders/o1');
  await assertSucceeds(updateDoc(orderRef, { courierArrivedAt: serverTimestamp() }));
  const batch = writeBatch(courier);
  batch.set(doc(courier, 'delivery_issues/issue1'), deliveryIssueData());
  batch.update(orderRef, { activeDeliveryIssueId: 'issue1' });
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(doc(as('cust1'), 'delivery_issues/issue1')));
  await assertFails(getDoc(doc(as('cust2'), 'delivery_issues/issue1')));
  await assertFails(deliver(courier, 'courier', stamp()));
  await assertSucceeds(getDoc(doc(as('admin1'), 'delivery_issues/issue1')));
});

test('delivery issue: لا بلاغ قبل تسجيل الوصول أو دون محاولة تواصل أو من مندوب آخر', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date() });
  await assertFails(setDoc(
    doc(as('cour1'), 'delivery_issues/no-arrival'),
    deliveryIssueData(),
  ));
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), { courierArrivedAt: new Date() }));
  await assertFails(setDoc(
    doc(as('cour1'), 'delivery_issues/no-contact'),
    deliveryIssueData({ contactAttempted: false }),
  ));
  await assertFails(setDoc(
    doc(as('cour2'), 'delivery_issues/wrong-courier'),
    deliveryIssueData({ courierId: 'cour2', createdBy: 'cour2' }),
  ));
});

test('delivery issue: الإدارة تختار إعادة المحاولة ويستأنف المندوب بأمان', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date(), courierArrivedAt: new Date() });
  const courier = as('cour1');
  const batch = writeBatch(courier);
  batch.set(doc(courier, 'delivery_issues/retry1'), deliveryIssueData());
  batch.update(doc(courier, 'orders/o1'), { activeDeliveryIssueId: 'retry1' });
  await assertSucceeds(batch.commit());
  await assertSucceeds(updateDoc(doc(as('admin1'), 'delivery_issues/retry1'), {
    status: 'retry',
    adminDecision: 'تم التواصل مع العميل ويمكن إعادة المحاولة',
    updatedAt: serverTimestamp(),
    updatedBy: 'admin1',
  }));
  const resume = writeBatch(courier);
  resume.update(doc(courier, 'delivery_issues/retry1'), {
    status: 'resolved',
    courierResumedAt: serverTimestamp(),
    courierResumedBy: 'cour1',
  });
  resume.update(doc(courier, 'orders/o1'), { activeDeliveryIssueId: deleteField() });
  await assertSucceeds(resume.commit());
  await assertSucceeds(deliver(courier, 'courier', stamp()));
});

test('delivery issue: الإرجاع للمحل يجب تأكيده قبل أن تغلق الإدارة الطلب', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date(), courierArrivedAt: new Date() });
  const courier = as('cour1');
  const batch = writeBatch(courier);
  batch.set(doc(courier, 'delivery_issues/return1'), deliveryIssueData());
  batch.update(doc(courier, 'orders/o1'), { activeDeliveryIssueId: 'return1' });
  await assertSucceeds(batch.commit());
  await assertSucceeds(updateDoc(doc(as('admin1'), 'delivery_issues/return1'), {
    status: 'return_to_store',
    adminDecision: 'أعد الطلب إلى المحل',
    updatedAt: serverTimestamp(),
    updatedBy: 'admin1',
  }));
  await assertSucceeds(updateDoc(doc(courier, 'delivery_issues/return1'), {
    status: 'returned_to_store',
    returnedAt: serverTimestamp(),
    returnedBy: 'cour1',
  }));
  const closeAttempt = writeBatch(as('admin1'));
  closeAttempt.update(doc(as('admin1'), 'orders/o1'), {
    status: 'cancelled',
    activeDeliveryIssueId: deleteField(),
    lastDeliveryIssueId: 'return1',
  });
  closeAttempt.set(doc(as('admin1'), 'orders/o1/statusHistory/cancelled'), {
    from: 'on_the_way', to: 'cancelled', actorUid: 'admin1', actorRole: 'admin', at: serverTimestamp(),
  });
  await assertFails(closeAttempt.commit()); // لا يكفي تأكيد المندوب وحده.
  await assertSucceeds(updateDoc(doc(as('owner1'), 'delivery_issues/return1'), {
    status: 'store_confirmed_return',
    storeReceivedAt: serverTimestamp(),
    storeReceivedBy: 'owner1',
  }));
  const close = writeBatch(as('admin1'));
  close.update(doc(as('admin1'), 'orders/o1'), {
    status: 'cancelled',
    activeDeliveryIssueId: deleteField(),
    lastDeliveryIssueId: 'return1',
  });
  close.set(doc(as('admin1'), 'orders/o1/statusHistory/cancelled'), {
    from: 'on_the_way', to: 'cancelled', actorUid: 'admin1', actorRole: 'admin', at: serverTimestamp(),
  });
  await assertSucceeds(close.commit());
  // المندوب يحتفظ بحق تقييم العميل بعد الإرجاع المؤكد من المحل والإلغاء الإداري.
  await assertSucceeds(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1'),
  ));
});

test('admin cancellation: إلغاء طلب قيد التجهيز يزيل تعيين المندوب', async () => {
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'orders/o1'), {
      status: 'preparing', courierId: 'cour1', courierName: 'C',
      courierPhone: '010', courierAt: new Date(),
    }));
  const db = as('admin1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), {
    status: 'cancelled', courierId: deleteField(), courierName: deleteField(),
    courierPhone: deleteField(), courierAt: deleteField(),
  });
  b.set(doc(db, 'orders/o1/statusHistory/cancelled'), {
    from: 'preparing', to: 'cancelled', actorUid: 'admin1', actorRole: 'admin', at: serverTimestamp(),
  });
  await assertSucceeds(b.commit());
  const order = (await getDoc(doc(db, 'orders/o1'))).data();
  assert.equal(order.status, 'cancelled');
  assert.equal('courierId' in order, false);
});

test('admin lifecycle: لا يتخطى المراحل ولا يعيد فتح الطلب النهائي ولا يسلّم دون ختم', async () => {
  // لا يمكن بدء الطريق من new مباشرة.
  await assertFails(changeStatus(as('admin1'), 'o1', 'new', 'on_the_way', 'admin'));
  await assertSucceeds(changeStatus(as('admin1'), 'o1', 'new', 'preparing', 'admin'));
  // لا يمكن بدء الطريق قبل تعيين مندوب وجاهزية المحل.
  await assertFails(changeStatus(as('admin1'), 'o1', 'preparing', 'on_the_way', 'admin'));
  await setOrder({ courierId: 'cour1', ready: true });
  await assertSucceeds(changeStatus(as('admin1'), 'o1', 'preparing', 'on_the_way', 'admin'));
  // لا يمكن إتمام التسليم دون الختم المالي.
  await assertFails(changeStatus(as('admin1'), 'o1', 'on_the_way', 'delivered', 'admin'));
  await setOrder({ status: 'delivered', deliveredBy: 'cour1', deliveredAt: new Date(),
    collectedAmount: 40, courierEarning: 20 });
  await assertFails(changeStatus(as('admin1'), 'o1', 'delivered', 'cancelled', 'admin'));
});
const stamp = (over = {}) => ({
  status: 'delivered', deliveredBy: 'cour1', deliveredAt: serverTimestamp(), collectedAmount: 40, courierEarning: 20, ...over,
});

test('couriers: السجل القديم بلا active يظل نشطًا، وactive=false يمنع الوصول', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'couriers/legacy'), { name: 'Legacy' });
    await setDoc(doc(db, 'couriers/disabled'), { name: 'Disabled', active: false });
    await setDoc(doc(db, 'couriers/null-active'), { name: 'Null active', active: null });
    await updateDoc(doc(db, 'orders/o1'), { status: 'preparing' });
    await setDoc(doc(db, 'courier_available_orders/o1'), {
      storeId: store, storeName: 'S', area: '', items: [], subtotal: 20,
      deliveryFee: 20, discount: 0, total: 40, status: 'preparing', createdAt: new Date(),
    });
  });
  await assertSucceeds(getDoc(doc(as('legacy'), 'courier_available_orders/o1')));
  await assertFails(getDoc(doc(as('disabled'), 'courier_available_orders/o1')));
  await assertFails(getDoc(doc(as('null-active'), 'courier_available_orders/o1')));
  const legacy = as('legacy');
  const claim = writeBatch(legacy);
  claim.update(doc(legacy, 'orders/o1'), {
    courierId: 'legacy', courierName: 'Legacy', courierPhone: '', courierAt: serverTimestamp(),
  });
  claim.delete(doc(legacy, 'courier_available_orders/o1'));
  await assertSucceeds(claim.commit());
});

test('applicants: المندوب يقدّم على طلب جاهز فقط ولا يتعيّن بنفسه، والمدير يختار', async () => {
  await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'couriers/cour2'), { name: 'C2', active: true }));
  const app = (uid) => ({ courierId: uid, courierName: 'C', courierPhone: '010', createdAt: serverTimestamp() });
  // طلب new: ممنوع التقديم
  await assertFails(setDoc(doc(as('cour1'), 'orders/o1/applicants/cour1'), app('cour1')));
  await setOrder({ status: 'preparing' });
  // المندوب يقرأ الطلبات المتاحة من courier_available_orders (من غير بيانات العميل)...
  await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), 'courier_available_orders/o1'), {
    storeId: store, storeName: 'S', items: [], subtotal: 20, deliveryFee: 20, total: 40, status: 'preparing', createdAt: new Date(),
  }));
  await assertSucceeds(getDoc(doc(as('cour1'), 'courier_available_orders/o1')));
  await assertSucceeds(getDocs(collection(as('cour1'), 'courier_available_orders')));
  await assertFails(getDoc(doc(as('cust1'), 'courier_available_orders/o1')));
  // ...ومايقدرش يقرأ orders اللي مش معيّن عليها (لا مباشرة ولا بالاستعلام)
  await assertFails(getDoc(doc(as('cour1'), 'orders/o1')));
  await assertFails(getDocs(query(collection(as('cour1'), 'orders'), where('status', '==', 'preparing'))));
  await assertFails(getDocs(collection(as('cour1'), 'orders')));
  await assertFails(getDocs(query(collection(as('cust2'), 'orders'), where('status', '==', 'preparing'))));
  await assertSucceeds(setDoc(doc(as('cour1'), 'orders/o1/applicants/cour1'), app('cour1')));
  await assertSucceeds(setDoc(doc(as('cour2'), 'orders/o1/applicants/cour2'), app('cour2')));
  // مش بإسم غيره، ولا عميل
  await assertFails(setDoc(doc(as('cour1'), 'orders/o1/applicants/cour2'), app('cour2')));
  await assertFails(setDoc(doc(as('cust1'), 'orders/o1/applicants/cust1'), app('cust1')));
  // المندوب ما يعيّن نفسه على الطلب
  await assertFails(updateDoc(doc(as('cour1'), 'orders/o1'), { courierId: 'cour1', courierName: 'C' }));
  // القراءة: المندوب بتاعه بس، والمدير الكل
  await assertSucceeds(getDoc(doc(as('cour1'), 'orders/o1/applicants/cour1')));
  await assertFails(getDoc(doc(as('cour1'), 'orders/o1/applicants/cour2')));
  await assertFails(getDocs(collection(as('cour1'), 'orders/o1/applicants')));
  await assertSucceeds(getDocs(collection(as('admin1'), 'orders/o1/applicants')));
  // المدير يعيّن، والمندوب يسحب تقديمه
  await assertSucceeds(updateDoc(doc(as('admin1'), 'orders/o1'), { courierId: 'cour2', courierName: 'C2', courierPhone: '' }));
  await assertSucceeds(deleteDoc(doc(as('cour1'), 'orders/o1/applicants/cour1')));
  // بعد التعيين: التقديم ممنوع
  await assertFails(setDoc(doc(as('cour1'), 'orders/o1/applicants/cour1'), app('cour1')));
});

// تغيير الحالة (on_the_way ← delivered) لازم يجي مع سجل في statusHistory في نفس الـ batch (إلزامي دائمًا
// في القواعد). فالتسليم بيتم بـ batch، والرفض بيتجرّب بنفس الـ batch عشان يفشل بسبب الختم مش بسبب السجل.
const deliver = (db, role, patch) => {
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), patch);
  b.set(doc(db, 'orders/o1/statusHistory/delivered'), {
    from: 'on_the_way', to: 'delivered', actorUid: actorUidOf(role), actorRole: role, at: serverTimestamp(),
  });
  return b.commit();
};

test('delivery: لا يمكن تسجيل التسليم قبل تسجيل الوصول للعميل', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date() });
  await assertFails(deliver(as('cour1'), 'courier', stamp()));
  await assertFails(deliver(as('admin1'), 'admin', stamp()));
});

test('delivery stamp: الختم إلزامي دائمًا والمندوب لا يزوّر أرقامه', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date(), courierArrivedAt: new Date() });
  await assertFails(deliver(as('cour1'), 'courier', { status: 'delivered' }));
  await assertFails(deliver(as('cour1'), 'courier', stamp({ courierEarning: 99 })));
  await assertFails(deliver(as('cour1'), 'courier', stamp({ collectedAmount: 5 })));
  await assertFails(deliver(as('cour1'), 'courier', stamp({ deliveredBy: 'cour2' })));
  await assertFails(deliver(as('cour1'), 'courier', stamp({ deliveredAt: new Date() })));
  await assertSucceeds(deliver(as('cour1'), 'courier', stamp()));
});

test('delivery stamp: لا يمكن تعديل ختم التسليم بعد اكتماله', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date(), courierArrivedAt: new Date() });
  await assertSucceeds(deliver(as('cour1'), 'courier', stamp()));
  await assertFails(updateDoc(doc(as('cour1'), 'orders/o1'), { courierEarning: 500 }));
});

test('delivery stamp: الأدمن يختم باسم المندوب المعيّن، والمبلغ المعتمد هو المحصّل', async () => {
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date(), courierArrivedAt: new Date(), verifiedTotal: 28 });
  await assertFails(deliver(as('admin1'), 'admin', stamp({ collectedAmount: 40 })));
  await assertSucceeds(deliver(as('admin1'), 'admin', stamp({ collectedAmount: 28 })));
});

test('role_requests: المستخدم يبعت طلبه هو فقط، والمدير يقبل، والمرفوض يعيد التقديم', async () => {
  const req = (uid, over = {}) => ({
    userId: uid, userEmail: 'a@x.com', type: 'courier', name: 'Ali', phone: '01012345678',
    vehicle: 'موتوسيكل', status: 'pending', createdAt: serverTimestamp(), ...over,
  });
  await assertSucceeds(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), req('cust1')));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust2_courier'), req('cust2')));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_courier2'), req('cust1', { type: 'courier2' })));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_store_owner'), req('cust1', { type: 'store_owner' }))); // من غير اسم محل
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), req('cust1', { status: 'approved' })));
  await assertFails(setDoc(doc(as('cust2'), 'role_requests/cust2_courier'), req('cust2', { phone: '123' })));
  // قراءة
  await assertSucceeds(getDoc(doc(as('cust1'), 'role_requests/cust1_courier')));
  await assertFails(getDoc(doc(as('cust2'), 'role_requests/cust1_courier')));
  await assertSucceeds(getDocs(query(collection(as('cust1'), 'role_requests'), where('userId', '==', 'cust1'))));
  await assertFails(getDocs(collection(as('cust1'), 'role_requests')));
  await assertSucceeds(getDocs(collection(as('admin1'), 'role_requests')));
  // المستخدم ما يقبلش نفسه، ولا المستخدم يعدّل وهو pending
  await assertFails(updateDoc(doc(as('cust1'), 'role_requests/cust1_courier'), { status: 'approved' }));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), req('cust1')));
  // المدير: قبول، وكتابة couriers
  const rv = { status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'admin1' };
  await assertFails(updateDoc(doc(as('admin1'), 'role_requests/cust1_courier'), { ...rv, name: 'hack' }));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'role_requests/cust1_courier'), rv));
  await assertSucceeds(setDoc(doc(as('admin1'), 'couriers/cust1'), { name: 'Ali', phone: '01012345678', active: true }, { merge: true }));
  // إعادة التقديم بعد الرفض فقط
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'role_requests/cust1_courier'), { status: 'rejected' }));
  await assertSucceeds(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), req('cust1')));
});

test('complaints: أي مسجّل يبعت باسمه، يقرأ بتاعته، والمدير يقرأ الكل ويقفلها', async () => {
  const c = (over = {}) => ({
    userId: 'cust1', userEmail: 'a@x.com', userName: 'Ali', kind: 'complaint', message: 'المندوب اتأخر جدًا',
    appRole: 'customer', status: 'open', createdAt: serverTimestamp(), ...over,
  });
  await assertSucceeds(setDoc(doc(as('cust1'), 'complaints/c1'), c()));
  await assertSucceeds(setDoc(doc(as('cust1'), 'complaints/c2'), c({ kind: 'order_issue', orderId: 'o1' })));
  await assertFails(setDoc(doc(as('cust2'), 'complaints/c3'), c({ kind: 'order_issue', orderId: 'o1', userId: 'cust2' }))); // طلب مش بتاعه
  await assertFails(setDoc(doc(as('cust1'), 'complaints/c4'), c({ kind: 'order_issue' }))); // من غير طلب
  await assertFails(setDoc(doc(as('cust1'), 'complaints/c5'), c({ userId: 'cust2' })));
  await assertFails(setDoc(doc(as('cust1'), 'complaints/c6'), c({ message: 'ab' })));
  await assertFails(setDoc(doc(as('cust1'), 'complaints/c7'), c({ status: 'resolved' })));
  await assertSucceeds(getDoc(doc(as('cust1'), 'complaints/c1')));
  await assertFails(getDoc(doc(as('cust2'), 'complaints/c1')));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'complaints/c1'), { status: 'resolved', adminNote: 'تم' }));
  await assertFails(updateDoc(doc(as('cust1'), 'complaints/c1'), { status: 'resolved' }));
  await assertFails(deleteDoc(doc(as('admin1'), 'complaints/c1')));
});

test('finalDeliveryFee: الأدمن بس يحدد الرسوم، والعمولة بتتبعها (رسوم التوصيل الأصلية متغيرة حسب المنطقة)', async () => {
  await assertFails(updateDoc(doc(as('cust1'), 'orders/o1'), { finalDeliveryFee: 0 }));
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1'), { finalDeliveryFee: 9999 }));
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1'), { finalDeliveryFee: 'x' }));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'orders/o1'), { finalDeliveryFee: 35, verifiedTotal: 55, verifiedAt: serverTimestamp() }));
  await setOrder({ status: 'on_the_way', courierId: 'cour1', pickedUpAt: new Date(), courierArrivedAt: new Date() });
  await assertFails(deliver(as('cour1'), 'courier', stamp({ collectedAmount: 55, courierEarning: 20 })));
  await assertSucceeds(deliver(as('cour1'), 'courier', stamp({ collectedAmount: 55, courierEarning: 35 })));
});

// ───────────── خصوصية العميل: بيانات التواصل في orders/{id}/private/contact ─────────────
const contactPath = 'orders/o1/private/contact';
const setOrderState = (over) => env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'orders/o1'), over));

test('خصوصية: مستند الطلب العام ممنوع يحمل موبايل أو عنوان أو إيميل', async () => {
  await assertFails(setDoc(doc(as('cust1'), 'orders/p1'), baseOrder('cust1', { phone: '01012345678' })));
  await assertFails(setDoc(doc(as('cust1'), 'orders/p2'), baseOrder('cust1', { address: 'عنوان تجريبي 1' })));
  await assertFails(setDoc(doc(as('cust1'), 'orders/p3'), baseOrder('cust1', { userEmail: 'a@x.com' })));
});

test('خصوصية: العميل بيكتب بيانات تواصل طلبه مع الطلب في نفس الـ batch بس', async () => {
  const db = as('cust1');
  const b = writeBatch(db);
  b.set(doc(db, 'orders/c1'), baseOrder('cust1'));
  b.set(doc(db, 'orders/c1/private/contact'), { userName: 'Ali', phone: '01012345678', address: 'عنوان تجريبي 1' });
  await assertSucceeds(b.commit());
  // ملاحظات المندوب (اختيارية) تنفع، بس لازم نص <= 300
  const bn = writeBatch(db);
  bn.set(doc(db, 'orders/c1n'), baseOrder('cust1'));
  bn.set(doc(db, 'orders/c1n/private/contact'), { userName: 'Ali', phone: '01012345678', address: 'عنوان تجريبي 1', courierNotes: 'الدور الرابع' });
  await assertSucceeds(bn.commit());
  const bl = writeBatch(db);
  bl.set(doc(db, 'orders/c1l'), baseOrder('cust1'));
  bl.set(doc(db, 'orders/c1l/private/contact'), { userName: 'Ali', phone: '01012345678', address: 'عنوان تجريبي 1', courierNotes: 'x'.repeat(301) });
  await assertFails(bl.commit());
  // رقم غلط
  const b2 = writeBatch(db);
  b2.set(doc(db, 'orders/c2'), baseOrder('cust1'));
  b2.set(doc(db, 'orders/c2/private/contact'), { userName: 'Ali', phone: '123', address: 'عنوان تجريبي 1' });
  await assertFails(b2.commit());
  // إضافة contact لطلب موجود أو لطلب عميل تاني
  await assertFails(setDoc(doc(as('cust2'), 'orders/o1/private/other'), { userName: 'x', phone: '01012345678', address: 'عنوان تجريبي 1' }));
  await assertFails(setDoc(doc(as('cust2'), contactPath), { userName: 'x', phone: '01012345678', address: 'عنوان تجريبي 1' }));
});

test('خصوصية: صاحب المحل لا يقرأ بيانات تواصل العميل (لكنه يقرأ الطلب)', async () => {
  await assertSucceeds(getDoc(doc(as('owner1'), 'orders/o1')));
  await assertFails(getDoc(doc(as('owner1'), contactPath)));
  await assertFails(getDoc(doc(as('owner2'), contactPath)));
});

test('خصوصية: المندوب يقرأ بيانات التواصل فقط وهو مكلّف بالطلب وجاري', async () => {
  await setOrderState({ status: 'preparing' });
  await assertFails(getDoc(doc(as('cour1'), contactPath))); // طلب متاح لسه ماستلمهوش
  await setOrderState({ status: 'preparing', courierId: 'cour1', pickedUpAt: new Date() });
  await assertSucceeds(getDoc(doc(as('cour1'), contactPath)));
  await setOrderState({ status: 'on_the_way' });
  await assertSucceeds(getDoc(doc(as('cour1'), contactPath)));
  await setOrderState({ status: 'delivered' });
  await assertFails(getDoc(doc(as('cour1'), contactPath))); // بعد التسليم يتقفل
  await setOrderState({ status: 'on_the_way', courierId: 'someone_else' });
  await assertFails(getDoc(doc(as('cour1'), contactPath))); // مندوب تاني
});

test('خصوصية: العميل والأدمن يقرأوا، وعميل تاني لأ، والعميل يعدّل/يحذف وهو new بس', async () => {
  await assertSucceeds(getDoc(doc(as('cust1'), contactPath)));
  await assertSucceeds(getDoc(doc(as('admin1'), contactPath)));
  await assertFails(getDoc(doc(as('cust2'), contactPath)));
  // الأدمن وعميل تاني ما يعدّلوش ولا يحذفوا
  await assertFails(deleteDoc(doc(as('admin1'), contactPath)));
  await assertFails(updateDoc(doc(as('cust2'), contactPath), { phone: '01112345678' }));
  // العميل يعدّل بياناته طالما الطلب new (وبيانات صحيحة بس)
  await assertSucceeds(updateDoc(doc(as('cust1'), contactPath), { phone: '01112345678' }));
  await assertFails(updateDoc(doc(as('cust1'), contactPath), { phone: '123' }));
  // أثناء التجهيز يظل العميل قادرًا على تحديث بياناته ما دام المندوب لم يستلم الطلب.
  await setOrderState({ status: 'preparing' });
  await assertSucceeds(updateDoc(doc(as('cust1'), contactPath), { phone: '01212345678' }));
  await assertFails(deleteDoc(doc(as('cust1'), contactPath)));
  // بعد تعيين المندوب تُقفل بيانات التواصل عن العميل.
  await setOrderState({ courierId: 'cour1', pickedUpAt: new Date() });
  await assertFails(updateDoc(doc(as('cust1'), contactPath), { phone: '01212345678' }));
  // وهو new: الحذف ينجح
  await seed();
  await assertSucceeds(deleteDoc(doc(as('cust1'), contactPath)));
});

test('إشعارات: لازم تتعلّق بطلب حقيقي ومستلمها عميله أو مندوبه', async () => {
  const n = (o = {}) => ({ userId: 'cust1', title: 't', body: 'b', orderId: 'o1', read: false, createdAt: serverTimestamp(), ...o });
  await assertSucceeds(setDoc(doc(as('owner1'), 'notifications/x1'), n()));
  await assertFails(setDoc(doc(as('owner1'), 'notifications/x2'), n({ userId: 'cust2' }))); // مش عميل الطلب
  await assertFails(setDoc(doc(as('owner2'), 'notifications/x3'), n())); // صاحب محل تاني
  await assertFails(setDoc(doc(as('owner1'), 'notifications/x4'), n({ orderId: 'nope' }))); // طلب مش موجود
  await assertFails(setDoc(doc(as('cour1'), 'notifications/x5'), n())); // مندوب مش مكلّف
});


test('special_requests: العميل ينشئ طلبًا صالحًا وصاحب المحل المعني فقط يقرأه', async () => {
  const request = {
    storeId: 'shop1', storeName: 'S', userId: 'cust1',
    description: 'منتج مخصوص', quantity: 2, imageUrl: '',
    voiceBase64: '', status: 'new', createdAt: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(as('cust1'), 'special_requests/sr1'), request));
  await assertSucceeds(getDoc(doc(as('owner1'), 'special_requests/sr1')));
  await assertFails(getDoc(doc(as('owner2'), 'special_requests/sr1')));
  await assertFails(getDoc(doc(as('cust2'), 'special_requests/sr1')));
  await assertFails(setDoc(doc(as('cust1'), 'special_requests/bad'), {
    ...request, quantity: 0,
  }));
});

test('store owner: حذف المحل وفك ربط حسابه يتمان في Batch واحدة', async () => {
  const db = as('owner1');
  const batch = writeBatch(db);
  batch.delete(doc(db, 'stores/shop1'));
  batch.delete(doc(db, 'storeOwners/owner1'));
  await assertSucceeds(batch.commit());
  const ownerLink = await assertSucceeds(getDoc(doc(db, 'storeOwners/owner1')));
  if (ownerLink.exists()) throw new Error('Owner link should be removed with the store.');
});
