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
    await setDoc(doc(db, 'couriers/storecour1'), { name: 'Store C', active: true, storeId: store });
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
const as = (uid, claims = {}) => env.authenticatedContext(uid, { email: 'a@x.com', firebase: { sign_in_provider: 'google.com' }, ...claims }).firestore();

beforeEach(() => seed());

test('auth: Firestore rejects email/password sessions when Google-only login is required', async () => {
  const db = as('email-user', { firebase: { sign_in_provider: 'password' } });
  await assertFails(setDoc(doc(db, 'orders/email-provider-order'), baseOrder('email-user')));
});


test('users: whitelist يمنع حقول غريبة', async () => {
  const db = as('cust1');
  await assertSucceeds(setDoc(doc(db, 'users/cust1'), { name: 'Ali', phone: '010', address: 'x' }, { merge: true }));
  await assertSucceeds(setDoc(doc(db, 'users/cust1'), { fcmInstallationIds: ['installation-id-1'] }, { merge: true }));
  await assertFails(setDoc(doc(db, 'users/cust1'), { fcmInstallationIds: Array(21).fill('installation-id') }, { merge: true }));
  await assertFails(setDoc(doc(db, 'users/cust1'), { wallet: 999 }, { merge: true }));
  await assertFails(setDoc(doc(db, 'users/cust1'), { role: 'admin' }, { merge: true }));
});

test('orders: إنشاء عادي ينجح (الأسعار غير مفعّلة)', async () => {
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/new1'), baseOrder('cust1')));
});

test('orders: الطلب الخاص ومرفقاته تُحفظ داخل نفس مستند الطلب', async () => {
  const request = {
    description: 'منتج مخصوص',
    quantity: 2,
    imageUrl: 'https://res.cloudinary.com/demo/image/upload/special_requests/sample.jpg',
    voiceBase64: 'QUJDRA==',
    createdAt: new Date().toISOString(),
  };
  await assertSucceeds(setDoc(
    doc(as('cust1'), 'orders/with-special-request'),
    baseOrder('cust1', { specialRequest: request }),
  ));
  await assertFails(setDoc(
    doc(as('cust1'), 'orders/invalid-special-request'),
    baseOrder('cust1', { specialRequest: { ...request, quantity: 100 } }),
  ));
  await assertFails(setDoc(
    doc(as('cust1'), 'orders/unknown-special-request-key'),
    baseOrder('cust1', { specialRequest: { ...request, customerPhone: '01012345678' } }),
  ));
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
    subtotal: qty * 10, total: qty * 10 + 20, editedAt: serverTimestamp(),
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
  mismatch.update(doc(db, 'courier_available_orders/o1'), {
    total: 999, editedAt: serverTimestamp(),
  });
  await assertFails(mismatch.commit());

  // تحديث الطلب وبيانات التواصل دون تحديث الـ feed في نفس الـ Batch لازم يُرفض.
  const missingFeed = writeBatch(db);
  missingFeed.update(doc(db, 'orders/o1'), {
    items: [{ name: 'p', price: 10, qty: 4, productId: 'p1' }],
    subtotal: 40, total: 60, editedAt: serverTimestamp(),
  });
  missingFeed.update(doc(db, 'orders/o1/private/contact'), { address: 'عنوان تجريبي 4' });
  await assertFails(missingFeed.commit());

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
      courierId: 'cour1', courierName: 'C', courierPhone: '01012345678', courierAt: serverTimestamp(), deliveryMode: 'external',
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
    courierId: 'cour1', courierName: 'C', courierPhone: '01012345678', courierAt: serverTimestamp(), deliveryMode: 'external',
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
    courierId: 'cour1', courierName: 'C', courierPhone: '01012345678', courierAt: serverTimestamp(), deliveryMode: 'external',
  });
  claim.delete(doc(courierDb, 'courier_available_orders/o1'));
  await assertSucceeds(claim.commit());
  const order = (await getDoc(doc(courierDb, 'orders/o1'))).data();
  assert.equal(order.courierId, 'cour1');
  assert.equal(order.total, 50);
  assert.equal((await getDoc(doc(courierDb, 'courier_available_orders/o1'))).exists(), false);
});


async function seedOnWay(deliveryMode = 'external') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const courierId = deliveryMode === 'store' ? 'storecour1' : 'cour1';
    await updateDoc(doc(db, 'orders/o1'), {
      status: 'on_the_way',
      courierId,
      courierName: 'C',
      courierAt: new Date(),
      pickedUpAt: new Date(),
      courierArrivedAt: new Date(),
      deliveryMode,
      ready: true,
    });
  });
}

async function reportDelivery(courierId = 'cour1') {
  await assertSucceeds(updateDoc(doc(as(courierId), 'orders/o1'), {
    customerDeliveryReportedAt: serverTimestamp(),
    customerDeliveryReportedBy: courierId,
  }));
}

test('delivery lifecycle: المندوب يبلغ بالتسليم ولا يستطيع إغلاق الطلب مباشرة', async () => {
  await seedOnWay('external');
  const courier = as('cour1');
  await assertFails(updateDoc(doc(as('cust1'), 'orders/o1'), {
    customerConfirmedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(courier, 'orders/o1'), {
    status: 'delivered',
    deliveredBy: 'cour1',
    deliveredAt: serverTimestamp(),
    collectedAmount: 40,
    courierEarning: 20,
  }));
  const admin = as('admin1');
  const adminClose = writeBatch(admin);
  adminClose.update(doc(admin, 'orders/o1'), {
    status: 'delivered',
    deliveredBy: 'cour1',
    deliveredAt: serverTimestamp(),
    collectedAmount: 40,
    courierEarning: 20,
  });
  adminClose.set(doc(admin, 'orders/o1/statusHistory/delivered'), {
    from: 'on_the_way', to: 'delivered', actorUid: 'admin1',
    actorRole: 'admin', at: serverTimestamp(),
  });
  await assertFails(adminClose.commit());
  await reportDelivery();
  const afterReport = (await getDoc(doc(as('cust1'), 'orders/o1'))).data();
  assert.equal(afterReport.status, 'on_the_way');
  assert.equal(afterReport.customerDeliveryReportedBy, 'cour1');
  await assertFails(updateDoc(doc(courier, 'orders/o1'), {
    customerDeliveryReportedAt: serverTimestamp(),
    customerDeliveryReportedBy: 'cour1',
  }));
});

test('delivery lifecycle: تأكيد العميل يغلق طلب مندوب المحل', async () => {
  await seedOnWay('store');
  await reportDelivery('storecour1');
  const db = as('cust1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), {
    status: 'delivered',
    customerConfirmedAt: serverTimestamp(),
    deliveredBy: 'storecour1',
    deliveredAt: serverTimestamp(),
    collectedAmount: 40,
    courierEarning: 20,
  });
  b.set(doc(db, 'orders/o1/statusHistory/delivered'), {
    from: 'on_the_way', to: 'delivered', actorUid: 'cust1',
    actorRole: 'customer', at: serverTimestamp(),
  });
  await assertSucceeds(b.commit());
  const order = (await getDoc(doc(db, 'orders/o1'))).data();
  assert.equal(order.status, 'delivered');
  assert.equal(order.deliveredBy, 'storecour1');
});

test('delivery lifecycle: المندوب الخارجي يسلم النقدية والمحل وحده يغلق الطلب', async () => {
  await seedOnWay('external');
  await reportDelivery('cour1');
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1'), {
    verifiedTotal: 35,
    verifiedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1'), {
    finalDeliveryFee: 15,
  }));
  await assertSucceeds(updateDoc(doc(as('cust1'), 'orders/o1'), {
    customerConfirmedAt: serverTimestamp(),
  }));
  const owner = as('owner1');
  const earlyClose = writeBatch(owner);
  earlyClose.update(doc(owner, 'orders/o1'), {
    status: 'delivered',
    deliveredBy: 'cour1',
    deliveredAt: serverTimestamp(),
    collectedAmount: 40,
    courierEarning: 20,
  });
  earlyClose.set(doc(owner, 'orders/o1/statusHistory/delivered'), {
    from: 'on_the_way', to: 'delivered', actorUid: 'owner1',
    actorRole: 'storeOwner', at: serverTimestamp(),
  });
  await assertFails(earlyClose.commit());
  const courier = as('cour1');
  await assertSucceeds(updateDoc(doc(courier, 'orders/o1'), {
    cashHandedToStoreAt: serverTimestamp(),
    cashHandedToStoreBy: 'cour1',
  }));
  await assertFails(updateDoc(doc(courier, 'orders/o1'), {
    status: 'delivered',
    deliveredBy: 'cour1',
    deliveredAt: serverTimestamp(),
    collectedAmount: 40,
    courierEarning: 20,
  }));
  const b = writeBatch(owner);
  b.update(doc(owner, 'orders/o1'), {
    status: 'delivered',
    deliveredBy: 'cour1',
    deliveredAt: serverTimestamp(),
    collectedAmount: 40,
    courierEarning: 20,
  });
  b.set(doc(owner, 'orders/o1/statusHistory/delivered'), {
    from: 'on_the_way', to: 'delivered', actorUid: 'owner1',
    actorRole: 'storeOwner', at: serverTimestamp(),
  });
  await assertSucceeds(b.commit());
  const order = (await getDoc(doc(owner, 'orders/o1'))).data();
  assert.equal(order.status, 'delivered');
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

