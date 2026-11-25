/**
 * «طلباتك على السريع»: منطق صافي (من غير Firestore ولا شبكة) عشان يتختبر لوحده.
 * الـWorker هو الكاتب الوحيد لـ quick_orders؛ القواعد بتمنع أي كتابة من التطبيق.
 * كل المبالغ بالقروش (أرقام صحيحة) عشان نتجنب كسور العشرية.
 *
 * المبدأ: الاتفاق على أي تغيير بيتم بالتليفون بين العميل والمندوب. التطبيق بيثبت بس:
 *   1) المقدم قبل الشراء لو التقدير فوق الحد (حاجز أمان مالي).
 *   2) كشف نهائي واحد (فواتير + أجرة + رسوم − مقدم) للعلم فقط. العميل يؤكد الاستلام بالرمز.
 * المندوب ما بيكتبش نصوص: أرقام وصور فواتير بس.
 *
 * دورة الطلب:
 *   open ← (accept) accepted ← (start-purchase + تقدير) purchasing [المندوب يدفع من جيبه، والمقدم اختياري]
 *   purchasing ← (receipt × n ثم submit-summary + أجرة) summary_approved (جاهز للتسليم)
 *   summary_approved ← (deliver بالرمز) delivered
 *   summary_pending ← (reject-summary) purchasing   (بعد موافقة العميل الكشف بيتقفل؛ أي حاجة بعدها بالتليفون)
 *   cancelled: العميل قبل الشراء، أو الإدارة في أي وقت قبل التسليم.
 */

type JsonMap = Record<string, unknown>;

export const QUICK_STATUSES = [
  "open", "accepted", "awaiting_advance", "purchasing", "summary_pending", "summary_approved",
  "delivered", "cancelled",
] as const;
export type QuickStatus = typeof QUICK_STATUSES[number];

export const QUICK_ACTIONS = [
  "edit", "edit-voice", "cancel", "accept", "release", "start-purchase",
  "advance-sent", "advance-received", "receipt", "receipt-remove",
  "submit-summary", "approve-summary", "reject-summary",
] as const;
export type QuickAction = typeof QUICK_ACTIONS[number];

export type QuickRole = "customer" | "courier" | "admin";

export interface QuickActor {
  uid: string;
  role: QuickRole;
  /** اسم المندوب (من couriers/{uid}.name) — بيتكتب على الطلب عند القبول. */
  name?: string;
  /** المندوب معتمد للطلبات السريعة (couriers/{uid}.quickEnabled == true). */
  quickEnabled?: boolean;
}

export interface QuickContext {
  orderId: string;
  now: Date;
  /** اسم حساب Cloudinary للتحقق من روابط الفواتير (لو فاضي أي حساب مقبول). */
  cloudName?: string;
}

export class QuickRuleError extends Error {
  constructor(readonly status: number, message: string, readonly code: string) {
    super(message);
  }
}

function fail(status: number, code: string, message: string): never {
  throw new QuickRuleError(status, message, code);
}

export const QUICK_LIMITS = {
  maxStores: 10,
  maxStoreName: 60,
  maxItemsText: 500,
  maxNotes: 300,
  maxReference: 40,
  maxReason: 200,
  maxReceipts: 20,
  /** أقصى قيمة فاتورة واحدة: 10,000 جنيه. */
  maxReceiptPiastres: 1_000_000,
} as const;

/** القيم الافتراضية لو الإدارة ما حددتش الحقل في app_info/quick_settings. */
export const QUICK_DEFAULTS = {
  /** حتى 200 جنيه = دفع عند الاستلام؛ أكتر = تحويل مقدم لمحفظة المندوب. */
  prepaidThresholdPiastres: 20_000,
  maximumAdvancePiastres: 100_000,
  maximumDeliveryPiastres: 20_000,
  maxPerDay: 5,
} as const;

export interface QuickSettings {
  enabled: boolean;
  prepaidThresholdPiastres: number;
  maximumAdvancePiastres: number;
  maximumDeliveryPiastres: number;
  maxPerDay: number;
}

function intIn(value: unknown, min: number, max: number): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max
    ? value
    : null;
}

