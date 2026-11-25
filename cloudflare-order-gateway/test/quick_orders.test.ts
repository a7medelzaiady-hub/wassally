import { describe, expect, it } from "vitest";
import {
  QuickRuleError,
  applyQuickAction,
  newQuickOrder,
  quickDeliveredPatch,
  quickDeliveryBlocker,
  quickServiceFee,
  quickApproxTotal,
  quickTotals,
  resolveQuickSettings,
  validateQuickStores,
  type QuickActor,
} from "../src/quick_orders";
import { serviceFeeFor } from "../src/index";

const ID = "cust1_abcdefghijklmnop";
const now = new Date("2026-11-22T12:00:00Z");
const ctx = { orderId: ID, now, cloudName: "g3n5pdfz" };
const customer: QuickActor = { uid: "cust1", role: "customer" };
const quickCourier: QuickActor = { uid: "cour1", role: "courier", name: "Mido", quickEnabled: true };
const otherQuickCourier: QuickActor = { uid: "cour2", role: "courier", name: "Sayed", quickEnabled: true };
const plainCourier: QuickActor = { uid: "cour3", role: "courier", name: "Normal", quickEnabled: false };
const admin: QuickActor = { uid: "admin1", role: "admin" };
const receiptUrl = (n = 1) =>
  `https://res.cloudinary.com/g3n5pdfz/image/upload/v1732270000/quick_receipts/${ID}/r${n}.jpg`;

type Doc = Record<string, unknown>;

function fresh(): Doc {
  return newQuickOrder({
    uid: "cust1",
    customerFirstName: "Ali",
    area: "وسط البلد",
    notes: "",
    stores: [{ name: "بقالة الخير", items: "رز، 2 زيت" }, { name: "", items: "كيلو لحمة" }],
    settings: resolveQuickSettings({ enabled: true }),
  });
}

/** يطبّق العملية ويرجّع المستند بعد الدمج (زي ما الـWorker بيعمل). */
function step(order: Doc, action: string, actor: QuickActor, body: Doc = {}): Doc {
  return { ...order, ...applyQuickAction(order, action, actor, body, ctx) };
}

function code(fn: () => unknown): string {
  try {
    fn();
  } catch (error) {
    if (error instanceof QuickRuleError) return `${error.status}:${error.code}`;
    throw error;
  }
  return "ok";
}

const accepted = () => step(fresh(), "accept", quickCourier);
const started = (estimate = 15000) =>
  step(accepted(), "start-purchase", quickCourier, { estimatedPurchasesPiastres: estimate });

/** طلب «جاري الشراء» بمقدم مؤكد. */
function withAdvance(estimate = 60000, amount = 60000): Doc {
  let o = started(estimate);
  o = step(o, "advance-sent", customer, { amountPiastres: amount, reference: "VF-1" });
  return step(o, "advance-received", quickCourier, { amountPiastres: amount });
}

const addReceipt = (o: Doc, amount: number, n = 1) =>
  step(o, "receipt", quickCourier, { amountPiastres: amount, imageUrl: receiptUrl(n) });

function submitted(delivery = 3000, receipts = [15000]): Doc {
  let o = started(15000);
  receipts.forEach((amount, i) => { o = addReceipt(o, amount, i + 1); });
  return step(o, "submit-summary", quickCourier, { deliveryPiastres: delivery });
}

const approved = (o = submitted()) => o; // summary ready automatically, no customer approval

describe("quick settings", () => {
  it("is always on by default; only enabled: false switches it off", () => {
    const s = resolveQuickSettings(null);
    expect(s.enabled).toBe(true);
    expect(s.prepaidThresholdPiastres).toBe(20000);
    expect(resolveQuickSettings({}).enabled).toBe(true);
    expect(resolveQuickSettings({ enabled: false }).enabled).toBe(false);
  });
  it("ignores invalid admin numbers", () => {
    const s = resolveQuickSettings({ enabled: true, prepaidThresholdPiastres: -5, maximumAdvancePiastres: 1.5, maxPerDay: 999 });
    expect(s.prepaidThresholdPiastres).toBe(20000);
    expect(s.maximumAdvancePiastres).toBe(100000);
    expect(s.maxPerDay).toBe(5);
    expect(resolveQuickSettings({ enabled: true, prepaidThresholdPiastres: 30000 }).prepaidThresholdPiastres).toBe(30000);
  });
});

