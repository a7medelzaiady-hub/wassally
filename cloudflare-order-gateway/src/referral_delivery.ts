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
  let channel: "customer" | "marketer";
  try {
    const attribution = await read("referral_attributions");
    if (!attribution) return;
    const decoded = decodeFirestoreReferralFields(attribution);
    if (decoded.channel !== "customer" && decoded.channel !== "marketer") return;
    channel = decoded.channel;
    const existing = await read("referral_first_orders");
    if (existing) {
      const { firstCompletedOrderId } = decodeFirestoreReferralFields(existing);
      if (typeof firstCompletedOrderId !== "string" || !validId.test(firstCompletedOrderId)) return;
      firstOrderId = firstCompletedOrderId;
    } else {
      const equal = (fieldPath: string, value: string) => ({
        fieldFilter: { field: { fieldPath }, op: "EQUAL", value: { stringValue: value } },
      });
      const result = await post("runQuery", { transaction, structuredQuery: {
        select: { fields: ["userId", "status", "deliveredAt"].map((fieldPath) => ({ fieldPath })) },
        from: [{ collectionId: "orders" }],
        where: { compositeFilter: { op: "AND", filters: [equal("userId", uid), equal("status", "delivered")] } },
        orderBy: [
          { field: { fieldPath: "deliveredAt" }, direction: "ASCENDING" },
          { field: { fieldPath: "__name__" }, direction: "ASCENDING" },
        ],
        limit: 1,
      } });
      if (!result.ok) throw new Error("Could not resolve first delivered order");
      const rows = JSON.parse(await result.text()) as Array<{ document?: { name: string; fields: Record<string, unknown> } }>;
      const doc = rows.find((row) => row.document)?.document;
      if (!doc) return;
      const prefix = `${root}/orders/`;
      if (!doc.name.startsWith(prefix)) return;
      firstOrderId = doc.name.slice(prefix.length);
      const order = decodeFirestoreReferralFields(doc.fields);
      if (!validId.test(firstOrderId) || order.userId !== uid || order.status !== "delivered" ||
          typeof order.deliveredAt !== "number" || !Number.isSafeInteger(order.deliveredAt) ||
          order.deliveredAt <= 0) return;
      const write = buildFirstCompletedOrderWrite(root, { invitedUid: uid, orderId: firstOrderId, completedAtMs: order.deliveredAt });
      const commit = await post("commit", { transaction, writes: [write] });
      if (!commit.ok) throw new Error("Could not record first delivered order");
      committed = true;
    }
  } finally {
    if (!committed) await post("rollback", { transaction }).catch(() => undefined);
  }
  await settleFirstOrderReferral(projectId, token, uid, firstOrderId, channel, transport);
}
