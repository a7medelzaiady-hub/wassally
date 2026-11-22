/**
 * «طلباتك على السريع»: منطق صافي (من غير Firestore ولا شبكة) عشان يتختبر لوحده.
 * الـWorker هو الكاتب الوحيد لـ quick_orders؛ القواعد بتمنع أي كتابة من التطبيق.
 * كل المبالغ بالقروش (أرقام صحيحة) عشان نتجنب كسور العشرية.
 *
 * دورة الطلب:
 *   open ← (accept) accepted ← (propose ثم approve) purchasing  [دفع عند الاستلام]
 *                                               ↘ awaiting_advance ← (advance-sent ثم advance-received) purchasing
 *   purchasing ← (receipt × n ثم lock-receipts) receipts_locked ← (deliver بالرمز) delivered
 *   cancelled: العميل قبل الشراء، أو الإدارة في أي وقت قبل التسليم.
 */

type JsonMap = Record<string, unknown>;

export const QUICK_STATUSES = [
  "open", "accepted", "awaiting_advance", "purchasing", "receipts_locked", "delivered", "cancelled",
] as const;
export type QuickStatus = typeof QUICK_STATUSES[number];

export const QUICK_ACTIONS = [
  "edit", "cancel", "accept", "release", "propose", "approve",
  "advance-sent", "advance-received", "receipt", "receipt-remove", "lock-receipts",
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
  maxCancelReason: 200,
  maxReceipts: 10,
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
  maxProposals: 3,
} as const;

export interface QuickSettings {
  enabled: boolean;
  prepaidThresholdPiastres: number;
  maximumAdvancePiastres: number;
  maximumDeliveryPiastres: number;
  maxPerDay: number;
  maxProposals: number;
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
    maxProposals: intIn(r.maxProposals, 1, 10) ?? QUICK_DEFAULTS.maxProposals,
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

function resetQuote(previous: unknown, courierId: string): JsonMap {
  const old = asMap(previous);
  return {
    courierId,
    revision: (numOrNull(old.revision) ?? 0) + 1,
    proposedDeliveryPiastres: null,
    estimatedPurchasesPiastres: null,
    agreedDeliveryPiastres: null,
    proposals: 0,
  };
}

const EMPTY_ADVANCE = { amountPiastres: null, reference: "", sentAt: null, confirmedAt: null };

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
    quote: resetQuote({ revision: 0 }, ""),
    // نسخة من إعدادات الإدارة لحظة الإنشاء: أي تعديل بعد كده ما يغيّرش طلب شغال.
    policy: {
      prepaidThresholdPiastres: input.settings.prepaidThresholdPiastres,
      maximumAdvancePiastres: input.settings.maximumAdvancePiastres,
      maximumDeliveryPiastres: input.settings.maximumDeliveryPiastres,
      maxProposals: input.settings.maxProposals,
    },
    paymentMode: "",
    advance: { ...EMPTY_ADVANCE },
    receipts: [],
    totals: null,
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

/** الحالات اللي العميل بيشوف فيها رمز التسليم (من القبول لحد التسليم). */
export const QUICK_PIN_STATUSES: readonly string[] = [
  "accepted", "awaiting_advance", "purchasing", "receipts_locked",
];

/** الحالات اللي المندوب المعيّن بيقرا فيها رقم العميل وعنوانه (نفس شرط القواعد). */
export const QUICK_CONTACT_STATUSES = QUICK_PIN_STATUSES;

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
  const quote = asMap(order.quote);
  const policy = asMap(order.policy);
  const advance = asMap(order.advance);
  const receipts = Array.isArray(order.receipts) ? order.receipts as JsonMap[] : [];
  const now = ctx.now;
  const rev = (numOrNull(order.rev) ?? 0) + 1;
  const threshold = numOrNull(policy.prepaidThresholdPiastres) ?? QUICK_DEFAULTS.prepaidThresholdPiastres;
  const maxAdvance = numOrNull(policy.maximumAdvancePiastres) ?? QUICK_DEFAULTS.maximumAdvancePiastres;
  const maxDelivery = numOrNull(policy.maximumDeliveryPiastres) ?? QUICK_DEFAULTS.maximumDeliveryPiastres;
  const maxProposals = numOrNull(policy.maxProposals) ?? QUICK_DEFAULTS.maxProposals;
  const forbidden = (): never => fail(403, "forbidden", "مش مسموح لك بالعملية دي على الطلب ده.");
  const wrongState = (): never => fail(409, "invalid_state", "حالة الطلب اتغيرت. حدّث الصفحة وحاول تاني.");

