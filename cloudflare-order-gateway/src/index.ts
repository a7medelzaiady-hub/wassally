import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";

interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT_EMAIL: string;
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: string;
  ALLOWED_ORIGINS?: string;
  DEFAULT_DELIVERY_FEE?: string;
  MAX_ORDER_LINES?: string;
  MAX_LINE_QTY?: string;
  CLOUDINARY_CLOUD_NAME?: string;
  CLOUDINARY_API_KEY?: string;
  CLOUDINARY_API_SECRET?: string;
  UPLOAD_RATE_LIMITER: RateLimit;
}

type JsonMap = Record<string, unknown>;
type FirestoreDoc = { name: string; fields?: Record<string, unknown>; updateTime?: string };

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

const firebaseKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);
let cachedAccessToken: { token: string; expiresAt: number } | undefined;
const firebaseUserStateCache = new Map<string, {
  checkedAt: number;
  validSince: number;
  disabled: boolean;
}>();
const FIREBASE_USER_STATE_CACHE_MS = 5_000;

function response(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

function corsHeaders(request: Request, env: Env): Headers {
  const headers = new Headers({ "Vary": "Origin" });
  const origin = request.headers.get("Origin");
  const allowed = (env.ALLOWED_ORIGINS ?? "").split(",").map((v) => v.trim()).filter(Boolean);
  if (origin && !allowed.includes(origin)) {
    throw new HttpError(403, "Origin is not allowed.");
  }
  if (origin && allowed.includes(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
    headers.set("Access-Control-Allow-Methods", "POST, PATCH, OPTIONS");
    headers.set("Access-Control-Max-Age", "600");
  }
  return headers;
}

function decodeValue(value: any): any {
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return new Date(value.timestampValue);
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) return decodeFields(value.mapValue.fields ?? {});
  return null;
}

function decodeFields(fields: Record<string, any>): JsonMap {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]));
}

function encodeValue(value: any): any {
  if (value === null || value === undefined) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") return Number.isInteger(value)
    ? { integerValue: String(value) }
    : { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  if (typeof value === "object") return { mapValue: { fields: encodeFields(value) } };
  throw new Error("Unsupported Firestore value.");
}

function encodeFields(fields: JsonMap): Record<string, unknown> {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, encodeValue(value)]));
}

export function shouldRequeueCourierOrder(data: JsonMap): boolean {
  const status = String(data.status ?? "");
  return ["preparing", "on_the_way"].includes(status) &&
    !String(data.activeDeliveryIssueId ?? "").trim() &&
    data.customerDeliveryReportedAt == null;
}

export const COURIER_FEED_FIELDS = [
  "storeId", "storeName", "area", "items", "subtotal", "deliveryFee",
  "finalDeliveryFee", "discount", "total", "status", "createdAt",
] as const;

export function sanitizeCourierFeed(data: JsonMap): JsonMap {
  return Object.fromEntries(
    COURIER_FEED_FIELDS
      .filter((field) => data[field] !== null && data[field] !== undefined)
      .map((field) => [field, data[field]]),
  );
}

export function courierAvailableFeedData(data: JsonMap): JsonMap {
  const feed: JsonMap = {
    storeId: data.storeId,
    storeName: data.storeName,
    area: data.area ?? "",
    items: data.items,
    subtotal: data.subtotal,
    deliveryFee: data.deliveryFee,
    finalDeliveryFee: data.finalDeliveryFee,
    discount: data.discount ?? 0,
    total: data.total,
    status: "preparing",
    createdAt: data.createdAt,
  };
  return sanitizeCourierFeed(feed);
}

export function anonymizeDeliveryIssue(data: JsonMap, uid: string): JsonMap {
  const patch: JsonMap = {};
  const isParty = data.courierId === uid || data.customerId === uid;
  if (data.courierId === uid) patch.courierId = "deleted";
  if (data.customerId === uid) patch.customerId = "deleted";
  if (data.createdBy === uid) patch.createdBy = "deleted";
  if (data.updatedBy === uid) patch.updatedBy = "deleted";
  if (isParty || data.updatedBy === uid) patch.adminDecision = "";
  if (isParty) patch.note = "";
  return patch;
}

export const PRIVATE_ORDER_FIELDS = [
  "userName", "userEmail", "email", "fullName", "customerFullName",
  "phone", "userPhone", "customerPhone", "address", "userAddress",
  "customerAddress", "courierNotes", "contact", "privateContact",
  "customerContact",
] as const;

export const CUSTOMER_ORDER_DELETE_FIELD_PATHS = [
  "customerName", "notes", "userId", "userDeleted",
  ...PRIVATE_ORDER_FIELDS,
] as const;

/** Strip legacy contact fields before writing a public order document. */
export function sanitizePublicOrder(data: JsonMap): JsonMap {
  const safe = { ...data };
  for (const field of PRIVATE_ORDER_FIELDS) delete safe[field];
  return safe;
}

export function firstName(value: unknown): string {
  return String(value ?? "").trim().split(/\s+/)[0] ?? "";
}