/** الخدمة شغالة دايمًا. enabled: false بس = زرار طوارئ لقفلها. أي رقم غير صالح بيرجع للافتراضي. */
export function resolveQuickSettings(raw: JsonMap | null): QuickSettings {
  const r = raw ?? {};
  return {
    enabled: r.enabled !== false,
    prepaidThresholdPiastres: intIn(r.prepaidThresholdPiastres, 0, 10_000_000) ??
      QUICK_DEFAULTS.prepaidThresholdPiastres,
    maximumAdvancePiastres: intIn(r.maximumAdvancePiastres, 100, 10_000_000) ??
      QUICK_DEFAULTS.maximumAdvancePiastres,
    maximumDeliveryPiastres: intIn(r.maximumDeliveryPiastres, 100, 100_000) ??
      QUICK_DEFAULTS.maximumDeliveryPiastres,
    maxPerDay: intIn(r.maxPerDay, 1, 50) ?? QUICK_DEFAULTS.maxPerDay,
  };
}

/** رسوم خدمة وصّلي: 2%، أقل حاجة 5 وأقصى حاجة 15 جنيه، مرة واحدة للطلب (نفس WasallyServiceFee). */
export function quickServiceFee(purchasesPiastres: number): number {
  if (!Number.isSafeInteger(purchasesPiastres) || purchasesPiastres <= 0) return 0;
  const computed = Math.floor((purchasesPiastres * 200 + 5000) / 10000);
  return Math.min(1500, Math.max(500, computed));
}

export interface QuickPricedItem {
  name: string;
  qty: number;
  unitPricePiastres: number;
}
export interface QuickStore {
  name: string;
  items: string;
  pricedItems?: QuickPricedItem[];
}

/** Display-only total; never use for advance, final bill or settlements. */
export function quickApproxTotal(stores: QuickStore[]): number {
  return stores.reduce((sum, store) =>
    sum + (store.pricedItems ?? []).reduce((n, item) =>
      n + item.qty * item.unitPricePiastres, 0), 0);
}

/** أقصى عدد صور «صوّر طلبك» في الطلب الواحد. */
export const QUICK_MAX_CUSTOMER_IMAGES = 3;
/** تسجيل صوتي واحد اختياري؛ الرابط لازم يكون فيديو Cloudinary في مجلد العميل الخاص. */
export function validateQuickVoice(input: unknown, isOwnVoice: (url: string) => boolean): string {
  if (input === undefined || input === null || input === "") return "";
  if (typeof input !== "string" || input.length > 450 || !isOwnVoice(input)) {
    fail(400, "invalid_voice", "التسجيل الصوتي غير صالح. سجّله من التطبيق تاني.");
  }
  return input;
}


/**
 * صور «صوّر طلبك»: لحد 3 روابط، كل رابط لازم يعدّي [isOwnImage]
 * (Cloudinary + مجلد العميل نفسه). غياب الحقل = مفيش صور.
 */
export function validateQuickImages(input: unknown, isOwnImage: (url: string) => boolean): string[] {
  if (input === undefined || input === null) return [];
  if (!Array.isArray(input) || input.length > QUICK_MAX_CUSTOMER_IMAGES) {
    fail(400, "invalid_images", `ممكن ترفع لحد ${QUICK_MAX_CUSTOMER_IMAGES} صور بس.`);
  }
  const urls = input.map((value) => (typeof value === "string" ? value.trim() : ""));
  if (urls.some((url) => !url || url.length > 450 || !isOwnImage(url)) ||
      new Set(urls).size !== urls.length) {
    fail(400, "invalid_images", "صورة الطلب غير صالحة. ارفعها تاني.");
  }
  return urls;
}

/**
 * المحلات: من 1 لـ10، اسم المحل اختياري (فاضي = المندوب يختار)، والطلبات نص حر.
 * لو العميل باعت صور للطلب [hasImages]، الكتابة بقت اختيارية (الصورة هي الطلب).
 */