test('notifications: استعلام شاشة الإشعارات (userId + ترتيب createdAt + limit) مسموح لصاحبه ومرفوض لغيره', async () => {
  const { collection, getDocs, query, where, orderBy, limit } = require('firebase/firestore');
  const n = { userId: 'cust1', title: 't', body: 'b', orderId: 'o1', read: false, createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as('admin1'), 'notifications/n1'), n));
  const mine = (uid, db) => query(collection(db, 'notifications'), where('userId', '==', uid), orderBy('createdAt', 'desc'), limit(100));
  const res = await assertSucceeds(getDocs(mine('cust1', as('cust1'))));
  assert.equal(res.size, 1);
  // نفس الاستعلام من غير ترتيب (الاستعلام البديل لو الفهرس ناقص) لازم يتقبل برضه
  await assertSucceeds(getDocs(query(collection(as('cust1'), 'notifications'), where('userId', '==', 'cust1'), limit(100))));
  // الاستعلام باسم عميل تاني مرفوض
  await assertFails(getDocs(mine('cust1', as('cust2'))));
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
  await assertFails(setDoc(
    doc(as('owner1'), 'customer_reviews/o1_store_owner'),
    customerReview('store_owner', 'owner1'),
  ));
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
  await assertFails(updateDoc(doc(as('cour1'), 'customer_reviews/o1_courier'), {
    moderationStatus: 'excluded',
  }));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'customer_reviews/o1_courier'), {
    moderationStatus: 'excluded',
    adminNote: 'تمت مراجعة البلاغ واستبعاد التقييم.',
    moderatedAt: serverTimestamp(),
    moderatedBy: 'admin1',
  }));
  await assertFails(updateDoc(doc(as('admin1'), 'customer_reviews/o1_courier'), {
    rating: 5,
  }));
});

test('customer reviews: المراجع يقدر يتحقق من تقييمه فقط باستعلام محدود', async () => {
  const { collection, getDocs, query, where } = require('firebase/firestore');
  await setOrder({ status: 'delivered', courierId: 'cour1', deliveredBy: 'cour1' });
  await assertSucceeds(setDoc(
    doc(as('cour1'), 'customer_reviews/o1_courier'),
    customerReview('courier', 'cour1'),
  ));

  const courierQuery = query(
    collection(as('cour1'), 'customer_reviews'),
    where('reviewerId', '==', 'cour1'),
    where('orderId', '==', 'o1'),
    where('reviewerRole', '==', 'courier'),
  );
  const courierReviews = await assertSucceeds(getDocs(courierQuery));
  assert.equal(courierReviews.size, 1);

  const ownerEmptyQuery = query(
    collection(as('owner1'), 'customer_reviews'),
    where('reviewerId', '==', 'owner1'),
    where('orderId', '==', 'o1'),
    where('reviewerRole', '==', 'store_owner'),
  );
  const ownerReviews = await assertSucceeds(getDocs(ownerEmptyQuery));
  assert.equal(ownerReviews.size, 0);

  const forgedQuery = query(
    collection(as('cust1'), 'customer_reviews'),
    where('orderId', '==', 'o1'),
  );
  await assertFails(getDocs(forgedQuery));
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
  const { collection, getDocs } = require('firebase/firestore');
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
  await assertFails(setDoc(doc(as('admin1'), 'customer_restrictions/cust2'), {
    ...restriction, customerId: 'cust2', sourceOrderId: 'missing',
  }));
  await assertSucceeds(setDoc(doc(as('admin1'), 'customer_restrictions/cust1'), restriction));
  await assertFails(setDoc(doc(as('cust1'), 'orders/restricted-order'), baseOrder('cust1')));
  await assertSucceeds(getDoc(doc(as('cust1'), 'customer_restrictions/cust1')));
  await assertFails(getDoc(doc(as('cust2'), 'customer_restrictions/cust1')));
  await assertFails(getDocs(collection(as('cust1'), 'customer_restrictions')));
  await assertSucceeds(getDocs(collection(as('admin1'), 'customer_restrictions')));
  await assertFails(updateDoc(doc(as('cust1'), 'customer_restrictions/cust1'), {
    active: false, clearedAt: serverTimestamp(), clearedBy: 'cust1',
  }));
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

test('owner: وصف الصنف واختياراته (optionGroups) بقيم سليمة فقط', async () => {
  const db = as('owner1');
  const ref = (id) => doc(db, `stores/shop1/products/${id}`);
  const p = { name: 'قهوة', price: 20, isAvailable: true, available: true, createdAt: serverTimestamp() };
  const groups = [
    { title: 'السكر', required: true, min: 1, max: 1, options: [{ name: 'سادة', price: 0 }, { name: 'مظبوط', price: 0 }] },
  ];
  await assertSucceeds(setDoc(ref('g1'), { ...p, description: 'قهوة باردة', optionGroups: groups }));
  await assertSucceeds(setDoc(ref('g2'), { ...p, optionGroups: [] }));
  await assertFails(setDoc(ref('g3'), { ...p, optionGroups: 'x' }));
  await assertFails(setDoc(ref('g4'), { ...p, optionGroups: Array(11).fill(groups[0]) }));
  await assertFails(setDoc(ref('g5'), { ...p, description: 'x'.repeat(501) }));
  await assertFails(setDoc(ref('g6'), { ...p, description: 5 }));
  await assertFails(setDoc(doc(as('owner2'), 'stores/shop1/products/g7'), { ...p, optionGroups: groups }));
});

test('owner: عميل عادي ما يكتبش أصناف', async () => {
  await assertFails(setDoc(doc(as('cust1'), 'stores/shop1/products/px'), { name: 'x', price: 5 }));
});

test('owner: يرفع نسخة الكتالوج +1 فقط، والعميل لا', async () => {
  const v = { version: 1, updatedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as('owner1'), 'app_info/catalog'), v, { merge: true }));
  await assertFails(setDoc(doc(as('cust1'), 'app_info/catalog'), v, { merge: true }));
});