  switch (action as QuickAction) {
    case "edit": {
      if (!isCustomer) forbidden();
      if (status !== "open" && status !== "accepted") wrongState();
      const patch: JsonMap = {
        stores: validateQuickStores(body.stores),
        notes: validateQuickNotes(body.notes),
        rev,
      };
      // بعد القبول: أي تعديل في الطلبات بيلغي عرض المندوب، ولازم يعرض من جديد والعميل يوافق.
      if (status === "accepted") patch.quote = resetQuote(quote, String(order.courierId ?? ""));
      return patch;
    }

    case "cancel": {
      const reason = typeof body.reason === "string" ? body.reason.trim() : "";
      if (reason.length > QUICK_LIMITS.maxCancelReason) fail(400, "invalid_reason", "سبب الإلغاء طويل.");
      if (isCustomer) {
        if (!CUSTOMER_CANCELLABLE.includes(status)) {
          fail(409, "not_cancellable", "المندوب بدأ الشراء. تواصل مع الإدارة لو فيه مشكلة.");
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
        advanceRefundDue: advance.sentAt instanceof Date || numOrNull(advance.amountPiastres) !== null,
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
        quote: resetQuote(quote, actor.uid),
        rev,
      };
    }

    case "release": {
      if (!isAssigned) forbidden();
      const advanceTouched = advance.sentAt instanceof Date;
      if (!(status === "accepted" || (status === "awaiting_advance" && !advanceTouched))) {
        fail(409, "not_releasable", "مينفعش تسيب الطلب بعد التحويل أو بدء الشراء. تواصل مع الإدارة.");
      }
      return {
        status: "open",
        courierId: "",
        courierName: "",
        acceptedAt: null,
        approvedAt: null,
        quote: resetQuote(quote, ""),
        paymentMode: "",
        advance: { ...EMPTY_ADVANCE },
        rev,
      };
    }

    case "propose": {
      if (!isAssigned) forbidden();
      if (status !== "accepted" || quote.courierId !== actor.uid ||
          numOrNull(quote.agreedDeliveryPiastres) !== null) {
        wrongState();
      }
      const proposals = numOrNull(quote.proposals) ?? 0;
      if (proposals >= maxProposals) {
        fail(409, "too_many_proposals", "وصلت لأقصى عدد عروض. اتفق مع العميل أو سيب الطلب.");
      }
      const delivery = intIn(body.deliveryPiastres, 0, maxDelivery);
      if (delivery === null) fail(400, "invalid_delivery", "أجر التوصيل خارج الحد المسموح.");
      const estimate = intIn(body.estimatedPurchasesPiastres, 100, Math.max(threshold, maxAdvance));
      if (estimate === null) {
        fail(400, "invalid_estimate", "تقدير المشتريات خارج سقف الطلبات السريعة.");
      }
      return {
        quote: {
          courierId: actor.uid,
          revision: (numOrNull(quote.revision) ?? 0) + 1,
          proposedDeliveryPiastres: delivery,
          estimatedPurchasesPiastres: estimate,
          agreedDeliveryPiastres: null,
          proposals: proposals + 1,
        },
        rev,
      };
    }

    case "approve": {
      if (!isCustomer) forbidden();
      const proposed = numOrNull(quote.proposedDeliveryPiastres);
      const estimate = numOrNull(quote.estimatedPurchasesPiastres);
      if (status !== "accepted" || proposed === null || estimate === null ||
          quote.courierId !== order.courierId || numOrNull(quote.agreedDeliveryPiastres) !== null) {
        wrongState();
      }
      if (body.expectedRevision !== quote.revision) {
        fail(409, "stale_quote", "المندوب غيّر العرض. راجع العرض الجديد.");
      }
      const mode = estimate! > threshold ? "advance" : "cod";
      return {
        quote: {
          ...quote,
          revision: (numOrNull(quote.revision) ?? 0) + 1,
          agreedDeliveryPiastres: proposed,
        },
        paymentMode: mode,
        status: mode === "advance" ? "awaiting_advance" : "purchasing",
        approvedAt: now,
        rev,
      };
    }

    case "advance-sent": {
      if (!isCustomer) forbidden();
      if (status !== "awaiting_advance") wrongState();
      if (advance.confirmedAt instanceof Date) wrongState();
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
      if (!isAssigned) forbidden();
      if (status !== "awaiting_advance" || !(advance.sentAt instanceof Date)) wrongState();
      // المندوب بيأكد المبلغ اللي وصله فعلًا، وده المعتمد في الحساب النهائي.
      const amount = intIn(body.amountPiastres, 100, maxAdvance);
      if (amount === null) fail(400, "invalid_advance", "المبلغ المستلم غير صالح.");
      return {
        advance: { ...advance, amountPiastres: amount, confirmedAt: now },
        status: "purchasing",
        rev,
      };
    }

    case "receipt": {
      if (!isAssigned) forbidden();
      if (status !== "purchasing") wrongState();
      if (receipts.length >= QUICK_LIMITS.maxReceipts) {
        fail(409, "too_many_receipts", "وصلت لأقصى عدد فواتير.");
      }
      const storeName = typeof body.storeName === "string" ? body.storeName.trim() : "";
      const amount = intIn(body.amountPiastres, 1, QUICK_LIMITS.maxReceiptPiastres);
      if (storeName.length < 1 || storeName.length > QUICK_LIMITS.maxStoreName || amount === null) {
        fail(400, "invalid_receipt", "اكتب اسم المحل وقيمة الفاتورة.");
      }
      if (!receiptUrlOk(body.imageUrl, ctx.orderId, ctx.cloudName)) {
        fail(400, "invalid_receipt_image", "ارفع صورة الفاتورة من التطبيق الأول.");
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

    case "lock-receipts": {
      if (!isAssigned) forbidden();
      if (status !== "purchasing") wrongState();
      if (receipts.length < 1) fail(409, "no_receipts", "ارفع فاتورة واحدة على الأقل.");
      const totals = quickTotals(order);
      const estimate = numOrNull(quote.estimatedPurchasesPiastres) ?? 0;
      return {
        status: "receipts_locked",
        receiptsLockedAt: now,
        totals,
        // للإدارة بس: الزيادة عن المتفق عليه على مسؤولية المندوب لو العميل رفض يدفعها.
        overEstimatePiastres: Math.max(0, totals.purchases - estimate),
        rev,
      };
    }
  }
  return fail(404, "unknown_action", "العملية غير معروفة.");
}

export interface QuickTotals {
  purchases: number;
  serviceFee: number;
  delivery: number;
  prepaid: number;
  /** موجب = العميل يدفع للمندوب عند التسليم، سالب = المندوب يرجّع للعميل. */
  due: number;
}

export function quickTotals(order: JsonMap): QuickTotals {
  const receipts = Array.isArray(order.receipts) ? order.receipts as JsonMap[] : [];
  let purchases = 0;
  for (const r of receipts) {
    const amount = numOrNull(asMap(r).amountPiastres);
    if (amount === null || amount < 0) fail(409, "invalid_receipt", "قيمة فاتورة غير صالحة.");
    purchases += amount!;
  }
  const delivery = numOrNull(asMap(order.quote).agreedDeliveryPiastres);
  if (delivery === null) fail(409, "not_agreed", "أجر التوصيل لم يُتفق عليه.");
  const advance = asMap(order.advance);
  const prepaid = advance.confirmedAt instanceof Date ? (numOrNull(advance.amountPiastres) ?? 0) : 0;
  const serviceFee = quickServiceFee(purchases);
  return { purchases, serviceFee, delivery: delivery!, prepaid, due: purchases + serviceFee + delivery! - prepaid };
}

/** شروط تأكيد التسليم بالرمز (قبل التحقق من الرمز نفسه). */
export function quickDeliveryBlocker(order: JsonMap, uid: string): string | null {
  if (order.courierId !== uid) return "الطلب غير معيّن لحسابك.";
  if (order.status !== "receipts_locked") return "اعتمد الفواتير الأول قبل التسليم.";
  if (!order.totals || typeof order.totals !== "object") return "الحساب النهائي غير موجود.";
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