export function validateQuickStores(input: unknown, hasImages = false): QuickStore[] {
  if (hasImages && (input === undefined || input === null ||
      (Array.isArray(input) && input.length === 0))) {
    return [{ name: "", items: "" }];
  }
  if (!Array.isArray(input) || input.length < 1 || input.length > QUICK_LIMITS.maxStores) {
    fail(400, "invalid_stores", "اكتب طلباتك لمحل واحد على الأقل (بحد أقصى 10 محلات).");
  }
  return input.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      fail(400, "invalid_stores", "بيانات المحل غير صحيحة.");
    }
    const e = entry as JsonMap;
    const name = typeof e.name === "string" ? e.name.trim() : "";
    const items = typeof e.items === "string" ? e.items.trim() : "";
    if (name.length > QUICK_LIMITS.maxStoreName || items.length > QUICK_LIMITS.maxItemsText ||
        (!hasImages && items.length < 1 &&
          !(Array.isArray(e.pricedItems) && e.pricedItems.length > 0))) {
      fail(400, "invalid_stores", "راجع اسم المحل والطلبات (الطلبات من 1 لـ500 حرف).");
    }
    // null أو غياب الحقل = محل من غير أصناف مسعّرة (نص حر بس).
    if (e.pricedItems === undefined || e.pricedItems === null) return { name, items };
    if (!Array.isArray(e.pricedItems) || e.pricedItems.length < 1 ||
        e.pricedItems.length > 30) {
      fail(400, "invalid_priced_items", "عدد الأصناف المسعّرة لازم يكون من 1 إلى 30.");
    }
    const pricedItems: QuickPricedItem[] = e.pricedItems.map((entry) => {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
        fail(400, "invalid_priced_items", "بيانات الصنف المسعّر غير صحيحة.");
      }
      const item = entry as JsonMap;
      const itemName = typeof item.name === "string" ? item.name.trim() : "";
      const qty = intIn(item.qty, 1, 99);
      const price = intIn(item.unitPricePiastres, 0, 1_000_000);
      if (!itemName || itemName.length > 100 || qty === null || price === null) {
        fail(400, "invalid_priced_items", "راجع اسم الصنف والكمية والسعر.");
      }
      return { name: itemName, qty, unitPricePiastres: price };
    });
    return { name, items, pricedItems };
  });
}

export function validateQuickNotes(input: unknown): string {
  const notes = typeof input === "string" ? input.trim() : "";
  if (notes.length > QUICK_LIMITS.maxNotes) fail(400, "invalid_notes", "الملاحظات طويلة.");
  return notes;
}

function asMap(value: unknown): JsonMap {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonMap : {};
}

function numOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) ? value : null;
}

const EMPTY_ADVANCE = { amountPiastres: null, reference: "", sentAt: null, confirmedAt: null };

/** حقول الكشف النهائي بتتمسح لما العميل يرفض الكشف (لازم كشف وموافقة جديدين). */
const CLEARED_SUMMARY = {
  totals: null,
  summarySubmittedAt: null,
  summaryApprovedAt: null,
};

export function newQuickOrder(input: {
  uid: string;
  customerFirstName: string;
  area: string;
  notes: string;
  stores: QuickStore[];
  settings: QuickSettings;
  customerImages?: string[];
  customerVoiceUrl?: string;
}): JsonMap {
  return {
    userId: input.uid,
    customerFirstName: input.customerFirstName,
    area: input.area,
    notes: input.notes,
    stores: input.stores,
    // صور «صوّر طلبك» (Cloudinary). بتتمسح مراجعها وملفاتها عند التسليم.
    customerImages: input.customerImages ?? [],
    // الصوت في private/contact بس لحماية خصوصية محتواه قبل قبول المندوب.
    hasCustomerVoice: Boolean(input.customerVoiceUrl),
    approxTotalPiastres: quickApproxTotal(input.stores),
    status: "open",
    courierId: "",
    courierName: "",
    // نسخة من إعدادات الإدارة لحظة الإنشاء: أي تعديل بعد كده ما يغيّرش طلب شغال.
    policy: {
      prepaidThresholdPiastres: input.settings.prepaidThresholdPiastres,
      maximumAdvancePiastres: input.settings.maximumAdvancePiastres,
      maximumDeliveryPiastres: input.settings.maximumDeliveryPiastres,
    },
    estimatedPurchasesPiastres: null,
    paymentMode: "",
    advance: { ...EMPTY_ADVANCE },
    receipts: [],
    deliveryPiastres: null,
    totals: null,
    summaryRevision: 0,
    rev: 1,
  };
}

