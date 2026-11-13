/**
 * إشعارات وصّلي (Firebase Cloud Functions v2).
 *
 * - طلب جديد            ← كل المديرين + صاحب المحل
 * - تغيير حالة الطلب    ← العميل صاحب الطلب
 * - تكليف مندوب بطلب    ← المندوب
 * - طلب اتلغى / اتسلّم  ← المديرين (والمندوب في حالة الإلغاء)
 *
 * توكنات الأجهزة متخزنة في users/{uid}.fcmTokens (التطبيق بيسجّلها).
 */
const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} = require('firebase-functions/v2/firestore');
const { defineSecret, defineString } = require('firebase-functions/params');
const crypto = require('crypto');
const functionsV1 = require('firebase-functions/v1');
const admin = require('firebase-admin');

admin.initializeApp();
// نفس منطقة قاعدة البيانات (europe-west3) عشان التشغيل يكون أسرع.
setGlobalOptions({ region: 'europe-west3', maxInstances: 5 });

const db = admin.firestore();

const CUSTOMER_STATUS_TEXT = {
  new: 'تم استلام طلبك',
  preparing: 'طلبك بيتجهز دلوقتي',
  on_the_way: 'طلبك في الطريق إليك',
  delivered: 'تم توصيل طلبك. بالهنا والشفا',
  cancelled: 'تم إلغاء طلبك',
};

function shortId(id) {
  return '#' + String(id).slice(0, 5).toUpperCase();
}

function money(n) {
  const v = Number(n) || 0;
  return (Number.isInteger(v) ? String(v) : v.toFixed(1)) + ' ج.م';
}

async function adminUids() {
  const snap = await db.collection('admins').get();
  return snap.docs.map((d) => d.id);
}

/** أصحاب المحل النشطين (storeOwners.storeId == storeId). فشل الاستعلام ما يوقفش الإشعار. */
async function ownerUids(storeId) {
  if (!storeId) return [];
  try {
    const snap = await db.collection('storeOwners').where('storeId', '==', storeId).get();
    return snap.docs.filter((d) => d.get('active') !== false).map((d) => d.id);
  } catch (e) {
    console.error('ownerUids failed', e);
    return [];
  }
}

/** بترجع [{uid, token}] لكل أجهزة المستخدمين المطلوبين. */
async function tokensOf(uids) {
  const out = [];
  await Promise.all(
    uids.map(async (uid) => {
      const snap = await db.collection('users').doc(uid).get();
      const list = snap.exists ? snap.get('fcmTokens') : null;
      if (!Array.isArray(list)) return;
      for (const token of list) {
        if (typeof token === 'string' && token) out.push({ uid, token });
      }
    }),
  );
  return out;
}

/** بتبعت إشعار لكل أجهزة المستخدمين، وبتمسح التوكنات الميتة. */
async function notify(uids, title, body, data = {}) {
  const unique = [...new Set(uids.filter(Boolean))];
  if (unique.length === 0) return;

  const entries = (await tokensOf(unique)).slice(0, 500);
  if (entries.length === 0) return;

  const res = await admin.messaging().sendEachForMulticast({
    tokens: entries.map((e) => e.token),
    notification: { title, body },
    data,
    android: { priority: 'high', notification: { sound: 'default' } },
  });

  const dead = [];
  res.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      dead.push(entries[i]);
    }
  });
  await Promise.all(
    dead.map((e) =>
      db
        .collection('users')
        .doc(e.uid)
        .update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(e.token),
        })
        .catch(() => {}),
    ),
  );
}


/**
 * قائمة آمنة للطلبات التي يمكن للمندوبين التقديم عليها.
 * لا تحتوي اسم العميل أو ملاحظاته أو هاتفه أو عنوانه أو بيانات الاتصال الخاصة.
 * الكتابة من السيرفر فقط، وتُحذف بمجرد التعيين أو الخروج من preparing.
 */