function money(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

export function isGoogleSignIn(payload: Record<string, unknown>): boolean {
  const firebase = payload.firebase;
  if (!firebase || typeof firebase !== "object" || Array.isArray(firebase)) return false;
  return (firebase as Record<string, unknown>).sign_in_provider === "google.com";
}

export function catalogPriceMatches(expected: number, actual: number): boolean {
  return Number.isFinite(expected) && expected > 0 && Math.abs(expected - actual) < 0.01;
}

export function calculateDiscount(subtotal: number, percent: number): number {
  if (!Number.isFinite(subtotal) || !Number.isFinite(percent) || percent <= 0 || percent > 50) {
    return 0;
  }
  return Math.floor(subtotal * percent + 1e-8) / 100;
}

export function effectiveCatalogPrice(product: JsonMap, now = Date.now()): number {
  const base = Number(product.price);
  const oldPrice = typeof product.oldPrice === "number" ? product.oldPrice : 0;
  if (!Number.isFinite(base) || base <= 0 || base > 20000) {
    throw new HttpError(409, "يوجد صنف بسعر غير صالح في الكتالوج.");
  }
  const expiry = product.offerEndsAt instanceof Date ? product.offerEndsAt.getTime() : null;
  if (expiry !== null && expiry <= now && oldPrice > base) return money(oldPrice);
  return money(base);
}

export function isAuthTimeAfterValidSince(authTime: number, validSince: number): boolean {
  return Number.isFinite(authTime) && Number.isFinite(validSince) && authTime >= validSince;
}

async function assertFirebaseUserActive(
  env: Env,
  uid: string,
  authTime: number,
  options: { allowMissingUser?: boolean; allowDisabled?: boolean } = {},
): Promise<void> {
  const now = Date.now();
  let state = firebaseUserStateCache.get(uid);
  if (!state || now - state.checkedAt > FIREBASE_USER_STATE_CACHE_MS) {
    const accessToken = await googleAccessToken(env);
    const lookup = await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/accounts:lookup`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ localId: [uid] }),
      },
    );
    if (!lookup.ok) {
      const detail = (await lookup.text()).slice(0, 500);
      if (detail.includes("USER_NOT_FOUND")) {
        if (options.allowMissingUser) return;
        throw new HttpError(401, "الحساب لم يعد نشطًا. سجّل الدخول من جديد.");
      }
      console.error("Firebase Auth account lookup failed", lookup.status, detail);
      throw new HttpError(503, "تعذر التحقق من حالة الحساب حاليًا. حاول مرة أخرى.");
    }
    const result = await lookup.json() as {
      users?: Array<{ localId?: string; validSince?: string; disabled?: boolean }>;
    };
    const user = result.users?.find((entry) => entry.localId === uid);
    if (!user) {
      if (options.allowMissingUser) return;
      throw new HttpError(401, "الحساب لم يعد نشطًا. سجّل الدخول من جديد.");
    }
    const validSince = Number(user.validSince);
    if (!Number.isFinite(validSince)) {
      throw new HttpError(503, "تعذر التحقق من صلاحية جلسة الحساب. حاول مرة أخرى.");
    }
    state = { checkedAt: now, validSince, disabled: user.disabled === true };
    firebaseUserStateCache.set(uid, state);
    if (firebaseUserStateCache.size > 1_000) {
      const oldestUid = firebaseUserStateCache.keys().next().value;
      if (oldestUid) firebaseUserStateCache.delete(oldestUid);
    }
  }
  if ((!options.allowDisabled && state.disabled) ||
      !isAuthTimeAfterValidSince(authTime, state.validSince)) {
    throw new HttpError(401, "انتهت صلاحية جلسة الحساب أو تم إلغاؤها. سجّل الدخول من جديد.");
  }
}

async function verifyCustomer(request: Request, env: Env): Promise<string> {
  const auth = request.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw new HttpError(401, "سجّل الدخول من جديد.");
  let payload;
  try {
    ({ payload } = await jwtVerify(token, firebaseKeys, {
      audience: env.FIREBASE_PROJECT_ID,
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
    }));
  } catch {
    throw new HttpError(401, "رمز تسجيل الدخول غير صالح أو منتهي.");
  }
  if (typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 128 ||
      !isGoogleSignIn(payload as Record<string, unknown>)) {
    throw new HttpError(401, "يلزم تسجيل الدخول بحساب جوجل صالح.");
  }
  await assertFirebaseUserActive(env, payload.sub, Number(payload.auth_time));
  return payload.sub;
}

async function googleAccessToken(env: Env): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }
  const privateKey = env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY.replace(/\\n/g, "\n");
  const key = await importPKCS8(privateKey, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/identitytoolkit",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(env.FIREBASE_SERVICE_ACCOUNT_EMAIL)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!tokenResponse.ok) throw new HttpError(503, "تعذر الاتصال بخدمة قاعدة البيانات.");
  const data = await tokenResponse.json() as { access_token?: string; expires_in?: number };
  if (!data.access_token) throw new HttpError(503, "تعذر الحصول على صلاحية قاعدة البيانات.");
  cachedAccessToken = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
  };
  return data.access_token;
}

function documentPath(projectId: string, path: string): string {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`;
}

async function getDocument(env: Env, path: string, token: string): Promise<FirestoreDoc | null> {
  const result = await fetch(documentPath(env.FIREBASE_PROJECT_ID, path), {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (result.status === 404) return null;
  if (!result.ok) throw new HttpError(503, "تعذر قراءة بيانات الطلب من قاعدة البيانات.");
  return await result.json() as FirestoreDoc;
}


export function isRecentAuthTime(authTime: number, nowSeconds = Math.floor(Date.now() / 1000)): boolean {
  return Number.isFinite(authTime) &&
    authTime > 0 &&
    authTime <= nowSeconds + 60 &&
    nowSeconds - authTime <= 300;
}

async function verifyRecentCustomer(request: Request, env: Env): Promise<string> {
  const auth = request.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw new HttpError(401, "سجّل الدخول من جديد.");
  let payload;
  try {
    ({ payload } = await jwtVerify(token, firebaseKeys, {
      audience: env.FIREBASE_PROJECT_ID,
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
    }));
  } catch {
    throw new HttpError(401, "لأمان حسابك، سجّل الدخول وأكّد هويتك من جديد قبل الحذف.");
  }
  const authTime = Number(payload.auth_time);
  if (typeof payload.sub !== "string" || !payload.sub ||
      !isRecentAuthTime(authTime) ||
      !isGoogleSignIn(payload as Record<string, unknown>)) {
    throw new HttpError(401, "لأمان حسابك، سجّل الدخول وأكّد هويتك من جديد قبل الحذف.");
  }
  // Allow USER_NOT_FOUND only for an idempotent retry after Auth deletion already succeeded.
  await assertFirebaseUserActive(env, payload.sub, authTime, {
    allowMissingUser: true,
    allowDisabled: true,
  });
  return payload.sub;
}

function firestoreDocumentsUrl(env: Env): string {
  return `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
}

function firestoreDocumentName(env: Env, path: string): string {
  return `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`;
}

async function commitFirestoreWrites(env: Env, token: string, writes: any[]): Promise<void> {
  if (!writes.length) return;
  for (let offset = 0; offset < writes.length; offset += 400) {
    const result = await fetch(`${firestoreDocumentsUrl(env)}:commit`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ writes: writes.slice(offset, offset + 400) }),
    });
    if (!result.ok) {
      const detail = (await result.text()).slice(0, 300);
      throw new HttpError(503, `تعذر استكمال تنظيف بيانات الحساب (${result.status}): ${detail}`);
    }
  }
}

async function commitFirestoreWriteGroups(
  env: Env,
  token: string,
  groups: any[][],
): Promise<void> {
  let batch: any[] = [];
  for (const group of groups) {
    if (batch.length + group.length > 400) {
      await commitFirestoreWrites(env, token, batch);
      batch = [];
    }
    batch.push(...group);
  }
  await commitFirestoreWrites(env, token, batch);
}

async function queryAccountDocuments(
  env: Env,
  token: string,
  collectionId: string,
  fieldPath: string,
  uid: string,
  parent = "",
  allDescendants = false,
): Promise<FirestoreDoc[]> {
  const endpoint = `${firestoreDocumentsUrl(env)}${parent ? `/${parent}` : ""}:runQuery`;
  const docs: FirestoreDoc[] = [];
  let cursor = "";
  for (;;) {
    const structuredQuery: any = {
      from: [{ collectionId, ...(allDescendants ? { allDescendants: true } : {}) }],
      ...(fieldPath ? { where: {
        fieldFilter: {
          field: { fieldPath },
          op: "EQUAL",
          value: { stringValue: uid },
        },
      } } : {}),
      orderBy: [{ field: { fieldPath: "__name__" }, direction: "ASCENDING" }],
      limit: 200,
      ...(cursor ? { startAt: { values: [{ referenceValue: cursor }], before: false } } : {}),
    };
    const result = await fetch(endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ structuredQuery }),
    });
    if (!result.ok) {
      const detail = (await result.text()).slice(0, 300);
      throw new HttpError(503, `تعذر قراءة سجلات حذف الحساب (${result.status}): ${detail}`);
    }
    const rows = await result.json() as Array<{ document?: FirestoreDoc }>;
    const page = rows.map((row) => row.document).filter((doc): doc is FirestoreDoc => Boolean(doc?.name));
    if (!page.length) break;
    docs.push(...page);
    cursor = page[page.length - 1].name;
    if (page.length < 200) break;
  }
  return docs;
}

async function mutateAccountQuery(
  env: Env,
  token: string,
  collectionId: string,
  fieldPath: string,
  uid: string,
  transform: (doc: FirestoreDoc) => JsonMap | null,
  parent = "",
  allDescendants = false,
): Promise<void> {
  const docs = await queryAccountDocuments(
    env, token, collectionId, fieldPath, uid, parent, allDescendants,
  );
  const writes = docs.map((doc) => {
    const patch = transform(doc);
    if (patch === null) return { delete: doc.name };
    const fieldPaths = Object.keys(patch);
    const values = Object.fromEntries(
      Object.entries(patch).filter(([, value]) => value !== null),
    );
    return {
      update: { name: doc.name, fields: encodeFields(values) },
      updateMask: { fieldPaths },
    };
  });
  await commitFirestoreWrites(env, token, writes);
}

async function deleteAccountData(env: Env, token: string, uid: string): Promise<void> {
  const ownerDoc = await getDocument(env, `storeOwners/${encodeURIComponent(uid)}`, token);
  const ownerData = ownerDoc ? decodeFields(ownerDoc.fields ?? {}) : {};
  const ownedStoreId = typeof ownerData.storeId === "string" ? ownerData.storeId : "";

  // Keep commercial order history, but remove every direct customer identifier/contact.
  const customerOrders = await queryAccountDocuments(env, token, "orders", "userId", uid);
  const customerWrites: any[] = [];
  for (const order of customerOrders) {
    customerWrites.push({
      update: {
        name: order.name,
        fields: encodeFields({
          customerName: "عميل محذوف",
          notes: "",
          userId: "deleted",
          userDeleted: true,
        }),
      },
      updateMask: { fieldPaths: [...CUSTOMER_ORDER_DELETE_FIELD_PATHS] },
    });
    const orderPath = order.name.split("/documents/")[1];
    customerWrites.push({ delete: firestoreDocumentName(env, `${orderPath}/private/contact`) });
  }
  await commitFirestoreWrites(env, token, customerWrites);

  // Remove courier applications and pseudonymize historical courier activity.
  await mutateAccountQuery(env, token, "applicants", "courierId", uid, () => null, "", true);
  const courierOrders = await queryAccountDocuments(env, token, "orders", "courierId", uid);
  const courierOrderWriteGroups: any[][] = [];
  for (const doc of courierOrders) {
    const data = decodeFields(doc.fields ?? {});
    const status = String(data.status ?? "");
    const orderPath = doc.name.split("/documents/")[1];
    const orderId = orderPath?.split("/").pop() ?? "";
    if (["delivered", "cancelled"].includes(status)) {
      const patch = {
        courierId: "deleted",
        courierName: "مندوب محذوف",
        courierPhone: "",
        deliveredBy: data.deliveredBy === uid ? "deleted" : String(data.deliveredBy ?? ""),
      };
      const historicalWrites: any[] = [{
        update: { name: doc.name, fields: encodeFields(patch) },
        updateMask: { fieldPaths: Object.keys(patch) },
      }];
      if (orderId) {
        historicalWrites.push({
          delete: firestoreDocumentName(env, `courier_available_orders/${encodeURIComponent(orderId)}`),
        });
      }
      courierOrderWriteGroups.push(historicalWrites);
      continue;
    }

    const requeue = shouldRequeueCourierOrder(data);
    const patch: JsonMap = {
      courierId: null,
      courierName: null,
      courierPhone: null,
      courierAt: null,
      deliveryMode: null,
    };
    if (status === "on_the_way" && requeue) {
      patch.status = "preparing";
      patch.courierArrivedAt = null;
      patch.pickedUpAt = null;
    }
    const fieldPaths = Object.keys(patch);
    const values = Object.fromEntries(
      Object.entries(patch).filter(([, value]) => value !== null),
    );
    const orderWrites: any[] = [{
      update: { name: doc.name, fields: encodeFields(values) },
      updateMask: { fieldPaths },
    }];

    if (orderId && requeue) {
      const feed = courierAvailableFeedData({ ...data, ...patch, courierId: "", status: "preparing" });
      orderWrites.push({
        update: {
          name: firestoreDocumentName(env, `courier_available_orders/${encodeURIComponent(orderId)}`),
          fields: encodeFields(feed),
        },
      });
    } else if (orderId) {
      orderWrites.push({
        delete: firestoreDocumentName(env, `courier_available_orders/${encodeURIComponent(orderId)}`),
      });
    }
    // Keep the order update and its available-feed change in the same Firestore commit.
    courierOrderWriteGroups.push(orderWrites);
  }
  await commitFirestoreWriteGroups(env, token, courierOrderWriteGroups);
  await mutateAccountQuery(env, token, "orders", "deliveredBy", uid, () => ({ deliveredBy: "deleted" }));
  await mutateAccountQuery(env, token, "statusHistory", "actorUid", uid, () => ({ actorUid: "deleted" }), "", true);

  // Remove user-authored support, complaints, applications, and notifications.
  for (const [collection, field] of [
    ["complaints", "userId"],
    ["role_requests", "userId"],
    ["notifications", "userId"],
  ]) {
    await mutateAccountQuery(env, token, collection, field, uid, () => null);
  }

  // Keep aggregate scores while removing the account link and free-text content.
  await mutateAccountQuery(env, token, "reviews", "userId", uid, () => ({
    userId: "deleted", comment: "", userDeleted: true,
  }));
  await mutateAccountQuery(env, token, "reviews", "courierId", uid, () => ({
    courierId: "deleted", comment: "", courierDeleted: true,
  }));
  await mutateAccountQuery(env, token, "customer_reviews", "reviewerId", uid, () => ({
    reviewerId: "deleted", comment: "", userDeleted: true,
  }));
  await mutateAccountQuery(env, token, "customer_reviews", "customerId", uid, () => ({
    customerId: "deleted", comment: "", customerDeleted: true,
  }));
  await mutateAccountQuery(env, token, "courier_settlements", "courierId", uid, () => ({
    courierId: "deleted", courierName: "مندوب محذوف", note: "", courierDeleted: true,
  }));

  // Delete unapproved store drafts owned by this account, including product subcollections.
  const applicantStores = await queryAccountDocuments(env, token, "stores", "ownerUid", uid);
  for (const draft of applicantStores) {
    const data = decodeFields(draft.fields ?? {});
    if (data.active === true || data.approved === true) continue;
    const storePath = draft.name.split("/documents/")[1];
    const draftProducts = await queryAccountDocuments(
      env, token, "products", "", uid, storePath,
    );
    await commitFirestoreWrites(env, token, [
      ...draftProducts.map((product) => ({ delete: product.name })),
      { delete: draft.name },
    ]);
  }

  // Delete support messages before their parent document (Firestore has no cascade delete).
  const chatPath = `support_chats/${encodeURIComponent(uid)}`;
  const chatMessages = await queryAccountDocuments(env, token, "messages", "", uid, chatPath);
  await commitFirestoreWrites(env, token, chatMessages.map((doc) => ({ delete: doc.name })));
  await commitFirestoreWrites(env, token, [{ delete: firestoreDocumentName(env, chatPath) }]);

  // Remove role/profile documents.
  await commitFirestoreWrites(env, token, [
    "admins", "couriers", "storeOwners", "supervisors",
    "customer_restrictions", "orderLimits", "first_orders",
  ].map((collection) => ({
    delete: firestoreDocumentName(env, `${collection}/${encodeURIComponent(uid)}`),
  })));

  if (ownedStoreId) {
    const remainingOwnerDocs = await queryAccountDocuments(
      env, token, "storeOwners", "storeId", ownedStoreId,
    );
    const activeOwner = remainingOwnerDocs.some((doc) =>
      decodeFields(doc.fields ?? {}).active !== false);
    if (!activeOwner) {
      const store = await getDocument(env, `stores/${encodeURIComponent(ownedStoreId)}`, token);
      if (store) await commitFirestoreWrites(env, token, [{
        update: {
          name: store.name,
          fields: encodeFields({
            active: false,
            ownerDeleted: true,
            updatedAt: new Date(),
          }),
        },
        updateMask: { fieldPaths: ["active", "ownerDeleted", "updatedAt", "ownerUid"] },
      }]);
    }
  }

  // Keep delivery-dispute history while removing either party's account link and free text.
  await mutateAccountQuery(env, token, "delivery_issues", "courierId", uid, (doc) =>
    anonymizeDeliveryIssue(decodeFields(doc.fields ?? {}), uid));
  await mutateAccountQuery(env, token, "delivery_issues", "customerId", uid, (doc) =>
    anonymizeDeliveryIssue(decodeFields(doc.fields ?? {}), uid));

  // Remove customer-uploaded special-request images before deleting their Firestore references.
  const specialRequestDocs = await queryAccountDocuments(env, token, "special_requests", "userId", uid);
  const hasSpecialRequestImages = specialRequestDocs.some((doc) =>
    isCloudinaryImageUrl(decodeFields(doc.fields ?? {}).imageUrl));
  const cloudinaryConfigured = Boolean(
    env.CLOUDINARY_CLOUD_NAME && env.CLOUDINARY_API_KEY && env.CLOUDINARY_API_SECRET,
  );
  if (cloudinaryConfigured) {
    await deleteCloudinarySpecialRequestAssets(env, uid);
  } else if (hasSpecialRequestImages) {
    throw new HttpError(503, "تعذر حذف صور الطلبات الخاصة من خدمة الصور. أعد المحاولة لاحقًا.");
  }
  // Remove special-request text, voice messages, and media URLs from Firestore.
  await commitFirestoreWrites(env, token, specialRequestDocs.map((doc) => ({ delete: doc.name })));

  await mutateAccountQuery(env, token, "couriers", "supervisorId", uid, () => ({ supervisorId: null }));
  await mutateAccountQuery(env, token, "account_deletions", "userId", uid, () => null);
  await commitFirestoreWrites(env, token, [
    { delete: firestoreDocumentName(env, `account_deletions/${encodeURIComponent(uid)}`) },
    { delete: firestoreDocumentName(env, `users/${encodeURIComponent(uid)}`) },
    { delete: firestoreDocumentName(env, `courier_settlement_balances/${encodeURIComponent(uid)}`) },
  ]);
}

async function deleteFirebaseAuthUser(env: Env, token: string, uid: string): Promise<void> {
  const result = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/accounts:delete`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ localId: uid }),
    },
  );
  if (!result.ok) {
    const detail = (await result.text()).slice(0, 500);
    // A retry after a lost response is successful if Firebase already deleted the user.
    if (detail.includes("USER_NOT_FOUND")) return;
    throw new HttpError(503, `تم تنظيف البيانات لكن تعذر حذف حساب تسجيل الدخول (${result.status}): ${detail}`);
  }
}