test('catalog: صاحب المحل يزود الإصدار خطوة واحدة فقط، بدون تزوير وقت التحديث', async () => {
  const ref = doc(as('owner1'), 'app_info/catalog');
  await assertSucceeds(setDoc(ref, { version: 1, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { version: increment(1), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { version: 999999, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { version: 2, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { version: increment(1), updatedAt: new Date('2020-01-01') }));
  await assertFails(updateDoc(ref, { version: increment(1), updatedAt: serverTimestamp(), injected: true }));
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
  await setOrder({ status: 'on_the_way', courierId: 'cour1', deliveryMode: 'external', pickedUpAt: new Date(), courierArrivedAt: new Date() });
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
  // بعد الاستئناف المندوب يبلّغ بالتسليم فقط؛ الإغلاق لا يتم منه مباشرة.
  await assertFails(deliver(courier, 'courier', stamp()));
  await reportDelivery('cour1');
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
  const adminDb = as('admin1');
  const closeAttempt = writeBatch(adminDb);
  closeAttempt.update(doc(adminDb, 'orders/o1'), {
    status: 'cancelled',
    activeDeliveryIssueId: deleteField(),
    lastDeliveryIssueId: 'return1',
  });
  closeAttempt.set(doc(adminDb, 'orders/o1/statusHistory/cancelled'), {
    from: 'on_the_way', to: 'cancelled', actorUid: 'admin1', actorRole: 'admin', at: serverTimestamp(),
  });
  await assertFails(closeAttempt.commit()); // لا يكفي تأكيد المندوب وحده.
  await assertSucceeds(updateDoc(doc(as('owner1'), 'delivery_issues/return1'), {
    status: 'store_confirmed_return',
    storeReceivedAt: serverTimestamp(),
    storeReceivedBy: 'owner1',
  }));
  const close = writeBatch(adminDb);
  close.update(doc(adminDb, 'orders/o1'), {
    status: 'cancelled',
    activeDeliveryIssueId: deleteField(),
    lastDeliveryIssueId: 'return1',
  });
  close.set(doc(adminDb, 'orders/o1/statusHistory/cancelled'), {
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
    courierPhone: deleteField(), courierAt: deleteField(), deliveryMode: deleteField(),
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
    courierId: 'legacy', courierName: 'Legacy', courierPhone: '', courierAt: serverTimestamp(), deliveryMode: 'external',
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
  const adminDb = as('admin1');
  const assignBatch = writeBatch(adminDb);
  assignBatch.update(doc(adminDb, 'orders/o1'), {
    courierId: 'cour2', courierName: 'C2', courierPhone: '', courierAt: serverTimestamp(), deliveryMode: 'external',
  });
  assignBatch.delete(doc(adminDb, 'courier_available_orders/o1'));
  await assertSucceeds(assignBatch.commit());
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

// الإغلاق لا يتم من المندوب ولا الأدمن مباشرة؛ في طلب مندوب المحل العميل يؤكد الاستلام ويُختم الطلب.
async function seedStoreReported(extra = {}) {
  await seedOnWay('store');
  await setOrder({ customerDeliveryReportedAt: new Date(), customerDeliveryReportedBy: 'storecour1', ...extra });
}
const storeStamp = (over = {}) => stamp({ deliveredBy: 'storecour1', ...over });
const customerClose = (patch) => {
  const db = as('cust1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), { customerConfirmedAt: serverTimestamp(), ...patch });
  b.set(doc(db, 'orders/o1/statusHistory/delivered'), {
    from: 'on_the_way', to: 'delivered', actorUid: 'cust1', actorRole: 'customer', at: serverTimestamp(),
  });
  return b.commit();
};

test('delivery stamp: الختم إلزامي دائمًا والمندوب لا يزوّر أرقامه', async () => {
  await seedStoreReported();
  await assertFails(customerClose({ status: 'delivered' }));
  await assertFails(customerClose(storeStamp({ courierEarning: 99 })));
  await assertFails(customerClose(storeStamp({ collectedAmount: 5 })));
  await assertFails(customerClose(storeStamp({ deliveredBy: 'cour2' })));
  await assertFails(customerClose(storeStamp({ deliveredAt: new Date() })));
  await assertSucceeds(customerClose(storeStamp()));
});

test('delivery stamp: لا يمكن تعديل ختم التسليم بعد اكتماله', async () => {
  await seedStoreReported();
  await assertSucceeds(customerClose(storeStamp()));
  await assertFails(updateDoc(doc(as('storecour1'), 'orders/o1'), { courierEarning: 500 }));
  await assertFails(updateDoc(doc(as('cust1'), 'orders/o1'), { courierEarning: 500 }));
});

test('delivery stamp: الأدمن لا يغلق الطلب، والمبلغ المعتمد هو المحصّل', async () => {
  await seedStoreReported({ verifiedTotal: 28 });
  await assertFails(deliver(as('admin1'), 'admin', storeStamp({ collectedAmount: 28 })));
  await assertFails(customerClose(storeStamp({ collectedAmount: 40 })));
  await assertSucceeds(customerClose(storeStamp({ collectedAmount: 28 })));
});

test('role_requests: طلب المحل ينشئ مسودة خاصة ولا تظهر إلا بعد اعتماد الإدارة', async () => {
  const courierRequest = (uid, over = {}) => ({
    userId: uid, userEmail: 'a@x.com', type: 'courier', name: 'Ali',
    phone: '01012345678', vehicle: 'موتوسيكل', status: 'pending',
    createdAt: serverTimestamp(), ...over,
  });
  const storeDraft = (uid, id, name, storePhone = '') => ({
    name, category: 'بقالة', address: 'شارع رئيسي ١', ownerUid: uid,
    active: false, approved: false, time: '',
    image: 'https://example.com/store.jpg',
    imageUrl: 'https://example.com/store.jpg',
    storePhone, productCount: 0,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  const storeRequest = (uid, id, name, extra = {}) => ({
    userId: uid, userEmail: 'a@x.com', type: 'store_owner', name: 'صاحب المحل',
    storeName: name, storeCategory: 'بقالة', address: 'شارع رئيسي ١',
    storeImageUrl: 'https://example.com/store.jpg', storeId: id,
    status: 'pending', createdAt: serverTimestamp(), ...extra,
  });

  await assertSucceeds(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), courierRequest('cust1')));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust2_courier'), courierRequest('cust2')));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_courier2'), courierRequest('cust1', { type: 'courier2' })));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_store_owner'), courierRequest('cust1', { type: 'store_owner' })));

  // إنشاء المسودة وطلب الانضمام في Batch واحدة، بدون اشتراط رقم صاحب المحل.
  const db3 = as('cust3');
  const b3 = db3.batch();
  b3.set(doc(db3, 'stores/draft3'), storeDraft('cust3', 'draft3', 'متجر'));
  b3.set(doc(db3, 'role_requests/cust3_store_owner'),
    storeRequest('cust3', 'draft3', 'متجر', { registrationNumber: '123456' }));
  await assertSucceeds(b3.commit());

  // تليفون المحل بديل مقبول، حتى بدون رقم صاحب المحل.
  const db5 = as('cust5');
  const b5 = db5.batch();
  b5.set(doc(db5, 'stores/draft5'), storeDraft('cust5', 'draft5', 'متجر هاتف', '01012345678'));
  b5.set(doc(db5, 'role_requests/cust5_store_owner'),
    storeRequest('cust5', 'draft5', 'متجر هاتف', { storePhone: '01012345678' }));
  await assertSucceeds(b5.commit());

  // السجل التجاري بديل مقبول أيضًا، ورقم صاحب المحل يظل اختياريًا.
  const db6 = as('cust6');
  const b6 = db6.batch();
  b6.set(doc(db6, 'stores/draft6'), storeDraft('cust6', 'draft6', 'متجر بلا هاتف'));
  b6.set(doc(db6, 'role_requests/cust6_store_owner'),
    storeRequest('cust6', 'draft6', 'متجر بلا هاتف', { registrationNumber: '123456' }));
  await assertSucceeds(b6.commit());

  // لا يكفي رقم صاحب المحل وحده كإثبات نشاط، ولا يسمح بإنشاء مسودة منفصلة عن الطلب.
  const db4 = as('cust4');
  const b4 = db4.batch();
  b4.set(doc(db4, 'stores/draft4'), storeDraft('cust4', 'draft4', 'متجر بلا إثبات'));
  b4.set(doc(db4, 'role_requests/cust4_store_owner'),
    storeRequest('cust4', 'draft4', 'متجر بلا إثبات', { phone: '01012345678' }));
  await assertFails(b4.commit());

  // المسودة والأصناف لا يقرأها إلا صاحبها أو المدير، وصاحبها يستطيع تجهيز الأصناف.
  await assertSucceeds(getDoc(doc(as('cust3'), 'stores/draft3')));
  await assertFails(getDoc(doc(as('cust2'), 'stores/draft3')));
  // استعلام الدليل العام ينجح بشرط active=true ولا يكشف المسودات.
  await assertSucceeds(getDocs(query(collection(as('cust2'), 'stores'), where('active', '==', true))));
  await assertFails(getDocs(query(collection(as('cust2'), 'stores'), where('active', '==', false))));
  await assertSucceeds(setDoc(doc(as('cust3'), 'stores/draft3/products/p1'), {
    name: 'عيش', price: 10, image: '', available: true,
  }));
  await assertFails(getDoc(doc(as('cust2'), 'stores/draft3/products/p1')));
  await assertSucceeds(getDoc(doc(as('admin1'), 'stores/draft3')));
  await assertFails(updateDoc(doc(as('cust3'), 'stores/draft3'), { active: true }));

  await assertFails(setDoc(doc(as('cust3'), 'role_requests/cust3_courier'), courierRequest('cust3')));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), courierRequest('cust1', { status: 'approved' })));
  await assertFails(setDoc(doc(as('cust2'), 'role_requests/cust2_courier'), courierRequest('cust2', { phone: '123' })));
  await assertSucceeds(getDoc(doc(as('cust1'), 'role_requests/cust1_courier')));
  await assertFails(getDoc(doc(as('cust2'), 'role_requests/cust1_courier')));
  await assertSucceeds(getDocs(query(collection(as('cust1'), 'role_requests'), where('userId', '==', 'cust1'))));
  await assertFails(getDocs(collection(as('cust1'), 'role_requests')));
  await assertSucceeds(getDocs(collection(as('admin1'), 'role_requests')));

  // المستخدم لا يستطيع قبول نفسه أو تعديل طلبه وهو pending.
  await assertFails(updateDoc(doc(as('cust1'), 'role_requests/cust1_courier'), { status: 'approved' }));
  await assertFails(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), courierRequest('cust1')));

  // الإدارة تعتمد المسودة وتربط حساب صاحب المحل في Batch واحدة.
  const adminDb = as('admin1');
  const approve = adminDb.batch();
  approve.set(doc(adminDb, 'storeOwners/cust3'), {
    name: 'صاحب المحل', storeId: 'draft3', active: true,
  });
  approve.update(doc(adminDb, 'stores/draft3'), { approved: true, active: true, ownerUid: deleteField() });
  approve.update(doc(adminDb, 'role_requests/cust3_store_owner'), {
    status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'admin1',
  });
  await assertSucceeds(approve.commit());
  const publicStore = await assertSucceeds(getDoc(doc(as('cust2'), 'stores/draft3')));
  assert.equal(publicStore.data().ownerUid, undefined);
  await assertSucceeds(getDoc(doc(as('cust2'), 'stores/draft3/products/p1')));
  await assertSucceeds(getDoc(doc(as('cust3'), 'stores/draft3')));

  // اعتماد محل غير مكتمل لا ينشره؛ لا يستطيع صاحبه فتحه بنفسه، والإدارة تفعّله بعد استكماله.
  const approve6 = adminDb.batch();
  approve6.set(doc(adminDb, 'storeOwners/cust6'), {
    name: 'صاحب المحل', storeId: 'draft6', active: true,
  });
  approve6.update(doc(adminDb, 'stores/draft6'), { approved: true, active: false, ownerUid: deleteField() });
  approve6.update(doc(adminDb, 'role_requests/cust6_store_owner'), {
    status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'admin1',
  });
  await assertSucceeds(approve6.commit());
  await assertFails(getDoc(doc(as('cust2'), 'stores/draft6')));
  await assertFails(updateDoc(doc(as('cust6'), 'stores/draft6'), { active: true }));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'stores/draft6'), { active: true }));
  await assertSucceeds(getDoc(doc(as('cust2'), 'stores/draft6')));

  // الإدارة تقبل المندوب وتكتب سجله؛ إعادة التقديم بعد الرفض فقط.
  await assertSucceeds(setDoc(doc(as('admin1'), 'couriers/cust1'), {
    name: 'Ali', phone: '01012345678', active: true,
  }, { merge: true }));
  const rv = { status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'admin1' };
  await assertFails(updateDoc(doc(as('admin1'), 'role_requests/cust1_courier'), { ...rv, name: 'hack' }));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'role_requests/cust1_courier'), rv));
  await env.withSecurityRulesDisabled((c) =>
    updateDoc(doc(c.firestore(), 'role_requests/cust1_courier'), { status: 'rejected' }));
  await assertSucceeds(setDoc(doc(as('cust1'), 'role_requests/cust1_courier'), courierRequest('cust1')));
});

