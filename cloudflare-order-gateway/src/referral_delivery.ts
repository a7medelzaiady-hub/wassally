import { buildStoreAttributionWrite } from "./referral_attribution";
import { buildFirstStoreOrderWrite } from "./referral_store_first_order_index";
import { settleStoreReferral } from "./referral_store_settlement";
import type { FirestoreTransport } from "./referral_commit";
import { buildFirstCompletedOrderWrite } from "./referral_first_order_index";
import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { readReferralDocument } from "./referral_read";
import { settleFirstOrderReferral } from "./referral_settlement";
import { beginReferralTransaction } from "./referral_transaction";

const validId = /^[A-Za-z0-9_-]{1,128}$/;

/** Resolve the earliest completed order from history, including orders that
 * predate the campaign. The delivered timestamp is stamped by Firestore.
 */
export async function settleCustomerDelivery(
  projectId: string,
  token: string,
  uid: string,
  transport: FirestoreTransport,
): Promise<void> {
  if (!validId.test(projectId) || !validId.test(uid)) return;
  const root = `projects/${projectId}/databases/(default)/documents`;
  const base = `https://firestore.googleapis.com/v1/${root}`;
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  const post = (operation: string, data: unknown) => transport(`${base}:${operation}`, {
    method: "POST", headers, body: JSON.stringify(data),
  });
  const transaction = await beginReferralTransaction(projectId, token, transport);
  const read = (collection: string) => readReferralDocument(projectId, collection, uid, transaction, token, transport);
  let committed = false;
  let firstOrderId: string;
  let channel: "customer" | "marketer" | "store_customer";
  try {
    const attribution = await read("referral_attributions");
    if (!attribution) return;
    const decoded = decodeFirestoreReferralFields(attribution);
    if (decoded.channel !== "customer" && decoded.channel !== "marketer" && decoded.channel !== "store_owner") return;
    channel = decoded.channel === "store_owner" ? "store_customer" : decoded.channel;
    const existing = await read("referral_first_orders");
    if (existing) {
      const { firstCompletedOrderId } = decodeFirestoreReferralFields(existing);
      if (typeof firstCompletedOrderId !== "string" || !validId.test(firstCompletedOrderId)) return;
      firstOrderId = firstCompletedOrderId;
    } else {
      const order = await firstDeliveredOrder(root, post, transaction, "userId", uid);
      if (!order) return;
      firstOrderId = order.orderId;
      const write = buildFirstCompletedOrderWrite(root, { invitedUid: uid, ...order });
      const commit = await post("commit", { transaction, writes: [write] });
      if (!commit.ok) throw new Error("Could not record first delivered order");
      committed = true;
    }
  } finally {
    if (!committed) await post("rollback", { transaction }).catch(() => undefined);
  }
  await settleFirstOrderReferral(projectId, token, uid, firstOrderId, channel, transport);
}

async function firstDeliveredOrder(
  root: string,
  post: (operation: string, data: unknown) => ReturnType<FirestoreTransport>,
  transaction: string,
  ownerField: "userId" | "storeId",
  ownerId: string,
): Promise<{ orderId: string; completedAtMs: number } | null> {
  const equal = (fieldPath: string, value: string) => ({
    fieldFilter: { field: { fieldPath }, op: "EQUAL", value: { stringValue: value } },
  });
  const result = await post("runQuery", { transaction, structuredQuery: {
    select: { fields: [ownerField, "status", "deliveredAt"].map((fieldPath) => ({ fieldPath })) },
    from: [{ collectionId: "orders" }],
    where: { compositeFilter: { op: "AND", filters: [equal(ownerField, ownerId), equal("status", "delivered")] } },
    orderBy: [
      { field: { fieldPath: "deliveredAt" }, direction: "ASCENDING" },
      { field: { fieldPath: "__name__" }, direction: "ASCENDING" },
    ],
    limit: 1,
  } });
  if (!result.ok) throw new Error("Could not resolve first delivered order");
  const rows = JSON.parse(await result.text()) as Array<{ document?: { name: string; fields: Record<string, unknown> } }>;
  const doc = rows.find((row) => row.document)?.document;
  if (!doc) return null;
  const prefix = `${root}/orders/`;
  if (!doc.name.startsWith(prefix)) return null;
  const orderId = doc.name.slice(prefix.length);
  const order = decodeFirestoreReferralFields(doc.fields);
  if (!validId.test(orderId) || order[ownerField] !== ownerId || order.status !== "delivered" ||
      typeof order.deliveredAt !== "number" || !Number.isSafeInteger(order.deliveredAt) ||
      order.deliveredAt <= 0) return null;
  return { orderId, completedAtMs: order.deliveredAt };
}

export async function settleStoreDelivery(
  projectId: string,
  token: string,
  storeId: string,
  transport: FirestoreTransport,
): Promise<void> {
  if (!validId.test(projectId) || !validId.test(storeId)) return;
  const root = `projects/${projectId}/databases/(default)/documents`;
  const post = (operation: string, data: unknown) => transport(
    `https://firestore.googleapis.com/v1/${root}:${operation}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(data),
    },
  );
  const transaction = await beginReferralTransaction(projectId, token, transport);
  const read = async (collection: string, key = storeId) => {
    const raw = await readReferralDocument(projectId, collection, key, transaction, token, transport);
    return raw && decodeFirestoreReferralFields(raw);
  };
  let committed = false;
  let orderId: string;
  try {
    const origin = await read("referral_store_origins");
    if (typeof origin?.uid !== "string" || !validId.test(origin.uid)) return;
    const existing = await read("referral_store_first_orders");
    if (existing) {
      if (typeof existing.firstCompletedOrderId !== "string" || !validId.test(existing.firstCompletedOrderId)) return;
      orderId = existing.firstCompletedOrderId;
    } else {
      const attribution = await read("referral_attributions", origin.uid);
      if (attribution?.channel !== "store_owner" || attribution.invitedUid !== origin.uid ||
          typeof attribution.inviterUid !== "string" || !validId.test(attribution.inviterUid) ||
          attribution.inviterUid === origin.uid || typeof attribution.code !== "string" ||
          typeof attribution.claimedAtMs !== "number" || typeof origin.approvalAt !== "number" ||
          attribution.claimedAtMs >= origin.approvalAt) return;
      const order = await firstDeliveredOrder(root, post, transaction, "storeId", storeId);
      if (!order) return;
      orderId = order.orderId;
      const commit = await post("commit", { transaction, writes: [
        buildStoreAttributionWrite(root, storeId, {
          invitedUid: origin.uid, inviterUid: attribution.inviterUid, channel: "store_owner",
          code: attribution.code, claimedAtMs: attribution.claimedAtMs,
        }),
        buildFirstStoreOrderWrite(root, { invitedStoreId: storeId, ...order }),
      ] });
      if (!commit.ok) throw new Error("Could not record first delivered store order");
      committed = true;
    }
  } finally {
    if (!committed) await post("rollback", { transaction }).catch(() => undefined);
  }
  await settleStoreReferral(projectId, token, { invitedStoreId: storeId, firstOrderId: orderId }, transport);
}