async function deleteAccount(request: Request, env: Env): Promise<Response> {
  if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_SERVICE_ACCOUNT_EMAIL ||
      !env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY) {
    throw new HttpError(503, "خدمة حذف الحساب غير مهيأة على الخادم.");
  }
  const uid = await verifyRecentCustomer(request, env);
  const token = await googleAccessToken(env);
  await deleteAccountData(env, token, uid);
  await deleteFirebaseAuthUser(env, token, uid);
  return response({ ok: true, deleted: true });
}

async function batchGetDocuments(env: Env, paths: string[], token: string): Promise<Map<string, JsonMap>> {
  if (!paths.length) return new Map();
  const result = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:batchGet`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ documents: paths.map((path) =>
        `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`) }),
    },
  );
  if (!result.ok) throw new HttpError(503, "تعذر تحميل كتالوج الأصناف.");
  const text = await result.text();
  const docs = new Map<string, JsonMap>();
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    const item = JSON.parse(line) as { found?: FirestoreDoc };
    if (item.found?.name) {
      const path = item.found.name.split("/documents/")[1];
      docs.set(path, decodeFields(item.found.fields ?? {}));
    }
  }
  return docs;
}

function productFromLegacy(store: JsonMap, name: string): JsonMap {
  const list = Array.isArray(store.products) ? store.products as JsonMap[] : [];
  const normalized = name.trim().replace(/\s+/g, " ").toLocaleLowerCase();
  const matches = list.filter((item) =>
    String(item.name ?? "").trim().replace(/\s+/g, " ").toLocaleLowerCase() === normalized);
  if (matches.length !== 1) {
    throw new HttpError(409, matches.length
      ? "يوجد أكثر من صنف بنفس الاسم في الكتالوج القديم؛ يلزم ترحيل الأصناف."
      : "الصنف لم يعد موجودًا في كتالوج المحل.");
  }
  return matches[0];
}

function validateContact(contact: any): JsonMap {
  if (!contact || typeof contact !== "object") throw new HttpError(400, "بيانات التواصل غير مكتملة.");
  const userName = String(contact.userName ?? "").trim();
  const phone = String(contact.phone ?? "").trim();
  const address = String(contact.address ?? "").trim();
  const courierNotes = String(contact.courierNotes ?? "").trim();
  if (userName.length < 1 || userName.length > 80 ||
      !/^01[0125][0-9]{8}$/.test(phone) ||
      address.length < 5 || address.length > 300 ||
      courierNotes.length > 300) {
    throw new HttpError(400, "راجع الاسم ورقم الهاتف والعنوان.");
  }
  return { userName, phone, address, ...(courierNotes ? { courierNotes } : {}) };
}

async function resolveItems(
  env: Env,
  token: string,
  storeId: string,
  store: JsonMap,
  lines: any[],
): Promise<{ items: JsonMap[]; subtotal: number }> {
  if (lines.length < 1 || lines.length > Number(env.MAX_ORDER_LINES ?? 100)) {
    throw new HttpError(400, "عدد الأصناف خارج الحدود المسموحة.");
  }
  const productIds = [...new Set(lines.map((line: any) => String(line?.productId ?? "").trim()).filter(Boolean))];
  if (productIds.some((id) => id.includes("/") || id.length > 150)) {
    throw new HttpError(400, "معرّف صنف غير صالح.");
  }
  const productPaths = productIds.map((id) => `stores/${encodeURIComponent(storeId)}/products/${encodeURIComponent(id)}`);
  const productDocs = await batchGetDocuments(env, productPaths, token);
  const seen = new Set<string>();
  const items: JsonMap[] = [];
  let subtotal = 0;
  for (const line of lines) {
    const qty = Number(line?.qty);
    if (!Number.isInteger(qty) || qty < 1 || qty > Number(env.MAX_LINE_QTY ?? 50)) {
      throw new HttpError(400, "كمية أحد الأصناف غير صالحة.");
    }
    const productId = String(line?.productId ?? "").trim();
    let product: JsonMap;
    let resolvedId = productId;
    let isLegacy = false;
    if (productId) {
      const path = `stores/${encodeURIComponent(storeId)}/products/${encodeURIComponent(productId)}`;
      const found = productDocs.get(path);
      if (!found) throw new HttpError(409, "أحد الأصناف لم يعد موجودًا في كتالوج المحل.");
      product = found;
    } else {
      const name = String(line?.name ?? "").trim();
      if (!name || name.length > 120) throw new HttpError(400, "صنف قديم بدون اسم صالح.");
      product = productFromLegacy(store, name);
      resolvedId = "";
      isLegacy = true;
    }
    if (product.available === false || product.isAvailable === false) {
      throw new HttpError(409, "أحد الأصناف غير متاح حاليًا.");
    }
    const name = String(product.name ?? "").trim();
    if (!name || name.length > 120) throw new HttpError(409, "بيانات صنف غير صالحة في الكتالوج.");
    const identity = resolvedId ? `id:${resolvedId}` : `legacy:${name.toLowerCase()}`;
    if (seen.has(identity)) throw new HttpError(400, "الصنف مكرر في الطلب.");
    seen.add(identity);
    const price = effectiveCatalogPrice(
      isLegacy ? { ...product, oldPrice: 0, offerEndsAt: null } : product,
    );
    const expectedPrice = Number(line?.expectedPrice);
    // expectedPrice is only a stale-cart check; the saved price always comes from Firestore.
    if (!catalogPriceMatches(expectedPrice, price)) {
      throw new HttpError(409, "سعر أحد الأصناف اتغير. راجع السلة قبل تأكيد الطلب.");
    }
    subtotal = money(subtotal + price * qty);
    items.push({ name, price, qty, ...(resolvedId ? { productId: resolvedId } : {}) });
  }
  if (!Number.isFinite(subtotal) || subtotal <= 0 || subtotal > 100000) {
    throw new HttpError(409, "إجمالي الأصناف خارج الحدود المسموحة.");
  }
  return { items, subtotal };
}

export function courierTopicMessage(orderId: string, storeName: string) {
  const shortId = "#" + orderId.slice(0, 5).toUpperCase();
  return {
    message: {
      topic: "couriers",
      notification: {
        title: "طلب توصيل جديد متاح " + shortId,
        body: String(storeName || "محل").slice(0, 80) + " • افتح التطبيق لمراجعة الطلب والتقديم عليه",
      },
      data: {
        type: "available_order",
        orderId,
      },
      android: {
        priority: "HIGH",
        ttl: "300s",
        notification: { sound: "default" },
      },
    },
  };
}

async function notifyCouriersOfNewOrder(
  env: Env,
  accessToken: string,
  orderId: string,
  storeName: string,
): Promise<void> {
  const sent = await fetch(
    `https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(courierTopicMessage(orderId, storeName)),
    },
  );
  if (!sent.ok) {
    const detail = (await sent.text()).slice(0, 500);
    throw new Error(`FCM send failed (${sent.status}): ${detail}`);
  }
}