describe("quick service fee", () => {
  it("matches the app formula: 2%, min 5, max 15 EGP, zero for nothing", () => {
    expect(quickServiceFee(0)).toBe(0);
    expect(quickServiceFee(10000)).toBe(500);
    expect(quickServiceFee(60000)).toBe(1200);
    expect(quickServiceFee(100000)).toBe(1500);
  });
  it("matches the existing Worker serviceFeeFor (EGP) exactly", () => {
    for (const egp of [1, 37.5, 250, 333.33, 749.99, 750, 5000]) {
      expect(quickServiceFee(Math.round(egp * 100))).toBe(Math.round(serviceFeeFor(egp) * 100));
    }
  });
});

describe("quick stores input", () => {
  it("accepts an empty store name (courier picks) but requires items", () => {
    expect(validateQuickStores([{ name: "", items: "عيش" }])).toEqual([{ name: "", items: "عيش" }]);
    expect(code(() => validateQuickStores([{ name: "x", items: "  " }]))).toBe("400:invalid_stores");
    expect(code(() => validateQuickStores([]))).toBe("400:invalid_stores");
    expect(code(() => validateQuickStores(Array(11).fill({ name: "", items: "x" })))).toBe("400:invalid_stores");
    expect(code(() => validateQuickStores([{ name: "x", items: "a".repeat(501) }]))).toBe("400:invalid_stores");
  });
});

describe("accepting", () => {
  it("only approved quick couriers can accept, first one wins", () => {
    expect(code(() => step(fresh(), "accept", plainCourier))).toBe("403:not_quick_courier");
    const a = accepted();
    expect(a.status).toBe("accepted");
    expect(a.courierId).toBe("cour1");
    expect(a.courierName).toBe("Mido");
    expect(code(() => step(a, "accept", otherQuickCourier))).toBe("409:already_taken");
  });
  it("a courier cannot accept their own order, and customers cannot accept", () => {
    expect(code(() => step({ ...fresh(), userId: "cour1" }, "accept", quickCourier))).toBe("403:own_order");
    expect(code(() => step(fresh(), "accept", customer))).toBe("403:not_quick_courier");
  });
});

describe("courier-funded purchases and optional advance", () => {
  it("the old negotiation actions no longer exist", () => {
    expect(code(() => step(accepted(), "propose", quickCourier, { deliveryPiastres: 3000 }))).toBe("404:unknown_action");
    expect(code(() => step(accepted(), "approve", customer, { expectedRevision: 1 }))).toBe("404:unknown_action");
  });
  it("up to 200 EGP (inclusive) is cash on delivery and purchasing starts at once", () => {
    const o = started(20000);
    expect(o.paymentMode).toBe("cod");
    expect(o.status).toBe("purchasing");
  });
  it("above 200 EGP: courier can buy with own money without advance", () => {
    const o = started(50000);
    expect(o.paymentMode).toBe("cod");
    expect(o.status).toBe("purchasing");
    expect(addReceipt(o, 100).status).toBe("purchasing");
    expect(code(() => step(o, "advance-received", quickCourier, { amountPiastres: 30000 }))).toBe("409:invalid_state");
  });
  it("customer may optionally transfer advance; only assigned courier confirms", () => {
    const o = started(50000);
    const sent = step(o, "advance-sent", customer, { amountPiastres: 30000, reference: "VF-123" });
    expect(code(() => step(sent, "advance-received", otherQuickCourier, { amountPiastres: 30000 }))).toBe("403:forbidden");
    expect(code(() => step(sent, "advance-received", customer, { amountPiastres: 30000 }))).toBe("403:forbidden");
    const confirmed = step(sent, "advance-received", quickCourier, { amountPiastres: 30000 });
    expect(confirmed.status).toBe("purchasing");
    expect((confirmed.advance as Doc).amountPiastres).toBe(30000);
    expect(code(() => step(o, "advance-sent", customer, { amountPiastres: 100001 }))).toBe("400:invalid_advance");
  });
  it("only the assigned courier sets the estimate, within the cap", () => {
    expect(code(() => step(accepted(), "start-purchase", otherQuickCourier, { estimatedPurchasesPiastres: 10000 })))
      .toBe("403:forbidden");
    expect(code(() => step(accepted(), "start-purchase", customer, { estimatedPurchasesPiastres: 10000 })))
      .toBe("403:forbidden");
    expect(code(() => step(accepted(), "start-purchase", quickCourier, { estimatedPurchasesPiastres: 100001 })))
      .toBe("400:invalid_estimate");
    expect(code(() => step(fresh(), "start-purchase", quickCourier, { estimatedPurchasesPiastres: 10000 })))
      .toBe("403:forbidden");
  });
});