test('customer restrictions: Fail-Closed مع مستند تقييد ناقص أو تالف', async () => {
  const put = (data) => env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'customer_restrictions/cust1'), data);
  });
  const past = new Date(Date.now() - 60 * 60 * 1000);
  const future = new Date(Date.now() + 60 * 60 * 1000);
  // active=true بدون expiresAt → يُمنع
  await put({ customerId: 'cust1', active: true });
  await assertFails(setDoc(doc(as('cust1'), 'orders/fc1'), baseOrder('cust1')));
  // expiresAt ليس Timestamp → يُمنع
  await put({ customerId: 'cust1', active: true, expiresAt: 'tomorrow' });
  await assertFails(setDoc(doc(as('cust1'), 'orders/fc2'), baseOrder('cust1')));
  // active غير منطقي (نص) بدون تاريخ → يُمنع
  await put({ customerId: 'cust1', active: 'true' });
  await assertFails(setDoc(doc(as('cust1'), 'orders/fc3'), baseOrder('cust1')));
  // تقييد ساري → يُمنع
  await put({ customerId: 'cust1', active: true, expiresAt: future });
  await assertFails(setDoc(doc(as('cust1'), 'orders/fc4'), baseOrder('cust1')));
  // تقييد منتهي فعلًا → يُسمح
  await put({ customerId: 'cust1', active: true, expiresAt: past });
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/fc5'), baseOrder('cust1')));
  // تقييد مُلغى صراحةً → يُسمح
  await put({ customerId: 'cust1', active: false, expiresAt: future });
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/fc6'), baseOrder('cust1')));
});

test('complaints: الإنشاء موقوف (الدعم واتساب)، المستندات القديمة تتقرأ وتتقفل بس', async () => {
  const c = (over = {}) => ({
    userId: 'cust1', userEmail: 'a@x.com', userName: 'Ali', kind: 'complaint', message: 'المندوب اتأخر جدًا',
    appRole: 'customer', status: 'open', createdAt: serverTimestamp(), ...over,
  });
  await assertFails(setDoc(doc(as('cust1'), 'complaints/c1'), c()));
  await assertFails(setDoc(doc(as('cust1'), 'complaints/c2'), c({ kind: 'order_issue', orderId: 'o1' })));
  await assertFails(setDoc(doc(as('admin1'), 'complaints/c3'), c()));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'complaints/old1'), {
      userId: 'cust1', kind: 'complaint', message: 'شكوى قديمة', status: 'open', appRole: 'customer',
    });
  });
  await assertSucceeds(getDoc(doc(as('cust1'), 'complaints/old1')));
  await assertFails(getDoc(doc(as('cust2'), 'complaints/old1')));
  await assertSucceeds(getDoc(doc(as('admin1'), 'complaints/old1')));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'complaints/old1'), { status: 'resolved', adminNote: 'تم' }));
  await assertFails(updateDoc(doc(as('cust1'), 'complaints/old1'), { status: 'resolved' }));
  await assertFails(deleteDoc(doc(as('admin1'), 'complaints/old1')));
});

test('support_chats: الإنشاء والتعديل والرسائل موقوفة، القراءة القديمة فقط', async () => {
  const chat = {
    userId: 'cust1', userName: 'Ali', userEmail: 'a@x.com', appRole: 'customer',
    lastMessage: 'مرحبا', lastSender: 'user', lastAt: serverTimestamp(),
    unreadForAdmin: true, unreadForUser: false,
  };
  await assertFails(setDoc(doc(as('cust1'), 'support_chats/cust1'), chat));
  await assertFails(setDoc(doc(as('admin1'), 'support_chats/cust1'), chat));
  await assertFails(setDoc(doc(as('cust1'), 'support_chats/cust1/messages/m1'), {
    senderId: 'cust1', senderRole: 'user', text: 'مرحبا', createdAt: serverTimestamp(),
  }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'support_chats/cust1'), { ...chat, lastAt: new Date() });
    await setDoc(doc(ctx.firestore(), 'support_chats/cust1/messages/m0'), {
      senderId: 'cust1', senderRole: 'user', text: 'قديمة', createdAt: new Date(),
    });
  });
  await assertSucceeds(getDoc(doc(as('cust1'), 'support_chats/cust1')));
  await assertFails(getDoc(doc(as('cust2'), 'support_chats/cust1')));
  await assertSucceeds(getDoc(doc(as('admin1'), 'support_chats/cust1')));
  await assertSucceeds(getDoc(doc(as('cust1'), 'support_chats/cust1/messages/m0')));
  await assertFails(updateDoc(doc(as('cust1'), 'support_chats/cust1'), { unreadForUser: false }));
  await assertFails(updateDoc(doc(as('admin1'), 'support_chats/cust1'), { unreadForAdmin: false }));
  await assertFails(deleteDoc(doc(as('admin1'), 'support_chats/cust1')));
});

test('الكوبونات موقوفة: طلب جديد بخصم يترفض حتى لو الكود صالح، وبدون خصم يعدّي', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'promos/SAVE10'), { percent: 10, active: true });
  });
  const base = baseOrder('cust1');
  const discounted = {
    ...base, promoCode: 'SAVE10', discount: 2,
    total: base.subtotal + base.deliveryFee - 2,
  };
  await assertFails(setDoc(doc(as('cust1'), 'orders/promo1'), discounted));
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/promo2'), baseOrder('cust1')));
});

test('finalDeliveryFee: الأدمن بس يحدد الرسوم، والعمولة بتتبعها (رسوم التوصيل الأصلية متغيرة حسب المنطقة)', async () => {
  await assertFails(updateDoc(doc(as('cust1'), 'orders/o1'), { finalDeliveryFee: 0 }));
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1'), { finalDeliveryFee: 9999 }));
  await assertFails(updateDoc(doc(as('admin1'), 'orders/o1'), { finalDeliveryFee: 'x' }));
  await assertSucceeds(updateDoc(doc(as('admin1'), 'orders/o1'), { finalDeliveryFee: 35, verifiedTotal: 55, verifiedAt: serverTimestamp() }));
  await seedStoreReported();
  await assertFails(customerClose(storeStamp({ collectedAmount: 55, courierEarning: 20 })));
  await assertSucceeds(customerClose(storeStamp({ collectedAmount: 55, courierEarning: 35 })));
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


test('special_requests: الإنشاء موقوف مؤقتًا للجميع، والقراءة للمستندات القديمة لصاحب المحل المعني والإدارة فقط', async () => {
  const request = {
    storeId: 'shop1', storeName: 'S', userId: 'cust1',
    description: 'منتج مخصوص', quantity: 2, imageUrl: '',
    voiceBase64: '', status: 'new', createdAt: serverTimestamp(),
  };
  // لا عميل ولا صاحب محل ولا مدير يقدر ينشئ مستندًا جديدًا (التطبيق بيستخدم orders.specialRequest).
  await assertFails(setDoc(doc(as('cust1'), 'special_requests/sr1'), request));
  await assertFails(setDoc(doc(as('owner1'), 'special_requests/sr2'), request));
  await assertFails(setDoc(doc(as('admin1'), 'special_requests/sr3'), request));
  await assertFails(setDoc(doc(as('cust1'), 'special_requests/voice-big'), {
    ...request, voiceBase64: 'A'.repeat(1000),
  }));

  // مستند قديم موجود: القراءة محصورة في صاحب المحل المعني والإدارة.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'special_requests/old1'), {
      ...request, createdAt: new Date(),
    });
  });
  await assertSucceeds(getDoc(doc(as('owner1'), 'special_requests/old1')));
  await assertSucceeds(getDoc(doc(as('admin1'), 'special_requests/old1')));
  await assertFails(getDoc(doc(as('owner2'), 'special_requests/old1')));
  await assertFails(getDoc(doc(as('cust1'), 'special_requests/old1')));
  await assertFails(updateDoc(doc(as('owner1'), 'special_requests/old1'), { status: 'done' }));
  await assertFails(deleteDoc(doc(as('admin1'), 'special_requests/old1')));
});