export function isCustomerRestricted(
  restriction: JsonMap | null,
  now = Date.now(),
): boolean {
  // Match Firestore rules: only explicit deactivation or a valid expired timestamp
  // releases a restriction. Missing/malformed expiry must fail closed.
  if (restriction === null) return false;
  if (restriction.active === false) return false;
  if (!(restriction.expiresAt instanceof Date)) return true;
  const expiresAt = restriction.expiresAt.getTime();
  return !Number.isFinite(expiresAt) || expiresAt > now;
}

async function createOrder(request: Request, env: Env): Promise<Response> {
  if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_SERVICE_ACCOUNT_EMAIL ||
      !env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY) {
    throw new HttpError(503, "بوابة الطلبات لم تكتمل تهيئتها بعد.");
  }
  const uid = await verifyCustomer(request, env);
  let input: any;
  try {
    input = await request.json();
  } catch {
    throw new HttpError(400, "بيانات الطلب غير مفهومة.");
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new HttpError(400, "صيغة بيانات الطلب غير صحيحة.");
  }

  const orderId = String(input.orderId ?? "");
  const storeId = String(input.storeId ?? "").trim();
  const lines = Array.isArray(input.items) ? input.items : [];
  const area = String(input.area ?? "").trim();
  const promoCode = String(input.promoCode ?? "").trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  const customerName = firstName(input.customerName);
  const notes = String(input.notes ?? "").trim();
  const contact = validateContact(input.contact);

  if (!orderId.startsWith(`${uid}_`) || !/^[A-Za-z0-9_-]{16,180}$/.test(orderId.slice(uid.length + 1))) {
    throw new HttpError(400, "معرّف الطلب غير صالح.");
  }
  if (!storeId || storeId.length > 100 || customerName.length < 1 ||
      customerName.length > 30 || notes.length > 500 ||
      lines.length < 1 || lines.length > Number(env.MAX_ORDER_LINES ?? 100)) {
    throw new HttpError(400, "بيانات الطلب خارج الحدود المسموحة.");
  }

  const token = await googleAccessToken(env);
  const orderPath = `orders/${orderId}`;
  const existing = await getDocument(env, orderPath, token);
  if (existing) {
    const old = decodeFields(existing.fields ?? {});
    if (old.userId === uid) return response({ orderId, reused: true });
    throw new HttpError(409, "معرّف الطلب مستخدم بالفعل.");
  }

  const [storeDoc, restrictionDoc, limitDoc, areasDoc] = await Promise.all([
    getDocument(env, `stores/${encodeURIComponent(storeId)}`, token),
    getDocument(env, `customer_restrictions/${uid}`, token),
    getDocument(env, `orderLimits/${uid}`, token),
    getDocument(env, "app_info/delivery_areas", token),
  ]);
  if (!storeDoc) throw new HttpError(404, "المحل غير موجود.");
  const store = decodeFields(storeDoc.fields ?? {});
  if (store.active !== undefined && store.active !== true) {
    throw new HttpError(409, "المحل مغلق حاليًا.");
  }
  const restriction = restrictionDoc ? decodeFields(restrictionDoc.fields ?? {}) : null;
  if (isCustomerRestricted(restriction)) {
    throw new HttpError(403, "حسابك مقيّد مؤقتًا أو بيانات التقييد غير مكتملة. راجع الدعم.");
  }
  const previousLimit = limitDoc ? decodeFields(limitDoc.fields ?? {}) : {};
  const lastAt = previousLimit.lastAt instanceof Date ? previousLimit.lastAt.getTime() : 0;
  if (lastAt && Date.now() - lastAt < 20_000) {
    throw new HttpError(429, "استنى شوية قبل إرسال طلب جديد.");
  }

  const rawAreas = areasDoc ? decodeFields(areasDoc.fields ?? {}).areas : null;
  const areaList = Array.isArray(rawAreas) ? rawAreas as JsonMap[] : [];
  let deliveryFee = Number(env.DEFAULT_DELIVERY_FEE ?? 20);
  let orderArea = "";
  if (areaList.length) {
    const selected = areaList.find((entry) => String(entry.name ?? "").trim() === area);
    if (!selected) throw new HttpError(400, "اختار منطقة توصيل صالحة.");
    if (typeof selected.fee !== "number") {
      throw new HttpError(409, "سعر منطقة التوصيل غير صالح في الإعدادات.");
    }
    deliveryFee = selected.fee;
    orderArea = area;
  } else if (area) {
    throw new HttpError(400, "قائمة مناطق التوصيل غير مفعّلة؛ أعد تحميل صفحة الدفع.");
  }
  if (!Number.isFinite(deliveryFee) || deliveryFee < 0 || deliveryFee > 500) {
    throw new HttpError(409, "رسوم التوصيل غير مضبوطة في إعدادات الإدارة.");
  }
  const expectedDeliveryFee = Number(input.expectedDeliveryFee);
  if (!Number.isFinite(expectedDeliveryFee) || Math.abs(expectedDeliveryFee - deliveryFee) >= 0.01) {
    throw new HttpError(409, "رسوم التوصيل اتغيرت. راجع الإجمالي قبل تأكيد الطلب.");
  }

  const { items, subtotal } = await resolveItems(env, token, storeId, store, lines);

  let discount = 0;
  let normalizedPromo = "";
  if (promoCode) {
    const promoDoc = await getDocument(env, `promos/${promoCode}`, token);
    const promo = promoDoc ? decodeFields(promoDoc.fields ?? {}) : {};
    const percent = typeof promo.percent === "number" ? promo.percent : 0;
    if (promo.active !== true || !Number.isFinite(percent) || percent <= 0 || percent > 50) {
      throw new HttpError(409, "الكوبون لم يعد صالحًا.");
    }
    discount = calculateDiscount(subtotal, percent);
    if (discount > 0 && discount < subtotal) normalizedPromo = promoCode;
    else discount = 0;
  }
  const total = money(subtotal + deliveryFee - discount);
  if (total <= 0 || total > 100000) throw new HttpError(409, "إجمالي الطلب غير صالح.");
  const expectedTotal = Number(input.expectedTotal);
  if (!Number.isFinite(expectedTotal) || Math.abs(expectedTotal - total) >= 0.01) {
    throw new HttpError(409, "إجمالي الطلب اتغير. راجع السلة قبل تأكيد الطلب.");
  }

  const storeName = String(store.name ?? "").trim();
  const order: JsonMap = {
    userId: uid,
    customerName,
    notes,
    storeId,
    storeName,
    items,
    subtotal,
    deliveryFee,
    total,
    paymentMethod: "cash",
    status: "new",
    ...(orderArea ? { area: orderArea } : {}),
    ...(normalizedPromo && discount > 0 ? { promoCode: normalizedPromo, discount } : {}),
  };
  if (!storeName || storeName.length > 100) {
    throw new HttpError(409, "بيانات المحل غير مكتملة.");
  }

  const writes = [
    {
      update: {
        name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${orderPath}`,
        fields: encodeFields(order),
      },
      updateTransforms: [{ fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: { exists: false },
    },
    {
      update: {
        name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${orderPath}/private/contact`,
        fields: encodeFields(contact),
      },
      currentDocument: { exists: false },
    },
    {
      update: {
        name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/orderLimits/${uid}`,
        fields: encodeFields({ lastAt: new Date() }),
      },
      updateTransforms: [{ fieldPath: "lastAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: limitDoc?.updateTime
        ? { updateTime: limitDoc.updateTime }
        : { exists: false },
    },
  ];
  const committed = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ writes }),
    },
  );
  if (committed.status === 409 || committed.status === 400) {
    throw new HttpError(409, "تم تغيير الطلب بالتزامن. راجع طلباتك قبل إعادة المحاولة.");
  }
  if (!committed.ok) throw new HttpError(503, "تعذر حفظ الطلب؛ حاول مرة أخرى.");
  // الإشعار يُرسل من الخادم بعد نجاح حفظ الطلب فقط. فشل FCM لا يلغي الطلب.
  try {
    await notifyCouriersOfNewOrder(env, token, orderId, String(order.storeName));
  } catch (error) {
    console.error("Courier push notification failed", error);
  }
  return response({ orderId, subtotal, deliveryFee, discount, total, items });
}

async function updateOrder(request: Request, env: Env, orderId: string): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  if (!/^[A-Za-z0-9_-]{1,180}$/.test(orderId)) throw new HttpError(400, "معرّف الطلب غير صالح.");
  let input: any;
  try {
    input = await request.json();
  } catch {
    throw new HttpError(400, "بيانات التعديل غير مفهومة.");
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new HttpError(400, "صيغة بيانات التعديل غير صحيحة.");
  }
  const lines = Array.isArray(input.items) ? input.items : [];
  const customerName = firstName(input.customerName);
  const notes = String(input.notes ?? "").trim();
  const contact = validateContact(input.contact);
  if (!customerName || customerName.length > 30 || notes.length > 500) {
    throw new HttpError(400, "راجع الاسم والملاحظات.");
  }

  const token = await googleAccessToken(env);
  const orderPath = `orders/${encodeURIComponent(orderId)}`;
  const orderDoc = await getDocument(env, orderPath, token);
  if (!orderDoc) throw new HttpError(404, "الطلب غير موجود.");
  const order = decodeFields(orderDoc.fields ?? {});
  if (order.userId !== uid) throw new HttpError(403, "لا تملك صلاحية تعديل هذا الطلب.");
  if (!["new", "preparing"].includes(String(order.status)) || String(order.courierId ?? "") !== "") {
    throw new HttpError(409, "لم يعد ممكنًا تعديل الطلب بعد استلامه أو تغيير حالته.");
  }

  const storeId = String(order.storeId ?? "");
  if (!storeId) throw new HttpError(409, "بيانات المحل غير مكتملة.");
  const [storeDoc, contactDoc, feedDoc] = await Promise.all([
    getDocument(env, `stores/${encodeURIComponent(storeId)}`, token),
    getDocument(env, `${orderPath}/private/contact`, token),
    order.status === "preparing"
      ? getDocument(env, `courier_available_orders/${encodeURIComponent(orderId)}`, token)
      : Promise.resolve(null),
  ]);
  if (!storeDoc || !contactDoc) throw new HttpError(409, "بيانات الطلب الخاصة أو كتالوج المحل غير متاح.");
  if (order.status === "preparing" && !feedDoc) {
    throw new HttpError(409, "تعذر تحديث قائمة المندوبين بأمان. حدّث الطلب وحاول مرة أخرى.");
  }
  const store = decodeFields(storeDoc.fields ?? {});
  const { items, subtotal } = await resolveItems(env, token, storeId, store, lines);

  const deliveryFee = Number(order.deliveryFee);
  if (!Number.isFinite(deliveryFee) || deliveryFee < 0 || deliveryFee > 500) {
    throw new HttpError(409, "رسوم التوصيل في الطلب غير صالحة.");
  }
  let discount = 0;
  let promoCode = String(order.promoCode ?? "").trim().toUpperCase();
  if (promoCode && Number(order.discount ?? 0) > 0 && Number(order.subtotal ?? 0) > 0) {
    const promoDoc = await getDocument(env, `promos/${promoCode}`, token);
    const promo = promoDoc ? decodeFields(promoDoc.fields ?? {}) : {};
    const percent = typeof promo.percent === "number" ? promo.percent : 0;
    if (promo.active === true && Number.isFinite(percent) && percent > 0 && percent <= 50) {
      const previousPercent = Number(order.discount) / Number(order.subtotal) * 100;
      discount = calculateDiscount(subtotal, Math.min(previousPercent, percent));
    } else {
      throw new HttpError(409, "الكوبون لم يعد صالحًا. راجع الخصم قبل تعديل الطلب.");
    }
  } else {
    promoCode = "";
  }
  const total = money(subtotal + deliveryFee - discount);
  if (total <= 0 || total > 100000) throw new HttpError(409, "إجمالي الطلب بعد التعديل غير صالح.");
  const expectedTotal = Number(input.expectedTotal);
  if (!Number.isFinite(expectedTotal) || Math.abs(expectedTotal - total) >= 0.01) {
    throw new HttpError(409, "إجمالي الطلب اتغير. راجع الأصناف والخصم قبل التعديل.");
  }

  const updatedOrder = sanitizePublicOrder({
    ...order,
    items,
    subtotal,
    total,
    notes,
    customerName,
  });
  delete updatedOrder.unavailableItems;
  if (discount > 0 && promoCode) {
    updatedOrder.discount = discount;
    updatedOrder.promoCode = promoCode;
  } else {
    delete updatedOrder.discount;
    delete updatedOrder.promoCode;
  }
  const updatedContact = contact;
  const writes: any[] = [
    {
      update: {
        name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${orderPath}`,
        fields: encodeFields(updatedOrder),
      },
      updateTransforms: [{ fieldPath: "editedAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: orderDoc.updateTime
        ? { updateTime: orderDoc.updateTime }
        : { exists: true },
    },
    {
      update: {
        name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${orderPath}/private/contact`,
        fields: encodeFields(updatedContact),
      },
      currentDocument: contactDoc.updateTime
        ? { updateTime: contactDoc.updateTime }
        : { exists: true },
    },
  ];
  if (order.status === "preparing" && feedDoc) {
    const feed = decodeFields(feedDoc.fields ?? {});
    const updatedFeed = sanitizeCourierFeed({
      ...feed,
      items,
      subtotal,
      discount,
      total,
    });
    writes.push({
      update: {
        name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/courier_available_orders/${encodeURIComponent(orderId)}`,
        fields: encodeFields(updatedFeed),
      },
      currentDocument: feedDoc.updateTime
        ? { updateTime: feedDoc.updateTime }
        : { exists: true },
    });
  }
  const committed = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ writes }),
    },
  );
  if (committed.status === 409 || committed.status === 400) {
    throw new HttpError(409, "حالة الطلب اتغيرت أثناء التعديل. حدّث الصفحة وحاول مرة أخرى.");
  }
  if (!committed.ok) throw new HttpError(503, "تعذر حفظ تعديل الطلب.");
  return response({ orderId, subtotal, deliveryFee, discount, total, items });
}

