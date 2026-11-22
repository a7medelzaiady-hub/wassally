/**
 * «طلباتك على السريع»: منطق صافي (من غير Firestore ولا شبكة) عشان يتختبر لوحده.
 * الـWorker هو الكاتب الوحيد لـ quick_orders؛ القواعد بتمنع أي كتابة من التطبيق.
 * كل المبالغ بالقروش (أرقام صحيحة) عشان نتجنب كسور العشرية.
 *
 * المبدأ: الاتفاق على أي تغيير بيتم بالتليفون بين العميل والمندوب. التطبيق بيثبت بس:
 *   1) المقدم قبل الشراء لو التقدير فوق الحد (حاجز أمان مالي).
 *   2) كشف نهائي واحد (فواتير + أجرة + رسوم − مقدم) يوافق عليه العميل قبل رمز التسليم.
 * المندوب ما بيكتبش نصوص: أرقام وصور فواتير بس.
 *
 * دورة الطلب:
 *   open ← (accept) accepted ← (start-purchase + تقدير) purchasing          [حتى الحد: دفع عند الاستلام]
 *                                                ↘ awaiting_advance ← (advance-sent ثم advance-received) purchasing
 *   purchasing ← (receipt × n ثم submit-summary + أجرة) summary_pending
 *   summary_pending ← (approve-summary) summary_approved ← (deliver بالرمز) delivered
 *   summary_pending ← (reject-summary) purchasing   |   summary_approved ← (reopen-summary) purchasing
 *   cancelled: العميل قبل الشراء، أو الإدارة في أي وقت قبل التسليم.
 */

type JsonMap = Record<string, unknown>;

export const QUICK_STATUSES = [
  "open", "accepted", "awaiting_advance", "purchasing", "summary_pending", "summary_approved",
  "delivered", "cancelled",
] as const;
export type QuickStatus = typeof QUICK_STATUSES[number];

export const QUICK_ACTIONS = [
  "edit", "cancel", "accept", "release", "start-purchase",
  "advance-sent", "advance-received", "receipt", "receipt-remove",
  "submit-summary", "approve-summary", "reject-summary", "reopen-summary",
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

/** الخدمة مقفولة لحد ما الإدارة تكتب enabled: true. أي رقم غير صالح بيرجع للافتراضي. */
export function resolveQuickSettings(raw: JsonMap | null): QuickSettings {
  const r = raw ?? {};
  return {
    enabled: r.enabled === true,
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

export interface QuickStore { name: string; items: string }

/** المحلات: من 1 لـ10، اسم المحل اختياري (فاضي = المندوب يختار)، والطلبات نص حر. */
export function validateQuickStores(input: unknown): QuickStore[] {
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
    if (name.length > QUICK_LIMITS.maxStoreName || items.length < 1 ||
        items.length > QUICK_LIMITS.maxItemsText) {
      fail(400, "invalid_stores", "راجع اسم المحل والطلبات (الطلبات من 1 لـ500 حرف).");
    }
    return { name, items };
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

/** حقول الكشف النهائي بتتمسح لما الكشف يترفض أو يتفتح تاني (لازم كشف وموافقة جديدين). */
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
}): JsonMap {
  return {
    userId: input.uid,
    customerFirstName: input.customerFirstName,
    area: input.area,
    notes: input.notes,
    stores: input.stores,
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

const CUSTOMER_CANCELLABLE: readonly string[] = ["open", "accepted", "awaiting_advance"];

/** الحالات اللي المندوب المعيّن بيقرا فيها رقم العميل وعنوانه (نفس شرط القواعد). */
export const QUICK_CONTACT_STATUSES: readonly string[] = [
  "accepted", "awaiting_advance", "purchasing", "summary_pending", "summary_approved",
];

/** رمز التسليم بيظهر للعميل بعد ما يوافق على الكشف النهائي بس. */
export const QUICK_PIN_STATUSES: readonly string[] = ["summary_approved"];

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
  const threshold = numOrNull(policy.prepaidThresholdPiastres) ?? QUICK_DEFAULTS.prepaidThresholdPiastres;
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
      return { stores: validateQuickStores(body.stores), notes: validateQuickNotes(body.notes), rev };
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
      if (!(status === "accepted" || (status === "awaiting_advance" && !(advance.sentAt instanceof Date)))) {
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
      // بعد المكالمة: المندوب يكتب رقم واحد = تقدير المشتريات. ده بيحدد الدفع عند الاستلام أو المقدم.
      if (!isAssigned) forbidden();
      if (status !== "accepted") wrongState();
      const estimate = intIn(body.estimatedPurchasesPiastres, 100, Math.max(threshold, maxAdvance));
      if (estimate === null) {
        fail(400, "invalid_estimate", "تقدير المشتريات خارج سقف الطلبات السريعة.");
      }
      const mode = estimate > threshold ? "advance" : "cod";
      return {
        estimatedPurchasesPiastres: estimate,
        paymentMode: mode,
        status: mode === "advance" ? "awaiting_advance" : "purchasing",
        rev,
      };
    }

    case "advance-sent": {
      if (!isCustomer) forbidden();
      if (status !== "awaiting_advance" || advance.confirmedAt instanceof Date) wrongState();
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
      // حاجز أمان: مفيش شراء فوق الحد قبل ما المندوب يأكد إن المقدم وصله.
      if (!isAssigned) forbidden();
      if (status !== "awaiting_advance" || !(advance.sentAt instanceof Date)) wrongState();
      const amount = intIn(body.amountPiastres, 100, maxAdvance);
      if (amount === null) fail(400, "invalid_advance", "المبلغ المستلم غير صالح.");
      return {
        advance: { ...advance, amountPiastres: amount, confirmedAt: now },
        status: "purchasing",
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
        status: "summary_pending",
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

    case "reopen-summary": {
      // أي تغيير بعد موافقة العميل = كشف جديد وموافقة جديدة.
      if (!isAssigned) forbidden();
      if (status !== "summary_approved" && status !== "summary_pending") wrongState();
      return { status: "purchasing", ...CLEARED_SUMMARY, rev };
    }
  }
  return fail(404, "unknown_action", "العملية غير معروفة.");
}

/** شروط تأكيد التسليم بالرمز (قبل التحقق من الرمز نفسه). */
export function quickDeliveryBlocker(order: JsonMap, uid: string): string | null {
  if (order.courierId !== uid) return "الطلب غير معيّن لحسابك.";
  if (order.status !== "summary_approved" || !(order.summaryApprovedAt instanceof Date)) {
    return "العميل لازم يوافق على الكشف النهائي الأول.";
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
    rev: (numOrNull(order.rev) ?? 0) + 1,
  };
}