function receiptUrlOk(url: unknown, orderId: string, cloudName?: string): boolean {
  if (typeof url !== "string" || url.length > 450) return false;
  const cloud = cloudName ? cloudName.replace(/[^A-Za-z0-9_-]/g, "") : "[^/]+";
  const id = orderId.replace(/[^A-Za-z0-9_-]/g, "");
  if (!id || id !== orderId) return false;
  return new RegExp(
    `^https://res\\.cloudinary\\.com/${cloud}/image/upload/(?:v[0-9]+/)?quick_receipts/${id}/[A-Za-z0-9_-]+\\.(?:jpg|jpeg|png|webp)$`,
  ).test(url);
}

/** العميل يلغي قبل بدء الشراء بس (المندوب بيدفع من جيبه من أول الشراء). */
const CUSTOMER_CANCELLABLE: readonly string[] = ["open", "accepted"];

/** الحالات اللي المندوب المعيّن بيقرا فيها رقم العميل وعنوانه (نفس شرط القواعد). */
export const QUICK_CONTACT_STATUSES: readonly string[] = [
  "accepted", "awaiting_advance", "purchasing", "summary_pending", "summary_approved",
];

/** رمز التسليم بيظهر للعميل بعد ما يوافق على الكشف النهائي بس. */
// summary_pending قديمة: لا نعطل استلام طلب سابق بسبب إزالة خطوة الموافقة.
export const QUICK_PIN_STATUSES: readonly string[] = ["summary_pending", "summary_approved"];

export interface QuickTotals {
  purchases: number;
  serviceFee: number;
  delivery: number;
  prepaid: number;
  /** موجب = العميل يدفع للمندوب عند التسليم، سالب = المندوب يرجّع للعميل. */
  due: number;
}

/** الكشف النهائي: مجموع الفواتير + الأجرة + رسوم وصّلي − المقدم المؤكد. */
export function quickTotals(receipts: unknown, deliveryPiastres: number, advance: unknown): QuickTotals {
  const list = Array.isArray(receipts) ? receipts : [];
  let purchases = 0;
  for (const r of list) {
    const amount = numOrNull(asMap(r).amountPiastres);
    if (amount === null || amount < 0) fail(409, "invalid_receipt", "قيمة فاتورة غير صالحة.");
    purchases += amount;
  }
  const adv = asMap(advance);
  const prepaid = adv.confirmedAt instanceof Date ? (numOrNull(adv.amountPiastres) ?? 0) : 0;
  const serviceFee = quickServiceFee(purchases);
  return {
    purchases,
    serviceFee,
    delivery: deliveryPiastres,
    prepaid,
    due: purchases + serviceFee + deliveryPiastres - prepaid,
  };
}

/**
 * يحسب التعديل المطلوب على مستند الطلب لعملية واحدة، أو يرمي QuickRuleError.
 * الـWorker بيكتب الناتج بشرط updateTime، فعمليتين متزامنتين ما يعدّوش الاتنين.
 */