export function canUploadSpecialRequestImage(storeId: string, store: JsonMap | null): boolean {
  return /^[A-Za-z0-9_-]{1,100}$/.test(storeId) && store?.active === true;
}

export function isCloudinaryImageUrl(value: unknown): boolean {
  if (typeof value !== "string") return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" &&
      url.hostname === "res.cloudinary.com" &&
      url.pathname.includes("/image/upload/");
  } catch {
    return false;
  }
}

export async function cloudinarySpecialRequestFolder(uid: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(uid));
  const hash = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")).join("");
  return `special_requests/${hash}`;
}

async function deleteCloudinarySpecialRequestAssets(env: Env, uid: string): Promise<void> {
  if (!env.CLOUDINARY_CLOUD_NAME || !env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET) {
    throw new HttpError(503, "تعذر تنظيف صور الطلبات الخاصة من خدمة الصور.");
  }
  const prefix = await cloudinarySpecialRequestFolder(uid);
  let nextCursor = "";
  for (let page = 0; page < 10; page++) {
    const url = new URL(
      `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/resources/image/upload`,
    );
    url.searchParams.set("prefix", prefix);
    url.searchParams.set("invalidate", "true");
    if (nextCursor) url.searchParams.set("next_cursor", nextCursor);
    const deleted = await fetch(url, {
      method: "DELETE",
      headers: {
        Authorization: `Basic ${btoa(`${env.CLOUDINARY_API_KEY}:${env.CLOUDINARY_API_SECRET}`)}`,
      },
    });
    if (!deleted.ok) {
      const detail = (await deleted.text()).slice(0, 300);
      console.error("Cloudinary special request cleanup failed", deleted.status, detail);
      throw new HttpError(503, "تعذر حذف صور الطلبات الخاصة. حاول حذف الحساب مرة أخرى.");
    }
    const result = await deleted.json() as { partial?: boolean; next_cursor?: string };
    if (!result.partial) return;
    if (!result.next_cursor) {
      throw new HttpError(503, "لم تكتمل إزالة كل صور الطلبات الخاصة. أعد محاولة حذف الحساب.");
    }
    nextCursor = result.next_cursor;
  }
  throw new HttpError(503, "توجد صور كثيرة مرتبطة بالحساب؛ أعد محاولة حذف الحساب لإكمال التنظيف.");
}

