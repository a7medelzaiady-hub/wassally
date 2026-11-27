import { describe, expect, it } from "vitest";
import {
  QuickRuleError,
  applyQuickAction,
  newQuickOrder,
  quickDeliveredPatch,
  quickDeliveryBlocker,
  quickServiceFee,
  resolveQuickSettings,
  validateErrandPickup,
  validateErrandType,
  type QuickActor,
} from "../src/quick_orders";

const now = new Date("2026-11-27T12:00:00Z");
const ctx = { orderId: "cust1_abcdefghijklmnop", now };
const customer: QuickActor = { uid: "cust1", role: "customer" };
const courier: QuickActor = { uid: "cour1", role: "courier", quickEnabled: true };
const stranger: QuickActor = { uid: "cour2", role: "courier", quickEnabled: true };

function fresh() {
  return newQuickOrder({
    uid: "cust1",
    customerFirstName: "Ali",
    area: "وسط البلد",
    notes: "",
    stores: [{ name: "", items: "استلم الطرد من المحل وسلمه للعميل في البيت" }],
    kind: "errand",
    errandType: "parcel",
    customerImages: ["https://private.photo/example"],
    settings: resolveQuickSettings({}),
  });
}
type Doc = Record<string, unknown>;
function apply(doc: Doc, action: string, actor: QuickActor, body: Doc = {}): Doc {
  return { ...doc, ...applyQuickAction(doc, action, actor, body, ctx) };
}
function error(fn: () => unknown): string {
  try { fn(); } catch (e) {
    if (e instanceof QuickRuleError) return `${e.status}:${e.code}`;
    throw e;
  }
  return "ok";
}