exports.syncCourierAvailableOrder = onDocumentWritten('orders/{orderId}', async (event) => {
  const after = event.data && event.data.after && event.data.after.exists
    ? event.data.after.data()
    : null;
  const id = event.params.orderId;
  const ref = db.collection('courier_available_orders').doc(id);

  if (!after || after.status !== 'preparing' ||
      String(after.courierId || '').trim() !== '') {
    await ref.delete().catch((e) => {
      if (e.code !== 5) throw e;
    });
    return;
  }

  const safeItems = Array.isArray(after.items)
    ? after.items.slice(0, 15).map((item) => ({
        name: String((item && item.name) || '').slice(0, 100),
        qty: Math.max(1, Math.min(50, Number((item && item.qty) || 1))),
      }))
    : [];

  await ref.set({
    storeId: String(after.storeId || ''),
    storeName: String(after.storeName || '').slice(0, 100),
    items: safeItems,
    total: Number(after.total) || 0,
    status: 'preparing',
    courierId: '',
    createdAt: after.createdAt || admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.onOrderCreated = onDocumentCreated('orders/{orderId}', async (event) => {
  const order = event.data && event.data.data();
  if (!order) return;
  const id = event.params.orderId;

  await notify(
    [...(await adminUids()), ...(await ownerUids(order.storeId))],
    'طلب جديد ' + shortId(id),
    `${order.customerName || 'عميل'} • ${order.storeName || 'محل'} • ${money(order.total)}`,
    { type: 'new_order', orderId: id },
  );
});

exports.onOrderUpdated = onDocumentUpdated('orders/{orderId}', async (event) => {
  if (!event.data) return;
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after) return;
  const id = event.params.orderId;
  const tasks = [];

  if (before.status !== after.status) {
    const text = CUSTOMER_STATUS_TEXT[after.status];
    if (text && after.userId) {
      tasks.push(
        notify([after.userId], 'طلبك ' + shortId(id), text, {
          type: 'status',
          orderId: id,
          status: String(after.status),
        }),
      );
    }

    if (after.status === 'cancelled' || after.status === 'delivered') {
      const cancelled = after.status === 'cancelled';
      tasks.push(
        (async () => {
          const uids = [...(await adminUids()), ...(await ownerUids(after.storeId))];
          if (cancelled && after.courierId) uids.push(after.courierId);
          await notify(
            uids,
            (cancelled ? 'طلب ملغي ' : 'تم تسليم طلب ') + shortId(id),
            `${after.customerName || 'عميل'} • ${money(after.total)}`,
            { type: cancelled ? 'cancelled' : 'delivered', orderId: id },
          );
        })(),
      );
    }
  }

  if (before.courierId !== after.courierId && after.courierId) {
    tasks.push(
      notify(
        [after.courierId],
        'طلب جديد ليك ' + shortId(id),
        `${after.storeName || 'محل'} • ${money(after.total)}`,
        { type: 'assigned', orderId: id },
      ),
    );
  }

  await Promise.all(tasks);
});

/**
 * عند حذف حساب: نمسح ملفه الشخصي، ونشيل بياناته الشخصية من طلباته القديمة
 * (بنسيب الأصناف والمبالغ والتواريخ كسجل مجهّل للمحاسبة).
 */
async function deleteQueryInBatches(query, transform) {
  let deleted = 0;
  let cursor = null;
  for (;;) {
    let pageQuery = query.orderBy(admin.firestore.FieldPath.documentId()).limit(400);
    if (cursor) pageQuery = pageQuery.startAfter(cursor);
    const page = await pageQuery.get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) {
      if (transform) batch.update(doc.ref, transform(doc));
      else batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += page.size;
    cursor = page.docs[page.docs.length - 1];
    if (page.size < 400) break;
  }
  return deleted;
}

async function deleteSubcollection(ref, name) {
  let deleted = 0;
  for (;;) {
    const page = await ref.collection(name).limit(400).get();
    if (page.empty) break;
    const batch = db.batch();
    page.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += page.size;
    if (page.size < 400) break;
  }
  return deleted;
}

/**
 * Account deletion cleanup. Preserve only genuinely de-identified financial/order
 * aggregates; remove role documents, user-generated support/complaint content,
 * device tokens and direct identifiers. Firestore subcollections are deleted
 * explicitly because deleting a parent document does not cascade.
 */
exports.onUserDeleted = functionsV1
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .auth.user().onDelete(async (user) => {
  const uid = user.uid;
  const ownerProfile = await db.collection('storeOwners').doc(uid).get();
  const ownedStoreId = ownerProfile.exists ? String(ownerProfile.get('storeId') || '') : '';

  // Customer orders: retain commercial lines/totals for accounting, remove contact data.
  {
    const baseQuery = db.collection('orders').where('userId', '==', uid);
    let cursor = null;
    for (;;) {
      let q = baseQuery.orderBy(admin.firestore.FieldPath.documentId()).limit(200);
      if (cursor) q = q.startAfter(cursor);
      const page = await q.get();
      if (page.empty) break;
      const batch = db.batch();
      for (const order of page.docs) {
        batch.update(order.ref, {
          customerName: 'عميل محذوف', notes: '', userId: 'deleted', userDeleted: true,
          userName: admin.firestore.FieldValue.delete(),
          userEmail: admin.firestore.FieldValue.delete(),
          phone: admin.firestore.FieldValue.delete(),
          address: admin.firestore.FieldValue.delete(),
        });
        batch.delete(order.ref.collection('private').doc('contact'));
      }
      await batch.commit();
      cursor = page.docs[page.docs.length - 1];
      if (page.size < 200) break;
    }
  }

  // Remove applicant records (subcollection under orders).
  await deleteQueryInBatches(
    db.collectionGroup('applicants').where('courierId', '==', uid), null,
  );

  // Active courier assignments must become available again; delivered records remain
  // for accounting but the courier identifier is pseudonymized.
  await deleteQueryInBatches(db.collection('orders').where('courierId', '==', uid), (doc) => {
    const d = doc.data();
    if (['delivered', 'cancelled'].includes(d.status)) {
      return {
        courierId: 'deleted', courierName: 'مندوب محذوف', courierPhone: '',
        deliveredBy: d.deliveredBy === uid ? 'deleted' : (d.deliveredBy || ''),
      };
    }
    return {
      courierId: admin.firestore.FieldValue.delete(),
      courierName: admin.firestore.FieldValue.delete(),
      courierPhone: admin.firestore.FieldValue.delete(),
      courierAt: admin.firestore.FieldValue.delete(),
      status: d.status === 'on_the_way' ? 'preparing' : d.status,
    };
  });
  await deleteQueryInBatches(db.collection('orders').where('deliveredBy', '==', uid), () => ({ deliveredBy: 'deleted' }));
  await deleteQueryInBatches(
    db.collectionGroup('statusHistory').where('actorUid', '==', uid),
    () => ({ actorUid: 'deleted' }),
  );

  // Remove user-authored content that contains contact details or free text.
  await deleteQueryInBatches(db.collection('complaints').where('userId', '==', uid), null);
  await deleteQueryInBatches(db.collection('role_requests').where('userId', '==', uid), null);
  await deleteQueryInBatches(db.collection('notifications').where('userId', '==', uid), null);

  // Keep aggregate rating values but remove the link/comment identifying the rater.
  await deleteQueryInBatches(db.collection('reviews').where('userId', '==', uid), () => ({
    userId: 'deleted', comment: admin.firestore.FieldValue.delete(), userDeleted: true,
  }));
  // If the deleted account was the rated courier, keep the numeric rating but
  // remove the courier identity and free-text comment from historical reviews.
  await deleteQueryInBatches(db.collection('reviews').where('courierId', '==', uid), () => ({
    courierId: 'deleted', comment: admin.firestore.FieldValue.delete(), courierDeleted: true,
  }));
  await deleteQueryInBatches(db.collection('courier_settlements').where('courierId', '==', uid), () => ({
    courierId: 'deleted', courierName: 'مندوب محذوف', note: '', courierDeleted: true,
  }));

  // Support chat has a messages subcollection; delete children before parent.
  const chatRef = db.collection('support_chats').doc(uid);
  await deleteSubcollection(chatRef, 'messages');
  await chatRef.delete().catch(() => {});

  // Remove role/profile documents for every supported role.
  const roleCollections = ['admins', 'couriers', 'storeOwners', 'supervisors'];
  await Promise.all(roleCollections.map((name) => db.collection(name).doc(uid).delete().catch(() => {})));

  // If this was the last active owner of a store, deactivate its listing. Keep
  // the store/catalog for possible reassignment by an administrator.
  if (ownedStoreId) {
    const remainingOwners = await db.collection('storeOwners')
      .where('storeId', '==', ownedStoreId).get();
    const hasActiveOwner = remainingOwners.docs.some((d) => d.get('active') !== false);
    if (!hasActiveOwner) {
      await db.collection('stores').doc(ownedStoreId).update({
        active: false, ownerDeleted: true, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error('store deactivation after owner deletion failed', e));
    }
  }

  // If this user supervised couriers, detach those couriers rather than leaving
  // references to a deleted supervisor. Do not delete the couriers' accounts.
  await deleteQueryInBatches(
    db.collection('couriers').where('supervisorId', '==', uid),
    () => ({ supervisorId: admin.firestore.FieldValue.delete() }),
  );

  await db.collection('first_orders').doc(uid).delete().catch(() => {});
  await deleteQueryInBatches(db.collection('account_deletions').where('userId', '==', uid), null);
  await db.collection('account_deletions').doc(uid).delete().catch(() => {});
  await db.collection('users').doc(uid).delete().catch(() => {});
});

/**
 * ترحيل لمرة واحدة للمدير: ينقل (الاسم الكامل، الموبايل، العنوان، الإيميل) من مستند كل طلب قديم
 * إلى orders/{id}/private/contact ويشيلهم من المستند العام، وبكده صاحب المحل والمناديب
 * ما يشوفوش بيانات العملاء. آمن للتكرار. بيرجّع { migrated } وممكن تناديه تاني لحد ما يرجّع done=true.
 */
exports.migrateOrderContacts = onCall({ timeoutSeconds: 540 }, async (request) => {
  if (!(await isCallerAdmin(request.auth))) {
    throw new HttpsError('permission-denied', 'للمديرين فقط.');
  }
  const FieldValue = admin.firestore.FieldValue;
  const LEGACY = ['userName', 'userEmail', 'phone', 'address'];
  let migrated = 0;
  let last = null;
  const started = Date.now();
  for (;;) {
    let q = db.collection('orders').orderBy(admin.firestore.FieldPath.documentId()).limit(200);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) return { migrated, done: true };
    const batch = db.batch();
    let ops = 0;
    for (const doc of page.docs) {
      const d = doc.data();
      if (!LEGACY.some((k) => k in d)) continue;
      const contactRef = doc.ref.collection('private').doc('contact');
      if (d.phone || d.address || d.userName) {
        batch.set(contactRef, {
          userName: String(d.userName || ''),
          phone: String(d.phone || ''),
          address: String(d.address || ''),
        });
      }
      const first = String(d.userName || '').trim().split(/\s+/)[0] || 'عميل';
      const upd = { customerName: d.customerName || first.slice(0, 30) };
      for (const k of LEGACY) upd[k] = FieldValue.delete();
      batch.update(doc.ref, upd);
      ops += 2;
      migrated += 1;
    }
    if (ops > 0) await batch.commit();
    last = page.docs[page.docs.length - 1];
    if (Date.now() - started > 480000) return { migrated, done: false };
  }
});

// ───────────────────────── إدارة الأدوار (من السيرفر فقط) ─────────────────────────

const ROLES = ['admin', 'courier', 'customer'];

async function isCallerAdmin(auth) {
  if (!auth) return false;
  if (auth.token && auth.token.admin === true) return true;
  const snap = await db.collection('admins').doc(auth.uid).get();
  return snap.exists;
}

/** بتضبط الـ Custom Claims ومستندات admins/couriers بشكل متسق. */
async function applyRole(uid, role, name) {
  const batch = db.batch();
  const adminRef = db.collection('admins').doc(uid);
  const courierRef = db.collection('couriers').doc(uid);
  // أي تغيير دور من هنا بيفك ارتباط المستخدم بمحل (ربط المحل من شاشة أصحاب المحلات).
  batch.delete(db.collection('storeOwners').doc(uid));
  if (role === 'admin') {
    batch.set(adminRef, { name: name || '' }, { merge: true });
    batch.delete(courierRef);
  } else if (role === 'courier') {
    batch.set(courierRef, { name: name || '', active: true }, { merge: true });
    batch.delete(adminRef);
  } else {
    batch.delete(adminRef);
    batch.delete(courierRef);
  }
  await batch.commit();
  await admin.auth().setCustomUserClaims(uid, {
    admin: role === 'admin',
    courier: role === 'courier',
  });
  // نلغي الجلسات القديمة عشان الدور الجديد يسري فورًا.
  await admin.auth().revokeRefreshTokens(uid);
}

/**
 * تغيير دور مستخدم. للمدير فقط.
 * data: { email: string, role: 'admin' | 'courier' | 'customer', name?: string }
 */
exports.setUserRole = onCall(async (request) => {
  if (!(await isCallerAdmin(request.auth))) {
    throw new HttpsError('permission-denied', 'للمديرين فقط.');
  }
  const email = String((request.data && request.data.email) || '')
    .trim()
    .toLowerCase();
  const role = String((request.data && request.data.role) || '');
  const name = String((request.data && request.data.name) || '').slice(0, 80);
  if (!email || !ROLES.includes(role)) {
    throw new HttpsError('invalid-argument', 'بيانات غير صحيحة.');
  }

  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (e) {
    throw new HttpsError('not-found', 'المستخدم ده لسه ماسجّلش في التطبيق.');
  }
  if (user.uid === request.auth.uid && role !== 'admin') {
    throw new HttpsError('failed-precondition', 'ماينفعش تشيل صلاحية المدير من نفسك.');
  }
  await applyRole(user.uid, role, name || user.displayName || '');
  return { uid: user.uid, role };
});

/**
 * لو المستخدم ليه مستند في admins/ (اتضاف يدويًا من الـ Console) بنثبّت له الـ claim،
 * عشان المديرين الحاليين ماحتاجوش أي خطوة إضافية.
 */
exports.refreshMyClaims = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'سجّل دخولك الأول.');
  }
  const uid = request.auth.uid;
  const isAdminDoc = (await db.collection('admins').doc(uid).get()).exists;
  const courierSnap = await db.collection('couriers').doc(uid).get();
  const isCourier = courierSnap.exists && courierSnap.get('active') !== false;
  const want = { admin: isAdminDoc, courier: isCourier };
  const have = request.auth.token || {};
  if (Boolean(have.admin) !== want.admin || Boolean(have.courier) !== want.courier) {
    await admin.auth().setCustomUserClaims(uid, want);
    return { changed: true };
  }
  return { changed: false };
});