export async function cloudinarySignature(
  params: Record<string, string>,
  secret: string,
): Promise<string> {
  const canonical = Object.keys(params).sort()
    .map((key) => `${key}=${params[key]}`)
    .join("&");
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(canonical + secret),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")).join("");
}

export async function isUploadRateLimited(
  limiter: { limit(options: { key: string }): Promise<{ success: boolean }> },
  uid: string,
): Promise<boolean> {
  const { success } = await limiter.limit({ key: uid });
  return !success;
}

export function isUploadSizeAllowed(size: number): boolean {
  return Number.isInteger(size) && size > 0 && size <= 5 * 1024 * 1024;
}

export function isUploadRequestLengthAllowed(value: string | null): boolean {
  if (value === null || !/^\d+$/.test(value)) return false;
  const length = Number(value);
  return Number.isSafeInteger(length) &&
    length > 0 &&
    length <= 5 * 1024 * 1024 + 64 * 1024;
}

export function detectImageContent(bytes: Uint8Array): { format: string; mime: string } | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { format: "jpg", mime: "image/jpeg" };
  }
  if (bytes.length >= 8 &&
      bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
      bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a &&
      bytes[6] === 0x1a && bytes[7] === 0x0a) {
    return { format: "png", mime: "image/png" };
  }
  if (bytes.length >= 12 &&
      String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
      String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") {
    return { format: "webp", mime: "image/webp" };
  }
  return null;
}