describe("مشوارك علينا: source privacy, fare agreement, PIN delivery", () => {
  it("validates types and private pickup address", () => {
    expect(validateErrandType("ready_order")).toBe("ready_order");
    expect(error(() => validateErrandType("bank_wire"))).toBe("400:invalid_errand_type");
    expect(validateErrandPickup(" شارع البحر  ")).toBe("شارع البحر");
    expect(error(() => validateErrandPickup("x"))).toBe("400:invalid_pickup");
    expect(error(() => validateErrandPickup(null))).toBe("400:invalid_pickup");
  });

  it("does not put private images or addresses in publicly readable order", () => {
    const doc = fresh();
    expect(doc.kind).toBe("errand");
    expect(doc.errandType).toBe("parcel");
    expect(doc.customerImages).toEqual([]);
    expect(doc.hasCustomerImages).toBe(true);
    expect(JSON.stringify(doc)).not.toContain("https://private.photo");
    expect(JSON.stringify(doc)).not.toContain("pickupAddress");
  });

  it("requires customer's approval of the exact amount before courier starts", () => {
    const accepted = apply(fresh(), "accept", courier);
    expect(error(() => apply(accepted, "start-purchase", courier))).toBe("409:quote_required");
    expect(error(() => apply(accepted, "quote-errand", stranger, { deliveryPiastres: 3000 }))).toBe("403:forbidden");
    expect(error(() => apply(accepted, "quote-errand", courier, { deliveryPiastres: 50000 }))).toBe("400:invalid_delivery");
    const quoted = apply(accepted, "quote-errand", courier, { deliveryPiastres: 3000 });
    expect(quoted.errandQuoteStatus).toBe("pending");
    expect(error(() => apply(quoted, "approve-errand-quote", stranger, { expectedQuotePiastres: 3000 }))).toBe("403:forbidden");
    expect(error(() => apply(quoted, "approve-errand-quote", customer, { expectedQuotePiastres: 2000 }))).toBe("409:stale_quote");
    const rejected = apply(quoted, "reject-errand-quote", customer);
    expect(rejected.errandQuoteStatus).toBe("rejected");
    expect(error(() => apply(rejected, "start-purchase", courier))).toBe("409:quote_required");
    const again = apply(rejected, "quote-errand", courier, { deliveryPiastres: 2500 });
    const approved = apply(again, "approve-errand-quote", customer, { expectedQuotePiastres: 2500 });
    expect(approved.errandQuoteStatus).toBe("accepted");
    expect(error(() => apply(approved, "quote-errand", courier, { deliveryPiastres: 3000 }))).toBe("409:invalid_state");
    const working = apply(approved, "start-purchase", courier);
    expect(working.status).toBe("purchasing");
    expect(working.estimatedPurchasesPiastres).toBe(0);
    expect(error(() => apply(working, "cancel", customer))).toBe("409:not_cancellable");
    expect(error(() => apply(working, "receipt", courier, { amountPiastres: 1000 }))).toBe("409:invalid_state");
    expect(error(() => apply(working, "advance-sent", customer, { amountPiastres: 1000 }))).toBe("409:invalid_state");
    expect(error(() => apply(working, "submit-summary", courier, { deliveryPiastres: 3000 }))).toBe("409:pickup_required");
    expect(error(() => apply(working, "confirm-errand-pickup", stranger))).toBe("403:forbidden");
    const collected = apply(working, "confirm-errand-pickup", courier);
    expect(collected.errandPickupConfirmedAt).toEqual(now);
    expect(error(() => apply(collected, "confirm-errand-pickup", courier))).toBe("409:invalid_state");
    expect(error(() => apply(collected, "submit-summary", courier, { deliveryPiastres: 3000 }))).toBe("409:quote_required");
    const ready = apply(collected, "submit-summary", courier, { deliveryPiastres: 2500 });
    expect(ready.status).toBe("summary_approved");
    expect(ready.totals).toEqual({ purchases: 0, serviceFee: 0, delivery: 2500, prepaid: 0, due: 2500 });
    expect(quickDeliveryBlocker(ready, "cour1")).toBe(null);
    const delivered = quickDeliveredPatch(ready, "cour1", now);
    expect(delivered.status).toBe("delivered");
    expect(delivered.collectedPiastres).toBe(2500);
    expect(delivered.courierOwedPiastres).toBe(quickServiceFee(2500));
    expect(delivered.hasCustomerImages).toBe(false);
  });

  it("release clears the old quote so the next courier cannot reuse it", () => {
    const accepted = apply(fresh(), "accept", courier);
    const quote = apply(accepted, "quote-errand", courier, { deliveryPiastres: 3000 });
    const released = apply(quote, "release", courier);
    expect(released.status).toBe("open");
    expect(released.errandQuotePiastres).toBe(null);
    expect(released.errandQuoteStatus).toBe("");
    const next = apply(released, "accept", stranger);
    expect(error(() => apply(next, "start-purchase", stranger))).toBe("409:quote_required");
  });

  it("unstructured errands without a physical pickup can finish without a pickup event", () => {
    let order = newQuickOrder({
      uid: "cust1", customerFirstName: "Ali", area: "وسط البلد", notes: "",
      stores: [{ name: "", items: "راجع المكتب في مشوار بسيط بدون استلام غرض" }],
      kind: "errand", errandType: "other",
      settings: resolveQuickSettings({}),
    });
    order = apply(order, "accept", courier);
    order = apply(order, "quote-errand", courier, { deliveryPiastres: 2000 });
    order = apply(order, "approve-errand-quote", customer, { expectedQuotePiastres: 2000 });
    order = apply(order, "start-purchase", courier);
    expect(error(() => apply(order, "confirm-errand-pickup", courier))).toBe("409:invalid_state");
    expect(apply(order, "submit-summary", courier, { deliveryPiastres: 2000 }).status).toBe("summary_approved");
  });

  it("regular quick orders keep receipts and do not accept errand quoting", () => {
    const regular = newQuickOrder({
      uid: "cust1", customerFirstName: "Ali", area: "وسط",
      notes: "", stores: [{ name: "", items: "عيش وسكر" }],
      settings: resolveQuickSettings({}),
    });
    const accepted = apply(regular, "accept", courier);
    expect(error(() => apply(accepted, "quote-errand", courier, { deliveryPiastres: 3000 }))).toBe("409:invalid_state");
    const buying = apply(accepted, "start-purchase", courier, { estimatedPurchasesPiastres: 3000 });
    expect(error(() => apply(buying, "submit-summary", courier, { deliveryPiastres: 2000 }))).toBe("409:no_receipts");
  });
});