test('store owner: لا يستطيع حذف مستند المحل؛ الحذف للإدارة فقط', async () => {
  const db = as('owner1');
  await assertFails(deleteDoc(doc(db, 'stores/shop1')));
  const batch = writeBatch(db);
  batch.delete(doc(db, 'stores/shop1'));
  batch.delete(doc(db, 'storeOwners/owner1'));
  await assertFails(batch.commit());
  await assertFails(deleteDoc(doc(as('owner2'), 'stores/shop1')));
  await assertSucceeds(deleteDoc(doc(as('admin1'), 'stores/shop1')));
});

test('storeOwners: صاحب المحل لا يفك ربط حسابه بنفسه؛ الإدارة فقط', async () => {
  await assertFails(deleteDoc(doc(as('owner1'), 'storeOwners/owner1')));
  await assertFails(deleteDoc(doc(as('owner1'), 'storeOwners/owner2')));
  await assertSucceeds(deleteDoc(doc(as('admin1'), 'storeOwners/owner1')));
});

test('account_deletions: مستند واحد لكل مستخدم وبحقول محددة', async () => {
  const db = as('cust1');
  await assertFails(setDoc(doc(db, 'account_deletions/random-id'), { userId: 'cust1', reason: 'x' }));
  await assertFails(setDoc(doc(db, 'account_deletions/cust1'), { userId: 'cust1', reason: 'x', junk: 'A'.repeat(1000) }));
  await assertFails(setDoc(doc(db, 'account_deletions/cust2'), { userId: 'cust2', reason: 'x' }));
  await assertFails(setDoc(doc(db, 'account_deletions/cust1'), { userId: 'cust2', reason: 'x' }));
  await assertFails(setDoc(doc(db, 'account_deletions/cust1'), { userId: 'cust1' }));
  await assertFails(setDoc(doc(db, 'account_deletions/cust1'), { userId: 'cust1', reason: 5 }));
  await assertFails(setDoc(doc(db, 'account_deletions/cust1'), { userId: 'cust1', reason: 'A'.repeat(201) }));
  await assertFails(setDoc(doc(db, 'account_deletions/cust1'), { userId: 'cust1', reason: 'x', createdAt: 'A'.repeat(5000) }));
  await assertSucceeds(setDoc(doc(db, 'account_deletions/cust1'), { userId: 'cust1', reason: 'x', createdAt: serverTimestamp() }));
});

test('account_deletions: الإنشاء بدون createdAt مسموح بحقول صحيحة', async () => {
  await assertSucceeds(setDoc(doc(as('cust1'), 'account_deletions/cust1'), { userId: 'cust1', reason: 'x' }));
});


test('store owner can assign only an active courier linked to the same store', async () => {
  await prepareOrderWithFeed();
  const db = as('owner1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), {
    courierId: 'storecour1', courierName: 'Store C', courierPhone: '',
    courierAt: serverTimestamp(), deliveryMode: 'store',
  });
  b.delete(doc(db, 'courier_available_orders/o1'));
  await assertSucceeds(b.commit());
  assert.equal((await getDoc(doc(db, 'orders/o1'))).data().deliveryMode, 'store');
});

test('store owner cannot assign an external courier as store courier', async () => {
  await prepareOrderWithFeed();
  const db = as('owner1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), {
    courierId: 'cour1', courierName: 'C', courierPhone: '',
    courierAt: serverTimestamp(), deliveryMode: 'store',
  });
  b.delete(doc(db, 'courier_available_orders/o1'));
  await assertFails(b.commit());
});

test('linked store courier cannot claim an external order from the public feed', async () => {
  await prepareOrderWithFeed();
  const db = as('storecour1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/o1'), {
    courierId: 'storecour1', courierName: 'Store C', courierPhone: '',
    courierAt: serverTimestamp(), deliveryMode: 'external',
  });
  b.delete(doc(db, 'courier_available_orders/o1'));
  await assertFails(b.commit());
});

// withSecurityRulesDisabled لا يرجّع قيمة الـ callback، فنحفظها في متغير خارجي.
const feedExists = async () => {
  let exists;
  await env.withSecurityRulesDisabled(async (c) => {
    exists = (await getDoc(doc(c.firestore(), 'courier_available_orders/o1'))).exists();
  });
  return exists;
};

test('courier assignment: التعيين الإداري يفشل لو الـ feed لم يُحذف في نفس العملية', async () => {
  await prepareOrderWithFeed();
  const db = as('admin1');
  const partial = writeBatch(db);
  partial.update(doc(db, 'orders/o1'), {
    courierId: 'cour1', courierName: 'C', courierPhone: '01012345678',
    courierAt: serverTimestamp(), deliveryMode: 'external',
  });
  await assertFails(partial.commit());
  assert.equal((await getDoc(doc(db, 'orders/o1'))).data().courierId ?? '', '');
  assert.equal(await feedExists(), true);

  const atomic = writeBatch(db);
  atomic.update(doc(db, 'orders/o1'), {
    courierId: 'cour1', courierName: 'C', courierPhone: '01012345678',
    courierAt: serverTimestamp(), deliveryMode: 'external',
  });
  atomic.delete(doc(db, 'courier_available_orders/o1'));
  await assertSucceeds(atomic.commit());
  assert.equal((await getDoc(doc(db, 'orders/o1'))).data().courierId, 'cour1');
  assert.equal(await feedExists(), false);
});

test('courier unassignment: لا يُفك الإسناد إلا مع إعادة feed مطابق في نفس العملية', async () => {
  await prepareOrderWithFeed();
  const admin = as('admin1');
  const assign = writeBatch(admin);
  assign.update(doc(admin, 'orders/o1'), {
    courierId: 'cour1', courierName: 'C', courierPhone: '01012345678',
    courierAt: serverTimestamp(), deliveryMode: 'external',
  });
  assign.delete(doc(admin, 'courier_available_orders/o1'));
  await assertSucceeds(assign.commit());

  const partial = writeBatch(admin);
  partial.update(doc(admin, 'orders/o1'), {
    courierId: deleteField(), courierName: deleteField(),
    courierPhone: deleteField(), courierAt: deleteField(), deliveryMode: deleteField(),
  });
  await assertFails(partial.commit());
  assert.equal((await getDoc(doc(admin, 'orders/o1'))).data().courierId, 'cour1');

  const order = (await getDoc(doc(admin, 'orders/o1'))).data();
  const atomic = writeBatch(admin);
  atomic.update(doc(admin, 'orders/o1'), {
    courierId: deleteField(), courierName: deleteField(),
    courierPhone: deleteField(), courierAt: deleteField(), deliveryMode: deleteField(),
  });
  atomic.set(doc(admin, 'courier_available_orders/o1'), {
    storeId: order.storeId, storeName: order.storeName, area: order.area ?? '',
    items: order.items, subtotal: order.subtotal, deliveryFee: order.deliveryFee,
    ...(order.finalDeliveryFee !== undefined ? { finalDeliveryFee: order.finalDeliveryFee } : {}),
    discount: order.discount ?? 0,
    total: order.total, status: 'preparing', createdAt: order.createdAt,
  });
  await assertSucceeds(atomic.commit());
  assert.equal((await getDoc(doc(admin, 'orders/o1'))).data().courierId ?? '', '');
  assert.equal(await feedExists(), true);
});


test('serverOrders: عند تفعيل البوابة الموثوقة تُرفض كتابة الطلب وحدّ الطلب مباشرة من التطبيق', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'app_info/security'), { serverOrders: true });
  });
  await assertFails(setDoc(doc(as('cust1'), 'orders/gateway-required'), {
    ...baseOrder('cust1'),
    createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(as('cust1'), 'orderLimits/cust1'), {
    lastAt: serverTimestamp(),
  }));
});

test('serverOrders: يمنع تعديل أصناف الطلب مباشرة من العميل بعد تفعيل البوابة', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'app_info/security'), { serverOrders: true });
  });
  await assertFails(updateDoc(doc(as('cust1'), 'orders/o1'), {
    items: [{ name: 'p', price: 1, qty: 2, productId: 'p1' }],
    subtotal: 2,
    total: 22,
    notes: '',
    customerName: 'Ali',
    editedAt: serverTimestamp(),
  }));
});