export function applyQuickAction(
  order: JsonMap,
  action: string,
  actor: QuickActor,
  body: JsonMap,
  ctx: QuickContext,
): JsonMap {
  if (!(QUICK_ACTIONS as readonly string[]).includes(action)) {
    fail(404, "unknown_action", "العملية غير معروفة.");
  }
  const status = String(order.status ?? "");
  if (status === "delivered" || status === "cancelled") {
    fail(409, "final", "الطلب انتهى ومينفعش يتعدّل.");
  }
  const isCustomer = actor.role === "customer" && actor.uid === order.userId;
  const isAssigned = actor.role === "courier" && actor.uid !== "" && actor.uid === order.courierId;
  const isAdmin = actor.role === "admin";
  const policy = asMap(order.policy);
  const advance = asMap(order.advance);
  const receipts = Array.isArray(order.receipts) ? order.receipts as JsonMap[] : [];
  const now = ctx.now;
  const rev = (numOrNull(order.rev) ?? 0) + 1;
  const summaryRevision = numOrNull(order.summaryRevision) ?? 0;
  const maxAdvance = numOrNull(policy.maximumAdvancePiastres) ?? QUICK_DEFAULTS.maximumAdvancePiastres;
  const maxDelivery = numOrNull(policy.maximumDeliveryPiastres) ?? QUICK_DEFAULTS.maximumDeliveryPiastres;
  const forbidden = (): never => fail(403, "forbidden", "مش مسموح لك بالعملية دي على الطلب ده.");
  const wrongState = (): never => fail(409, "invalid_state", "حالة الطلب اتغيرت. حدّث الصفحة وحاول تاني.");
  const reasonOf = (value: unknown): string => {
    const reason = typeof value === "string" ? value.trim() : "";
    if (reason.length > QUICK_LIMITS.maxReason) fail(400, "invalid_reason", "السبب طويل.");
    return reason;
  };

  switch (action as QuickAction) {
    case "edit": {
      // قبل القبول بس. بعد القبول أي تغيير بيتم بالتليفون مع المندوب.
      if (!isCustomer) forbidden();
      if (status !== "open") {
        fail(409, "edit_after_accept", "المندوب قبل الطلب. كلّمه بالتليفون لأي تغيير.");
      }
      const stores = validateQuickStores(body.stores);
      return { stores, approxTotalPiastres: quickApproxTotal(stores), notes: validateQuickNotes(body.notes), rev };
    }

    case "edit-voice": {
      // تعديل الصوت/حذفه مسموح لصاحب الطلب قبل قبول المندوب فقط.
      // الـWorker بيتأكد من ملكية رابط Cloudinary قبل الوصول هنا.
      if (!isCustomer) forbidden();
      if (status !== "open") {
        fail(409, "edit_after_accept", "بعد قبول المندوب لا يمكن تغيير التسجيل. كلّمه بالتليفون.");
      }
      if (typeof body.customerVoiceUrl !== "string") {
        fail(400, "invalid_voice", "حدد التسجيل الجديد أو احذف التسجيل.");
      }
      const voice = body.customerVoiceUrl;
      // لازم يفضل فيه طلب مكتوب أو صورة أو تسجيل بعد الحذف.
      validateQuickStores(order.stores, quickCustomerImages(order).length > 0 || voice.length > 0);
      return { hasCustomerVoice: voice.length > 0, rev };
    }

    case "cancel": {
      const reason = reasonOf(body.reason);
      if (isCustomer) {
        if (!CUSTOMER_CANCELLABLE.includes(status)) {
          fail(409, "not_cancellable", "المندوب بدأ الشراء. تواصل معاه أو مع الإدارة لو فيه مشكلة.");
        }
      } else if (!isAdmin) {
        forbidden();
      }
      return {
        status: "cancelled",
        cancelledAt: now,
        cancelledBy: isCustomer ? "customer" : "admin",
        cancelReason: reason,
        // العميل كان قال إنه حوّل: المندوب لازم يرجّع المبلغ (الإدارة بتتابع).
        advanceRefundDue: advance.sentAt instanceof Date,
        rev,
      };
    }

    case "accept": {
      if (actor.role !== "courier" || actor.quickEnabled !== true) {
        fail(403, "not_quick_courier", "حسابك مش معتمد للطلبات السريعة.");
      }
      if (actor.uid === order.userId) fail(403, "own_order", "مينفعش تقبل طلبك انت.");
      if (status !== "open" || String(order.courierId ?? "") !== "") {
        fail(409, "already_taken", "الطلب اتقبل من مندوب تاني.");
      }
      return {
        status: "accepted",
        courierId: actor.uid,
        courierName: String(actor.name ?? "").trim().slice(0, 80),
        acceptedAt: now,
        rev,
      };
    }

    case "release": {
      if (!isAssigned) forbidden();
      // لو العميل حوّل مقدم (حتى قبل الشراء) المندوب ما يسيبش الطلب والفلوس معاه: الإدارة تتدخل.
      if (status !== "accepted" || advance.sentAt instanceof Date) {
        fail(409, "not_releasable", "مينفعش تسيب الطلب بعد التحويل أو بدء الشراء. تواصل مع الإدارة.");
      }
      return {
        status: "open",
        courierId: "",
        courierName: "",
        acceptedAt: null,
        estimatedPurchasesPiastres: null,
        paymentMode: "",
        advance: { ...EMPTY_ADVANCE },
        rev,
      };
    }

    case "start-purchase": {
      // بعد المكالمة: المندوب يكتب رقم واحد = تقدير المشتريات (للعرض والإدارة). الشراء يبدأ على طول.
      if (!isAssigned) forbidden();
      if (status !== "accepted") wrongState();
      const estimate = intIn(body.estimatedPurchasesPiastres, 100, maxAdvance);
      if (estimate === null) {
        fail(400, "invalid_estimate", "تقدير المشتريات خارج سقف الطلبات السريعة.");
      }
      const mode = "cod"; // المندوب يمول المشتريات؛ المقدم اختياري مهما كان التقدير.
      return {
        estimatedPurchasesPiastres: estimate,
        paymentMode: mode,
        status: "purchasing",
        rev,
      };
    }

    case "advance-sent": {
      if (!isCustomer) forbidden();
      if (!["accepted", "purchasing"].includes(status) || advance.sentAt instanceof Date) wrongState();
      const amount = intIn(body.amountPiastres, 100, maxAdvance);
      if (amount === null) fail(400, "invalid_advance", "مبلغ التحويل خارج السقف المسموح.");
      const reference = typeof body.reference === "string" ? body.reference.trim() : "";
      if (reference.length > QUICK_LIMITS.maxReference) fail(400, "invalid_reference", "رقم العملية طويل.");
      return {
        advance: { amountPiastres: amount, reference, sentAt: now, confirmedAt: null },
        rev,
      };
    }

    case "advance-received": {
      // مقدم اختياري: بيتخصم من الكشف بس بعد ما المندوب يأكد إن المبلغ وصله.
      if (!isAssigned) forbidden();
      if (status !== "purchasing" || !(advance.sentAt instanceof Date) || advance.confirmedAt instanceof Date) wrongState();
      const amount = intIn(body.amountPiastres, 100, maxAdvance);
      if (amount === null) fail(400, "invalid_advance", "المبلغ المستلم غير صالح.");
      return {
        advance: { ...advance, amountPiastres: amount, confirmedAt: now },
        rev,
      };
    }

    case "receipt": {
      // صورة الفاتورة + مبلغها رقم. اسم المحل اختياري (المندوب مش لازم يكتب).
      if (!isAssigned) forbidden();
      if (status !== "purchasing") wrongState();
      if (receipts.length >= QUICK_LIMITS.maxReceipts) {
        fail(409, "too_many_receipts", "وصلت لأقصى عدد فواتير.");
      }
      const amount = intIn(body.amountPiastres, 1, QUICK_LIMITS.maxReceiptPiastres);
      if (amount === null) fail(400, "invalid_receipt", "اكتب مبلغ الفاتورة.");
      const storeName = typeof body.storeName === "string" ? body.storeName.trim() : "";
      if (storeName.length > QUICK_LIMITS.maxStoreName) fail(400, "invalid_receipt", "اسم المحل طويل.");
      if (!receiptUrlOk(body.imageUrl, ctx.orderId, ctx.cloudName)) {
        fail(400, "invalid_receipt_image", "صوّر الفاتورة من التطبيق الأول.");
      }
      return {
        receipts: [...receipts, { storeName, amountPiastres: amount, imageUrl: body.imageUrl, uploadedAt: now }],
        rev,
      };
    }

    case "receipt-remove": {
      if (!isAssigned) forbidden();
      if (status !== "purchasing") wrongState();
      const index = intIn(body.index, 0, receipts.length - 1);
      if (index === null) fail(400, "invalid_index", "الفاتورة غير موجودة.");
      return { receipts: receipts.filter((_, i) => i !== index), rev };
    }

    case "submit-summary": {
      // المندوب يكتب الأجرة رقم واحد، والبرنامج يحسب الكشف من الفواتير.
      if (!isAssigned) forbidden();
      if (status !== "purchasing") wrongState();
      if (receipts.length < 1) fail(409, "no_receipts", "صوّر فاتورة واحدة على الأقل.");
      const delivery = intIn(body.deliveryPiastres, 0, maxDelivery);
      if (delivery === null) fail(400, "invalid_delivery", "أجرة التوصيل خارج الحد المسموح.");
      const totals = quickTotals(receipts, delivery, advance);
      return {
        // الكشف للعرض فقط؛ لا ننتظر موافقة العميل على الفاتورة.
        status: "summary_approved",
        deliveryPiastres: delivery,
        totals,
        summaryRevision: summaryRevision + 1,
        summarySubmittedAt: now,
        summaryApprovedAt: null,
        // للإدارة بس: الزيادة عن التقدير على مسؤولية المندوب لو العميل رفض.
        overEstimatePiastres: Math.max(0, totals.purchases - (numOrNull(order.estimatedPurchasesPiastres) ?? 0)),
        rev,
      };
    }

    case "approve-summary": {
      if (!isCustomer) forbidden();
      if (status !== "summary_pending") wrongState();
      // الموافقة على نفس الكشف اللي العميل شافه (لو المندوب بعت كشف أحدث، يراجعه الأول).
      if (body.expectedSummaryRevision !== summaryRevision) {
        fail(409, "stale_summary", "الكشف اتغيّر. راجع الكشف الجديد.");
      }
      return { status: "summary_approved", summaryApprovedAt: now, rev };
    }

    case "reject-summary": {
      // رفض = مفيش تسليم ولا تسوية. الطلب يرجع للمندوب يتصل بالعميل ويعدّل الكشف، أو الإدارة تتدخل.
      if (!isCustomer) forbidden();
      if (status !== "summary_pending") wrongState();
      return {
        status: "purchasing",
        ...CLEARED_SUMMARY,
        summaryRejectedAt: now,
        summaryRejectReason: reasonOf(body.reason),
        summaryRejections: (numOrNull(order.summaryRejections) ?? 0) + 1,
        rev,
      };
    }

  }
  return fail(404, "unknown_action", "العملية غير معروفة.");
}

