import { quoteReferralPoints } from "./referral_points";
import { districtFromAddress } from "./address_district";
import { commissionAmounts } from "./referral_commission";
import { buildAdminReferralSettingsWrite } from "./referral_admin_settings";
import { parseReferralSettings } from "./referral_settings";
import { ReferralPayoutConflict, updateReferralPayout } from "./referral_payout";
import { getOrIssueReferralCode } from "./referral_campaign";
import { settleCustomerDelivery, settleStoreDelivery } from "./referral_delivery";
import { registerReferral } from "./referral_registration";
import {
  REFERRAL_IDENTITY_COLLECTION,
  googleSubjectFromFirebaseLookup,
  hasValidIdentitySecret,
  identityMarkerExpiresAt,
  isActiveDeletedIdentity,
  referralIdentityDocumentId,
  isValidAndroidSsaid,
  referralDeviceDocumentId,
  referralDeviceOwnerDigest,
  referralDeviceEligibility,
} from "./referral_identity";
import { pruneExpiredDeletedReferralIdentities } from "./referral_identity_prune";
import { isOriginalRegistrationSession } from "./referral_first_session";
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";
import {
  OrderGroupError,
  orderGroupCode,
  parseOrderGroupId,
  planOrderGroup,
} from "./order_groups";
import { DELIVERY_PIN_MAX_ATTEMPTS, deriveDeliveryPin, equalPin, isDeliveryPin } from "./delivery_pin";
import {
  QUICK_PIN_STATUSES,
  QuickRuleError,
  applyQuickAction,
  newQuickOrder,
  quickCustomerImages,
  quickCustomerVoice,
  quickDeliveredPatch,
  validateQuickImages,
  validateQuickVoice,
  quickDeliveryBlocker,
  resolveQuickSettings,
  validateQuickNotes,
  validateQuickStores,
  validateErrandType,
  validateErrandPickup,
  type QuickActor,
} from "./quick_orders";

interface Env {
  FIREBASE_PROJECT_ID: string;
  REFERRAL_REGISTRATION_ENABLED?: string;
  REFERRAL_DELIVERY_ENABLED?: string;
  /** Cloudflare secret; 32+ bytes, never committed or exposed to clients. */
  REFERRAL_IDENTITY_HMAC_KEY?: string;
  /** Set true in production. App Check must pass for device-bound claims. */
  REFERRAL_DEVICE_APP_CHECK_REQUIRED?: string;
  FIREBASE_SERVICE_ACCOUNT_EMAIL: string;
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: string;
  ALLOWED_ORIGINS?: string;
  DEFAULT_DELIVERY_FEE?: string;
  MAX_ORDER_LINES?: string;
  MAX_LINE_QTY?: string;
  // الحد الأقصى لطلبات العميل الواحد في اليوم (بتوقيت القاهرة). الافتراضي 10.
  MAX_ORDERS_PER_DAY?: string;
  CLOUDINARY_CLOUD_NAME?: string;
  CLOUDINARY_API_KEY?: string;
  CLOUDINARY_API_SECRET?: string;
  UPLOAD_RATE_LIMITER: RateLimit;
  // حد تقريبي لطلبات الإنشاء/التعديل لكل عميل (قبل أي قراءة Firestore). اختياري: لو مش مضبوط السلوك زي ما كان.
  ORDER_RATE_LIMITER?: RateLimit;
  // App Check: off (الافتراضي، بدون أي تغيير) | monitor (تسجيل فقط) | enforce (رفض الطلب بدون رمز صالح).
  APP_CHECK_MODE?: string;
  // رقم مشروع Firebase (Project number) المطلوب للتحقق من رموز App Check.
  FIREBASE_PROJECT_NUMBER?: string;
  // سر اشتقاق رمز التسليم (secret في Cloudflare، مش في wrangler.toml). من غيره ميزة الرمز متوقفة.
  DELIVERY_PIN_SECRET?: string;
}

type JsonMap = Record<string, unknown>;
type FirestoreDoc = { name: string; fields?: Record<string, unknown>; updateTime?: string };

class HttpError extends Error {
  // code: machine-readable reason for the app (e.g. "catalog_mismatch" = the customer's cached
  // catalog is behind; the app then stops trusting its aggregated menu for that store).
  constructor(readonly status: number, message: string, readonly code?: string) {
    super(message);
  }
}

const CATALOG_MISMATCH = "catalog_mismatch";

const firebaseKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);
let cachedAccessToken: { token: string; expiresAt: number } | undefined;
const appCheckKeys = createRemoteJWKSet(new URL("https://firebaseappcheck.googleapis.com/v1/jwks"));

export type AppCheckMode = "off" | "monitor" | "enforce";

export function appCheckMode(value: unknown): AppCheckMode {
  const mode = String(value ?? "").trim().toLowerCase();
  return mode === "monitor" || mode === "enforce" ? mode : "off";
}

/**
 * يتحقق من رمز Firebase App Check في الهيدر X-Firebase-AppCheck.
 * off: لا يفعل شيئًا. monitor: يسجّل الفشل ويكمل. enforce: يرفض الطلب.
 */