describe("receipts: photo + amount only", () => {
  it("store name is optional; several receipts are summed", () => {
    let o = started();
    o = addReceipt(o, 12000, 1);
    o = addReceipt(o, 3000, 2);
    const receipts = o.receipts as Doc[];
    expect(receipts.length).toBe(2);
    expect(receipts[0].storeName).toBe("");
    const s = step(o, "submit-summary", quickCourier, { deliveryPiastres: 2500 });
    expect((s.totals as Doc).purchases).toBe(15000);
  });
  it("accepts only receipt images uploaded for this order", () => {
    const o = started();
    const bad = [
      `https://res.cloudinary.com/g3n5pdfz/image/upload/quick_receipts/other_order_123456789/r.jpg`,
      `https://res.cloudinary.com/evil/image/upload/quick_receipts/${ID}/r.jpg`,
      `https://example.com/quick_receipts/${ID}/r.jpg`,
      `https://res.cloudinary.com/g3n5pdfz/image/upload/special_requests/${ID}/r.jpg`,
    ];
    for (const imageUrl of bad) {
      expect(code(() => step(o, "receipt", quickCourier, { amountPiastres: 100, imageUrl }))).toBe("400:invalid_receipt_image");
    }
    expect(code(() => step(o, "receipt", quickCourier, { imageUrl: receiptUrl() }))).toBe("400:invalid_receipt");
    expect(code(() => step(o, "receipt", customer, { amountPiastres: 100, imageUrl: receiptUrl() }))).toBe("403:forbidden");
  });
  it("can remove a receipt before submitting the summary", () => {
    let o = addReceipt(addReceipt(started(), 100, 1), 200, 2);
    o = step(o, "receipt-remove", quickCourier, { index: 0 });
    expect((o.receipts as Doc[]).map((r) => r.amountPiastres)).toEqual([200]);
    expect(code(() => step(o, "receipt-remove", quickCourier, { index: 5 }))).toBe("400:invalid_index");
  });
});