/** شروط تأكيد التسليم بالرمز (قبل التحقق من الرمز نفسه). */
export function quickDeliveryBlocker(order: JsonMap, uid: string): string | null {
  if (order.courierId !== uid) return "الطلب غير معيّن لحسابك.";
  if (!QUICK_PIN_STATUSES.includes(String(order.status))) {
    return "الكشف النهائي لم يجهز بعد.";
  }
  if (!order.totals || typeof order.totals !== "object") return "الكشف النهائي غير موجود.";
  return null;
}

/**
 * التعديل عند التسليم. رسوم وصّلي بتتسجل على المندوب (courierOwedPiastres) على نفس مستند الطلب،
 * فالطلب المسلّم نفسه هو قيد التسوية (مرة واحدة لكل طلب، ومفيش تكرار).
 */
export function quickDeliveredPatch(order: JsonMap, uid: string, now: Date): JsonMap {
  const totals = asMap(order.totals);
  return {
    status: "delivered",
    deliveredAt: now,
    deliveredBy: uid,
    courierOwedPiastres: numOrNull(totals.serviceFee) ?? 0,
    collectedPiastres: numOrNull(totals.due) ?? 0,
    // صور العميل بتتشال من الطلب لحظة تأكيد الاستلام (والملفات بتتمسح من Cloudinary).
    customerImages: [],
    hasCustomerVoice: false,
    rev: (numOrNull(order.rev) ?? 0) + 1,
  };
}

/** صور العميل اللي محتاجة تتمسح من Cloudinary بعد التسليم. */
export function quickCustomerImages(order: JsonMap): string[] {
  const raw = order.customerImages;
  return Array.isArray(raw) ? raw.filter((v): v is string => typeof v === "string" && v.length > 0) : [];
}

/** رابط صوت العميل من private/contact، لا من الطلب العام. */
export function quickCustomerVoice(order: JsonMap): string {
  return typeof order.customerVoiceUrl === "string" ? order.customerVoiceUrl : "";
}