// ───────────────────────── رفع الصور على Cloudinary بتوقيع من السيرفر ─────────────────────────
// بدل الـ unsigned preset المفتوح: التطبيق بيطلب توقيع قصير العمر من هنا، والتوقيع مربوط بالمجلد
// وبصيغ الصور المسموحة، ومحتاج تسجيل دخول + App Check + صلاحية (مدير أو صاحب محل نشط).
//
// إعداد لمرة واحدة:
//   firebase functions:secrets:set CLOUDINARY_API_SECRET
//   وفي functions/.env  →  CLOUDINARY_API_KEY=xxxx  و  CLOUDINARY_CLOUD_NAME=g3n5pdfz
const CLOUDINARY_API_SECRET = defineSecret('CLOUDINARY_API_SECRET');
const CLOUDINARY_API_KEY = defineString('CLOUDINARY_API_KEY');
const CLOUDINARY_CLOUD_NAME = defineString('CLOUDINARY_CLOUD_NAME', { default: 'g3n5pdfz' });

const UPLOAD_FOLDERS = ['stores', 'products', 'banners'];
const ALLOWED_FORMATS = 'jpg,jpeg,png,webp';

async function canUploadTo(auth, folder, storeId) {
  if (!auth) return false;
  if (await isCallerAdmin(auth)) return true;
  if (folder === 'banners' || !storeId || !/^[A-Za-z0-9_-]{1,100}$/.test(storeId)) return false;
  const snap = await db.collection('storeOwners').doc(auth.uid).get();
  return snap.exists && snap.get('active') !== false && snap.get('storeId') === storeId;
}