describe("final summary for display only", () => {
  it("courier enters one delivery number; the app computes one statement", () => {
    const s = submitted(3000, [15000]);
    expect(s.status).toBe("summary_approved");
    expect(s.totals).toEqual({ purchases: 15000, serviceFee: 500, delivery: 3000, prepaid: 0, due: 18500 });
    expect(code(() => step(started(), "submit-summary", quickCourier, { deliveryPiastres: 3000 }))).toBe("409:no_receipts");
    const o = addReceipt(started(), 100);
    expect(code(() => step(o, "submit-summary", quickCourier, { deliveryPiastres: 20001 }))).toBe("400:invalid_delivery");
    expect(code(() => step(o, "submit-summary", customer, { deliveryPiastres: 3000 }))).toBe("403:forbidden");
  });
  it("subtracts the confirmed advance (negative due = courier refunds)", () => {
    let o = withAdvance(60000, 60000);
    o = addReceipt(o, 20000, 1);
    o = addReceipt(o, 40000, 2);
    const s = step(o, "submit-summary", quickCourier, { deliveryPiastres: 4000 });
    expect(s.totals).toEqual({ purchases: 60000, serviceFee: 1200, delivery: 4000, prepaid: 60000, due: 5200 });
    expect(quickTotals([{ amountPiastres: 25000 }], 3000, { amountPiastres: 50000, confirmedAt: now }).due)
      .toBe(25000 + 500 + 3000 - 50000);
    expect(quickTotals([{ amountPiastres: 25000 }], 3000, { amountPiastres: 50000, sentAt: now }).prepaid).toBe(0);
  });
  it("receipts and fee are frozen while the summary is pending or approved", () => {
    const s = submitted();
    expect(code(() => addReceipt(s, 1, 9))).toBe("409:invalid_state");
    expect(code(() => step(s, "receipt-remove", quickCourier, { index: 0 }))).toBe("409:invalid_state");
    expect(code(() => step(s, "submit-summary", quickCourier, { deliveryPiastres: 1 }))).toBe("409:invalid_state");
    expect(code(() => addReceipt(approved(s), 1, 9))).toBe("409:invalid_state");
  });
  it("customer approves only the statement they saw; courier cannot approve", () => {
    const s = { ...submitted(), status: "summary_pending" }; // legacy only
    expect(code(() => step(s, "approve-summary", quickCourier, { expectedSummaryRevision: s.summaryRevision })))
      .toBe("403:forbidden");
    expect(code(() => step(s, "approve-summary", customer, { expectedSummaryRevision: 99 }))).toBe("409:stale_summary");
    const a = approved(s);
    expect(a.status).toBe("summary_approved");
    expect(a.summaryApprovedAt).toEqual(now);
  });
  it("rejection = no delivery: back to the courier with the statement cleared", () => {
    const r = step({ ...submitted(), status: "summary_pending" }, "reject-summary", customer, { reason: "الحساب مش مظبوط" });
    expect(r.status).toBe("purchasing");
    expect(r.totals).toBe(null);
    expect(r.summaryRejections).toBe(1);
    expect(quickDeliveryBlocker(r, "cour1")).not.toBe(null);
    // لو تم رفض كشف قديم، المندوب يعدّل ويبعت كشف جديد برقم مراجعة أعلى.
    const again = step(addReceipt(r, 500, 5), "submit-summary", quickCourier, { deliveryPiastres: 3000 });
    expect(again.summaryRevision).toBe(2);
    expect(code(() => step(again, "approve-summary", customer, { expectedSummaryRevision: 1 }))).toBe("409:stale_summary");
  });
  it("the approved statement is locked: no reopening, no new receipts or summary", () => {
    const a = approved();
    expect(code(() => step(a, "reopen-summary", quickCourier))).toBe("404:unknown_action");
    expect(code(() => step(a, "submit-summary", quickCourier, { deliveryPiastres: 1 }))).toBe("409:invalid_state");
    expect(code(() => step(a, "reject-summary", customer))).toBe("409:invalid_state");
  });
});