test('courier settlements: الإيصال ورصيد المندوب لازم يتسجلوا ذريًا وبنفس المبلغ', async () => {
  const admin = as('admin1');
  const settlement = {
    courierId: 'cour1',
    courierName: 'C',
    amount: 10,
    amountMinor: 1000,
    note: 'توريد نقدية',
    createdBy: 'admin1',
    createdAt: serverTimestamp(),
  };
  const balance = {
    courierId: 'cour1',
    settledAmountMinor: 1000,
    lastSettlementId: 's1',
    updatedAt: serverTimestamp(),
  };

  const receiptOnly = writeBatch(admin);
  receiptOnly.set(doc(admin, 'courier_settlements/s1'), settlement);
  await assertFails(receiptOnly.commit());

  const balanceOnly = writeBatch(admin);
  balanceOnly.set(doc(admin, 'courier_settlement_balances/cour1'), balance);
  await assertFails(balanceOnly.commit());

  const first = writeBatch(admin);
  first.set(doc(admin, 'courier_settlements/s1'), settlement);
  first.set(doc(admin, 'courier_settlement_balances/cour1'), balance);
  await assertSucceeds(first.commit());

  const wrongAmount = writeBatch(admin);
  wrongAmount.set(doc(admin, 'courier_settlements/s2'), {
    ...settlement, amount: 5, amountMinor: 500, createdAt: serverTimestamp(),
  });
  wrongAmount.update(doc(admin, 'courier_settlement_balances/cour1'), {
    settledAmountMinor: 1600,
    lastSettlementId: 's2',
    updatedAt: serverTimestamp(),
  });
  await assertFails(wrongAmount.commit());

  const second = writeBatch(admin);
  second.set(doc(admin, 'courier_settlements/s2'), {
    ...settlement, amount: 5, amountMinor: 500, createdAt: serverTimestamp(),
  });
  second.update(doc(admin, 'courier_settlement_balances/cour1'), {
    settledAmountMinor: 1500,
    lastSettlementId: 's2',
    updatedAt: serverTimestamp(),
  });
  await assertSucceeds(second.commit());

  await assertSucceeds(getDoc(doc(as('cour1'), 'courier_settlements/s1')));
  await assertFails(getDoc(doc(as('cust1'), 'courier_settlements/s1')));
  const { collection, getDocs, query, where } = require('firebase/firestore');
  const ownReceipts = query(
    collection(as('cour1'), 'courier_settlements'),
    where('courierId', '==', 'cour1'),
  );
  await assertSucceeds(getDocs(ownReceipts));
  await assertFails(getDocs(collection(as('cour1'), 'courier_settlements')));
  await assertFails(setDoc(doc(as('cour1'), 'courier_settlements/forged'), {
    ...settlement, createdAt: serverTimestamp(),
  }));
  await assertFails(getDoc(doc(as('cour1'), 'courier_settlement_balances/cour1')));
  await assertSucceeds(getDoc(doc(admin, 'courier_settlement_balances/cour1')));
});

test('courier settlements: التوريدان المتزامنان لا يضاعفان الرصيد', async () => {
  const admin = as('admin1');
  const initial = writeBatch(admin);
  initial.set(doc(admin, 'courier_settlements/base'), {
    courierId: 'cour1', courierName: 'C', amount: 10, amountMinor: 1000,
    note: '', createdBy: 'admin1', createdAt: serverTimestamp(),
  });
  initial.set(doc(admin, 'courier_settlement_balances/cour1'), {
    courierId: 'cour1', settledAmountMinor: 1000,
    lastSettlementId: 'base', updatedAt: serverTimestamp(),
  });
  await assertSucceeds(initial.commit());

  const makeAttempt = (id) => {
    const batch = writeBatch(admin);
    batch.set(doc(admin, `courier_settlements/${id}`), {
      courierId: 'cour1', courierName: 'C', amount: 5, amountMinor: 500,
      note: '', createdBy: 'admin1', createdAt: serverTimestamp(),
    });
    batch.update(doc(admin, 'courier_settlement_balances/cour1'), {
      settledAmountMinor: 1500,
      lastSettlementId: id,
      updatedAt: serverTimestamp(),
    });
    return batch.commit();
  };

  const results = await Promise.allSettled([
    makeAttempt('parallel-a'),
    makeAttempt('parallel-b'),
  ]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  const { collection, getDocs, query, where } = require('firebase/firestore');
  const receipts = await assertSucceeds(getDocs(query(
    collection(admin, 'courier_settlements'),
    where('courierId', '==', 'cour1'),
  )));
  assert.equal(receipts.size, 2);
  assert.equal(
    (await getDoc(doc(admin, 'courier_settlement_balances/cour1'))).data().settledAmountMinor,
    1500,
  );
});

test('courier settlements: لا يقبل مبلغًا غير صالح أو إيصالًا دون رصيد مطابق', async () => {
  const admin = as('admin1');
  const invalid = writeBatch(admin);
  invalid.set(doc(admin, 'courier_settlements/bad'), {
    courierId: 'cour1',
    courierName: 'C',
    amount: 0,
    amountMinor: 0,
    note: '',
    createdBy: 'admin1',
    createdAt: serverTimestamp(),
  });
  await assertFails(invalid.commit());

  const mismatched = writeBatch(admin);
  mismatched.set(doc(admin, 'courier_settlements/mismatch'), {
    courierId: 'cour1',
    courierName: 'C',
    amount: 12,
    amountMinor: 1200,
    note: '',
    createdBy: 'admin1',
    createdAt: serverTimestamp(),
  });
  mismatched.set(doc(admin, 'courier_settlement_balances/cour1'), {
    courierId: 'cour1',
    settledAmountMinor: 1100,
    lastSettlementId: 'mismatch',
    updatedAt: serverTimestamp(),
  });
  await assertFails(mismatched.commit());

  const inconsistentUnits = writeBatch(admin);
  inconsistentUnits.set(doc(admin, 'courier_settlements/inconsistent-units'), {
    courierId: 'cour1',
    courierName: 'C',
    amount: 12,
    amountMinor: 1199,
    note: '',
    createdBy: 'admin1',
    createdAt: serverTimestamp(),
  });
  inconsistentUnits.set(doc(admin, 'courier_settlement_balances/cour1'), {
    courierId: 'cour1',
    settledAmountMinor: 1199,
    lastSettlementId: 'inconsistent-units',
    updatedAt: serverTimestamp(),
  });
  await assertFails(inconsistentUnits.commit());
});


// ───────── حدّ 1000 تعبير في قواعد الطلبات: مسارات الأسوأ والتهريب بين الأدوار ─────────
// (الـ CI بيفشل كمان لو ظهر "maximum of 1000 expressions" في سجل الـ Emulator.)

test('expression limit: مستخدم واحد بكل الأدوار يمرّ بكل فروع التحديث وينجح بمساره الصحيح', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins/multi1'), { name: 'M' });
    await setDoc(doc(db, 'couriers/multi1'), { name: 'M', active: true });
    await setDoc(doc(db, 'storeOwners/multi1'), { name: 'M', storeId: store, active: true });
    await setDoc(doc(db, 'orders/om1'), { ...baseOrder('multi1'), createdAt: new Date() });
  });
  const db = as('multi1');
  const b = writeBatch(db);
  b.update(doc(db, 'orders/om1'), { status: 'preparing' });
  b.set(doc(db, 'orders/om1/statusHistory/preparing'), {
    from: 'new', to: 'preparing', actorUid: 'multi1', actorRole: 'owner', at: serverTimestamp(),
  });
  await assertSucceeds(b.commit());
  await assertSucceeds(updateDoc(doc(db, 'orders/om1'), { ready: true, readyAt: serverTimestamp() }));
  // الإخفاء من سجل العميل: ممنوع والطلب لسه شغال، ومسموح بعد ما يخلص
  // (فرع العميل بعد مرور بقية الأدوار على نفس المستخدم).
  await assertFails(updateDoc(doc(db, 'orders/om1'), { customerHidden: true }));
  await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'orders/om1'), { status: 'cancelled' }));
  await assertSucceeds(updateDoc(doc(db, 'orders/om1'), { customerHidden: true }));
});

test('orders: مفيش حذف فعلي من التطبيق، والإخفاء للطلبات المنتهية بس', async () => {
  // o1 جديد ومملوك لـ cust1 (من seed)
  await assertFails(deleteDoc(doc(as('cust1'), 'orders/o1')));
  await assertFails(deleteDoc(doc(as('cust1'), 'orders/o1/private/contact')));
  await assertFails(deleteDoc(doc(as('owner1'), 'orders/o1')));
  // إخفاء طلب جديد (لسه شغال) مرفوض
  await assertFails(updateDoc(doc(as('cust1'), 'orders/o1'), { customerHidden: true }));
  // الإلغاء من العميل وهو جديد مسموح، وبعده الإخفاء مسموح
  await assertSucceeds(changeStatus(as('cust1'), 'o1', 'new', 'cancelled', 'customer'));
  await assertSucceeds(updateDoc(doc(as('cust1'), 'orders/o1'), { customerHidden: true }));
  // عميل تاني ما يقدرش يخفي طلب مش بتاعه
  await assertFails(updateDoc(doc(as('cust2'), 'orders/o1'), { customerHidden: true }));
  // الطلب لسه موجود للمحل والإدارة
  await assertSucceeds(getDoc(doc(as('owner1'), 'orders/o1')));
  await assertSucceeds(getDoc(doc(as('admin1'), 'orders/o1')));
});

test('expression limit: لا تهريب مفاتيح بين أدوار مختلفة في تحديث واحد', async () => {
  await seedOnWay('external');
  // مندوب: وصول + تغيير حالة
  await assertFails(updateDoc(doc(as('cour1'), 'orders/o1'), {
    courierArrivedAt: serverTimestamp(), status: 'delivered',
  }));
  // مندوب: وصول + مفتاح إداري
  await assertFails(updateDoc(doc(as('cour1'), 'orders/o1'), {
    courierArrivedAt: serverTimestamp(), verifiedTotal: 1,
  }));
  // عميل: إخفاء + إلغاء
  await assertFails(updateDoc(doc(as('cust1'), 'orders/o1'), {
    customerHidden: true, status: 'cancelled',
  }));
  // صاحب المحل: حالة + إخفاء العميل
  await assertFails(updateDoc(doc(as('owner1'), 'orders/o1'), {
    status: 'delivered', customerHidden: true,
  }));
});

