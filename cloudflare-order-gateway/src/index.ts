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

export function firstName(value: unknown): string {
  return String(value ?? "").trim().split(/\s+/)[0] ?? "";
}

function money(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
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

async function verifyCustomer(request: Request, env: Env): Promise<string> {
  const auth = request.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw new HttpError(401, "سجّل الدخول من جديد.");
  try {
    const { payload } = await jwtVerify(token, firebaseKeys, {
      audience: env.FIREBASE_PROJECT_ID,
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
    });
    if (typeof payload.sub !== "string" || !payload.sub || payload.sub.length > 128) {
      throw new Error("Missing subject");
    }
    return payload.sub;
  } catch {
    throw new HttpError(401, "رمز تسجيل الدخول غير صالح أو منتهي.");
  }
}

async function googleAccessToken(env: Env): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.token;
  }
  const privateKey = env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY.replace(/\\n/g, "\n");
  const key = await importPKCS8(privateKey, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging",
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
  const restriction = restrictionDoc ? decodeFields(restrictionDoc.fields ?? {}) : {};
  if (restriction.active === true &&
      restriction.expiresAt instanceof Date &&
      restriction.expiresAt.getTime() > Date.now()) {
    throw new HttpError(403, "حسابك مقيّد مؤقتًا. راجع زر الشكاوى للاعتراض.");
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

  const order: JsonMap = {
    userId: uid,
    customerName,
    notes,
    storeId,
    storeName: String(store.name ?? "").trim(),
    items,
    subtotal,
    deliveryFee,
    total,
    paymentMethod: "cash",
    status: "new",
    ...(orderArea ? { area: orderArea } : {}),
    ...(normalizedPromo && discount > 0 ? { promoCode: normalizedPromo, discount } : {}),
  };
  if (!order.storeName || order.storeName.length > 100) {
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

  const updatedOrder: JsonMap = {
    ...order,
    items,
    subtotal,
    total,
    notes,
    customerName,
  };
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
    const updatedFeed = {
      ...feed,
      items,
      subtotal,
      discount,
      total,
    };
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

async function signCloudinaryUpload(request: Request, env: Env): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  if (!env.CLOUDINARY_CLOUD_NAME || !env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET) {
    throw new HttpError(503, "خدمة رفع الصور الموقّع غير مهيأة على الخادم.");
  }
  let input: any;
  try { input = await request.json(); } catch { throw new HttpError(400, "بيانات رفع الصورة غير مفهومة."); }
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new HttpError(400, "صيغة بيانات رفع الصورة غير صحيحة.");
  const folder = String(input.folder ?? "");
  const storeId = String(input.storeId ?? "").trim();
  if (!["stores", "products", "banners"].includes(folder)) throw new HttpError(400, "مجلد الصور غير مسموح.");
  if (storeId.length > 100 || (storeId && !/^[A-Za-z0-9_-]+$/.test(storeId))) throw new HttpError(400, "معرّف المحل غير صالح.");
  const token = await googleAccessToken(env);
  const [adminDoc, ownerDoc, roleRequestDoc] = await Promise.all([
    getDocument(env, `admins/${encodeURIComponent(uid)}`, token),
    getDocument(env, `storeOwners/${encodeURIComponent(uid)}`, token),
    getDocument(env, `role_requests/${encodeURIComponent(uid + "_store_owner")}`, token),
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
    (folder === "stores" && storeId === "" && !requestedStoreId);
  if (folder === "banners" ? !isAdmin : !(isAdmin || (storeId && isOwner) || isApplicant)) {
    throw new HttpError(403, "مش مسموح لك ترفع صورة في المجلد ده.");
  }
  const uploadFolder = folder === "banners" || isAdmin
    ? folder
    : `${folder}/${isApplicant ? (requestedStoreId || "applications/" + uid) : storeId}`;
  const timestamp = Math.floor(Date.now() / 1000);
  const allowedFormats = "jpg,jpeg,png,webp";
  const signature = await cloudinarySignature({
    allowed_formats: allowedFormats,
    folder: uploadFolder,
    overwrite: "false",
    timestamp: String(timestamp),
    unique_filename: "true",
    use_filename: "false",
  }, env.CLOUDINARY_API_SECRET);
  return response({ cloudName: env.CLOUDINARY_CLOUD_NAME, apiKey: env.CLOUDINARY_API_KEY, timestamp, folder: uploadFolder, allowedFormats, overwrite: false, uniqueFilename: true, useFilename: false, signature });
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
    if (request.method === "POST" && url.pathname === "/v1/uploads/sign") {
      try {
        const result = await signCloudinaryUpload(request, env);
        const mergedHeaders = new Headers(result.headers);
        headers.forEach((value, key) => mergedHeaders.set(key, value));
        return new Response(await result.text(), { status: result.status, headers: mergedHeaders });
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(500, "تعذر تجهيز رفع الصورة.");
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