describe("editing, cancelling and releasing", () => {
  it("customer edits freely before acceptance only; after that it's a phone call", () => {
    const edited = step(fresh(), "edit", customer, { stores: [{ name: "", items: "عيش" }] });
    expect(edited.stores).toEqual([{ name: "", items: "عيش" }]);
    expect(code(() => step(accepted(), "edit", customer, { stores: [{ name: "", items: "x" }] }))).toBe("409:edit_after_accept");
    expect(code(() => step(fresh(), "edit", quickCourier, { stores: [{ name: "", items: "x" }] }))).toBe("403:forbidden");
  });
  it("customer cancels before purchasing only; admin any time before delivery", () => {
    expect(step(fresh(), "cancel", customer).status).toBe("cancelled");
    expect(step(accepted(), "cancel", customer).status).toBe("cancelled");
    expect(code(() => step(started(), "cancel", customer))).toBe("409:not_cancellable");
    expect(code(() => step(started(), "cancel", quickCourier))).toBe("403:forbidden");
    const byAdmin = step(submitted(), "cancel", admin, { reason: "مشكلة" });
    expect(byAdmin.cancelledBy).toBe("admin");
    expect(code(() => step(byAdmin, "edit", customer, { stores: [{ name: "", items: "x" }] }))).toBe("409:final");
  });
  it("flags a refund when the customer cancels after sending the advance", () => {
    const sent = step(accepted(), "advance-sent", customer, { amountPiastres: 30000 });
    expect(step(sent, "cancel", customer).advanceRefundDue).toBe(true);
    expect(step(fresh(), "cancel", customer).advanceRefundDue).toBe(false);
    expect(code(() => step(started(30000), "cancel", customer))).toBe("409:not_cancellable");
  });
  it("courier can release before purchasing and before any advance; order reopens for others", () => {
    const released = step(accepted(), "release", quickCourier);
    expect(released.status).toBe("open");
    expect(released.courierId).toBe("");
    expect(released.paymentMode).toBe("");
    expect(step(released, "accept", otherQuickCourier).courierId).toBe("cour2");
    // العميل حوّل والطلب لسه «اتقبل»: المندوب ما يسيبش الطلب والفلوس معاه.
    const sent = step(accepted(), "advance-sent", customer, { amountPiastres: 30000 });
    expect(code(() => step(sent, "release", quickCourier))).toBe("409:not_releasable");
    expect(code(() => step(started(30000), "release", quickCourier))).toBe("409:not_releasable");
  });
});

describe("delivery gate", () => {
  it("PIN delivery as soon as the final statement is ready", () => {
    expect(quickDeliveryBlocker(started(), "cour1")).not.toBe(null);
    expect(quickDeliveryBlocker(submitted(), "cour1")).toBe(null);
    const a = approved();
    expect(quickDeliveryBlocker(a, "cour2")).not.toBe(null);
    expect(quickDeliveryBlocker(a, "cour1")).toBe(null);
    const done = quickDeliveredPatch(a, "cour1", now);
    expect(done.status).toBe("delivered");
    expect(done.courierOwedPiastres).toBe(500);
    expect(done.collectedPiastres).toBe(18500);
  });
  it("rejects unknown actions", () => {
    expect(code(() => step(fresh(), "hack", customer))).toBe("404:unknown_action");
  });
});