test('expression limit: طلب بأقصى عدد أصناف (100) ينجح و101 يُرفض', async () => {
  const mk = (n) => Array.from({ length: n }, (_, i) => ({ name: `p${i}`, price: 10, qty: 1, productId: `p${i}` }));
  const order = (n) => baseOrder('cust1', { items: mk(n), subtotal: 10 * n, total: 10 * n + 20 });
  await assertSucceeds(setDoc(doc(as('cust1'), 'orders/big100'), order(100)));
  await assertFails(setDoc(doc(as('cust1'), 'orders/big101'), order(101)));
});

// ───────────── الكتالوج المجمّع (catalog_versions / store_index / menu) ─────────────
test('catalog menu: صاحب المحل يكتب قائمة محله فقط، والعميل يقرأ قائمة المحل النشط', async () => {
  const menu = { items: { p1: { name: 'p', price: 10 } }, count: 1, updatedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(as('owner1'), 'stores/shop1/menu/current'), menu));
  await assertFails(setDoc(doc(as('owner1'), 'stores/shop2/menu/current'), menu));
  await assertFails(setDoc(doc(as('cust1'), 'stores/shop1/menu/current'), menu));
  await assertFails(setDoc(doc(as('owner1'), 'stores/shop1/menu/other'), menu));
  await assertFails(setDoc(doc(as('owner1'), 'stores/shop1/menu/current'), { ...menu, junk: 1 }));
  await assertSucceeds(getDoc(doc(as('cust1'), 'stores/shop1/menu/current')));
  await assertSucceeds(setDoc(doc(as('admin1'), 'stores/shop2/menu/current'), menu));
  await assertFails(deleteDoc(doc(as('owner1'), 'stores/shop1/menu/current')));
});

test('catalog menu: قائمة محل غير نشط لا يقرأها العميل', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await updateDoc(doc(db, 'stores/shop2'), { active: false });
    await setDoc(doc(db, 'stores/shop2/menu/current'), { items: {}, count: 0 });
  });
  await assertFails(getDoc(doc(as('cust1'), 'stores/shop2/menu/current')));
  await assertSucceeds(getDoc(doc(as('owner2'), 'stores/shop2/menu/current')));
});

test('catalog versions: صاحب المحل يزوّد إصدار محله والفهرس بواحد فقط', async () => {
  const owner = as('owner1');
  const ref = doc(owner, 'app_info/catalog_versions');
  await assertSucceeds(setDoc(ref, { m_shop1: increment(1), stores: increment(1), updatedAt: serverTimestamp() }, { merge: true }));
  await assertSucceeds(setDoc(ref, { m_shop1: increment(1) }, { merge: true }));
  await assertFails(setDoc(ref, { m_shop1: increment(2) }, { merge: true }));
  await assertFails(setDoc(ref, { m_shop2: increment(1) }, { merge: true }));
  await assertFails(setDoc(ref, { stores: -1 }, { merge: true }));
  await assertFails(setDoc(ref, { stores: increment(5) }, { merge: true }));
  // التعطيل = سالب آخر إصدار صالح (الإصدار كان 2).
  await assertFails(setDoc(ref, { m_shop1: -1 }, { merge: true }));
  await assertSucceeds(setDoc(ref, { m_shop1: -2 }, { merge: true }));
  // indexReady للمدير بس (بيتكتب بعد بناء الفهرس الكامل).
  await assertFails(setDoc(ref, { indexReady: true }, { merge: true }));
  await assertFails(setDoc(doc(as('cust1'), 'app_info/catalog_versions'), { m_shop1: increment(1) }, { merge: true }));
  await assertSucceeds(setDoc(doc(as('admin1'), 'app_info/catalog_versions'), { stores: -1, m_shop2: 7 }, { merge: true }));
  await assertSucceeds(getDoc(doc(as('cust1'), 'app_info/catalog_versions')));
});

test('catalog store_index: صاحب المحل يحدّث خانة محله بنفس الاسم فقط', async () => {
  const entry = { name: 'S', active: true, time: '20-30', order: 1, rating: 4 };
  const owner = as('owner1');
  const ref = doc(owner, 'app_info/store_index');
  await assertSucceeds(setDoc(ref, { s_shop1: entry, updatedAt: serverTimestamp() }, { merge: true }));
  await assertFails(setDoc(ref, { s_shop1: { ...entry, name: 'اسم مزيف' } }, { merge: true }));
  await assertFails(setDoc(ref, { s_shop1: { ...entry, category: 'مطاعم' } }, { merge: true }));
  await assertFails(setDoc(ref, { s_shop1: { ...entry, active: false } }, { merge: true }));
  await assertFails(setDoc(ref, { s_shop2: { ...entry, name: 'S2' } }, { merge: true }));
  // محل نشط: صاحبه ما يقدرش يخفيه من الفهرس (الشيل مسموح بس لمحل مقفول/محذوف).
  await assertFails(setDoc(ref, { s_shop1: deleteField() }, { merge: true }));
  await assertFails(setDoc(doc(as('cust1'), 'app_info/store_index'), { s_shop1: entry }, { merge: true }));
  await assertSucceeds(setDoc(doc(as('admin1'), 'app_info/store_index'), { s_shop2: { name: 'S2', active: true } }, { merge: true }));
  await assertSucceeds(getDoc(doc(as('cust1'), 'app_info/store_index')));
});

test('catalog store_index: حد أمان 250 محل — صاحب محل جديد ما يضيفش خانة لو الفهرس مليان', async () => {
  const entry = { name: 'S', active: true, time: '20-30', order: 1, rating: 4 };
  const full = { updatedAt: new Date() };
  for (let i = 0; i < 250; i++) full[`s_x${i}`] = { name: `X${i}`, active: true };
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'app_info/store_index'), full);
  });
  const ref = doc(as('owner1'), 'app_info/store_index');
  await assertFails(setDoc(ref, { s_shop1: entry, updatedAt: serverTimestamp() }, { merge: true }));
  // لو محله موجود ضمن الـ 250، تحديثه مسموح (العدد ما زادش).
  const withShop = { ...full };
  delete withShop.s_x0;
  withShop.s_shop1 = entry;
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'app_info/store_index'), withShop);
  });
  await assertSucceeds(setDoc(ref, { s_shop1: entry, updatedAt: serverTimestamp() }, { merge: true }));
});

test('catalog versions: تعديل موجّه وقت ما القائمة معطلة بيترفض، وإعادة البناء ما تكررش رقم', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'app_info/catalog_versions'), { m_shop1: -2 });
  });
  const ref = doc(as('owner1'), 'app_info/catalog_versions');
  // جهاز تاني عطّل القائمة: الزيادة الموجّهة (-2 → -1) لازم تترفض، فالمزامنة تعيد البناء.
  await assertFails(setDoc(ref, { m_shop1: increment(1) }, { merge: true }));
  await assertFails(setDoc(ref, { m_shop1: 2 }, { merge: true }));
  await assertSucceeds(setDoc(ref, { m_shop1: 3 }, { merge: true }));
  await assertSucceeds(setDoc(ref, { m_shop1: -3 }, { merge: true }));
  // رجوع لرقم اتستخدم قبل كده (3) مرفوض: لازم 4.
  await assertFails(setDoc(ref, { m_shop1: 3 }, { merge: true }));
  await assertSucceeds(setDoc(ref, { m_shop1: 4 }, { merge: true }));
});

test('catalog store_index: محل موقوف لا يضاف للفهرس، وصاحب محل موقوف الحساب لا يكتب', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'stores/shop1'), { active: false });
  });
  const entry = { name: 'S', active: true, time: '20-30', order: 1, rating: 4 };
  await assertFails(setDoc(doc(as('owner1'), 'app_info/store_index'), { s_shop1: entry }, { merge: true }));
  await assertSucceeds(setDoc(doc(as('owner1'), 'app_info/store_index'), { s_shop1: deleteField() }, { merge: true }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'storeOwners/owner1'), { active: false });
  });
  await assertFails(setDoc(doc(as('owner1'), 'app_info/catalog_versions'), { m_shop1: increment(1) }, { merge: true }));
});

test('catalog store_index: صاحب المحل ما يقدرش يزوّر التقييم أو الترتيب أو الرقم أو يضيف حقول', async () => {
  const entry = { name: 'S', active: true, time: '20-30', order: 1, rating: 4 };
  const ref = doc(as('owner1'), 'app_info/store_index');
  await assertSucceeds(setDoc(ref, { s_shop1: entry }, { merge: true }));
  for (const forged of [
    { rating: 5 }, { order: 0 }, { storePhone: '01099999999' }, { ratingSum: 50, ratingCount: 10 },
    { ownerUid: 'owner1' }, { approved: true }, { junk: 'x' }, { image: 'https://x' },
  ]) {
    await assertFails(setDoc(ref, { s_shop1: { ...entry, ...forged } }, { merge: true }));
  }
  // حذف حقل عرض موجود في مستند المحل (زي التقييم أو الترتيب) مرفوض برضه.
  // (merge بيدمج الخريطة الداخلية، فالحذف لازم deleteField.)
  await assertFails(setDoc(ref, { s_shop1: { ...entry, rating: deleteField() } }, { merge: true }));
  await assertFails(setDoc(ref, { s_shop1: { ...entry, order: deleteField() } }, { merge: true }));
});