exports.signUpload = onCall(
  { secrets: [CLOUDINARY_API_SECRET], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'سجّل دخولك الأول.');
    }
    const folder = String((request.data && request.data.folder) || '');
    if (!UPLOAD_FOLDERS.includes(folder)) {
      throw new HttpsError('invalid-argument', 'مجلد غير مسموح.');
    }
    const storeId = String((request.data && request.data.storeId) || '');
    if (!(await canUploadTo(request.auth, folder, storeId))) {
      throw new HttpsError('permission-denied', 'مش مسموح لك ترفع صور للمحل ده.');
    }
    const uploadFolder = (await isCallerAdmin(request.auth)) || folder === 'banners'
      ? folder
      : `${folder}/${storeId}`;
    const timestamp = Math.floor(Date.now() / 1000);
    // المعاملات بترتّب أبجديًا ثم secret (طريقة Cloudinary في التوقيع).
    const toSign = `allowed_formats=${ALLOWED_FORMATS}&folder=${uploadFolder}&timestamp=${timestamp}`;
    const signature = crypto
      .createHash('sha1')
      .update(toSign + CLOUDINARY_API_SECRET.value())
      .digest('hex');
    return {
      cloudName: CLOUDINARY_CLOUD_NAME.value(),
      apiKey: CLOUDINARY_API_KEY.value(),
      timestamp,
      folder: uploadFolder,
      allowedFormats: ALLOWED_FORMATS,
      signature,
    };
  },
);