describe("display-only approximate price guide", () => {
  it("accepts priced items and calculates totals in piastres", () => {
    const stores = validateQuickStores([{
      name: "بقالة",
      items: "",
      pricedItems: [
        { name: "لبن", qty: 2, unitPricePiastres: 3500 },
        { name: "عيش", qty: 3, unitPricePiastres: 200 },
      ],
    }]);
    expect(quickApproxTotal(stores)).toBe(7600);
    const order = newQuickOrder({
      uid: "cust1", customerFirstName: "Ali", area: "وسط البلد",
      notes: "", stores, settings: resolveQuickSettings({ enabled: true }),
    });
    expect(order.approxTotalPiastres).toBe(7600);
    expect(order.estimatedPurchasesPiastres).toBe(null);
  });
  it("rejects invalid quantities and negative prices", () => {
    expect(code(() => validateQuickStores([{
      name: "", items: "حليب",
      pricedItems: [{ name: "حليب", qty: 100, unitPricePiastres: 100 }],
    }]))).toBe("400:invalid_priced_items");
    expect(code(() => validateQuickStores([{
      name: "", items: "حليب",
      pricedItems: [{ name: "حليب", qty: 1, unitPricePiastres: -1 }],
    }]))).toBe("400:invalid_priced_items");
  });
  it("treats a missing or null pricedItems as free text only", () => {
    expect(validateQuickStores([{ name: "", items: "عيش", pricedItems: null }])).toEqual([{ name: "", items: "عيش" }]);
    expect(code(() => validateQuickStores([{ name: "", items: "", pricedItems: null }]))).toBe("400:invalid_stores");
    expect(code(() => validateQuickStores([{ name: "", items: "", pricedItems: [] }]))).toBe("400:invalid_stores");
  });
  it("mixes free text and priced items, and rejects bad priced items", () => {
    const stores = validateQuickStores([
      { name: "الخير", items: "عيش بلدي", pricedItems: [{ name: "زيت لتر", qty: 2, unitPricePiastres: 7500 }] },
      { name: "", items: "كيلو لحمة" },
    ]);
    expect(quickApproxTotal(stores)).toBe(15000);
    expect(stores[1].pricedItems).toBe(undefined);
    const bad = [
      { name: "زيت", qty: 0, unitPricePiastres: 100 },
      { name: "زيت", qty: 1.5, unitPricePiastres: 100 },
      { name: "زيت", qty: 1, unitPricePiastres: 75.5 },
      { name: "  ", qty: 1, unitPricePiastres: 100 },
      { name: "زيت", qty: 1, unitPricePiastres: 1_000_001 },
    ];
    for (const item of bad) {
      expect(code(() => validateQuickStores([{ name: "", items: "", pricedItems: [item] }]))).toBe("400:invalid_priced_items");
    }
    const tooMany = Array(31).fill({ name: "x", qty: 1, unitPricePiastres: 100 });
    expect(code(() => validateQuickStores([{ name: "", items: "", pricedItems: tooMany }]))).toBe("400:invalid_priced_items");
  });
  it("edit recomputes the estimate; the estimate never drives the advance or the final bill", () => {
    const edited = step(fresh(), "edit", customer, {
      stores: [{ name: "", items: "", pricedItems: [{ name: "رز كيلو", qty: 10, unitPricePiastres: 3500 }] }],
      approxTotalPiastres: 1,
    });
    expect(edited.approxTotalPiastres).toBe(35000);
    // تقدير المندوب 150 جنيه → دفع عند الاستلام، حتى لو التقدير التقريبي 350 جنيه.
    const o = step(step(edited, "accept", quickCourier), "start-purchase", quickCourier, { estimatedPurchasesPiastres: 15000 });
    expect(o.paymentMode).toBe("cod");
    const s = step(addReceipt(o, 9000), "submit-summary", quickCourier, { deliveryPiastres: 2000 });
    expect((s.totals as Doc).purchases).toBe(9000);
  });
  it("full journey: accept → estimate → advance → receipts → statement → PIN delivery", () => {
    let o = step(fresh(), "accept", quickCourier);
    o = step(o, "start-purchase", quickCourier, { estimatedPurchasesPiastres: 50000 });
    expect(o.status).toBe("purchasing");
    o = step(o, "advance-sent", customer, { amountPiastres: 50000, reference: "VF-9" });
    o = step(o, "advance-received", quickCourier, { amountPiastres: 50000 });
    o = addReceipt(o, 30000, 1);
    o = addReceipt(o, 22000, 2);
    o = step(o, "submit-summary", quickCourier, { deliveryPiastres: 4000 });
    expect(quickDeliveryBlocker(o, "cour1")).toBe(null);
    expect(o.totals).toEqual({ purchases: 52000, serviceFee: 1040, delivery: 4000, prepaid: 50000, due: 7040 });
    expect(quickDeliveryBlocker(o, "cour1")).toBe(null);
    const done = { ...o, ...quickDeliveredPatch(o, "cour1", now) };
    expect(done.status).toBe("delivered");
    expect(done.courierOwedPiastres).toBe(1040);
    expect(code(() => step(done, "cancel", admin))).toBe("409:final");
  });
});