test('catalog store_index: العروض نص مضغوط واحد "hl" بطول محدود', async () => {
  const entry = { name: 'S', active: true, time: '20-30', order: 1, rating: 4 };
  const ref = doc(as('owner1'), 'app_info/store_index');
  const hl = JSON.stringify({ o: Array(4).fill({ n: 'عرض', p: 10, op: 12, i: 'https://img' }), b: [] });
  await assertSucceeds(setDoc(ref, { s_shop1: { ...entry, hl } }, { merge: true }));
  await assertSucceeds(setDoc(ref, { s_shop1: { ...entry, hl: 'x'.repeat(1400) } }, { merge: true }));
  await assertFails(setDoc(ref, { s_shop1: { ...entry, hl: 'x'.repeat(1401) } }, { merge: true }));
  await assertFails(setDoc(ref, { s_shop1: { ...entry, hl: ['x'] } }, { merge: true }));
  // الشكل القديم (قوائم) مبقاش مقبول في الفهرس.
  await assertFails(setDoc(ref, { s_shop1: { ...entry, hl: deleteField(), offerItems: [] } }, { merge: true }));
});

test('catalog rating sync: آخر عميل قيّم يحدّث رقمي التقييم في الفهرس بقيم المحل بالظبط وبس', async () => {
  const entry = { name: 'S', active: true, time: '20-30', order: 1, rating: 4, ratingSum: 5, ratingCount: 1 };
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await updateDoc(doc(db, 'stores/shop1'), { ratingSum: 9, ratingCount: 2, lastReviewId: 'r1' });
    await setDoc(doc(db, 'reviews/r1'), { userId: 'cust1', storeId: 'shop1', rating: 4, orderId: 'o1' });
    await setDoc(doc(db, 'app_info/store_index'), { s_shop1: entry, s_shop2: { name: 'S2', active: true } });
    await setDoc(doc(db, 'app_info/catalog_versions'), { stores: 5, indexReady: true });
  });
  const ref = (uid) => doc(as(uid), 'app_info/store_index');
  const sync = (sum, count, sid = 'shop1') =>
    ({ [`s_${sid}`]: { ratingSum: sum, ratingCount: count }, ratingSync: sid });

  // تزوير أرقام أو عميل تاني: مرفوض.
  await assertFails(setDoc(ref('cust1'), sync(10, 2), { merge: true }));
  await assertFails(setDoc(ref('cust2'), sync(9, 2), { merge: true }));
  // حقل تاني في الخانة أو حقل في المستند غير ratingSync: مرفوض.
  await assertFails(setDoc(ref('cust1'), { s_shop1: { ratingSum: 9, ratingCount: 2, order: 0 }, ratingSync: 'shop1' }, { merge: true }));
  await assertFails(setDoc(ref('cust1'), { ...sync(9, 2), updatedAt: serverTimestamp() }, { merge: true }));
  // محل تاني (آخر تقييم مش بتاعه) أو خانة مش موجودة: مرفوض.
  await assertFails(setDoc(ref('cust1'), sync(0, 0, 'shop2'), { merge: true }));
  await assertFails(setDoc(ref('cust1'), sync(0, 0, 'shop9'), { merge: true }));
  // القيم الصحيحة من آخر عميل قيّم: مسموح، ورقم إصدار الفهرس ما بيتغيرش.
  await assertSucceeds(setDoc(ref('cust1'), sync(9, 2), { merge: true }));
  await assertFails(setDoc(doc(as('cust1'), 'app_info/catalog_versions'), { stores: 6 }, { merge: true }));

  // تقييم أحدث وصل: الكتابة القديمة (9/2) مرفوضة حتى من صاحبها، والأحدث بس اللي يتقبل.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await updateDoc(doc(db, 'stores/shop1'), { ratingSum: 14, ratingCount: 3, lastReviewId: 'r2' });
    await setDoc(doc(db, 'reviews/r2'), { userId: 'cust2', storeId: 'shop1', rating: 5, orderId: 'o2' });
  });
  await assertFails(setDoc(ref('cust1'), sync(9, 2), { merge: true }));
  await assertFails(setDoc(ref('cust1'), sync(14, 3), { merge: true }));
  await assertSucceeds(setDoc(ref('cust2'), sync(14, 3), { merge: true }));

  // تحديث صاحب المحل لخانته بعد كده (بالأرقام الجديدة) شغال عادي مع وجود ratingSync.
  await assertSucceeds(setDoc(ref('owner1'), {
    s_shop1: { ...entry, ratingSum: 14, ratingCount: 3 }, updatedAt: serverTimestamp(),
  }, { merge: true }));
  let snap;
  await env.withSecurityRulesDisabled(async (ctx) => {
    snap = (await getDoc(doc(ctx.firestore(), 'app_info/store_index'))).data();
  });
  assert.equal(snap.s_shop1.ratingSum, 14);
  assert.equal(snap.s_shop1.ratingCount, 3);
  assert.equal(snap.s_shop1.name, 'S');
});

test('catalog store_index: فوق حد الـ 250، تعديل خانة موجودة مسموح طالما العدد ما زادش', async () => {
  const entry = { name: 'S', active: true, time: '20-30', order: 1, rating: 4 };
  const over = { updatedAt: new Date(), s_shop1: entry };
  for (let i = 0; i < 260; i++) over[`s_x${i}`] = { name: `X${i}`, active: true };
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'app_info/store_index'), over);
  });
  const ref = doc(as('owner1'), 'app_info/store_index');
  await assertSucceeds(setDoc(ref, { s_shop1: { ...entry, hl: '{}' }, updatedAt: serverTimestamp() }, { merge: true }));
});

test('catalog versions: الأرقام ما تتكررش بعد التعطيل، وbig_ لمحله بس، وindexReady للمدير بس', async () => {
  const ref = doc(as('owner1'), 'app_info/catalog_versions');
  await assertFails(setDoc(ref, { indexReady: true, m_shop1: 1 }));
  await assertSucceeds(setDoc(ref, { m_shop1: 1 }));
  await assertSucceeds(setDoc(ref, { m_shop1: 2 }, { merge: true }));
  // تعطيل = -2 (سالب السابق)، مش أي رقم سالب.
  await assertFails(setDoc(ref, { m_shop1: -1 }, { merge: true }));
  await assertSucceeds(setDoc(ref, { m_shop1: -2 }, { merge: true }));
  // الرجوع لازم يبقى 3 (|−2|+1)؛ 1 أو 2 اتستخدموا قبل كده والعميل ممكن يكون مخزّنهم.
  await assertFails(setDoc(ref, { m_shop1: 1 }, { merge: true }));
  await assertFails(setDoc(ref, { m_shop1: 2 }, { merge: true }));
  await assertFails(setDoc(ref, { m_shop1: 5 }, { merge: true }));
  await assertSucceeds(setDoc(ref, { m_shop1: 3 }, { merge: true }));
  // التعطيل من حالة معطلة أو صفر مرفوض (ما فيش سالب لسالب).
  await assertSucceeds(setDoc(ref, { m_shop1: -3 }, { merge: true }));
  await assertFails(setDoc(ref, { m_shop1: 3 }, { merge: true }));
  await assertSucceeds(setDoc(ref, { big_shop1: true }, { merge: true }));
  await assertFails(setDoc(ref, { big_shop2: true }, { merge: true }));
  await assertFails(setDoc(ref, { big_shop1: 'yes' }, { merge: true }));
  await assertFails(setDoc(ref, { indexReady: false }, { merge: true }));
});

test('catalog: صاحب طلب انضمام يدير قائمة وإصدار مسودته بس، ومسودته ما تدخلش الفهرس', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'stores/draft1'), { name: 'مسودة', category: 'مطاعم', ownerUid: 'app1', active: false, approved: false });
    await setDoc(doc(db, 'role_requests/app1_store_owner'), { userId: 'app1', type: 'store_owner', status: 'pending', storeId: 'draft1' });
  });
  const db = as('app1');
  await assertSucceeds(setDoc(doc(db, 'stores/draft1/menu/current'), { items: {}, count: 0 }));
  await assertFails(setDoc(doc(db, 'stores/shop1/menu/current'), { items: {}, count: 0 }));
  await assertSucceeds(setDoc(doc(db, 'app_info/catalog_versions'), { m_draft1: 1 }, { merge: true }));
  await assertFails(setDoc(doc(db, 'app_info/catalog_versions'), { m_shop1: 1 }, { merge: true }));
  await assertFails(setDoc(doc(db, 'app_info/store_index'), { s_draft1: { name: 'مسودة', category: 'مطاعم', active: true } }, { merge: true }));
  await assertSucceeds(setDoc(doc(db, 'app_info/store_index'), { s_draft1: deleteField() }, { merge: true }));
});