async function uploadCloudinaryImage(request: Request, env: Env): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  if (await isUploadRateLimited(env.UPLOAD_RATE_LIMITER, uid)) {
    throw new HttpError(429, "وصلت للحد المؤقت لرفع الصور. حاول بعد دقيقة.");
  }
  if (!env.CLOUDINARY_CLOUD_NAME || !env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET) {
    throw new HttpError(503, "خدمة رفع الصور الآمنة غير مهيأة على الخادم.");
  }

  if (!isUploadRequestLengthAllowed(request.headers.get("Content-Length"))) {
    throw new HttpError(413, "حجم طلب رفع الصورة غير صالح أو يتجاوز الحد المسموح.");
  }
  if (!(request.headers.get("Content-Type") ?? "").toLowerCase().startsWith("multipart/form-data;")) {
    throw new HttpError(400, "صيغة طلب رفع الصورة غير صحيحة.");
  }
  let input: FormData;
  try {
    input = await request.formData();
  } catch {
    throw new HttpError(400, "ملف الصورة غير مفهوم.");
  }
  const folder = String(input.get("folder") ?? "");
  const storeId = String(input.get("storeId") ?? "").trim();
  const file = input.get("file");
  if (!(file instanceof File)) throw new HttpError(400, "اختار صورة صحيحة قبل الرفع.");
  if (!isUploadSizeAllowed(file.size)) {
    throw new HttpError(413, "حجم الصورة يجب ألا يتجاوز 5MB.");
  }
  if (!["stores", "products", "banners", "special_requests"].includes(folder)) {
    throw new HttpError(400, "مجلد الصور غير مسموح.");
  }
  if (storeId.length > 100 || (storeId && !/^[A-Za-z0-9_-]+$/.test(storeId))) {
    throw new HttpError(400, "معرّف المحل غير صالح.");
  }

  const token = await googleAccessToken(env);
  const [adminDoc, ownerDoc, roleRequestDoc, specialRequestStoreDoc] = await Promise.all([
    getDocument(env, `admins/${encodeURIComponent(uid)}`, token),
    getDocument(env, `storeOwners/${encodeURIComponent(uid)}`, token),
    getDocument(env, `role_requests/${encodeURIComponent(uid + "_store_owner")}`, token),
    folder === "special_requests" && storeId
      ? getDocument(env, `stores/${encodeURIComponent(storeId)}`, token)
      : Promise.resolve(null),
  ]);
  const isAdmin = adminDoc !== null;
  const owner = ownerDoc ? decodeFields(ownerDoc.fields ?? {}) : {};
  const isOwner = ownerDoc !== null && owner.active !== false && owner.storeId === storeId;
  const roleRequest = roleRequestDoc ? decodeFields(roleRequestDoc.fields ?? {}) : {};
  const requestedStoreId = typeof roleRequest.storeId === "string" ? roleRequest.storeId : "";
  const applicantStoreDoc = folder === "stores" && requestedStoreId &&
    ["pending", "rejected"].includes(String(roleRequest.status))
      ? await getDocument(env, `stores/${encodeURIComponent(requestedStoreId)}`, token)
      : null;
  const applicantStore = applicantStoreDoc ? decodeFields(applicantStoreDoc.fields ?? {}) : {};
  const isApplicant = (applicantStoreDoc !== null && applicantStore.ownerUid === uid &&
    (storeId === "" || storeId === requestedStoreId)) ||
    (folder === "stores" && storeId === "" &&
      (!roleRequestDoc || ["pending", "rejected"].includes(String(roleRequest.status))));
  const specialRequestStore = specialRequestStoreDoc
    ? decodeFields(specialRequestStoreDoc.fields ?? {})
    : null;
  const isSpecialRequestUpload = canUploadSpecialRequestImage(storeId, specialRequestStore);
  if (folder === "banners" ? !isAdmin
      : folder === "special_requests" ? !(isAdmin || isSpecialRequestUpload)
      : !(isAdmin || (storeId && isOwner) || isApplicant)) {
    throw new HttpError(403, "مش مسموح لك ترفع صورة في المجلد ده.");
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const detected = detectImageContent(bytes);
  if (!detected) throw new HttpError(415, "صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WEBP.");
  const uploadFolder = folder === "special_requests"
    ? await cloudinarySpecialRequestFolder(uid)
    : folder === "banners" || isAdmin
      ? folder
      : `${folder}/${isApplicant ? (requestedStoreId || "applications/" + uid) : storeId}`;
  const timestamp = Math.floor(Date.now() / 1000);
  const publicId = crypto.randomUUID();
  const signedParams = {
    allowed_formats: "jpg,jpeg,png,webp",
    ...(folder === "special_requests" ? {} : { folder: uploadFolder }),
    overwrite: "false",
    public_id: folder === "special_requests" ? `${uploadFolder}/${publicId}` : publicId,
    timestamp: String(timestamp),
    unique_filename: "true",
    use_filename: "false",
  };
  const signature = await cloudinarySignature(signedParams, env.CLOUDINARY_API_SECRET);
  const upload = new FormData();
  upload.append("file", new Blob([bytes], { type: detected.mime }), `${publicId}.${detected.format}`);
  upload.append("api_key", env.CLOUDINARY_API_KEY);
  for (const [key, value] of Object.entries(signedParams)) upload.append(key, value);
  upload.append("signature", signature);

  const uploaded = await fetch(
    `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/image/upload`,
    { method: "POST", body: upload },
  );
  if (!uploaded.ok) {
    const detail = (await uploaded.text()).slice(0, 300);
    console.error("Cloudinary upload failed", uploaded.status, detail);
    throw new HttpError(502, "تعذر رفع الصورة إلى خدمة الصور. حاول مرة أخرى.");
  }
  const result = await uploaded.json() as { secure_url?: string };
  const secureUrl = typeof result.secure_url === "string" ? result.secure_url : "";
  let parsedUrl: URL;
  try { parsedUrl = new URL(secureUrl); } catch { throw new HttpError(502, "خدمة الصور لم ترجع رابطًا صالحًا."); }
  if (parsedUrl.protocol !== "https:" ||
      !(parsedUrl.hostname === "res.cloudinary.com" || parsedUrl.hostname.endsWith(".res.cloudinary.com")) ||
      !parsedUrl.pathname.startsWith(`/${env.CLOUDINARY_CLOUD_NAME}/image/upload/`)) {
    throw new HttpError(502, "خدمة الصور لم ترجع رابطًا آمنًا.");
  }
  return response({ url: secureUrl });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    let headers: Headers;
    try {
      headers = corsHeaders(request, env);
    } catch (error) {
      const e = error instanceof HttpError ? error : new HttpError(403, "Origin is not allowed.");
      return response({ error: e.message }, e.status);
    }
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return response({ ok: true, service: "wasally-order-gateway" }, 200, headers);
    }
    if (request.method === "POST" && url.pathname === "/v1/account/delete") {
      try {
        const result = await deleteAccount(request, env);
        const mergedHeaders = new Headers(result.headers);
        headers.forEach((value, key) => mergedHeaders.set(key, value));
        return new Response(await result.text(), { status: result.status, headers: mergedHeaders });
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(500, "تعذر حذف الحساب بأمان. لم يتم تأكيد حذف حساب تسجيل الدخول.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/uploads") {
      try {
        const result = await uploadCloudinaryImage(request, env);
        const mergedHeaders = new Headers(result.headers);
        headers.forEach((value, key) => mergedHeaders.set(key, value));
        return new Response(await result.text(), { status: result.status, headers: mergedHeaders });
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(500, "تعذر رفع الصورة.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    const editPrefix = "/v1/orders/";
    const rawEditId = url.pathname.startsWith(editPrefix)
      ? url.pathname.slice(editPrefix.length)
      : "";
    const isCreate = request.method === "POST" && url.pathname === "/v1/orders";
    const isEdit = request.method === "PATCH" && rawEditId.length > 0 && !rawEditId.includes("/");
    if (!isCreate && !isEdit) return response({ error: "Not found." }, 404, headers);
    try {
      const result = isCreate
        ? await createOrder(request, env)
        : await updateOrder(request, env, decodeURIComponent(rawEditId));
      const mergedHeaders = new Headers(result.headers);
      headers.forEach((value, key) => mergedHeaders.set(key, value));
      return new Response(await result.text(), {
        status: result.status,
        headers: mergedHeaders,
      });
    } catch (error) {
      const e = error instanceof HttpError ? error : new HttpError(500, "حدث خطأ غير متوقع أثناء إنشاء الطلب.");
      return response({ error: e.message }, e.status, headers);
    }
  },
};
