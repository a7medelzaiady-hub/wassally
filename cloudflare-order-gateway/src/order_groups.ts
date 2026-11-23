/**
 * رقم تجميع مشترك لطلبات العميل من محلات مختلفة في نفس رحلة التسوق (اختياري).
 *
 * - كل طلب بيفضل مستقل: رقمه وحالته ورسومه ومندوبه. الرقم ده للعرض والتنظيم بس.
 * - العميل هو اللي بيختار يجمع (التطبيق بيبعت groupId مع الطلب)، مش كل طلباته تلقائيًا.
 * - مستند order_groups/{groupId} بيربط الرقم بصاحبه: محدش يقدر يضيف طلب على رقم مش بتاعه،
 *   والرقم بيقفل بعد مدة أو بعد عدد طلبات معين، ومحل واحد مرة واحدة بس في المجموعة.
 * - الربط بيحصل لحظة إنشاء الطلب بس (مفيش ربط طلب قديم)، فالعميل ما يقدرش يربط طلب مش بتاعه.
 * - المندوب بيشوف groupCode (6 حروف) بس، من غير أي بيانات للعميل.
 */

type JsonMap = Record<string, unknown>;

export const ORDER_GROUP_MAX_ORDERS = 5;
export const ORDER_GROUP_TTL_MS = 6 * 60 * 60 * 1000;

const GROUP_ID = /^grp_[A-Za-z0-9]{20}$/;

export class OrderGroupError extends Error {
  constructor(readonly status: number, message: string, readonly code: string) {
    super(message);
  }
}

export function isOrderGroupId(value: unknown): value is string {
  return typeof value === "string" && GROUP_ID.test(value);
}

/** الكود اللي بيظهر للمندوب والمحل: آخر 6 حروف كبيرة (من غير أي بيانات للعميل). */
export function orderGroupCode(groupId: string): string {
  return groupId.slice(-6).toUpperCase();
}

/** يقرا groupId من بيانات الطلب: فاضي = طلب مش مجمّع. أي قيمة تانية لازم تكون بالصيغة الصح. */
export function parseOrderGroupId(raw: unknown): string {
  if (raw === undefined || raw === null || raw === "") return "";
  if (!isOrderGroupId(raw)) {
    throw new OrderGroupError(400, "رقم تجميع الطلبات غير صالح. حدّث التطبيق وحاول تاني.", "invalid_group");
  }
  return raw;
}

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
}

export interface OrderGroupPlan {
  /** الحقول الكاملة لمستند المجموعة بعد إضافة الطلب. */
  fields: JsonMap;
  /** المجموعة جديدة (أول طلب) = نكتبها بشرط exists:false. */
  isNew: boolean;
}

/**
 * يقرر إضافة الطلب للمجموعة أو يرمي OrderGroupError.
 * الـWorker بيكتب الناتج في نفس commit الطلب بشرط exists:false أو updateTime،
 * فطلبين متزامنين على نفس المجموعة ما يعدّوش الحدود.
 */
export function planOrderGroup(
  existing: JsonMap | null,
  input: { uid: string; orderId: string; storeId: string; now: Date },
): OrderGroupPlan {
  const { uid, orderId, storeId, now } = input;
  if (!existing) {
    return {
      isNew: true,
      fields: {
        userId: uid,
        orderIds: [orderId],
        storeIds: [storeId],
        count: 1,
        createdAt: now,
        expiresAt: new Date(now.getTime() + ORDER_GROUP_TTL_MS),
      },
    };
  }
  if (existing.userId !== uid) {
    throw new OrderGroupError(403, "رقم التجميع ده مش تبع حسابك.", "group_forbidden");
  }
  const expiresAt = existing.expiresAt instanceof Date ? existing.expiresAt.getTime() : 0;
  if (!expiresAt || expiresAt <= now.getTime()) {
    throw new OrderGroupError(409, "رقم التجميع انتهى. اطلب الطلب ده لوحده أو ابدأ تجميع جديد.", "group_expired");
  }
  const orderIds = stringList(existing.orderIds);
  const storeIds = stringList(existing.storeIds);
  const count = typeof existing.count === "number" ? existing.count : orderIds.length;
  if (count >= ORDER_GROUP_MAX_ORDERS || orderIds.length >= ORDER_GROUP_MAX_ORDERS) {
    throw new OrderGroupError(409, `المجموعة وصلت لأقصى عدد طلبات (${ORDER_GROUP_MAX_ORDERS}).`, "group_full");
  }
  if (storeIds.includes(storeId)) {
    throw new OrderGroupError(409, "فيه طلب من نفس المحل في المجموعة دي بالفعل.", "group_store_repeat");
  }
  if (orderIds.includes(orderId)) {
    throw new OrderGroupError(409, "الطلب ده موجود في المجموعة بالفعل.", "group_order_repeat");
  }
  return {
    isNew: false,
    fields: {
      ...existing,
      orderIds: [...orderIds, orderId],
      storeIds: [...storeIds, storeId],
      count: count + 1,
    },
  };
}