async function assertAppCheck(request: Request, env: Env): Promise<void> {
  const mode = appCheckMode(env.APP_CHECK_MODE);
  if (mode === "off") return;
  const projectNumber = String(env.FIREBASE_PROJECT_NUMBER ?? "").trim();
  if (!/^[0-9]{6,20}$/.test(projectNumber)) {
    if (mode === "enforce") throw new HttpError(503, "إعدادات التحقق من التطبيق غير مكتملة.");
    console.warn("App Check monitor skipped: FIREBASE_PROJECT_NUMBER is not configured");
    return;
  }
  const token = request.headers.get("X-Firebase-AppCheck") ?? "";
  let failure = "";
  let keysUnavailable = false;
  if (!token) {
    failure = "missing";
  } else {
    try {
      const { payload } = await jwtVerify(token, appCheckKeys, {
        issuer: `https://firebaseappcheck.googleapis.com/${projectNumber}`,
        audience: `projects/${projectNumber}`,
        algorithms: ["RS256"],
      });
      if (typeof payload.sub !== "string" || !payload.sub) failure = "no-app-id";
    } catch (error) {
      // تعذر جلب مفاتيح Google (شبكة/مهلة) ≠ رمز غير صالح؛ لا نلوم نسخة التطبيق على عطل خارجي.
      const code = String((error as { code?: unknown })?.code ?? "");
      // ERR_JOSE_GENERIC: رد غير 200 أو JSON تالف من خادم مفاتيح Google.
      keysUnavailable = !code || code === "ERR_JWKS_TIMEOUT" || code === "ERR_JWKS_INVALID" ||
        code === "ERR_JOSE_GENERIC";
      failure = keysUnavailable ? "keys-unavailable" : "invalid";
    }
  }
  if (!failure) return;
  if (mode === "enforce") {
    if (keysUnavailable) {
      throw new HttpError(503, "تعذر التحقق من التطبيق حاليًا. حاول مرة أخرى بعد قليل.");
    }
    throw new HttpError(401, "تعذر التحقق من نسخة التطبيق. حدّث التطبيق وحاول تاني.");
  }
  console.warn("App Check monitor: request without a valid token", failure);
}
const firebaseUserStateCache = new Map<string, {
  checkedAt: number;
  createdAtMs: number;
  lastLoginAtMs: number;
  googleSubject: string | null;
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
    headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Firebase-AppCheck");
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
  "finalDeliveryFee", "discount", "total", "status", "createdAt", "groupCode",
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
    // كود التجميع بس (6 حروف) من غير groupId الكامل ولا أي بيانات للعميل.
    ...(typeof data.groupCode === "string" && data.groupCode ? { groupCode: data.groupCode } : {}),
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

/**
 * Resolve selected option labels against the store-owned catalog.
 * Client-provided option prices are never trusted; optionsTotal is only a stale-cart check.
 */
export function resolveCatalogOptions(
  product: JsonMap,
  line: JsonMap,
): { options: string[]; optionsTotal: number } {
  const rawGroups = product.optionGroups ?? [];
  const selectedRaw = line.options ?? [];
  if (!Array.isArray(rawGroups) || rawGroups.length > 10 ||
      !Array.isArray(selectedRaw) || selectedRaw.length > 200) {
    throw new HttpError(409, "خيارات أحد الأصناف غير صالحة في الكتالوج.");
  }
  if (selectedRaw.some((value) => typeof value !== "string")) {
    throw new HttpError(400, "صيغة اختيارات أحد الأصناف غير صحيحة.");
  }
  const selected = selectedRaw.map((value) => value.trim());
  if (selected.some((name) => !name || name.length > 80) ||
      new Set(selected).size !== selected.length) {
    throw new HttpError(400, "اختيارات أحد الأصناف غير صالحة أو مكررة.");
  }

  const groups: Array<{ min: number; max: number; names: Set<string> }> = [];
  const matches = new Map<string, number[]>();
  const optionPrices = new Map<string, number>();
  for (const rawGroup of rawGroups) {
    if (!rawGroup || typeof rawGroup !== "object" || Array.isArray(rawGroup)) {
      throw new HttpError(409, "مجموعة خيارات غير صالحة في الكتالوج.");
    }
    const group = rawGroup as JsonMap;
    const rawOptions = Array.isArray(group.options) ? group.options : [];
    if (!rawOptions.length || rawOptions.length > 20) {
      throw new HttpError(409, "عدد اختيارات المجموعة غير صالح في الكتالوج.");
    }
    const min = group.min === undefined ? 0 : Number(group.min);
    const max = group.max === undefined ? 1 : Number(group.max);
    if (!Number.isInteger(min) || !Number.isInteger(max) ||
        min < 0 || max < 1 || max > rawOptions.length || min > max) {
      throw new HttpError(409, "حدود مجموعة الخيارات غير صالحة في الكتالوج.");
    }
    const names = new Set<string>();
    for (const rawOption of rawOptions) {
      if (!rawOption || typeof rawOption !== "object" || Array.isArray(rawOption)) {
        throw new HttpError(409, "اختيار غير صالح في الكتالوج.");
      }
      const option = rawOption as JsonMap;
      const name = String(option.name ?? "").trim();
      const price = option.price === undefined ? 0 : Number(option.price);
      if (!name || name.length > 80 || !Number.isFinite(price) || price < 0 || price > 20000 ||
          names.has(name)) {
        throw new HttpError(409, "اسم أو سعر اختيار غير صالح في الكتالوج.");
      }
      names.add(name);
      const indexes = matches.get(name) ?? [];
      indexes.push(groups.length);
      matches.set(name, indexes);
      optionPrices.set(name, price);
    }
    groups.push({ min, max, names });
  }

  const counts = groups.map(() => 0);
  let optionsTotal = 0;
  for (const name of selected) {
    const indexes = matches.get(name) ?? [];
    if (indexes.length !== 1) {
      throw new HttpError(409, "أحد الاختيارات لم يعد متاحًا أو اسمه مكرر في الكتالوج.", CATALOG_MISMATCH);
    }
    const groupIndex = indexes[0];
    counts[groupIndex] += 1;
    optionsTotal += optionPrices.get(name) ?? 0;
  }
  for (let i = 0; i < groups.length; i++) {
    if (counts[i] < groups[i].min || counts[i] > groups[i].max) {
      throw new HttpError(409, "راجع الاختيارات المطلوبة لأحد الأصناف.");
    }
  }

  if (line.optionsTotal !== undefined && typeof line.optionsTotal !== "number") {
    throw new HttpError(400, "قيمة إضافات أحد الأصناف غير صحيحة.");
  }
  const expectedOptionsTotal = line.optionsTotal === undefined ? 0 : line.optionsTotal;
  optionsTotal = money(optionsTotal);
  if (!Number.isFinite(expectedOptionsTotal) ||
      Math.abs(expectedOptionsTotal - optionsTotal) >= 0.01) {
    throw new HttpError(409, "سعر إضافات أحد الأصناف اتغير. راجع اختياراتك.", CATALOG_MISMATCH);
  }
  return { options: selected, optionsTotal };
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
      const upstreamBody = await lookup.text();
      if (upstreamBody.includes("USER_NOT_FOUND")) {
        if (options.allowMissingUser) return;
        throw new HttpError(401, "الحساب لم يعد نشطًا. سجّل الدخول من جديد.");
      }
      console.error("Firebase Auth account lookup failed", lookup.status);
      throw new HttpError(503, "تعذر التحقق من حالة الحساب حاليًا. حاول مرة أخرى.");
    }
    const result = await lookup.json() as {
      users?: Array<{
        localId?: string; validSince?: string; disabled?: boolean;
        createdAt?: string; lastLoginAt?: string;
        providerUserInfo?: Array<{ providerId?: string; rawId?: string }>;
      }>;
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
    state = {
      checkedAt: now,
      validSince,
      disabled: user.disabled === true,
      createdAtMs: Number(user.createdAt),
      lastLoginAtMs: Number(user.lastLoginAt),
      googleSubject: googleSubjectFromFirebaseLookup(user.providerUserInfo),
    };
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

async function verifyCustomer(request: Request, env: Env, firstRegistration = false): Promise<string> {
  await assertAppCheck(request, env);
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
  if (firstRegistration) {
    const state = firebaseUserStateCache.get(payload.sub);
    const createdAtMs = state?.createdAtMs ?? 0;
    const authTimeMs = Number(payload.auth_time) * 1000;
    const lastLoginAtMs = state?.lastLoginAtMs ?? 0;
    // A code may be entered only during the *original Google registration
    // session*. Later Google sign-ins cannot claim, regardless of order
    // history or elapsed time. Firebase Auth metadata is authoritative.
    if (!isOriginalRegistrationSession(createdAtMs, lastLoginAtMs, authTimeMs)) {
      throw new HttpError(403, "كود الدعوة متاح عند إنشاء حساب جديد فقط.");
    }
  }
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

async function getDocument(env: Env, path: string, token: string, signal?: AbortSignal): Promise<FirestoreDoc | null> {
  const result = await fetch(documentPath(env.FIREBASE_PROJECT_ID, path), {
    signal,
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
  await assertAppCheck(request, env);
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

// The app shows stores from one aggregated index (app_info/store_index). When a store is
// deactivated here, nobody is left to remove its entry, so do it now and bump the index version
// (customers re-read the index once). Best effort: failure must not block account deletion.
async function removeStoreFromCatalogIndex(env: Env, token: string, storeId: string): Promise<void> {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(storeId)) return;
  try {
    await commitFirestoreWrites(env, token, [
      {
        update: { name: firestoreDocumentName(env, "app_info/store_index"), fields: {} },
        updateMask: { fieldPaths: [`\`s_${storeId}\``] },
      },
      {
        transform: {
          document: firestoreDocumentName(env, "app_info/catalog_versions"),
          fieldTransforms: [{ fieldPath: "stores", increment: { integerValue: "1" } }],
        },
      },
    ]);
  } catch (error) {
    console.error("Catalog index cleanup failed", error instanceof Error ? error.message : error);
  }
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
      console.error("Firestore account cleanup commit failed", result.status);
      throw new HttpError(503, "تعذر استكمال تنظيف بيانات الحساب حاليًا. حاول مرة أخرى.");
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
      console.error("Firestore account cleanup query failed", result.status);
      throw new HttpError(503, "تعذر قراءة سجلات حذف الحساب حاليًا. حاول مرة أخرى.");
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
      if (store) await removeStoreFromCatalogIndex(env, token, ownedStoreId);
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
    const upstreamBody = await result.text();
    // A retry after a lost response is successful if Firebase already deleted the user.
    if (upstreamBody.includes("USER_NOT_FOUND")) return;
    console.error("Firebase Auth account deletion failed", result.status);
    throw new HttpError(503, "تم تنظيف البيانات لكن تعذر حذف حساب تسجيل الدخول حاليًا. أعد المحاولة.");
  }
}

/**
 * In the deletion flow, the verified Google subject is only used in memory.
 * Deleting accounts is never blocked by a missing secret or missing provider
 * metadata: the right to delete must be preserved. The referral CLAIM endpoint
 * fails closed in that state, and production rollout requires the secret.
 */
async function rememberDeletedReferralIdentity(
  env: Env,
  token: string,
  uid: string,
): Promise<void> {
  const googleSubject = firebaseUserStateCache.get(uid)?.googleSubject ?? null;
  if (!hasValidIdentitySecret(env.REFERRAL_IDENTITY_HMAC_KEY) || !googleSubject) {
    console.warn("Referral re-registration protection not configured for account deletion");
    return;
  }
  const marker = await referralIdentityDocumentId(
    env.REFERRAL_IDENTITY_HMAC_KEY!, googleSubject,
  );
  await commitFirestoreWrites(env, token, [{
    update: {
      name: firestoreDocumentName(env, `${REFERRAL_IDENTITY_COLLECTION}/${marker}`),
      fields: encodeFields({
        reason: "deleted_account_referral_prevention",
        createdAt: new Date(),
        expiresAt: identityMarkerExpiresAt(new Date()),
      }),
    },
  }]);
}

const REFERRAL_DEVICE_COLLECTION = "referral_device_bindings";

async function assertReferralDeviceAppCheck(request: Request, env: Env): Promise<void> {
  // In production, require valid Play Integrity-backed App Check for the
  // invitation binding path, even while the rest of the app is in monitor mode.
  // "false" is reserved for CI/emulator staging, not a release configuration.
  if (env.REFERRAL_DEVICE_APP_CHECK_REQUIRED !== "false") {
    await assertAppCheck(request, { ...env, APP_CHECK_MODE: "enforce" });
  }
}

/**
 * One Google identity per Android app-scoped device can receive a new-user
 * invitation. All Google sign-ins attempt this lightweight binding, even if
 * the account will not use a code, so a second account cannot impersonate a
 * new user from the same phone merely because the first skipped the code.
 *
 * The on-device SSAID is never persisted or logged; this stores HMAC digests
 * only. Android SSAID is not a cryptographic attestation: App Check must also
 * pass, and rooted/virtual devices cannot be guaranteed unique.
 */
async function bindReferralDevice(
  env: Env, token: string, uid: string, deviceId: unknown,
): Promise<boolean> {
  if (!hasValidIdentitySecret(env.REFERRAL_IDENTITY_HMAC_KEY)) {
    throw new HttpError(503, "حماية مكافآت الإحالة غير مهيأة حاليًا.");
  }
  if (!isValidAndroidSsaid(deviceId)) {
    throw new HttpError(403, "تعذر التحقق من جهازك لاستحقاق كود الدعوة.");
  }
  const subject = firebaseUserStateCache.get(uid)?.googleSubject;
  if (!subject) throw new HttpError(403, "تعذر التحقق من هوية جوجل للمكافأة.");
  const key = env.REFERRAL_IDENTITY_HMAC_KEY!;
  const digest = await referralDeviceDocumentId(key, deviceId);
  const owner = await referralDeviceOwnerDigest(key, subject);
  const path = `${REFERRAL_DEVICE_COLLECTION}/${digest}`;
  const name = firestoreDocumentName(env, path);

  // Conditional create/replace is safe if two accounts bind concurrently.
  for (let attempt = 0; attempt < 3; attempt++) {
    const existing = await getDocument(env, path, token);
    const now = new Date();
    const decision = referralDeviceEligibility(
      existing ? decodeFields(existing.fields ?? {}) : null, owner, now,
    );
    if (decision === "block") return false;
    if (decision === "same") return true;
    if (decision === "replace-expired" && !existing?.updateTime) {
      throw new HttpError(503, "تعذر التحقق من سجل الجهاز حاليًا.");
    }
    const result = await fetch(`${firestoreDocumentsUrl(env)}:commit`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`, "Content-Type": "application/json",
      },
      body: JSON.stringify({ writes: [{
        update: {
          name,
          fields: encodeFields({
            googleOwnerDigest: owner,
            createdAt: now,
            expiresAt: identityMarkerExpiresAt(now),
          }),
        },
        currentDocument: existing
          ? { updateTime: existing.updateTime }
          : { exists: false },
      }] }),
    });
    if (result.ok) return true;
    // A racing registration may have won; re-read instead of overwriting.
    if (result.status === 409 || result.status === 412) continue;
    throw new HttpError(503, "تعذر تسجيل حماية الإحالة على الجهاز.");
  }
  throw new HttpError(503, "حاول التحقق من الجهاز مرة ثانية.");
}

async function rejectPreviouslyDeletedReferralIdentity(
  env: Env,
  uid: string,
  token: string,
): Promise<void> {
  if (!hasValidIdentitySecret(env.REFERRAL_IDENTITY_HMAC_KEY)) {
    throw new HttpError(503, "حماية الإحالات غير مهيأة حاليًا.");
  }
  const googleSubject = firebaseUserStateCache.get(uid)?.googleSubject;
  if (!googleSubject) {
    throw new HttpError(403, "تعذر التحقق من أهلية كود الإحالة لحساب جوجل.");
  }
  const marker = await referralIdentityDocumentId(
    env.REFERRAL_IDENTITY_HMAC_KEY!, googleSubject,
  );
  const deleted = await getDocument(
    env, `${REFERRAL_IDENTITY_COLLECTION}/${marker}`, token,
  );
  if (deleted && isActiveDeletedIdentity(decodeFields(deleted.fields ?? {}), new Date())) {
    throw new HttpError(403, "كود الدعوة للمستخدم الجديد فقط، ولا يُعاد بعد حذف الحساب.");
  }
}

async function deleteAccount(request: Request, env: Env): Promise<Response> {
  if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_SERVICE_ACCOUNT_EMAIL ||
      !env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY) {
    throw new HttpError(503, "خدمة حذف الحساب غير مهيأة على الخادم.");
  }
  const uid = await verifyRecentCustomer(request, env);
  const token = await googleAccessToken(env);
  await rememberDeletedReferralIdentity(env, token, uid);
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
  const docs = new Map<string, JsonMap>();
  for (const item of parseBatchGetResponse(await result.text())) {
    if (item.found?.name) {
      const path = item.found.name.split("/documents/")[1];
      docs.set(path, decodeFields(item.found.fields ?? {}));
    }
  }
  return docs;
}

/**
 * رد Firestore REST على documents:batchGet بيرجع JSON array منسّق على كذا سطر
 * ([{"found": ...}, {"missing": ...}]). الكود القديم كان بيعمل JSON.parse لكل سطر لوحده،
 * فأول طلب حقيقي فيه أصناف كتالوج كان بيقع بـ SyntaxError = HTTP 500.
 * بنقبل الـarray (الشكل الحقيقي)، أو object واحد، أو سطر لكل عنصر (NDJSON).
 */
export function parseBatchGetResponse(text: string): Array<{ found?: FirestoreDoc; missing?: string }> {
  const trimmed = text.trim();
  if (!trimmed) return [];
  try {
    const parsed = JSON.parse(trimmed) as unknown;
    if (Array.isArray(parsed)) return parsed as Array<{ found?: FirestoreDoc }>;
    if (parsed && typeof parsed === "object") return [parsed as { found?: FirestoreDoc }];
  } catch {
    // مش JSON واحد: نجرب سطر لكل عنصر.
  }
  try {
    return trimmed.split("\n").filter((line) => line.trim()).map((line) => {
      const item = JSON.parse(line) as unknown;
      if (!item || typeof item !== "object" || Array.isArray(item)) throw new Error("bad item");
      return item as { found?: FirestoreDoc };
    });
  } catch {
    throw new HttpError(503, "تعذر قراءة كتالوج الأصناف من قاعدة البيانات.");
  }
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

/** هوية سطر الطلب: الصنف + اختياراته (مرتبة)، عشان نفس الصنف باختيار مختلف يبقى سطر مستقل. */
export function orderLineIdentity(productId: string, name: string, options: unknown[] = []) {
  const base = productId ? `id:${productId}` : `legacy:${name.toLowerCase()}`;
  const opts = options.map((o) => String(o).trim()).filter(Boolean).sort();
  return opts.length ? `${base}|${opts.join("\u0001")}` : base;
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
  // Validate every line before batchGet so malformed requests cannot trigger needless Firestore reads.
  for (const line of lines) {
    if (!line || typeof line !== "object" || Array.isArray(line)) {
      throw new HttpError(400, "بيانات أحد الأصناف غير صحيحة.");
    }
    if (typeof line.qty !== "number" || !Number.isInteger(line.qty) ||
        line.qty < 1 || line.qty > Number(env.MAX_LINE_QTY ?? 50)) {
      throw new HttpError(400, "كمية أحد الأصناف غير صالحة.");
    }
    if (typeof line.expectedPrice !== "number" || !Number.isFinite(line.expectedPrice) ||
        line.expectedPrice <= 0) {
      throw new HttpError(400, "سعر الصنف المرسل غير صالح.");
    }
    if (line.productId !== undefined && typeof line.productId !== "string") {
      throw new HttpError(400, "معرّف صنف غير صالح.");
    }
    if (line.options !== undefined &&
        (!Array.isArray(line.options) || line.options.length > 200 ||
          line.options.some((option: unknown) => typeof option !== "string"))) {
      throw new HttpError(400, "صيغة اختيارات أحد الأصناف غير صحيحة.");
    }
    if (line.optionsTotal !== undefined &&
        (typeof line.optionsTotal !== "number" || !Number.isFinite(line.optionsTotal) ||
          line.optionsTotal < 0)) {
      throw new HttpError(400, "قيمة إضافات أحد الأصناف غير صحيحة.");
    }
    if (!String(line.productId ?? "").trim() &&
        (typeof line.name !== "string" || !line.name.trim() || line.name.length > 200)) {
      throw new HttpError(400, "اسم الصنف غير صالح.");
    }
  }
  const productIds = [...new Set(lines.map((line: any) => String(line.productId ?? "").trim()).filter(Boolean))];
  if (productIds.some((id) => id.includes("/") || id.length > 150)) {
    throw new HttpError(400, "معرّف صنف غير صالح.");
  }
  const productPaths = productIds.map((id) => `stores/${encodeURIComponent(storeId)}/products/${encodeURIComponent(id)}`);
  const productDocs = await batchGetDocuments(env, productPaths, token);
  const seen = new Set<string>();
  const items: JsonMap[] = [];
  let subtotal = 0;
  for (const line of lines) {
    if (!line || typeof line !== "object" || Array.isArray(line)) {
      throw new HttpError(400, "بيانات أحد الأصناف غير صحيحة.");
    }
    const qty = line.qty;
    if (typeof qty !== "number" || !Number.isInteger(qty) ||
        qty < 1 || qty > Number(env.MAX_LINE_QTY ?? 50)) {
      throw new HttpError(400, "كمية أحد الأصناف غير صالحة.");
    }
    if (line.productId !== undefined && typeof line.productId !== "string") {
      throw new HttpError(400, "معرّف صنف غير صالح.");
    }
    const productId = String(line.productId ?? "").trim();
    let product: JsonMap;
    let resolvedId = productId;
    let isLegacy = false;
    if (productId) {
      const path = `stores/${encodeURIComponent(storeId)}/products/${encodeURIComponent(productId)}`;
      const found = productDocs.get(path);
      if (!found) throw new HttpError(409, "أحد الأصناف لم يعد موجودًا في كتالوج المحل.", CATALOG_MISMATCH);
      product = found;
    } else {
      const name = String(line?.name ?? "").trim();
      if (!name || name.length > 120) throw new HttpError(400, "صنف قديم بدون اسم صالح.");
      product = productFromLegacy(store, name);
      resolvedId = "";
      isLegacy = true;
    }
    if (product.available === false || product.isAvailable === false) {
      throw new HttpError(409, "أحد الأصناف غير متاح حاليًا.", CATALOG_MISMATCH);
    }
    const name = String(product.name ?? "").trim();
    if (!name || name.length > 120) throw new HttpError(409, "بيانات صنف غير صالحة في الكتالوج.");
    const resolvedOptions = resolveCatalogOptions(product, line as JsonMap);
    // نفس الصنف باختيارات مختلفة (فلفل بلدي / صوب) سطرين مختلفين، مش تكرار.
    const identity = orderLineIdentity(resolvedId, name, resolvedOptions.options);
    if (seen.has(identity)) throw new HttpError(400, "الصنف مكرر في الطلب.");
    seen.add(identity);
    const basePrice = effectiveCatalogPrice(
      isLegacy ? { ...product, oldPrice: 0, offerEndsAt: null } : product,
    );
    const price = money(basePrice + resolvedOptions.optionsTotal);
    const expectedPrice = line.expectedPrice;
    if (typeof expectedPrice !== "number" || !Number.isFinite(expectedPrice)) {
      throw new HttpError(400, "سعر الصنف المرسل غير صالح.");
    }
    // expectedPrice is only a stale-cart check; the saved price and option surcharges come from Firestore.
    if (!catalogPriceMatches(expectedPrice, price)) {
      throw new HttpError(409, "سعر أحد الأصناف أو إضافاته اتغير. راجع السلة قبل تأكيد الطلب.", CATALOG_MISMATCH);
    }
    subtotal = money(subtotal + price * qty);
    items.push({
      name,
      price,
      qty,
      ...(resolvedId ? { productId: resolvedId } : {}),
      ...(resolvedOptions.options.length
        ? { options: resolvedOptions.options, optionsTotal: resolvedOptions.optionsTotal }
        : {}),
    });
  }
  if (!Number.isFinite(subtotal) || subtotal <= 0 || subtotal > 100000) {
    throw new HttpError(409, "إجمالي الأصناف خارج الحدود المسموحة.");
  }
  return { items, subtotal };
}

export function courierTopicMessage(storeName: string) {
  return {
    message: {
      topic: "couriers",
      notification: {
        title: "طلب توصيل جديد متاح",
        body: String(storeName || "محل").slice(0, 80) + " • افتح التطبيق لمراجعة الطلب والتقديم عليه",
      },
      data: {
        type: "available_order",
      },
      android: {
        priority: "HIGH",
        ttl: "1800s",
        notification: { sound: "default" },
      },
    },
  };
}

async function notifyCouriersOfNewOrder(
  env: Env,
  accessToken: string,
  storeName: string,
): Promise<boolean> {
  const sent = await fetch(
    `https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(courierTopicMessage(storeName)),
      signal: AbortSignal.timeout(5_000),
    },
  );
  if (!sent.ok) {
    const detail = (await sent.text()).slice(0, 500);
    throw new Error(`FCM send failed (${sent.status}): ${detail}`);
  }
  return true;
}

/**
 * رسوم خدمة وصّلي على العميل: 2% من الأصناف (بعد الخصم)، أقل حاجة 5 وأقصى حاجة 15 جنيه.
 * بالقروش عشان نتجنب كسور العشرية (نفس WasallyServiceFee في التطبيق).
 */
export function serviceFeeFor(itemsAfterDiscount: number): number {
  if (!Number.isFinite(itemsAfterDiscount) || itemsAfterDiscount <= 0) return 0;
  const piastres = Math.round(itemsAfterDiscount * 100);
  const computed = Math.floor((piastres * 200 + 5000) / 10000);
  return Math.min(1500, Math.max(500, computed)) / 100;
}

export const ORDERS_PAUSED_MESSAGE = "استقبال الطلبات متوقف مؤقتًا. جرّب بعد شوية.";
export const DEFAULT_MAX_ORDERS_PER_DAY = 50;
/**
 * حد طلبات لكل عميل على إنشاء/تعديل الطلب، قبل أي قراءة Firestore: طلب مرفوض بالفاصل (20 ثانية)
 * أو بالحد اليومي كان بيكلّف قراءات كتير، وتعديل الطلب (PATCH) ماكانش عليه أي حد. من غير ده حساب
 * واحد بتوكن صالح يقدر يستهلك حصة Spark اليومية. لو الـbinding مش مضبوط أو فشل، الطلب بيكمل
 * (الحماية دي طبقة إضافية، وما تعطّلش العملاء لو Cloudflare نفسه فيه عطل).
 */
export async function assertOrderRateLimit(
  limiter: { limit(options: { key: string }): Promise<{ success: boolean }> } | undefined,
  uid: string,
): Promise<void> {
  if (!limiter) return;
  let success = true;
  try {
    ({ success } = await limiter.limit({ key: `order:${uid}` }));
  } catch (error) {
    console.warn("order rate limiter unavailable", error instanceof Error ? error.name : typeof error);
    return;
  }
  if (!success) {
    throw new HttpError(429, "طلبات كتير في وقت قصير. استنى دقيقة وحاول تاني.", "rate_limited");
  }
}

const DAILY_LIMIT_CODE = "daily_limit";

/** مفتاح اليوم بتوقيت القاهرة (YYYY-MM-DD)، بيراعي التوقيت الصيفي تلقائيًا. */
export function cairoDayKey(now: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/**
 * الحد اليومي المطبّق: قيمة app_info/delivery_areas.maxOrdersPerDay لو رقم صحيح من 1 لـ100
 * (بدون قراءة إضافية: المستند بيتقرا أصلًا)، وإلا MAX_ORDERS_PER_DAY من الإعدادات، وإلا 10.
 */
export function resolveMaxOrdersPerDay(configured: unknown, envValue: unknown): number {
  const fromDoc = Number(configured);
  if (typeof configured === "number" && Number.isInteger(fromDoc) && fromDoc >= 1 && fromDoc <= 100) {
    return fromDoc;
  }
  const fromEnv = Number(envValue);
  if (Number.isInteger(fromEnv) && fromEnv >= 1 && fromEnv <= 100) return fromEnv;
  return DEFAULT_MAX_ORDERS_PER_DAY;
}

/** عدد طلبات العميل المسجّلة النهارده (صفر لو آخر عدّاد من يوم تاني). */
export function ordersCountedToday(limit: JsonMap, dayKey: string): number {
  const count = limit.dailyCount;
  return limit.day === dayKey && typeof count === "number" && Number.isFinite(count) && count > 0
    ? Math.floor(count)
    : 0;
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
  await assertOrderRateLimit(env.ORDER_RATE_LIMITER, uid);
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
  const rawSpecialRequest = input.specialRequest;
  let specialRequest: JsonMap | undefined;
  if (rawSpecialRequest !== undefined && rawSpecialRequest !== null) {
    if (typeof rawSpecialRequest !== "object" || Array.isArray(rawSpecialRequest)) {
      throw new HttpError(400, "بيانات الطلب الخاص غير صحيحة.");
    }
    const description = String(rawSpecialRequest.description ?? "").trim();
    const quantity = Number(rawSpecialRequest.quantity ?? 1);
    const imageUrl = String(rawSpecialRequest.imageUrl ?? "");
    const voiceUrl = String(rawSpecialRequest.voiceUrl ?? "");
    // الصوت جوه مستند الطلب (base64) اتلغى: كان بيكبّر الطلب لحد 700KB.
    if (String(rawSpecialRequest.voiceBase64 ?? "")) {
      throw new HttpError(400, "حدّث التطبيق عشان تبعت رسالة صوتية.");
    }
    if (description.length > 300 || !Number.isInteger(quantity) || quantity < 1 || quantity > 99 ||
        (imageUrl && (!isCloudinaryImageUrl(imageUrl) || imageUrl.length > 450)) ||
        (voiceUrl && !isCloudinaryVoiceUrl(voiceUrl)) ||
        (!description && !imageUrl && !voiceUrl)) {
      throw new HttpError(400, "راجع وصف الطلب الخاص والمرفقات.");
    }
    if (voiceUrl &&
        !cloudinaryPublicIdFromUrl(voiceUrl).startsWith(await cloudinarySpecialRequestFolder(uid) + "/")) {
      throw new HttpError(403, "الرسالة الصوتية لا تخص حسابك.");
    }
    specialRequest = {
      description,
      quantity,
      ...(imageUrl ? { imageUrl } : {}),
      ...(voiceUrl ? { voiceUrl } : {}),
      createdAt: String(rawSpecialRequest.createdAt ?? "").slice(0, 40),
    };
  }
  const contact = validateContact(input.contact);
  // تجميع اختياري يختاره العميل لطلبات نفس رحلة التسوق (محل مختلف لكل طلب).
  let groupId = "";
  try {
    groupId = parseOrderGroupId(input.groupId);
  } catch (error) {
    if (error instanceof OrderGroupError) throw new HttpError(error.status, error.message, error.code);
    throw error;
  }

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
    if (old.userId === uid) {
      if (!isSameStoreOrderReplay(old.userId, old.storeId, uid, storeId)) {
        throw new HttpError(409, "معرّف الطلب مرتبط بمحل مختلف. أعد إرسال الطلب.");
      }
      return response({ orderId, reused: true });
    }
    throw new HttpError(409, "معرّف الطلب مستخدم بالفعل.");
  }

  const [storeDoc, restrictionDoc, limitDoc, areasDoc, groupDoc] = await Promise.all([
    getDocument(env, `stores/${encodeURIComponent(storeId)}`, token),
    getDocument(env, `customer_restrictions/${uid}`, token),
    getDocument(env, `orderLimits/${uid}`, token),
    getDocument(env, "app_info/delivery_areas", token),
    groupId ? getDocument(env, `order_groups/${groupId}`, token) : Promise.resolve(null),
  ]);
  // مفتاح طوارئ من الإدارة: app_info/delivery_areas.ordersPaused = true يوقف الطلبات الجديدة
  // (المستند ده بيتقري أصلًا هنا، فمفيش قراءة زيادة).
  if (areasDoc && decodeFields(areasDoc.fields ?? {}).ordersPaused === true) {
    throw new HttpError(503, ORDERS_PAUSED_MESSAGE, "orders_paused");
  }
  if (!storeDoc) throw new HttpError(404, "المحل غير موجود.");
  const store = decodeFields(storeDoc.fields ?? {});
  if (store.active !== undefined && store.active !== true) {
    throw new HttpError(409, "المحل مغلق حاليًا.");
  }
  if (store.isOpen === false) {
    throw new HttpError(409, "المحل مغلق الآن. جرّب بعد شوية.", "store_closed");
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
  // الحد اليومي: العدّاد في نفس مستند orderLimits وبيتكتب في نفس الـcommit بشرط updateTime،
  // فطلبين متزامنين مش هيعدّوا الحد (واحد بس بينجح والتاني بياخد 409). مفيش قراءات ولا كتابات زيادة.
  const dayKey = cairoDayKey(new Date());
  const todaysOrders = ordersCountedToday(previousLimit, dayKey);
  const maxPerDay = resolveMaxOrdersPerDay(
    areasDoc ? decodeFields(areasDoc.fields ?? {}).maxOrdersPerDay : undefined,
    env.MAX_ORDERS_PER_DAY,
  );
  if (todaysOrders >= maxPerDay) {
    throw new HttpError(
      429,
      `وصلت للحد اليومي للطلبات (${maxPerDay} طلبات). جرّب بكرة أو تواصل مع الدعم.`,
      DAILY_LIMIT_CODE,
    );
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
  } else {
    // مفيش قائمة مناطق: التطبيق بيبعت أول العنوان (الحي) عشان يظهر للأدمن والمناديب.
    // بنعيد تنضيفه هنا (اسم المنطقة بس) لأن المستند العام بيشوفه صاحب المحل.
    // لو العميل كان مختار منطقة من قائمة اتشالت، فرق رسوم التوصيل تحت بيرفض الطلب.
    orderArea = districtFromAddress(area);
  }
  if (!Number.isFinite(deliveryFee) || deliveryFee < 0 || deliveryFee > 500) {
    throw new HttpError(409, "رسوم التوصيل غير مضبوطة في إعدادات الإدارة.");
  }
  const expectedDeliveryFee = Number(input.expectedDeliveryFee);
  if (!Number.isFinite(expectedDeliveryFee) || Math.abs(expectedDeliveryFee - deliveryFee) >= 0.01) {
    throw new HttpError(409, "رسوم التوصيل اتغيرت. راجع الإجمالي قبل تأكيد الطلب.");
  }

  const { items, subtotal } = await resolveItems(env, token, storeId, store, lines);

  // الكوبونات موقوفة: التطبيق مابقاش يبعت كود. أي كود بيوصل هنا مرفوض بدل ما يتعمله خصم.
  // للرجوع: استرجع منطق الخصم من تاريخ git (promos/{code}).
  if (promoCode) throw new HttpError(409, "الكوبونات غير مفعّلة حاليًا.");
  const discount = 0;
  const normalizedPromo = "";
  const serviceFee = serviceFeeFor(subtotal - discount);
  const requestedPoints = input.referralPoints ?? 0;
  if (!Number.isSafeInteger(requestedPoints) || requestedPoints < 0) {
    throw new HttpError(400, "عدد نقاط الإحالة غير صالح.");
  }
  let referralDiscountMinor = 0;
  let pointWrites: unknown[] = [];
  if (requestedPoints > 0) {
    if (env.REFERRAL_REGISTRATION_ENABLED !== "true" ||
        env.REFERRAL_DELIVERY_ENABLED !== "true") {
      throw new HttpError(409, "استخدام نقاط الإحالة غير متاح حاليًا.");
    }
    const [settings, balance] = await Promise.all([
      getDocument(env, "app_info/referral_config", token),
      getDocument(env, `referral_balances/${uid}`, token),
    ]);
    const policy = settings && parseReferralSettings(decodeFields(settings.fields ?? {})).redemption;
    const quote = quoteReferralPoints(
      policy || undefined,
      balance ? decodeFields(balance.fields ?? {}).points : undefined,
      Math.round(subtotal * 100),
    );
    if (requestedPoints !== quote.points || !settings?.updateTime || !balance?.updateTime ||
        input.expectedReferralDiscountMinor !== quote.discountMinor) {
      throw new HttpError(409, "خصم النقاط اتغير. احسبه من جديد قبل تأكيد الطلب.");
    }
    referralDiscountMinor = quote.discountMinor;
    pointWrites = [
      { verify: settings.name, currentDocument: { updateTime: settings.updateTime } },
      referralPointsBalanceWrite(env, uid, -requestedPoints, balance.updateTime),
      {
        update: {
          name: firestoreDocumentName(env, `referral_redemptions/${orderId}`),
          fields: encodeFields({
            storeId, points: requestedPoints, discountMinor: referralDiscountMinor,
            status: "reserved",
          }),
        },
        currentDocument: { exists: false },
      },
    ];
  }
  const total = money(subtotal + deliveryFee - discount + serviceFee - referralDiscountMinor / 100);
  if (total <= 0 || total > 100000) throw new HttpError(409, "إجمالي الطلب غير صالح.");
  const expectedTotal = Number(input.expectedTotal);
  if (!Number.isFinite(expectedTotal) || Math.abs(expectedTotal - total) >= 0.01) {
    throw new HttpError(409, "إجمالي الطلب اتغير. راجع السلة قبل تأكيد الطلب.");
  }

  // التجميع بيتراجع بعد كل فحوصات الطلب، والمستند بيتكتب في نفس الـcommit (بشرط).
  let groupPlan: ReturnType<typeof planOrderGroup> | null = null;
  if (groupId) {
    try {
      groupPlan = planOrderGroup(groupDoc ? decodeFields(groupDoc.fields ?? {}) : null, {
        uid, orderId, storeId, now: new Date(),
      });
    } catch (error) {
      if (error instanceof OrderGroupError) throw new HttpError(error.status, error.message, error.code);
      throw error;
    }
  }

  const storeName = String(store.name ?? "").trim();
  const order: JsonMap = {
    userId: uid,
    customerName,
    notes,
    storeId,
    storeName,
    items,
    ...(specialRequest ? { specialRequest } : {}),
    subtotal,
    deliveryFee,
    serviceFee,
    total,
    paymentMethod: "cash",
    ...(referralDiscountMinor > 0 ? { referralDiscountMinor } : {}),
    status: "new",
    ...(orderArea ? { area: orderArea } : {}),
    ...(normalizedPromo && discount > 0 ? { promoCode: normalizedPromo, discount } : {}),
    ...(groupId ? { groupId, groupCode: orderGroupCode(groupId) } : {}),
  };
  if (!storeName || storeName.length > 100) {
    throw new HttpError(409, "بيانات المحل غير مكتملة.");
  }

  const writes = [
    ...pointWrites,
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
        fields: encodeFields({ lastAt: new Date(), day: dayKey, dailyCount: todaysOrders + 1 }),
      },
      updateTransforms: [{ fieldPath: "lastAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: limitDoc?.updateTime
        ? { updateTime: limitDoc.updateTime }
        : { exists: false },
    },
    ...(groupPlan ? [{
      update: {
        name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/order_groups/${groupId}`,
        fields: encodeFields(groupPlan.fields),
      },
      currentDocument: groupPlan.isNew || !groupDoc?.updateTime
        ? { exists: false }
        : { updateTime: groupDoc.updateTime },
    }] : []),
  ];
  const committed = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ writes }),
    },
  );
  if ([400, 409, 412].includes(committed.status)) {
    throw new HttpError(409, "تم تغيير الطلب بالتزامن. راجع طلباتك قبل إعادة المحاولة.");
  }
  if (!committed.ok) throw new HttpError(503, "تعذر حفظ الطلب؛ حاول مرة أخرى.");
  // الإشعار يُرسل من الخادم بعد نجاح حفظ الطلب فقط. فشل FCM لا يلغي الطلب.
  try {
    await notifyCouriersOfNewOrder(env, token, String(order.storeName));
  } catch (error) {
    console.error("Courier push notification failed", error);
  }
  return response({
    orderId, subtotal, deliveryFee, discount, total, items,
    ...(groupId ? { groupCode: orderGroupCode(groupId) } : {}),
  });
}

async function updateOrder(request: Request, env: Env, orderId: string): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  await assertOrderRateLimit(env.ORDER_RATE_LIMITER, uid);
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
  // الطلبات القديمة (قبل رسوم الخدمة) بتفضل من غير رسوم حتى بعد التعديل.
  const serviceFee = typeof order.serviceFee === "number" ? serviceFeeFor(subtotal - discount) : 0;
  const referralDiscountMinor = Number(order.referralDiscountMinor ?? 0);
  if (Math.round(subtotal * 100) < referralDiscountMinor) {
    throw new HttpError(409, "قيمة الأصناف بعد التعديل أقل من خصم النقاط المحجوز.");
  }
  const total = money(subtotal + deliveryFee - discount + serviceFee - referralDiscountMinor / 100);
  if (total <= 0 || total > 100000) throw new HttpError(409, "إجمالي الطلب بعد التعديل غير صالح.");
  const expectedTotal = Number(input.expectedTotal);
  if (!Number.isFinite(expectedTotal) || Math.abs(expectedTotal - total) >= 0.01) {
    throw new HttpError(409, "إجمالي الطلب اتغير. راجع الأصناف والخصم قبل التعديل.");
  }

  const updatedOrder = sanitizePublicOrder({
    ...order,
    items,
    subtotal,
    ...(typeof order.serviceFee === "number" ? { serviceFee } : {}),
    total,
    notes,
    customerName,
  });
  delete updatedOrder.unavailableItems;
  // An approval applies to the previous cart and must be renewed after editing.
  delete updatedOrder.verifiedTotal;
  delete updatedOrder.verifiedAt;
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
      updateTransforms: [{ fieldPath: "editedAt", setToServerValue: "REQUEST_TIME" }],
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
  if ([400, 409, 412].includes(committed.status)) {
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

/** رابط رسالة صوتية مرفوعة لمجلد الطلبات الخاصة على Cloudinary. */
export function isCloudinaryVoiceUrl(value: unknown): boolean {
  if (typeof value !== "string" || value.length > 450) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" &&
      url.hostname === "res.cloudinary.com" &&
      url.pathname.includes("/video/upload/") &&
      url.pathname.includes("/special_requests/");
  } catch {
    return false;
  }
}

/** public_id للأصل من رابط Cloudinary (من غير v123 والامتداد). */
export function cloudinaryPublicIdFromUrl(value: string): string {
  const segments = new URL(value).pathname.split("/").filter(Boolean);
  const uploadIndex = segments.indexOf("upload");
  if (uploadIndex < 0) return "";
  const assetSegments = segments.slice(uploadIndex + 1);
  if (assetSegments[0] && /^v\d+$/.test(assetSegments[0])) assetSegments.shift();
  const last = assetSegments.pop() ?? "";
  return [...assetSegments, last.replace(/\.[^.]+$/, "")].join("/");
}

export async function cloudinarySpecialRequestFolder(uid: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(uid));
  const hash = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")).join("");
  return `special_requests/${hash}`;
}

/** مجلد صور «صوّر طلبك» للعميل: جوه مجلد طلباته الخاصة، فحذف الحساب بيمسحه كمان. */
export async function quickRequestFolder(uid: string): Promise<string> {
  return `${await cloudinarySpecialRequestFolder(uid)}/quick`;
}

/** صورة «صوّر طلبك» صالحة ومن مجلد العميل نفسه. */
export function isOwnQuickImage(url: string, folder: string, cloudName?: string): boolean {
  if (!isCloudinaryImageUrl(url)) return false;
  if (cloudName && !new URL(url).pathname.startsWith(`/${cloudName}/image/upload/`)) return false;
  return cloudinaryPublicIdFromUrl(url).startsWith(folder + "/");
}

/** مسح صور «صوّر طلبك» من Cloudinary (بعد التسليم). بترجع الصور اللي ما اتمسحتش. */
/** فيديو m4a واحد من العميل، محفوظ في مسار غير قابل لحقن رابط طرف آخر. */
export function isOwnQuickVoice(url: string, folder: string, cloudName?: string): boolean {
  if (!isCloudinaryVoiceUrl(url)) return false;
  if (cloudName && !new URL(url).pathname.startsWith(`/${cloudName}/video/upload/`)) return false;
  return cloudinaryPublicIdFromUrl(url).startsWith(folder + "/");
}

/** حذف الملفات الصوتية من التخزين الفعلي، مش مجرد إزالة رابط Firestore. */
export async function destroyQuickVoice(env: Env, url: string, folder: string): Promise<boolean> {
  if (!url) return true;
  if (!env.CLOUDINARY_CLOUD_NAME || !env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET ||
      !isOwnQuickVoice(url, folder, env.CLOUDINARY_CLOUD_NAME)) return false;
  try {
    const timestamp = String(Math.floor(Date.now() / 1000));
    const params = { invalidate: "true", public_id: cloudinaryPublicIdFromUrl(url), timestamp };
    const signature = await cloudinarySignature(params, env.CLOUDINARY_API_SECRET);
    const form = new FormData();
    for (const [key, value] of Object.entries(params)) form.append(key, value);
    form.append("api_key", env.CLOUDINARY_API_KEY);
    form.append("signature", signature);
    const deleted = await fetch(`https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/video/destroy`,
      { method: "POST", body: form });
    const result = deleted.ok ? await deleted.json() as { result?: string } : {};
    return ["ok", "not found"].includes(String(result.result ?? ""));
  } catch { return false; }
}

export async function destroyQuickImages(env: Env, urls: string[], folder: string): Promise<string[]> {
  const failed: string[] = [];
  if (!urls.length) return failed;
  if (!env.CLOUDINARY_CLOUD_NAME || !env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET) return urls;
  for (const url of urls) {
    const publicId = cloudinaryPublicIdFromUrl(url);
    if (!isOwnQuickImage(url, folder, env.CLOUDINARY_CLOUD_NAME) || !publicId) {
      failed.push(url);
      continue;
    }
    try {
      const timestamp = String(Math.floor(Date.now() / 1000));
      const signature = await cloudinarySignature(
        { invalidate: "true", public_id: publicId, timestamp },
        env.CLOUDINARY_API_SECRET,
      );
      const form = new FormData();
      form.append("public_id", publicId);
      form.append("timestamp", timestamp);
      form.append("invalidate", "true");
      form.append("api_key", env.CLOUDINARY_API_KEY);
      form.append("signature", signature);
      const deleted = await fetch(
        `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/image/destroy`,
        { method: "POST", body: form },
      );
      const result = deleted.ok ? await deleted.json() as { result?: string } : {};
      if (!["ok", "not found"].includes(String(result.result ?? ""))) failed.push(url);
    } catch {
      failed.push(url);
    }
  }
  return failed;
}

export async function deleteCloudinarySpecialRequestAssets(env: Env, uid: string): Promise<void> {
  if (!env.CLOUDINARY_CLOUD_NAME || !env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET) {
    throw new HttpError(503, "تعذر تنظيف صور الطلبات الخاصة من خدمة الصور.");
  }
  const prefix = await cloudinarySpecialRequestFolder(uid);
  // الصور (image) والرسائل الصوتية (video على Cloudinary).
  for (const resourceType of ["image", "video"]) {
    await deleteCloudinaryPrefix(env, resourceType, prefix);
  }
}

async function deleteCloudinaryPrefix(env: Env, resourceType: string, prefix: string): Promise<void> {
  let nextCursor = "";
  for (let page = 0; page < 10; page++) {
    const url = new URL(
      `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/resources/${resourceType}/upload`,
    );
    const params = new URLSearchParams({ prefix, invalidate: "true" });
    if (nextCursor) params.set("next_cursor", nextCursor);
    const deleted = await fetch(url, {
      method: "DELETE",
      headers: {
        Authorization: `Basic ${btoa(`${env.CLOUDINARY_API_KEY}:${env.CLOUDINARY_API_SECRET}`)}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
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

/** رسالة صوتية من التطبيق: m4a (حاوية MP4 = ftyp) أو AAC خام (ADTS). */
export function detectAudioContent(bytes: Uint8Array): { format: string; mime: string } | null {
  if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(4, 8)) === "ftyp") {
    return { format: "m4a", mime: "audio/mp4" };
  }
  if (bytes.length >= 7 && bytes[0] === 0xff && (bytes[1] & 0xf6) === 0xf0) {
    return { format: "aac", mime: "audio/aac" };
  }
  return null;
}

export const MAX_VOICE_UPLOAD_BYTES = 1024 * 1024;

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
  if (!["stores", "products", "banners", "special_requests", "quick_receipts", "quick_requests", "quick_voices"].includes(folder)) {
    throw new HttpError(400, "مجلد الصور غير مسموح.");
  }
  if (storeId.length > 100 || (storeId && !/^[A-Za-z0-9_-]+$/.test(storeId))) {
    throw new HttpError(400, "معرّف المحل غير صالح.");
  }

  // «صوّر طلبك»: أي عميل مسجّل يرفع صور ورقة طلباته في مجلده هو بس،
  // من غير أي قراءة من Firestore. الصور بتتربط بالطلب عند إنشائه.
  if (folder === "quick_voices") {
    if (file.size > MAX_VOICE_UPLOAD_BYTES) throw new HttpError(413, "التسجيل الصوتي أكبر من 1MB.");
    const bytes = new Uint8Array(await file.arrayBuffer());
    const audio = detectAudioContent(bytes);
    if (!audio) throw new HttpError(415, "صيغة الصوت غير مدعومة. سجل بصيغة m4a.");
    return await signedCloudinaryImageUpload(env, bytes, audio,
      `${await quickRequestFolder(uid)}/voice`, "video");
  }
  if (folder === "quick_requests") {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const image = detectImageContent(bytes);
    if (!image) throw new HttpError(415, "صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WEBP.");
    return await signedCloudinaryImageUpload(env, bytes, image, await quickRequestFolder(uid));
  }

  const token = await googleAccessToken(env);
  // فواتير «طلباتك على السريع»: المندوب المعيّن بس، والطلب «جاري الشراء».
  if (folder === "quick_receipts") {
    const quickOrderId = String(input.get("orderId") ?? "");
    if (!/^[A-Za-z0-9_-]{16,200}$/.test(quickOrderId)) throw new HttpError(400, "معرّف الطلب غير صالح.");
    const quickDoc = await getDocument(env, `quick_orders/${encodeURIComponent(quickOrderId)}`, token);
    const quick = quickDoc ? decodeFields(quickDoc.fields ?? {}) : null;
    if (!quick || quick.courierId !== uid || quick.status !== "purchasing") {
      throw new HttpError(403, "مش مسموح لك ترفع فاتورة للطلب ده.");
    }
    const receiptBytes = new Uint8Array(await file.arrayBuffer());
    const receiptImage = detectImageContent(receiptBytes);
    if (!receiptImage) throw new HttpError(415, "صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WEBP.");
    return await signedCloudinaryImageUpload(env, receiptBytes, receiptImage, `quick_receipts/${quickOrderId}`);
  }
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
  const image = detectImageContent(bytes);
  // الرسائل الصوتية مسموحة في مجلد الطلبات الخاصة بس، وبحد 1MB.
  const voice = !image && folder === "special_requests" ? detectAudioContent(bytes) : null;
  const detected = image ?? voice;
  if (!detected) throw new HttpError(415, "صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WEBP.");
  if (voice && bytes.length > MAX_VOICE_UPLOAD_BYTES) {
    throw new HttpError(413, "الرسالة الصوتية أكبر من 1MB. سجّل رسالة أقصر.");
  }
  const resourceType = voice ? "video" : "image";
  const uploadFolder = folder === "special_requests"
    ? await cloudinarySpecialRequestFolder(uid)
    : folder === "banners" || isAdmin
      ? folder
      : `${folder}/${isApplicant ? (requestedStoreId || "applications/" + uid) : storeId}`;
  const timestamp = Math.floor(Date.now() / 1000);
  const publicId = crypto.randomUUID();
  const signedParams = {
    allowed_formats: voice ? "m4a,aac,mp4" : "jpg,jpeg,png,webp",
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
    `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/${resourceType}/upload`,
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
      !parsedUrl.pathname.startsWith(`/${env.CLOUDINARY_CLOUD_NAME}/${resourceType}/upload/`)) {
    throw new HttpError(502, "خدمة الصور لم ترجع رابطًا آمنًا.");
  }
  return response({ url: secureUrl });
}

async function cleanupConfirmedOrderAttachments(
  request: Request,
  env: Env,
  orderId: string,
): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  const token = await googleAccessToken(env);
  const path = `orders/${encodeURIComponent(orderId)}`;
  const doc = await getDocument(env, path, token);
  if (!doc) throw new HttpError(404, "الطلب غير موجود.");
  const order = decodeFields(doc.fields ?? {});
  if (order.userId !== uid) throw new HttpError(403, "لا تملك صلاحية تنظيف مرفقات هذا الطلب.");
  if (!(order.customerConfirmedAt instanceof Date)) {
    throw new HttpError(409, "لا يمكن حذف المرفقات قبل تأكيد العميل استلام الطلب.");
  }
  return cleanupOrderAttachmentsFor(env, token, doc, uid, orderId);
}

/** الطلب فيه مرفقات (صورة/صوت) لسه ما اتمسحتش. */
export function hasPendingAttachments(order: JsonMap): boolean {
  const special = order.specialRequest;
  if (!special || typeof special !== "object") return false;
  const s = special as JsonMap;
  if (s.cleanupStatus === "deleted") return false;
  return Boolean(s.imageUrl) || Boolean(s.voiceUrl) || Boolean(s.voiceBase64);
}

/** مسح مرفقات الطلب (صورة Cloudinary + الصوت) بعد التسليم. [ownerUid] = عميل الطلب. */
async function cleanupOrderAttachmentsFor(
  env: Env,
  token: string,
  doc: FirestoreDoc,
  ownerUid: string,
  orderId: string,
): Promise<Response> {
  const uid = ownerUid;
  const order = decodeFields(doc.fields ?? {});
  const special = order.specialRequest && typeof order.specialRequest === "object"
    ? Object.assign({}, order.specialRequest as JsonMap)
    : null;
  if (!special) return response({ cleaned: true, alreadyClean: true });
  if (special.cleanupStatus === "deleted") return response({ cleaned: true, alreadyClean: true });

  const currentDocument = doc.updateTime
    ? { updateTime: doc.updateTime }
    : { exists: true };
  const markFailed = async () => {
    await commitFirestoreWrites(env, token, [{
      update: {
        name: doc.name,
        fields: encodeFields({ specialRequest: { cleanupStatus: "failed" } }),
      },
      updateMask: { fieldPaths: ["specialRequest.cleanupStatus"] },
      currentDocument,
    }]);
  };
  const assets: Array<{ url: string; resourceType: string }> = [];
  const imageUrl = String(special.imageUrl ?? "");
  const voiceUrl = String(special.voiceUrl ?? "");
  if (imageUrl) assets.push({ url: imageUrl, resourceType: "image" });
  if (voiceUrl) assets.push({ url: voiceUrl, resourceType: "video" });
  const expectedPrefix = assets.length ? await cloudinarySpecialRequestFolder(uid) : "";
  for (const asset of assets) {
    const validUrl = asset.resourceType === "image"
      ? isCloudinaryImageUrl(asset.url)
      : isCloudinaryVoiceUrl(asset.url);
    if (!validUrl || !env.CLOUDINARY_CLOUD_NAME ||
        !env.CLOUDINARY_API_KEY || !env.CLOUDINARY_API_SECRET) {
      await markFailed();
      throw new HttpError(503, "تعذر التحقق من المرفق أو إعدادات حذفه. يمكن إعادة المحاولة.");
    }
    const publicId = cloudinaryPublicIdFromUrl(asset.url);
    if (!publicId) throw new HttpError(400, "مسار المرفق غير صالح.");
    if (!publicId.startsWith(expectedPrefix + "/")) {
      throw new HttpError(403, "المرفق لا يخص هذا العميل.");
    }
    const timestamp = String(Math.floor(Date.now() / 1000));
    const signature = await cloudinarySignature(
      { invalidate: "true", public_id: publicId, timestamp },
      env.CLOUDINARY_API_SECRET,
    );
    const form = new FormData();
    form.append("public_id", publicId);
    form.append("timestamp", timestamp);
    form.append("invalidate", "true");
    form.append("api_key", env.CLOUDINARY_API_KEY);
    form.append("signature", signature);
    const deleted = await fetch(
      `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/${asset.resourceType}/destroy`,
      { method: "POST", body: form },
    );
    if (!deleted.ok) {
      await markFailed();
      throw new HttpError(503, "تعذر حذف المرفق من التخزين. أعد المحاولة.");
    }
    const result = await deleted.json() as { result?: string };
    if (!["ok", "not found"].includes(String(result.result ?? ""))) {
      await markFailed();
      throw new HttpError(503, "لم تؤكد خدمة الصور حذف المرفق. أعد المحاولة.");
    }
  }

  delete special.imageUrl;
  delete special.voiceUrl;
  delete special.voiceBase64;
  special.cleanupStatus = "deleted";
  special.cleanedAt = new Date();
  await commitFirestoreWrites(env, token, [{
    update: { name: doc.name, fields: encodeFields({ specialRequest: special }) },
    updateMask: { fieldPaths: ["specialRequest"] },
    currentDocument,
  }]);
  return response({ cleaned: true, orderId });
}

export default {
  async scheduled(_controller: ScheduledController, env: Env, _ctx: ExecutionContext): Promise<void> {
    if (!hasValidIdentitySecret(env.REFERRAL_IDENTITY_HMAC_KEY)) return;
    const token = await googleAccessToken(env);
    // Only the HMAC document IDs are ever touched. No user email, raw Google
    // subject or Firebase UID is persisted by this retention job.
    const deletedCount = await pruneExpiredDeletedReferralIdentities(
      env.FIREBASE_PROJECT_ID, token, fetch,
    );
    const expiredDevices = await pruneExpiredDeletedReferralIdentities(
      env.FIREBASE_PROJECT_ID, token, fetch, new Date(), 10, REFERRAL_DEVICE_COLLECTION,
    );
    if (deletedCount || expiredDevices) {
      console.info("Expired referral protection markers deleted", deletedCount + expiredDevices);
    }
  },
  async fetch(request: Request, env: Env, ctx?: ExecutionContext): Promise<Response> {
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
    if (request.method === "POST" && url.pathname === "/v1/referrals/campaign") {
      if (env.REFERRAL_REGISTRATION_ENABLED !== "true") {
        return response({ error: "حملة الإحالات غير متاحة حاليًا." }, 404, headers);
      }
      try {
        return response(await referralCampaign(request, env, ctx), 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(503, "تعذر فتح حملة الإحالات.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/referrals/settings") {
      if (env.REFERRAL_REGISTRATION_ENABLED !== "true") {
        return response({ error: "حملة الإحالات غير متاحة حاليًا." }, 404, headers);
      }
      try {
        return response(await referralSettings(request, env), 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(503, "تعذر تحديث إعدادات الإحالات.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/referrals/points/quote") {
      if (env.REFERRAL_REGISTRATION_ENABLED !== "true" ||
          env.REFERRAL_DELIVERY_ENABLED !== "true") {
        return response({ error: "خصم نقاط الإحالة غير متاح حاليًا." }, 404, headers);
      }
      try {
        return response(await referralPointsQuote(request, env), 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(503, "تعذر حساب خصم نقاط الإحالة.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/referrals/redemption") {
      try {
        return response(await referralRedemption(request, env), 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(503, "تعذر تحديث تسوية خصم النقاط.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/referrals/commissions") {
      if (env.REFERRAL_DELIVERY_ENABLED !== "true") {
        return response({ error: "تسوية خصم الإحالة غير متاحة حاليًا." }, 404, headers);
      }
      try {
        return response(await settleReferralCommission(request, env), 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(503, "تعذر تسجيل تسوية العمولة.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/referrals/payouts") {
      if (env.REFERRAL_DELIVERY_ENABLED !== "true") {
        return response({ error: "صرف مكافآت الإحالات غير متاح حاليًا." }, 404, headers);
      }
      try {
        return response(await referralPayout(request, env), 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : error instanceof ReferralPayoutConflict
          ? new HttpError(409, "مفيش رصيد متاح أو فيه طلب صرف جاري بالفعل. حدّث الصفحة.")
          : new HttpError(503, "تعذر تحديث طلب صرف المكافأة.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/referrals/device-binding") {
      if (env.REFERRAL_REGISTRATION_ENABLED !== "true") {
        return response({ error: "الإحالات غير متاحة حاليًا." }, 404, headers);
      }
      try {
        await assertReferralDeviceAppCheck(request, env);
        const uid = await verifyCustomer(request, env);
        const body = await request.json().catch(() => null) as { deviceId?: unknown } | null;
        const token = await googleAccessToken(env);
        const eligible = await bindReferralDevice(env, token, uid, body?.deviceId);
        return response({ eligible }, 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(503, "تعذر التحقق من الجهاز حاليًا.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/referrals/registration") {
      if (env.REFERRAL_REGISTRATION_ENABLED !== "true") {
        return response({ error: "التسجيل بكود الإحالة غير متاح حاليًا." }, 404, headers);
      }
      try {
        await assertReferralDeviceAppCheck(request, env);
        const uid = await verifyCustomer(request, env, true);
        const limit = await env.ORDER_RATE_LIMITER?.limit({ key: "referral-registration:" + uid });
        if (limit?.success === false) throw new HttpError(429, "حاول مرة أخرى بعد قليل.");
        const body = await request.json().catch(() => null) as { code?: unknown; deviceId?: unknown } | null;
        if (typeof body?.code !== "string" || body.code.length > 32) {
          throw new HttpError(400, "اكتب كود إحالة صحيح.");
        }
        const token = await googleAccessToken(env);
        await rejectPreviouslyDeletedReferralIdentity(env, uid, token);
        const deviceEligible = await bindReferralDevice(env, token, uid, body?.deviceId);
        if (!deviceEligible) throw new HttpError(403, "نفس الموبايل لا يستحق أكثر من إحالة تسجيل جديدة.");
        const accepted = await registerReferral({
          projectId: env.FIREBASE_PROJECT_ID,
          token,
          uid,
          code: body.code,
          createdAtMs: firebaseUserStateCache.get(uid)?.createdAtMs ?? 0,
          now: Date.now(),
        }, fetch);
        if (!accepted) throw new HttpError(409, "كود الإحالة غير متاح لهذا التسجيل.");
        return response({ accepted: true }, 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(503, "تعذر حفظ كود الإحالة حاليًا.");
        return response({ error: e.message }, e.status, headers);
      }
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
    const cleanupPrefix = "/v1/orders/";
    const cleanupSuffix = "/cleanup-attachments";
    const cleanupOrderId = request.method === "POST" &&
      url.pathname.startsWith(cleanupPrefix) && url.pathname.endsWith(cleanupSuffix)
        ? url.pathname.slice(cleanupPrefix.length, -cleanupSuffix.length)
        : "";
    const isCleanup = cleanupOrderId.length > 0 && !cleanupOrderId.includes("/");
    if (request.method === "POST" && url.pathname === "/v1/order-events") {
      try {
        const result = await notifyOrderEvent(request, env, ctx);
        return response(result, 200, headers);
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(500, "تعذر إرسال إشعار الطلب.");
        return response({ error: e.message }, e.status, headers);
      }
    }
    if (request.method === "POST" && url.pathname === "/v1/notify-admins") {
      try {
        const result = await notifyAdmins(request, env);
        const mergedHeaders = new Headers(result.headers);
        headers.forEach((value, key) => mergedHeaders.set(key, value));
        return new Response(await result.text(), { status: result.status, headers: mergedHeaders });
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(500, "حدث خطأ غير متوقع.");
        return response(e.code ? { error: e.message, code: e.code } : { error: e.message }, e.status, headers);
      }
    }
    if (url.pathname === "/v1/quick" || url.pathname.startsWith("/v1/quick/")) {
      try {
        const result = await routeQuick(request, env, url.pathname, ctx) ?? response({ error: "Not found." }, 404);
        const mergedHeaders = new Headers(result.headers);
        headers.forEach((value, key) => mergedHeaders.set(key, value));
        return new Response(await result.text(), { status: result.status, headers: mergedHeaders });
      } catch (error) {
        if (!(error instanceof HttpError)) {
          console.error("quick_order_unexpected_exception", error instanceof Error ? error.name : typeof error);
        }
        const e = error instanceof HttpError ? error : new HttpError(500, "حدث خطأ غير متوقع.");
        const code = e.code ?? (e.status === 409 ? "rejected" : undefined);
        return response(code ? { error: e.message, code } : { error: e.message }, e.status, headers);
      }
    }
    const pinMatch = url.pathname.match(/^\/v1\/orders\/([^/]+)\/(delivery-pin|deliver)$/);
    if (pinMatch) {
      try {
        const id = decodeURIComponent(pinMatch[1]);
        const result = pinMatch[2] === "delivery-pin" && request.method === "GET"
          ? await getDeliveryPin(request, env, id)
          : pinMatch[2] === "deliver" && request.method === "POST"
            ? await deliverWithPin(request, env, id, ctx)
            : response({ error: "Not found." }, 404);
        const mergedHeaders = new Headers(result.headers);
        headers.forEach((value, key) => mergedHeaders.set(key, value));
        return new Response(await result.text(), { status: result.status, headers: mergedHeaders });
      } catch (error) {
        const e = error instanceof HttpError ? error : new HttpError(500, "حدث خطأ غير متوقع.");
        return response(e.code ? { error: e.message, code: e.code } : { error: e.message }, e.status, headers);
      }
    }
    const isCreate = request.method === "POST" && url.pathname === "/v1/orders";
    const isEdit = request.method === "PATCH" && rawEditId.length > 0 && !rawEditId.includes("/");
    if (!isCreate && !isEdit && !isCleanup) return response({ error: "Not found." }, 404, headers);
    try {
      const result = isCreate
        ? await createOrder(request, env)
        : isCleanup
          ? await cleanupConfirmedOrderAttachments(request, env, decodeURIComponent(cleanupOrderId))
          : await updateOrder(request, env, decodeURIComponent(rawEditId));
      const mergedHeaders = new Headers(result.headers);
      headers.forEach((value, key) => mergedHeaders.set(key, value));
      return new Response(await result.text(), {
        status: result.status,
        headers: mergedHeaders,
      });
    } catch (error) {
      if (!(error instanceof HttpError)) {
        // Do not log request bodies, tokens, user data, or raw error messages.
        const errorType = error instanceof Error ? error.name : typeof error;
        const stackLocations = error instanceof Error
          ? (error.stack ?? "").split("\n").slice(1, 5)
              .map((frame) => frame.match(/(?:index|worker|bundle)\.(?:ts|js):\d+:\d+/)?.[0] ?? "unknown")
          : [];
        console.error("order_gateway_unexpected_exception", {
          route: isCreate ? "create" : isCleanup ? "cleanup" : "edit",
          errorType,
          stackLocations,
        });
      }
      const e = error instanceof HttpError ? error : new HttpError(500, "حدث خطأ غير متوقع أثناء إنشاء الطلب.");
      // Business rejections (409) always carry a code so the app never guesses from the text.
      const code = e.code ?? (e.status === 409 ? "rejected" : undefined);
      return response(code ? { error: e.message, code } : { error: e.message }, e.status, headers);
    }
  },
};

// ───────────── رمز التسليم ─────────────

const PIN_DISABLED = "خدمة رمز التسليم غير مفعّلة حاليًا. تواصل مع الدعم.";

/** سبب منع المندوب من تأكيد التسليم، أو null لو مسموح. (نفس شروط بلاغ التسليم القديم.) */
export function courierDeliveryBlocker(order: JsonMap, uid: string): string | null {
  if (order.courierId !== uid) return "الطلب غير معيّن لحسابك.";
  if (order.status !== "on_the_way") return "لازم يكون الطلب «في الطريق».";
  if (order.ready !== true) return "المحل لم يؤكد جاهزية الطلب بعد.";
  if (!(order.courierArrivedAt instanceof Date)) return "سجّل وصولك إلى عنوان العميل أولًا.";
  if (typeof order.activeDeliveryIssueId === "string" && order.activeDeliveryIssueId) {
    return "يوجد بلاغ توصيل مفتوح لهذا الطلب.";
  }
  if (order.customerConfirmedAt instanceof Date) return "تم تأكيد تسليم هذا الطلب بالفعل.";
  if (order.deliveryMode !== "store" && order.deliveryMode !== "external") {
    return "نوع المندوب غير محدد على الطلب.";
  }
  return null;
}

/** الحقول اللي بتتكتب على الطلب لما الرمز يطلع صح (نفس اللي كان بيكتبه تأكيد العميل). */
export function pinDeliveryUpdate(order: JsonMap, uid: string, now: Date): JsonMap {
  const base: JsonMap = {
    customerDeliveryReportedAt: now,
    customerDeliveryReportedBy: uid,
    customerConfirmedAt: now,
    deliveryPinVerifiedAt: now,
  };
  if (order.deliveryMode !== "store") return base;
  const fee = typeof order.finalDeliveryFee === "number" ? order.finalDeliveryFee : Number(order.deliveryFee);
  const total = typeof order.verifiedTotal === "number" ? order.verifiedTotal : Number(order.total);
  return {
    ...base,
    status: "delivered",
    deliveredBy: uid,
    deliveredAt: now,
    collectedAmount: total,
    courierEarning: fee,
  };
}

function docName(env: Env, path: string): string {
  return `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`;
}

async function commitOrConflict(env: Env, token: string, writes: unknown[]): Promise<void> {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ writes }),
    },
  );
  if ([400, 409, 412].includes(res.status)) {
    throw new HttpError(409, "حالة الطلب اتغيرت. حدّث الصفحة وحاول تاني.", "conflict");
  }
  if (!res.ok) throw new HttpError(503, "تعذر الحفظ؛ حاول مرة أخرى.");
}

/** العميل بيجيب رمز تسليم طلبه وهو «في الطريق». */
async function getDeliveryPin(request: Request, env: Env, orderId: string): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  if (!env.DELIVERY_PIN_SECRET) throw new HttpError(503, PIN_DISABLED, "pin_disabled");
  const token = await googleAccessToken(env);
  const doc = await getDocument(env, `orders/${encodeURIComponent(orderId)}`, token);
  if (!doc) throw new HttpError(404, "الطلب غير موجود.");
  const order = decodeFields(doc.fields ?? {});
  if (order.userId !== uid) throw new HttpError(403, "لا تملك صلاحية على هذا الطلب.");
  // الرمز بيتحسب من رقم الطلب بس (ثابت حتى لو العميل عدّل الطلب)، فبيظهر من أول الطلب
  // لحد التسليم أو الإلغاء.
  if (!["new", "preparing", "on_the_way"].includes(String(order.status)) ||
      order.customerConfirmedAt instanceof Date) {
    throw new HttpError(409, "الرمز بيظهر طول ما الطلب لسه شغال، وبيقفل بعد التسليم أو الإلغاء.", "pin_not_available");
  }
  return response({ pin: await deriveDeliveryPin(orderId, env.DELIVERY_PIN_SECRET) });
}

/** المندوب يأكد التسليم بالرمز. 5 محاولات غلط = الرمز يتقفل والإدارة تقرر. */
function referralPointsBalanceWrite(env: Env, uid: string, points: number, updateTime?: string) {
  return {
    transform: {
      document: firestoreDocumentName(env, `referral_balances/${uid}`),
      fieldTransforms: [{ fieldPath: "points", increment: { integerValue: String(points) } }],
    },
    ...(updateTime ? { currentDocument: { updateTime } } : {}),
  };
}

async function refundReferralOrder(
  env: Env, token: string, orderId: string, orderDoc: FirestoreDoc,
) {
  const order = decodeFields(orderDoc.fields ?? {});
  if (order.status !== "cancelled" || !orderDoc.updateTime ||
      !order.referralDiscountMinor || order.userDeleted === true) return;
  const doc = await getDocument(env, `referral_redemptions/${orderId}`, token);
  if (!doc?.updateTime) return;
  const data = decodeFields(doc.fields ?? {});
  if (data.status !== "reserved") return;
  if (typeof order.userId !== "string" || data.discountMinor !== order.referralDiscountMinor ||
      typeof data.points !== "number" || !Number.isSafeInteger(data.points) || data.points < 1) {
    throw new Error("invalid points reservation");
  }
  await commitOrConflict(env, token, [
    { verify: orderDoc.name, currentDocument: { updateTime: orderDoc.updateTime } },
    referralPointsBalanceWrite(env, order.userId, data.points),
    {
      update: { name: doc.name, fields: encodeFields({ status: "refunded" }) },
      updateMask: { fieldPaths: ["status"] },
      currentDocument: { updateTime: doc.updateTime },
    },
  ]);
}

async function referralRedemption(request: Request, env: Env): Promise<JsonMap> {
  const uid = await verifyCustomer(request, env);
  const limit = await env.ORDER_RATE_LIMITER?.limit({ key: "referral-redemption:" + uid });
  if (limit?.success === false) throw new HttpError(429, "حاول مرة أخرى بعد قليل.");
  const { orderId, action, reference } = await readJsonBody(request);
  if (typeof orderId !== "string" || !/^[A-Za-z0-9_-]{1,180}$/.test(orderId) ||
      !["refund", "claim", "paid"].includes(String(action))) {
    throw new HttpError(400, "راجع رقم الطلب والإجراء.");
  }
  const token = await googleAccessToken(env);
  const orderDoc = await getDocument(env, `orders/${orderId}`, token);
  if (!orderDoc?.updateTime) throw new HttpError(404, "الطلب غير موجود.");
  const order = decodeFields(orderDoc.fields ?? {});
  if (action === "refund") {
    if (order.userId !== uid && !await getDocument(env, `admins/${uid}`, token)) {
      throw new HttpError(403, "الطلب لا يخص حسابك.");
    }
    if (order.status !== "cancelled") throw new HttpError(409, "الطلب غير ملغي.");
    await refundReferralOrder(env, token, orderId, orderDoc);
    return { processed: true };
  }
  if (!await getDocument(env, `admins/${uid}`, token)) {
    throw new HttpError(403, "تسوية خصم النقاط من صلاحيات الإدارة.");
  }
  if (order.status !== "delivered" || !order.referralDiscountMinor) {
    throw new HttpError(409, "التسوية متاحة لطلب بنقاط تم تسليمه.");
  }
  const doc = await getDocument(env, `referral_redemptions/${orderId}`, token);
  if (!doc?.updateTime) throw new HttpError(404, "سجل الخصم غير موجود.");
  const data = decodeFields(doc.fields ?? {});
  if (data.storeId !== order.storeId || data.discountMinor !== order.referralDiscountMinor) {
    throw new HttpError(409, "بيانات التسوية غير متطابقة.");
  }
  const result = { storeId: data.storeId, discountMinor: data.discountMinor };
  if (action === "paid" && (typeof reference !== "string" ||
      reference.trim().length < 5 || reference.length > 120)) {
    throw new HttpError(400, "اكتب مرجع التحويل اليدوي.");
  }
  if (data.status === "paid") {
    if (action === "paid" && data.processingBy === uid && data.reference === String(reference).trim()) {
      return { ...result, status: "paid" };
    }
    throw new HttpError(409, "التسوية مسددة بالفعل.");
  }
  if (data.status === "processing" && data.processingBy !== uid) {
    throw new HttpError(409, "مسؤول آخر بيتابع التسوية.");
  }
  if (action === "claim" && data.status === "processing") return { ...result, status: "processing" };
  if ((action === "claim" && data.status !== "reserved") ||
      (action === "paid" && data.status !== "processing")) {
    throw new HttpError(409, "حالة التسوية لا تسمح بالإجراء.");
  }

  const changes = action === "claim"
    ? { status: "processing", processingBy: uid }
    : { status: "paid", reference: String(reference).trim(), paidAt: new Date() };
  await commitOrConflict(env, token, [
    { verify: orderDoc.name, currentDocument: { updateTime: orderDoc.updateTime } },
    {
      update: { name: doc.name, fields: encodeFields(changes) },
      updateMask: { fieldPaths: Object.keys(changes) },
      currentDocument: { updateTime: doc.updateTime },
    },
  ]);
  return { ...result, status: changes.status };
}

async function referralPointsQuote(request: Request, env: Env): Promise<JsonMap> {
  const uid = await verifyCustomer(request, env);
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw new HttpError(400, "الحساب غير صالح.");
  const limit = await env.ORDER_RATE_LIMITER?.limit({ key: "referral-points:" + uid });
  if (limit?.success === false) throw new HttpError(429, "حاول مرة أخرى بعد قليل.");
  const { itemsSubtotalMinor } = await readJsonBody(request);
  if (typeof itemsSubtotalMinor !== "number" || !Number.isSafeInteger(itemsSubtotalMinor) ||
      itemsSubtotalMinor < 0 || itemsSubtotalMinor > 10_000_000) {
    throw new HttpError(400, "راجع قيمة الأصناف.");
  }
  const token = await googleAccessToken(env);
  const [config, balance] = await Promise.all([
    getDocument(env, "app_info/referral_config", token),
    getDocument(env, `referral_balances/${uid}`, token),
  ]);
  const policy = config ? parseReferralSettings(decodeFields(config.fields ?? {})).redemption : undefined;
  return quoteReferralPoints(
    policy, balance ? decodeFields(balance.fields ?? {}).points : undefined, itemsSubtotalMinor,
  );
}

async function settleReferralCommission(request: Request, env: Env): Promise<JsonMap> {
  const adminUid = await verifyCustomer(request, env);
  const safeId = /^[A-Za-z0-9_-]{1,128}$/;
  if (!safeId.test(adminUid)) throw new HttpError(400, "الحساب غير صالح.");
  const limit = await env.ORDER_RATE_LIMITER?.limit({ key: "referral-commission:" + adminUid });
  if (limit?.success === false) throw new HttpError(429, "حاول مرة أخرى بعد قليل.");
  const token = await googleAccessToken(env);
  if (!await getDocument(env, `admins/${adminUid}`, token)) {
    throw new HttpError(403, "تسجيل تسوية العمولة من صلاحيات الإدارة.");
  }

  const { ownerUid, storeId, reference, dueMinor } = await readJsonBody(request);
  if (typeof ownerUid !== "string" || !safeId.test(ownerUid) ||
      typeof storeId !== "string" || !safeId.test(storeId) ||
      typeof reference !== "string" || !/^[A-Za-z0-9_-]{4,64}$/.test(reference) ||
      typeof dueMinor !== "number" || !Number.isSafeInteger(dueMinor) ||
      dueMinor < 1 || dueMinor > 10_000_000) {
    throw new HttpError(400, "راجع بيانات المحل ومرجع العمولة والمبلغ بالقروش.");
  }

  const settlementPath = `referral_commission_settlements/${storeId.length}-${storeId}-${reference}`;
  const previous = await getDocument(env, settlementPath, token);
  if (previous) {
    const saved = decodeFields(previous.fields ?? {});
    if (saved.ownerUid !== ownerUid || saved.dueMinor !== dueMinor) {
      throw new HttpError(409, "مرجع العمولة اتسجل بالفعل ببيانات مختلفة.");
    }
    return { dueMinor, discountMinor: saved.discountMinor, payableMinor: saved.payableMinor };
  }

  const balancePath = `referral_balances/${ownerUid}`;
  const [mapping, balance] = await Promise.all([
    getDocument(env, `storeOwners/${ownerUid}`, token),
    getDocument(env, balancePath, token),
  ]);
  const owner = mapping ? decodeFields(mapping.fields ?? {}) : null;
  if (!mapping?.updateTime || owner?.storeId !== storeId || owner.active === false) {
    throw new HttpError(409, "الحساب مش صاحب المحل المحدد.");
  }
  if (balance && !balance.updateTime) throw new HttpError(503, "تعذر تأكيد إصدار الرصيد.");
  const amounts = commissionAmounts(
    dueMinor, balance ? decodeFields(balance.fields ?? {}).commissionDiscountMinor : undefined,
  );
  await commitOrConflict(env, token, [
    {
      verify: mapping.name,
      currentDocument: { updateTime: mapping.updateTime },
    },
    {
      update: {
        name: firestoreDocumentName(env, settlementPath),
        fields: encodeFields({ ...amounts, ownerUid, storeId, reference, adminUid }),
      },
      updateTransforms: [{ fieldPath: "settledAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: { exists: false },
    },
    ...(amounts.discountMinor > 0 ? [{
      transform: {
        document: firestoreDocumentName(env, balancePath),
        fieldTransforms: [{
          fieldPath: "commissionDiscountMinor",
          increment: { integerValue: String(-amounts.discountMinor) },
        }],
      },
      currentDocument: { updateTime: balance!.updateTime },
    }] : []),
  ]);
  return amounts;
}

async function referralPayout(request: Request, env: Env): Promise<JsonMap> {
  const uid = await verifyCustomer(request, env);
  if (!/^[A-Za-z0-9_-]{1,96}$/.test(uid)) throw new HttpError(400, "الحساب غير صالح.");
  const limit = await env.ORDER_RATE_LIMITER?.limit({ key: "referral-payout:" + uid });
  if (limit?.success === false) throw new HttpError(429, "حاول مرة أخرى بعد قليل.");
  const { action, requestId, payoutId, reference } = await readJsonBody(request);
  const token = await googleAccessToken(env);
  if (action === "request") {
    if (typeof requestId !== "string" || !/^[a-f0-9]{24}$/.test(requestId)) {
      throw new HttpError(400, "بيانات طلب الصرف غير صالحة.");
    }
    return updateReferralPayout(env.FIREBASE_PROJECT_ID, token, {
      kind: "request", uid, requestId,
    }, fetch);
  }
  if (!await getDocument(env, `admins/${uid}`, token)) throw new HttpError(403, "الإجراء من صلاحيات الإدارة.");
  if (action === "list") {
    const query = await fetch(`${firestoreDocumentsUrl(env)}:runQuery`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ structuredQuery: {
        from: [{ collectionId: "referral_payouts" }],
        where: { fieldFilter: {
          field: { fieldPath: "status" }, op: "IN",
          value: { arrayValue: { values: [{ stringValue: "pending" }, { stringValue: "processing" }] } },
        } },
        limit: 50,
      } }),
    });
    if (!query.ok) throw new HttpError(503, "تعذر تحميل طلبات الصرف.");
    const rows = await query.json() as Array<{ document?: FirestoreDoc }>;
    return { pending: rows.flatMap(({ document }) => document ? [{
      id: document.name.split("/").at(-1),
      ...decodeFields(document.fields ?? {}),
      canResolve: decodeFields(document.fields ?? {}).processingBy === uid,
    }] : []) };
  }
  if (typeof payoutId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(payoutId)) {
    throw new HttpError(400, "طلب الصرف غير صالح.");
  }
  if (action === "claim") {
    return updateReferralPayout(env.FIREBASE_PROJECT_ID, token, {
      kind: "claim", payoutId, adminUid: uid,
    }, fetch);
  }
  if ((action !== "paid" && action !== "rejected") ||
      typeof reference !== "string" || reference.trim().length < 5 || reference.length > 120) {
    throw new HttpError(400, "اكتب رقم مرجع التحويل أو سبب الرفض.");
  }
  return updateReferralPayout(env.FIREBASE_PROJECT_ID, token, {
    kind: action, payoutId, reference: reference.trim(), adminUid: uid,
  }, fetch);
}

async function referralSettings(request: Request, env: Env): Promise<JsonMap> {
  const uid = await verifyCustomer(request, env);
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw new HttpError(400, "الحساب غير صالح.");
  const limit = await env.ORDER_RATE_LIMITER?.limit({ key: "referral-settings:" + uid });
  if (limit?.success === false) throw new HttpError(429, "حاول مرة أخرى بعد قليل.");
  const token = await googleAccessToken(env);
  if (!await getDocument(env, `admins/${uid}`, token)) throw new HttpError(403, "الإعدادات من صلاحيات الإدارة.");
  const { settings } = await readJsonBody(request);
  const doc = await getDocument(env, "app_info/referral_config", token);
  const current = doc ? parseReferralSettings(decodeFields(doc.fields ?? {})) : null;
  if (settings === undefined) return { settings: current };
  let parsed;
  try {
    parsed = parseReferralSettings(settings);
  } catch {
    throw new HttpError(400, "راجع قيم المكافآت وحدودها.");
  }
  const version = current?.version ?? 0;
  if (parsed.version !== version + 1) throw new HttpError(409, "الإعدادات اتغيرت. حدّث الصفحة وحاول تاني.");
  if (doc && !doc.updateTime) throw new HttpError(503, "تعذر تأكيد إصدار إعدادات الإحالات.");
  const write = buildAdminReferralSettingsWrite(
    firestoreDocumentName(env, "").slice(0, -1), parsed, version, doc?.updateTime ?? null,
  );
  const commit = await fetch(`${firestoreDocumentsUrl(env)}:commit`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ writes: [write] }),
  });
  if (commit.status === 409 || commit.status === 412) {
    throw new HttpError(409, "الإعدادات اتغيرت. حدّث الصفحة وحاول تاني.");
  }
  if (!commit.ok) throw new HttpError(503, "تعذر حفظ إعدادات الإحالات.");
  return { settings: parsed };
}

async function referralCampaign(request: Request, env: Env, ctx?: ExecutionContext): Promise<JsonMap> {
  const uid = await verifyCustomer(request, env);
  const safeId = /^[A-Za-z0-9_-]{1,128}$/;
  if (!safeId.test(uid)) throw new HttpError(400, "الحساب غير صالح.");
  const limit = await env.ORDER_RATE_LIMITER?.limit({ key: "referral-campaign:" + uid });
  if (limit?.success === false) throw new HttpError(429, "حاول مرة أخرى بعد قليل.");
  const { channel, marketerUid } = await readJsonBody(request);
  if (channel !== "customer" && channel !== "store_owner" && channel !== "marketer") {
    throw new HttpError(400, "نوع كود الإحالة غير صالح.");
  }
  const token = await googleAccessToken(env);
  let codeOwnerUid = uid;
  let storeId: string | undefined;
  if (channel === "marketer") {
    if (typeof marketerUid !== "string" || !safeId.test(marketerUid)) {
      throw new HttpError(400, "اكتب معرّف حساب المسوّق.");
    }
    if (!await getDocument(env, `admins/${uid}`, token)) {
      throw new HttpError(403, "إصدار أكواد المسوقين من صلاحيات الإدارة.");
    }
    if (!await getDocument(env, `users/${marketerUid}`, token)) {
      throw new HttpError(404, "حساب المسوّق غير موجود.");
    }
    codeOwnerUid = marketerUid;
  } else if (channel === "store_owner") {
    const mapping = await getDocument(env, `storeOwners/${uid}`, token);
    const owner = mapping && decodeFields(mapping.fields ?? {});
    if (owner?.active === false || typeof owner?.storeId !== "string" || !safeId.test(owner.storeId)) {
      throw new HttpError(403, "الكود متاح لأصحاب المحلات المعتمدة.");
    }
    storeId = owner.storeId;
    const storeDoc = await getDocument(env, `stores/${storeId}`, token);
    const store = storeDoc && decodeFields(storeDoc.fields ?? {});
    if (store?.approved !== true || store.active !== true) {
      throw new HttpError(403, "الكود متاح بعد اعتماد المحل وتفعيله.");
    }
  }
  const code = await getOrIssueReferralCode(env.FIREBASE_PROJECT_ID, token, {
    uid: codeOwnerUid, issuerUid: uid, channel,
  }, fetch);
  if (channel === "marketer") return { code, rewardsEnabled: env.REFERRAL_DELIVERY_ENABLED === "true" };
  // An invited user or owner can recover from a missed or interrupted delivery callback.
  scheduleReferralDelivery(env, ctx, token, { userId: uid, storeId });
  const [balance, marketerCode] = await Promise.all([
    getDocument(env, `referral_balances/${uid}`, token),
    getDocument(env, `referral_marketer_codes/${uid}`, token),
  ]);
  return {
    code,
    balance: balance ? decodeFields(balance.fields ?? {}) : {},
    marketerCode: marketerCode ? decodeFields(marketerCode.fields ?? {}).code : null,
    rewardsEnabled: env.REFERRAL_DELIVERY_ENABLED === "true",
  };
}

function scheduleReferralDelivery(env: Env, ctx: ExecutionContext | undefined, token: string, order: JsonMap): void {
  if (env.REFERRAL_DELIVERY_ENABLED !== "true" || !ctx) return;
  const jobs = [];
  if (typeof order.userId === "string") {
    jobs.push(settleCustomerDelivery(env.FIREBASE_PROJECT_ID, token, order.userId, fetch));
  }
  if (typeof order.storeId === "string") {
    jobs.push(settleStoreDelivery(env.FIREBASE_PROJECT_ID, token, order.storeId, fetch));
  }
  ctx.waitUntil(Promise.allSettled(jobs).then((results) => {
    if (results.some((result) => result.status === "rejected")) {
      console.error("Referral settlement failed after delivery");
    }
  }));
}

async function deliverWithPin(request: Request, env: Env, orderId: string, ctx?: ExecutionContext): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  if (!env.DELIVERY_PIN_SECRET) throw new HttpError(503, PIN_DISABLED, "pin_disabled");
  let body: any;
  try {
    body = await request.json();
  } catch {
    throw new HttpError(400, "بيانات غير صالحة.");
  }
  if (!isDeliveryPin(body?.pin)) throw new HttpError(400, "اكتب رمز من 4 أرقام.", "pin_invalid");

  const token = await googleAccessToken(env);
  const orderPath = `orders/${encodeURIComponent(orderId)}`;
  const attemptsPath = `deliveryPinAttempts/${encodeURIComponent(orderId)}`;
  const [orderDoc, courierDoc, attemptsDoc] = await Promise.all([
    getDocument(env, orderPath, token),
    getDocument(env, `couriers/${encodeURIComponent(uid)}`, token),
    getDocument(env, attemptsPath, token),
  ]);
  if (!courierDoc) throw new HttpError(403, "حساب المندوب غير معتمد.");
  const courier = decodeFields(courierDoc.fields ?? {});
  if (courier.active !== undefined && courier.active !== true) {
    throw new HttpError(403, "حساب المندوب غير نشط. راجع الإدارة.");
  }
  if (!orderDoc) throw new HttpError(404, "الطلب غير موجود.");
  const order = decodeFields(orderDoc.fields ?? {});
  const blocker = courierDeliveryBlocker(order, uid);
  if (blocker) throw new HttpError(409, blocker, "not_deliverable");

  const prev = attemptsDoc ? decodeFields(attemptsDoc.fields ?? {}) : {};
  const attempts = Number.isSafeInteger(prev.attempts) ? Number(prev.attempts) : 0;
  if (prev.locked === true || attempts >= DELIVERY_PIN_MAX_ATTEMPTS) {
    throw new HttpError(423, "الرمز اتقفل بعد محاولات غلط كتير. الإدارة هتراجع الطلب.", "pin_locked");
  }
  const attemptsPrecondition = attemptsDoc?.updateTime
    ? { updateTime: attemptsDoc.updateTime }
    : { exists: false };
  const orderPrecondition = orderDoc.updateTime ? { updateTime: orderDoc.updateTime } : { exists: true };
  const expected = await deriveDeliveryPin(orderId, env.DELIVERY_PIN_SECRET);

  if (!equalPin(body.pin, expected)) {
    const next = attempts + 1;
    const locked = next >= DELIVERY_PIN_MAX_ATTEMPTS;
    const writes: unknown[] = [{
      update: { name: docName(env, attemptsPath), fields: encodeFields({ attempts: next, locked, orderId }) },
      updateTransforms: [{ fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: attemptsPrecondition,
    }];
    if (locked) {
      // علامة على الطلب عشان الإدارة تشوفه (الرمز نفسه مش بيتخزن).
      writes.push({
        // mask فاضي: مفيش حقل بيتمسح أو يتغيّر غير الطابع الزمني اللي بيتحط بالـtransform.
        update: { name: docName(env, orderPath), fields: {} },
        updateMask: { fieldPaths: [] },
        updateTransforms: [{ fieldPath: "deliveryPinLockedAt", setToServerValue: "REQUEST_TIME" }],
        currentDocument: orderPrecondition,
      });
    }
    await commitOrConflict(env, token, writes);
    if (locked) {
      throw new HttpError(423, "الرمز اتقفل بعد محاولات غلط كتير. الإدارة هتراجع الطلب.", "pin_locked");
    }
    const left = DELIVERY_PIN_MAX_ATTEMPTS - next;
    throw new HttpError(400, `الرمز غلط. فاضل ${left} محاولات.`, "pin_wrong");
  }

  const now = new Date();
  const update = pinDeliveryUpdate(order, uid, now);
  const stampFields = Object.keys(update).filter((k) => update[k] instanceof Date);
  const plain: JsonMap = {};
  for (const [k, v] of Object.entries(update)) if (!(v instanceof Date)) plain[k] = v;
  const writes: unknown[] = [{
    update: { name: docName(env, orderPath), fields: encodeFields(plain) },
    // الطوابع الزمنية بتتحط بالـtransform (وقت السيرفر)، فمش في الـmask.
    updateMask: { fieldPaths: Object.keys(plain) },
    updateTransforms: stampFields.map((fieldPath) => ({ fieldPath, setToServerValue: "REQUEST_TIME" })),
    currentDocument: orderPrecondition,
  }];
  if (update.status === "delivered") {
    writes.push({
      update: {
        name: docName(env, `${orderPath}/statusHistory/delivered`),
        fields: encodeFields({ from: "on_the_way", to: "delivered", actorUid: uid, actorRole: "courier", via: "pin" }),
      },
      updateTransforms: [{ fieldPath: "at", setToServerValue: "REQUEST_TIME" }],
    });
  }
  if (attemptsDoc) writes.push({ delete: docName(env, attemptsPath), currentDocument: attemptsPrecondition });
  await commitOrConflict(env, token, writes);
  if (update.status === "delivered") scheduleReferralDelivery(env, ctx, token, order);
  // مرفقات الطلب الخاص كانت بتتمسح لما العميل يدوس تأكيد الاستلام؛ دلوقتي بعد الرمز الصحيح.
  // محاولة واحدة، وفشلها ما يأثرش على التسليم (العميل لما يفتح الطلب بيعيد المحاولة).
  if (hasPendingAttachments(order) && typeof order.userId === "string") {
    try {
      const fresh = await getDocument(env, orderPath, token);
      if (fresh) await cleanupOrderAttachmentsFor(env, token, fresh, order.userId, orderId);
    } catch (error) {
      console.error("Attachment cleanup after PIN delivery failed", error instanceof HttpError ? error.status : "error");
    }
  }
  await Promise.allSettled([
    notifyOrderParticipant(env, token, order.userId, orderId, "order_update", "تم تسليم طلبك"),
    update.status === "delivered" && typeof order.storeId === "string" &&
      notifyStoreOwners(env, token, order.storeId, orderId, "تم تسليم طلب من المحل", uid),
  ]);
  return response({ delivered: update.status === "delivered", confirmed: true });
}

// ───────────── إشعار الإدارة بطلب انضمام أو بلاغ تعذر تسليم ─────────────

export type AdminNoticeKind = "join_request" | "delivery_issue";
const ADMIN_NOTICE_MAX_AGE_MS = 10 * 60 * 1000;

/** نص الإشعار من غير أي بيانات شخصية (توبيك admins مش محمي، فالمحتوى عام). */
export function adminNoticeMessage(kind: AdminNoticeKind, detail: string) {
  const title = kind === "join_request" ? "طلب انضمام جديد" : "بلاغ تعذر تسليم جديد";
  const body = kind === "join_request"
    ? (detail === "store_owner" ? "صاحب محل" : detail === "courier" ? "مندوب" : "طلب") + " • افتح الطلبات والرسائل للمراجعة"
    : "مندوب سجّل تعذر تسليم • افتح الطلبات والرسائل";
  return {
    message: {
      topic: "admins",
      notification: { title, body },
      data: { type: "admin_inbox", kind },
      android: { priority: "HIGH", ttl: "3600s", notification: { sound: "default" } },
    },
  };
}

/**
 * سبب رفض إرسال الإشعار أو null لو مسموح: لازم المستند يكون جديد (آخر 10 دقايق)
 * وصاحبه هو اللي بيطلب الإشعار. ده بيمنع استخدام الـendpoint في إزعاج الإدارة.
 */
export function adminNoticeBlocker(kind: AdminNoticeKind, id: string, doc: JsonMap | null, uid: string, now = Date.now()): string | null {
  if (!doc) return "not_found";
  const created = doc.createdAt instanceof Date ? doc.createdAt.getTime() : 0;
  if (!created || now - created > ADMIN_NOTICE_MAX_AGE_MS || created - now > 60_000) return "stale";
  if (kind === "join_request") {
    if (doc.userId !== uid || !id.startsWith(uid + "_")) return "forbidden";
    if (doc.status !== "pending") return "not_pending";
  } else if (doc.createdBy !== uid) {
    return "forbidden";
  }
  return null;
}

async function notifyAdmins(request: Request, env: Env): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  let body: any;
  try {
    body = await request.json();
  } catch {
    throw new HttpError(400, "بيانات غير صالحة.");
  }
  const kind = body?.kind;
  const id = typeof body?.id === "string" ? body.id : "";
  if ((kind !== "join_request" && kind !== "delivery_issue") || !/^[A-Za-z0-9_-]{1,160}$/.test(id)) {
    throw new HttpError(400, "بيانات غير صالحة.");
  }
  const token = await googleAccessToken(env);
  const col = kind === "join_request" ? "role_requests" : "delivery_issues";
  const docRaw = await getDocument(env, `${col}/${encodeURIComponent(id)}`, token);
  const doc = docRaw ? decodeFields(docRaw.fields ?? {}) : null;
  const blocker = adminNoticeBlocker(kind, id, doc, uid);
  if (blocker) throw new HttpError(blocker === "forbidden" ? 403 : 409, "مش ممكن إرسال الإشعار.", blocker);

  // مرة واحدة لكل مستند: مستند تسجيل بشرط exists:false (الطلب المكرر بياخد sent:false).
  const noticePath = `adminNotices/${kind}_${encodeURIComponent(id)}`;
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ writes: [{
        update: {
          name: `projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${noticePath}`,
          fields: encodeFields({ kind, id, by: uid }),
        },
        updateTransforms: [{ fieldPath: "at", setToServerValue: "REQUEST_TIME" }],
        currentDocument: { exists: false },
      }] }),
    },
  );
  if (res.status === 409 || res.status === 400) return response({ sent: false, reason: "already_sent" });
  if (!res.ok) throw new HttpError(503, "تعذر الإرسال حاليًا.");

  const detail = kind === "join_request" ? String(doc?.type ?? "") : "";
  const [sent] = await Promise.all([
    fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(adminNoticeMessage(kind, detail)),
    }),
    kind === "delivery_issue" && typeof doc?.orderId === "string" &&
      notifyOrderParticipant(
        env, token, doc.customerId, doc.orderId, "order_update", "تعذر تسليم طلبك",
      ),
  ]);
  if (!sent.ok) {
    console.error("Admin FCM send failed", sent.status);
    throw new HttpError(503, "تعذر إرسال الإشعار.");
  }
  return response({ sent: true });
}

const orderPushTitles = {
  preparing: "المحل بدأ تجهيز طلبك",
  on_the_way: "طلبك في الطريق",
  delivered: "تم تسليم طلبك",
  cancelled: "تم إلغاء طلبك",
} as const;

function recentOrderEvent(date: unknown): date is Date {
  return date instanceof Date &&
    date.getTime() >= Date.now() - 10 * 60_000 && date.getTime() <= Date.now() + 60_000;
}

/**
 * Reserve a unique event while sending, then mark it sent only after at least one
 * FCM acceptance. An all-failed dispatch releases the reservation for a retry.
 * Pending reservations prevent concurrent duplicate sends without a Firestore read.
 */
export async function deliverClaimedOrderPush(
  env: Env,
  accessToken: string,
  path: string,
  event: string,
  sends: Array<() => Promise<boolean>>,
): Promise<boolean> {
  const name = firestoreDocumentName(env, path);
  const url = `${firestoreDocumentsUrl(env)}:commit`;
  const headers = { Authorization: `Bearer ${accessToken}`, "content-type": "application/json" };
  const claim = await fetch(url, {
    method: "POST", headers,
    body: JSON.stringify({ writes: [{
      update: { name, fields: encodeFields({ event, state: "pending" }) },
      updateTransforms: [{ fieldPath: "at", setToServerValue: "REQUEST_TIME" }],
      currentDocument: { exists: false },
    }] }),
  });
  if (!claim.ok) {
    const error = await claim.json().catch(() => null) as { error?: { status?: string } } | null;
    if (["ALREADY_EXISTS", "FAILED_PRECONDITION"].includes(error?.error?.status ?? "")) return false;
    throw new HttpError(503, "تعذر تجهيز إشعار الطلب.");
  }

  let accepted = false;
  try {
    const results = await Promise.allSettled(sends.map((send) => send()));
    accepted = results.some((result) => result.status === "fulfilled" && result.value === true);
    if (!accepted) throw new HttpError(503, "تعذر إرسال إشعار الطلب.");
    const confirmed = await fetch(url, {
      method: "POST", headers,
      body: JSON.stringify({ writes: [{
        update: { name, fields: encodeFields({ state: "sent" }) },
        updateMask: { fieldPaths: ["state"] },
        currentDocument: { exists: true },
      }] }),
    });
    if (!confirmed.ok) {
      // Keep the claim after FCM accepted a message. Releasing would duplicate it.
      console.error("Order push accepted but final marker update failed", confirmed.status);
      throw new HttpError(503, "تعذر تأكيد إرسال الإشعار.");
    }
    return true;
  } catch (error) {
    if (!accepted) {
      try {
        const release = await fetch(url, {
          method: "POST", headers,
          body: JSON.stringify({ writes: [{ delete: name, currentDocument: { exists: true } }] }),
        });
        if (!release.ok) console.error("Failed to release unsuccessful order push", release.status);
      } catch {
        console.error("Failed to release unsuccessful order push");
      }
    }
    throw error;
  }
}

async function notifyOrderEvent(request: Request, env: Env, ctx?: ExecutionContext): Promise<JsonMap> {
  const uid = await verifyCustomer(request, env);
  await assertOrderRateLimit(env.ORDER_RATE_LIMITER, `notify:${uid}`);
  const { orderId, event, status } = await readJsonBody(request);
  if (typeof orderId !== "string" || !/^[A-Za-z0-9_-]{1,180}$/.test(orderId) ||
    typeof event !== "string" || !["created", "assigned", "ready", "status"].includes(event)) {
    throw new HttpError(400, "بيانات إشعار الطلب غير صالحة.");
  }

  const token = await googleAccessToken(env);
  const path = `orders/${orderId}`;
  const orderDoc = await getDocument(env, path, token);
  if (!orderDoc) throw new HttpError(404, "الطلب غير موجود.");
  const order = decodeFields(orderDoc.fields ?? {});
  const storeId = typeof order.storeId === "string" ? order.storeId : "";
  const courierId = typeof order.courierId === "string" ? order.courierId : "";
  let key = event;
  let customerTitle = "";
  let courierTitle = "";
  let storeTitle = "";
  let notifyAvailableCouriers = false;

  if (event === "created") {
    if (order.userId !== uid) throw new HttpError(403, "الطلب لا يخص حسابك.");
    if (order.status !== "new" || !recentOrderEvent(order.createdAt)) return { orderId, processed: false };
    storeTitle = "طلب جديد للمحل";
  } else if (event === "status") {
    if (typeof status !== "string" || !Object.hasOwn(orderPushTitles, status)) {
      throw new HttpError(400, "حالة الطلب غير صالحة.");
    }
    if (order.status !== status) return { orderId, processed: false };
    const historyDoc = await getDocument(env, `${path}/statusHistory/${status}`, token);
    const history = historyDoc ? decodeFields(historyDoc.fields ?? {}) : {};
    if (history.actorUid !== uid) throw new HttpError(403, "التحديث لا يخص حسابك.");
    if (history.to !== status || history.via === "pin" || !recentOrderEvent(history.at)) {
      return { orderId, processed: false };
    }
    key = `status_${status}`;
    customerTitle = orderPushTitles[status as keyof typeof orderPushTitles];
    if (status === "on_the_way") storeTitle = "المندوب استلم طلبًا من المحل";
    if (status === "delivered") {
      storeTitle = "تم تسليم طلب من المحل";
      scheduleReferralDelivery(env, ctx, token, order);
    }
    if (status === "cancelled") {
      try {
        await refundReferralOrder(env, token, orderId, orderDoc);
      } catch {
        console.error("Referral refund requires retry");
      }
      storeTitle = "تم إلغاء طلب من المحل";
      courierTitle = "تم إلغاء طلب توصيل";
    }
  } else {
    if (order.status !== "preparing") return { orderId, processed: false };
    const assigned = event === "assigned";
    if (assigned
      ? !courierId || !recentOrderEvent(order.courierAt)
      : order.ready !== true || !recentOrderEvent(order.readyAt)) {
      return { orderId, processed: false };
    }
    if (assigned && courierId === uid) {
      const courier = await getDocument(env, `couriers/${encodeURIComponent(uid)}`, token);
      if (!courier || decodeFields(courier.fields ?? {}).active === false) {
        throw new HttpError(403, "حساب المندوب غير نشط.");
      }
    } else {
      const [ownerDoc, adminDoc] = await Promise.all([
        getDocument(env, `storeOwners/${encodeURIComponent(uid)}`, token),
        getDocument(env, `admins/${encodeURIComponent(uid)}`, token),
      ]);
      const owner = ownerDoc ? decodeFields(ownerDoc.fields ?? {}) : {};
      if (!adminDoc && (!storeId || owner.storeId !== storeId || owner.active === false)) {
        throw new HttpError(403, "الطلب لا يخص حسابك.");
      }
    }
    if (assigned) {
      key = `assigned_${(order.courierAt as Date).getTime()}`;
      customerTitle = "تم تعيين مندوب لطلبك";
      if (courierId !== uid) courierTitle = "تم تعيين طلب توصيل لك";
    } else {
      customerTitle = "طلبك جاهز للاستلام من المحل";
      courierTitle = "طلب التوصيل جاهز للاستلام";
      notifyAvailableCouriers = !courierId;
    }
  }

  const recipients: Array<() => Promise<boolean>> = [];
  if (customerTitle && order.userId !== uid) {
    recipients.push(() => notifyOrderParticipant(env, token, order.userId, orderId, "order_update", customerTitle));
  }
  if (courierTitle && courierId !== uid) {
    recipients.push(() => notifyOrderParticipant(env, token, courierId, orderId, "courier_order_update", courierTitle));
  }
  if (storeTitle && storeId) {
    recipients.push(() => notifyStoreOwners(env, token, storeId, orderId, storeTitle, uid));
  }
  if (notifyAvailableCouriers) {
    recipients.push(() => notifyCouriersOfNewOrder(env, token, String(order.storeName)));
  }
  const processed = await deliverClaimedOrderPush(env, token, `${path}/pushEvents/${key}`, event, recipients);
  return { orderId, processed };
}

async function notifyStoreOwners(
  env: Env, token: string, storeId: string, orderId: string, title: string, actorUid: string,
): Promise<boolean> {
  const owners = await queryAccountDocuments(env, token, "storeOwners", "storeId", storeId);
  const results = await Promise.allSettled(owners.map((doc) => {
    const recipient = doc.name.split("/").pop();
    if (recipient !== actorUid && decodeFields(doc.fields ?? {}).active !== false) {
      return notifyOrderParticipant(env, token, recipient, orderId, "store_order_update", title);
    }
    return Promise.resolve(false);
  }));
  return results.some((result) => result.status === "fulfilled" && result.value);
}

export function isSameStoreOrderReplay(existingUserId: unknown, existingStoreId: unknown, userId: string, storeId: string): boolean {
  return existingUserId === userId && existingStoreId === storeId;
}

// ───────────── «طلباتك على السريع» (quick_orders) ─────────────
// الـWorker هو الكاتب الوحيد للمجموعة؛ قواعد Firestore بتمنع أي كتابة من التطبيق.
// كل كتابة بشرط updateTime، فعمليتين متزامنتين (مثلًا مندوبين بيقبلوا نفس الطلب) واحدة بس بتنجح.

const QUICK_ID = /^[A-Za-z0-9_-]{16,180}$/;

/** رفع صورة موقّع على Cloudinary في مجلد محدد (نفس إعدادات رفع صور المحلات). */
async function signedCloudinaryImageUpload(
  env: Env,
  bytes: Uint8Array<ArrayBuffer>,
  detected: { format: string; mime: string },
  folder: string,
  resourceType: "image" | "video" = "image",
): Promise<Response> {
  const timestamp = Math.floor(Date.now() / 1000);
  const publicId = crypto.randomUUID();
  const signedParams = {
    allowed_formats: resourceType === "video" ? "m4a,aac,mp4" : "jpg,jpeg,png,webp",
    folder,
    overwrite: "false",
    public_id: publicId,
    timestamp: String(timestamp),
    unique_filename: "true",
    use_filename: "false",
  };
  const signature = await cloudinarySignature(signedParams, env.CLOUDINARY_API_SECRET!);
  const upload = new FormData();
  upload.append("file", new Blob([bytes], { type: detected.mime }), `${publicId}.${detected.format}`);
  upload.append("api_key", env.CLOUDINARY_API_KEY!);
  for (const [key, value] of Object.entries(signedParams)) upload.append(key, value);
  upload.append("signature", signature);
  const uploaded = await fetch(
    `https://api.cloudinary.com/v1_1/${env.CLOUDINARY_CLOUD_NAME}/${resourceType}/upload`,
    { method: "POST", body: upload },
  );
  if (!uploaded.ok) {
    console.error("Cloudinary receipt upload failed", uploaded.status);
    throw new HttpError(502, "تعذر رفع الصورة إلى خدمة الصور. حاول مرة أخرى.");
  }
  const result = await uploaded.json() as { secure_url?: string };
  const secureUrl = typeof result.secure_url === "string" ? result.secure_url : "";
  let parsedUrl: URL;
  try { parsedUrl = new URL(secureUrl); } catch { throw new HttpError(502, "خدمة الصور لم ترجع رابطًا صالحًا."); }
  if (parsedUrl.protocol !== "https:" || parsedUrl.hostname !== "res.cloudinary.com" ||
      !parsedUrl.pathname.startsWith(`/${env.CLOUDINARY_CLOUD_NAME}/${resourceType}/upload/`)) {
    throw new HttpError(502, "خدمة الصور لم ترجع رابطًا آمنًا.");
  }
  return response({ url: secureUrl });
}

function quickError(error: unknown): never {
  if (error instanceof QuickRuleError) throw new HttpError(error.status, error.message, error.code);
  throw error;
}

async function readJsonBody(request: Request): Promise<JsonMap> {
  const text = await request.text();
  if (!text.trim()) return {};
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new HttpError(400, "بيانات غير مفهومة.");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new HttpError(400, "صيغة البيانات غير صحيحة.");
  return body as JsonMap;
}

export function quickTopicMessage(isErrand = false) {
  return {
    message: {
      topic: "quick_couriers",
      notification: {
        title: isErrand ? "مشوار جديد على وصّلي" : "طلب سريع جديد",
        body: "افتح التطبيق لمراجعة الطلبات المتاحة.",
      },
      data: { type: "quick_order" },
      android: { priority: "HIGH", ttl: "1800s", notification: { sound: "default" } },
    },
  };
}

/** Returns true only when FCM accepted a message for at least one device. No extra Firestore reads. */
export async function notifyOrderParticipant(
  env: Env,
  token: string,
  recipient: unknown,
  orderId: string,
  type: "quick_customer_update" | "quick_courier_update" | "order_update" | "store_order_update" | "courier_order_update",
  title: string,
): Promise<boolean> {
  if (typeof recipient !== "string" || !recipient) return false;
  try {
    // A recipient lookup must not eat the timeout budget of every FCM request.
    const user = await getDocument(env, `users/${encodeURIComponent(recipient)}`, token, AbortSignal.timeout(5_000));
    const tokens = user ? decodeFields(user.fields ?? {}).fcmTokens : null;
    if (!Array.isArray(tokens)) return false;
    const devices = [...new Set(tokens.filter(
      (value): value is string => typeof value === "string" && value.length > 0 && value.length <= 4096,
    ))].slice(-10);
    const sent = await Promise.allSettled(devices.map(async (device) => {
      const result = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
        method: "POST",
        signal: AbortSignal.timeout(5_000),
        headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify({
          message: {
            token: device,
            notification: { title, body: "افتح وصّلي لمراجعة تفاصيل الطلب." },
            data: { type, orderId },
            android: { priority: "HIGH", notification: { sound: "default" } },
          },
        }),
      });
      if (result.ok) return { accepted: true, invalid: false, device };
      // FCM HTTP v1 can return UNREGISTERED in error details (or as HTTP 404).
      const errorBody = await result.text().catch(() => "");
      const invalid = result.status === 404 || /UNREGISTERED/.test(errorBody);
      return { accepted: false, invalid, device };
    }));
    const outcomes = sent.flatMap((result) => result.status === "fulfilled" ? [result.value] : []);
    const invalidDevices = outcomes.filter((entry) => entry.invalid).map((entry) => entry.device);
    if (invalidDevices.length) {
      // Firestore arrayRemove via REST transform: a write, never a read.
      try {
        await commitFirestoreWrites(env, token, [{
          transform: {
            document: firestoreDocumentName(env, `users/${encodeURIComponent(recipient)}`),
            fieldTransforms: [{
              fieldPath: "fcmTokens",
              removeAllFromArray: { values: invalidDevices.map((device) => ({ stringValue: device })) },
            }],
          },
        }]);
      } catch {
        console.error("Stale FCM token cleanup failed");
      }
    }
    const success = outcomes.some((entry) => entry.accepted);
    if (sent.some((result) => result.status === "rejected") ||
        outcomes.some((entry) => !entry.accepted && !entry.invalid)) {
      console.error("Order participant push failed");
    }
    return success;
  } catch {
    console.error("Order participant push failed");
    return false;
  }
}

const quickCustomerUpdates: Readonly<Record<string, string>> = {
  "quote-errand": "المندوب عرض أجرة المشوار — راجع السعر ووافق عليه",
  accept: "مندوب قبل طلبك السريع",
  release: "طلبك السريع بيدوّر على مندوب تاني",
  "advance-received": "المندوب أكّد استلام المقدم",
  "submit-summary": "كشف طلبك السريع جاهز — استلم طلبك بالرمز",
};

const quickCourierUpdates: Readonly<Record<string, string>> = {
  "approve-errand-quote": "العميل وافق على أجرة المشوار — تقدر تبدأ",
  "reject-errand-quote": "العميل رفض أجرة المشوار — قدّم سعر تاني",
  "advance-sent": "العميل سجّل تحويل المقدم",
  "approve-summary": "العميل وافق على كشف الحساب",
  "reject-summary": "العميل طلب مراجعة كشف الحساب",
  cancel: "تم إلغاء الطلب السريع",
};

/** POST /v1/quick — العميل ينشئ طلب سريع. نفس معرّف الطلب مرتين = نفس الطلب (مفيش تكرار). */
async function createQuickOrder(request: Request, env: Env): Promise<Response> {
  if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_SERVICE_ACCOUNT_EMAIL ||
      !env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY) {
    throw new HttpError(503, "بوابة الطلبات لم تكتمل تهيئتها بعد.");
  }
  const uid = await verifyCustomer(request, env);
  await assertOrderRateLimit(env.ORDER_RATE_LIMITER, uid);
  const input = await readJsonBody(request);
  const orderId = String(input.orderId ?? "");
  if (!orderId.startsWith(`${uid}_`) || !/^[A-Za-z0-9_-]{16,180}$/.test(orderId.slice(uid.length + 1))) {
    throw new HttpError(400, "معرّف الطلب غير صالح.");
  }
  const kind = input.kind === undefined ? "quick" : input.kind;
  if (kind !== "quick" && kind !== "errand") {
    throw new HttpError(400, "نوع الخدمة غير معروف.", "invalid_kind");
  }
  const customerFirstName = firstName(input.customerName);
  const area = typeof input.area === "string" ? input.area.trim() : "";
  if (customerFirstName.length < 1 || customerFirstName.length > 30 || area.length > 60) {
    throw new HttpError(400, "راجع الاسم والمنطقة.");
  }
  let stores, notes, customerImages: string[] = [], customerVoiceUrl = "";
  let errandType: ReturnType<typeof validateErrandType> | undefined;
  let pickupAddress = "";
  try {
    if (kind === "errand") {
      errandType = validateErrandType(input.errandType);
      const rawContact = input.contact && typeof input.contact === "object" &&
        !Array.isArray(input.contact) ? input.contact as JsonMap : {};
      pickupAddress = validateErrandPickup(rawContact.pickupAddress);
    }
    const folder = await quickRequestFolder(uid);
    customerImages = validateQuickImages(input.customerImages,
      (url) => isOwnQuickImage(url, folder, env.CLOUDINARY_CLOUD_NAME));
    customerVoiceUrl = validateQuickVoice(input.customerVoiceUrl,
      (url) => isOwnQuickVoice(url, folder + "/voice", env.CLOUDINARY_CLOUD_NAME));
    stores = validateQuickStores(input.stores, customerImages.length > 0 || !!customerVoiceUrl);
    if (kind === "errand" && (
      stores.length !== 1 ||
      stores[0].name !== "" ||
      stores[0].pricedItems?.length ||
      stores[0].items.length < 10
    )) {
      throw new QuickRuleError(400, "اكتب تفاصيل المشوار (10 أحرف على الأقل) من غير أصناف مسعّرة.", "invalid_errand");
    }
    notes = validateQuickNotes(input.notes);
  } catch (error) {
    quickError(error);
  }
  const contact = validateContact(input.contact);

  const token = await googleAccessToken(env);
  const orderPath = `quick_orders/${orderId}`;
  const existing = await getDocument(env, orderPath, token);
  if (existing) {
    const old = decodeFields(existing.fields ?? {});
    if (old.userId === uid) return response({ orderId, reused: true, order: old });
    throw new HttpError(409, "معرّف الطلب مستخدم بالفعل.", "id_taken");
  }
  const [settingsDoc, restrictionDoc, limitDoc] = await Promise.all([
    getDocument(env, "app_info/quick_settings", token),
    getDocument(env, `customer_restrictions/${uid}`, token),
    getDocument(env, `quickLimits/${uid}`, token),
  ]);
  const settings = resolveQuickSettings(settingsDoc ? decodeFields(settingsDoc.fields ?? {}) : null);
  if (!settings.enabled) {
    throw new HttpError(503, "خدمة «طلباتك على السريع» غير متاحة حاليًا.", "quick_disabled");
  }
  const restriction = restrictionDoc ? decodeFields(restrictionDoc.fields ?? {}) : null;
  if (isCustomerRestricted(restriction)) {
    throw new HttpError(403, "حسابك مقيّد مؤقتًا أو بيانات التقييد غير مكتملة. راجع الدعم.");
  }
  // حد مستقل عن الطلبات العادية (quickLimits) عشان الخدمة ما تأثرش على حد طلبات المحلات.
  const previousLimit = limitDoc ? decodeFields(limitDoc.fields ?? {}) : {};
  const lastAt = previousLimit.lastAt instanceof Date ? previousLimit.lastAt.getTime() : 0;
  if (lastAt && Date.now() - lastAt < 20_000) {
    throw new HttpError(429, "استنى شوية قبل إرسال طلب جديد.", "rate_limited");
  }
  const dayKey = cairoDayKey(new Date());
  const todays = ordersCountedToday(previousLimit, dayKey);
  if (todays >= settings.maxPerDay) {
    throw new HttpError(429, `وصلت للحد اليومي للطلبات السريعة (${settings.maxPerDay}). جرّب بكرة.`, DAILY_LIMIT_CODE);
  }

  const order = newQuickOrder({
    uid, customerFirstName, area, notes: notes!, stores: stores!, settings, customerImages, customerVoiceUrl,
    kind, errandType,
  });
  await commitOrConflict(env, token, [
    {
      update: { name: docName(env, orderPath), fields: encodeFields(order) },
      updateTransforms: [{ fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: { exists: false },
    },
    {
      update: { name: docName(env, `${orderPath}/private/contact`), fields: encodeFields({
         ...contact, ...(kind === "errand" ? { pickupAddress, customerImages } : {}), customerVoiceUrl,
       }) },
      currentDocument: { exists: false },
    },
    {
      update: {
        name: docName(env, `quickLimits/${uid}`),
        fields: encodeFields({ lastAt: new Date(), day: dayKey, dailyCount: todays + 1 }),
      },
      updateTransforms: [{ fieldPath: "lastAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: limitDoc?.updateTime ? { updateTime: limitDoc.updateTime } : { exists: false },
    },
  ]);
  try {
    const sent = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify(quickTopicMessage(kind === "errand")),
    });
    if (!sent.ok) console.error("Quick courier push failed", sent.status);
  } catch (error) {
    console.error("Quick courier push failed", error instanceof Error ? error.name : "error");
  }
  return response({ orderId, order });
}

/** مين اللي بيطلب العملية: صاحب الطلب، أو مندوب نشط، أو الإدارة. */
async function resolveQuickActor(env: Env, token: string, uid: string, order: JsonMap): Promise<QuickActor> {
  if (order.userId === uid) return { uid, role: "customer" };
  const courierDoc = await getDocument(env, `couriers/${encodeURIComponent(uid)}`, token);
  if (courierDoc) {
    const courier = decodeFields(courierDoc.fields ?? {});
    if (courier.active === undefined || courier.active === true) {
      return {
        uid,
        role: "courier",
        name: typeof courier.name === "string" ? courier.name : "",
        quickEnabled: courier.quickEnabled === true,
      };
    }
  }
  const adminDoc = await getDocument(env, `admins/${encodeURIComponent(uid)}`, token);
  if (adminDoc) return { uid, role: "admin" };
  throw new HttpError(403, "مش مسموح لك بالعملية دي على الطلب ده.", "forbidden");
}

/** POST /v1/quick/{orderId}/{action} — كل عمليات الطلب بعد الإنشاء (ماعدا التسليم بالرمز). */
async function quickOrderAction(request: Request, env: Env, orderId: string, action: string): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  await assertOrderRateLimit(env.ORDER_RATE_LIMITER, uid);
  if (!QUICK_ID.test(orderId)) throw new HttpError(400, "معرّف الطلب غير صالح.");
  const body = await readJsonBody(request);
  const token = await googleAccessToken(env);
  const orderPath = `quick_orders/${encodeURIComponent(orderId)}`;
  const doc = await getDocument(env, orderPath, token);
  if (!doc) throw new HttpError(404, "الطلب غير موجود.", "not_found");
  const order = decodeFields(doc.fields ?? {});
  const actor = await resolveQuickActor(env, token, uid, order);
  let voiceDoc: FirestoreDoc | null = null;
  let voiceCleanup: string[] = [];
  let voiceFolder = "";
  if (action === "edit-voice") {
    // Never load another customer's private voice URL.
    if (order.userId !== uid || actor.role !== "customer") {
      throw new HttpError(403, "لا تملك صلاحية تعديل الصوت.", "forbidden");
    }
    if (order.status !== "open") {
      throw new HttpError(409, "تعديل الصوت متاح قبل قبول المندوب فقط.", "edit_after_accept");
    }
    if (!Object.prototype.hasOwnProperty.call(body, "customerVoiceUrl")) {
      throw new HttpError(400, "حدد التسجيل الجديد أو احذف التسجيل.", "invalid_voice");
    }
    voiceFolder = (await quickRequestFolder(uid)) + "/voice";
    try {
      body.customerVoiceUrl = validateQuickVoice(body.customerVoiceUrl,
        (url) => isOwnQuickVoice(url, voiceFolder, env.CLOUDINARY_CLOUD_NAME));
    } catch (error) { quickError(error); }
    voiceDoc = await getDocument(env, `${orderPath}/private/contact`, token);
    if (!voiceDoc) throw new HttpError(503, "بيانات الطلب الخاصة غير متاحة.");
    const contact = decodeFields(voiceDoc.fields ?? {});
    const previousVoice = quickCustomerVoice(contact);
    const nextVoice = String(body.customerVoiceUrl);
    voiceCleanup = [
      ...new Set([
        ...(Array.isArray(contact.customerVoicesPendingCleanup)
          ? contact.customerVoicesPendingCleanup.filter((u): u is string => typeof u === "string")
          : []),
        ...(typeof contact.customerVoicePendingCleanup === "string" &&
            contact.customerVoicePendingCleanup ? [contact.customerVoicePendingCleanup] : []),
        ...(previousVoice && previousVoice !== nextVoice ? [previousVoice] : []),
      ]),
    ].filter((url) => isOwnQuickVoice(url, voiceFolder, env.CLOUDINARY_CLOUD_NAME));
  }
  let patch: JsonMap;
  try {
    patch = applyQuickAction(order, action, actor, body, {
      orderId,
      now: new Date(),
      cloudName: env.CLOUDINARY_CLOUD_NAME,
    });
  } catch (error) {
    quickError(error);
  }
  const writes: unknown[] = [{
    update: { name: doc.name, fields: encodeFields(patch!) },
    updateMask: { fieldPaths: Object.keys(patch!) },
    currentDocument: doc.updateTime ? { updateTime: doc.updateTime } : { exists: true },
  }];
  if (voiceDoc) {
    const voicePatch = {
      customerVoiceUrl: String(body.customerVoiceUrl),
      customerVoicesPendingCleanup: voiceCleanup,
      customerVoicePendingCleanup: "",
    };
    writes.push({
      update: { name: voiceDoc.name, fields: encodeFields(voicePatch) },
      updateMask: { fieldPaths: Object.keys(voicePatch) },
      currentDocument: voiceDoc.updateTime ? { updateTime: voiceDoc.updateTime } : { exists: true },
    });
  }
  await commitOrConflict(env, token, writes);
  // Delete replaced recordings only *after* the atomic Firestore update succeeds.
  // If Cloudinary fails, the private contact retains cleanup URLs for PIN delivery.
  if (voiceDoc && voiceCleanup.length) {
    const removed: string[] = [];
    for (const url of voiceCleanup) {
      if (await destroyQuickVoice(env, url, voiceFolder)) removed.push(url);
    }
    if (removed.length) {
      try {
        const latest = await getDocument(env, `${orderPath}/private/contact`, token);
        if (latest) {
          const privateNow = decodeFields(latest.fields ?? {});
          const pending = Array.isArray(privateNow.customerVoicesPendingCleanup)
            ? privateNow.customerVoicesPendingCleanup.filter((v): v is string => typeof v === "string")
            : [];
          const remaining = pending.filter((v) => !removed.includes(v));
          if (remaining.length !== pending.length) {
            await commitOrConflict(env, token, [{
              update: { name: latest.name, fields: encodeFields({ customerVoicesPendingCleanup: remaining }) },
              updateMask: { fieldPaths: ["customerVoicesPendingCleanup"] },
              currentDocument: latest.updateTime ? { updateTime: latest.updateTime } : { exists: true },
            }]);
          }
        }
      } catch { /* The retained pending list can be retried at delivery. */ }
    }
  }
  const customerTitle = quickCustomerUpdates[action] ??
    (action === "cancel" && actor.role === "admin" ? "تم إلغاء طلبك السريع" : undefined);
  const courierTitle = quickCourierUpdates[action];
  await Promise.all([
    customerTitle && notifyOrderParticipant(
      env, token, order.userId, orderId, "quick_customer_update", customerTitle,
    ),
    courierTitle && notifyOrderParticipant(
      env, token, order.courierId, orderId, "quick_courier_update", courierTitle,
    ),
  ]);
  return response({ orderId, order: { ...order, ...patch! } });
}

/** GET /v1/quick/{orderId}/delivery-pin — العميل بيجيب رمز التسليم من القبول لحد التسليم. */
async function getQuickDeliveryPin(request: Request, env: Env, orderId: string): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  if (!env.DELIVERY_PIN_SECRET) throw new HttpError(503, PIN_DISABLED, "pin_disabled");
  if (!QUICK_ID.test(orderId)) throw new HttpError(400, "معرّف الطلب غير صالح.");
  const token = await googleAccessToken(env);
  const doc = await getDocument(env, `quick_orders/${encodeURIComponent(orderId)}`, token);
  if (!doc) throw new HttpError(404, "الطلب غير موجود.", "not_found");
  const order = decodeFields(doc.fields ?? {});
  if (order.userId !== uid) throw new HttpError(403, "لا تملك صلاحية على هذا الطلب.");
  if (!QUICK_PIN_STATUSES.includes(String(order.status))) {
    throw new HttpError(409, "الرمز بيظهر بعد تجهيز الكشف النهائي وبيقفل بعد التسليم أو الإلغاء.", "pin_not_available");
  }
  return response({ pin: await deriveDeliveryPin("quick:" + orderId, env.DELIVERY_PIN_SECRET) });
}

/** POST /v1/quick/{orderId}/deliver — المندوب يأكد التسليم برمز العميل. 5 محاولات غلط = قفل. */
async function deliverQuickWithPin(request: Request, env: Env, orderId: string, ctx?: ExecutionContext): Promise<Response> {
  const uid = await verifyCustomer(request, env);
  if (!env.DELIVERY_PIN_SECRET) throw new HttpError(503, PIN_DISABLED, "pin_disabled");
  if (!QUICK_ID.test(orderId)) throw new HttpError(400, "معرّف الطلب غير صالح.");
  const body = await readJsonBody(request);
  if (!isDeliveryPin(body.pin)) throw new HttpError(400, "اكتب رمز من 4 أرقام.", "pin_invalid");
  const token = await googleAccessToken(env);
  const orderPath = `quick_orders/${encodeURIComponent(orderId)}`;
  const attemptsPath = `deliveryPinAttempts/${encodeURIComponent("quick_" + orderId)}`;
  const [orderDoc, courierDoc, attemptsDoc] = await Promise.all([
    getDocument(env, orderPath, token),
    getDocument(env, `couriers/${encodeURIComponent(uid)}`, token),
    getDocument(env, attemptsPath, token),
  ]);
  if (!courierDoc) throw new HttpError(403, "حساب المندوب غير معتمد.");
  const courier = decodeFields(courierDoc.fields ?? {});
  if (courier.active !== undefined && courier.active !== true) {
    throw new HttpError(403, "حساب المندوب غير نشط. راجع الإدارة.");
  }
  if (!orderDoc) throw new HttpError(404, "الطلب غير موجود.", "not_found");
  const order = decodeFields(orderDoc.fields ?? {});
  const blocker = quickDeliveryBlocker(order, uid);
  if (blocker) throw new HttpError(409, blocker, "not_deliverable");

  const prev = attemptsDoc ? decodeFields(attemptsDoc.fields ?? {}) : {};
  const attempts = Number.isSafeInteger(prev.attempts) ? Number(prev.attempts) : 0;
  if (prev.locked === true || attempts >= DELIVERY_PIN_MAX_ATTEMPTS) {
    throw new HttpError(423, "الرمز اتقفل بعد محاولات غلط كتير. الإدارة هتراجع الطلب.", "pin_locked");
  }
  const attemptsPrecondition = attemptsDoc?.updateTime ? { updateTime: attemptsDoc.updateTime } : { exists: false };
  const orderPrecondition = orderDoc.updateTime ? { updateTime: orderDoc.updateTime } : { exists: true };
  const expected = await deriveDeliveryPin("quick:" + orderId, env.DELIVERY_PIN_SECRET);

  if (!equalPin(body.pin, expected)) {
    const next = attempts + 1;
    const locked = next >= DELIVERY_PIN_MAX_ATTEMPTS;
    const writes: unknown[] = [{
      update: { name: docName(env, attemptsPath), fields: encodeFields({ attempts: next, locked, orderId, kind: "quick" }) },
      updateTransforms: [{ fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME" }],
      currentDocument: attemptsPrecondition,
    }];
    if (locked) {
      writes.push({
        update: { name: docName(env, orderPath), fields: {} },
        updateMask: { fieldPaths: [] },
        updateTransforms: [{ fieldPath: "deliveryPinLockedAt", setToServerValue: "REQUEST_TIME" }],
        currentDocument: orderPrecondition,
      });
    }
    await commitOrConflict(env, token, writes);
    if (locked) throw new HttpError(423, "الرمز اتقفل بعد محاولات غلط كتير. الإدارة هتراجع الطلب.", "pin_locked");
    throw new HttpError(400, `الرمز غلط. فاضل ${DELIVERY_PIN_MAX_ATTEMPTS - next} محاولات.`, "pin_wrong");
  }

  const patch = quickDeliveredPatch(order, uid, new Date());
  // المشاوير: صور الطرد والعناوين في private/contact فقط.
  const voicePath = `${orderPath}/private/contact`;
  const voiceDoc = await getDocument(env, voicePath, token);
  const contact = voiceDoc ? decodeFields(voiceDoc.fields ?? {}) : {};
  const images = order.kind === "errand" ? quickCustomerImages(contact) : quickCustomerImages(order);
  const voice = quickCustomerVoice(contact);
  const pendingVoices = [
    ...new Set([
      ...(Array.isArray(contact.customerVoicesPendingCleanup)
        ? contact.customerVoicesPendingCleanup.filter((v): v is string => typeof v === "string")
        : []),
      ...(typeof contact.customerVoicePendingCleanup === "string" &&
          contact.customerVoicePendingCleanup ? [contact.customerVoicePendingCleanup] : []),
      ...(voice ? [voice] : []),
    ]),
  ];
  const imagesFolder = (images.length || pendingVoices.length)
    ? await quickRequestFolder(String(order.userId ?? "")) : "";
  const undeleted = await destroyQuickImages(env, images, imagesFolder);
  const voiceFolder = imagesFolder + "/voice";
  const failedVoices: string[] = [];
  for (const url of pendingVoices) {
    if (!await destroyQuickVoice(env, url, voiceFolder)) failedVoices.push(url);
  }
  if (undeleted.length && order.kind !== "errand") {
    // طلبات المشتريات تستخدم حقل التنظيف القديم.
    patch.customerImagesPendingCleanup = undeleted;
  }
  const writes: unknown[] = [{
    update: { name: docName(env, orderPath), fields: encodeFields(patch) },
    updateMask: { fieldPaths: Object.keys(patch) },
    currentDocument: orderPrecondition,
  }];
  if (voiceDoc) {
    const voicePatch = {
      customerVoiceUrl: "",
      customerVoicePendingCleanup: "",
      customerVoicesPendingCleanup: failedVoices,
      ...(order.kind === "errand" ? {
        customerImages: [],
        customerImagesPendingCleanup: undeleted,
      } : {}),
    };
    writes.push({
      update: { name: voiceDoc.name, fields: encodeFields(voicePatch) },
      updateMask: { fieldPaths: Object.keys(voicePatch) },
      currentDocument: voiceDoc.updateTime ? { updateTime: voiceDoc.updateTime } : { exists: true },
    });
  }
  if (attemptsDoc) writes.push({ delete: docName(env, attemptsPath), currentDocument: attemptsPrecondition });
  await commitOrConflict(env, token, writes);
  scheduleReferralDelivery(env, ctx, token, { userId: order.userId });
  await notifyOrderParticipant(
    env, token, order.userId, orderId, "quick_customer_update", "تم تسليم طلبك السريع",
  );
  return response({ orderId, delivered: true, order: { ...order, ...patch } });
}

/** توجيه مسارات /v1/quick. بيرجع null لو المسار مش تبع الخدمة. */
async function routeQuick(request: Request, env: Env, pathname: string, ctx?: ExecutionContext): Promise<Response | null> {
  if (pathname === "/v1/quick") {
    return request.method === "POST" ? await createQuickOrder(request, env) : response({ error: "Not found." }, 404);
  }
  const match = pathname.match(/^\/v1\/quick\/([^/]+)\/([a-z-]+)$/);
  if (!match) return null;
  const orderId = decodeURIComponent(match[1]);
  const action = match[2];
  if (action === "delivery-pin") {
    return request.method === "GET" ? await getQuickDeliveryPin(request, env, orderId) : response({ error: "Not found." }, 404);
  }
  if (request.method !== "POST") return response({ error: "Not found." }, 404);
  if (action === "deliver") return await deliverQuickWithPin(request, env, orderId, ctx);
  return await quickOrderAction(request, env, orderId, action);
}
