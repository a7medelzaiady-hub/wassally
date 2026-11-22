import { describe, expect, it } from "vitest";
import {
  QuickRuleError,
  applyQuickAction,
  newQuickOrder,
  quickDeliveredPatch,
  quickDeliveryBlocker,
  quickServiceFee,
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

function settings(over: Record<string, unknown> = {}) {
  return resolveQuickSettings({ enabled: true, ...over });
}

function fresh() {
  return newQuickOrder({
    uid: "cust1",
    customerFirstName: "Ali",
    area: "وسط البلد",
    notes: "",
    stores: [{ name: "بقالة الخير", items: "رز، 2 زيت" }, { name: "", items: "كيلو لحمة" }],
    settings: settings(),
  });
}

/** يطبّق العملية ويرجّع المستند بعد الدمج (زي ما الـWorker بيعمل). */
function step(order: Record<string, unknown>, action: string, actor: QuickActor, body: Record<string, unknown> = {}) {
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

function accepted() {
  return step(fresh(), "accept", quickCourier);
}

function agreed(estimate = 15000, delivery = 3000) {
  const proposed = step(accepted(), "propose", quickCourier, {
    deliveryPiastres: delivery, estimatedPurchasesPiastres: estimate,
  });
  return step(proposed, "approve", customer, {
    expectedRevision: (proposed.quote as Record<string, unknown>).revision,
  });
}

describe("quick settings", () => {
  it("is disabled until the admin sets enabled: true, with safe defaults", () => {
    const s = resolveQuickSettings(null);
    expect(s.enabled).toBe(false);
    expect(s.prepaidThresholdPiastres).toBe(20000);
    expect(resolveQuickSettings({ enabled: "yes" }).enabled).toBe(false);
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
    const own = { ...fresh(), userId: "cour1" };
    expect(code(() => step(own, "accept", quickCourier))).toBe("403:own_order");
    expect(code(() => step(fresh(), "accept", customer))).toBe("403:not_quick_courier");
  });
});

describe("delivery fee quote", () => {
  it("only the assigned courier proposes, within the admin maximum", () => {
    const a = accepted();
    expect(code(() => step(a, "propose", otherQuickCourier, { deliveryPiastres: 3000, estimatedPurchasesPiastres: 10000 })))
      .toBe("403:forbidden");
    expect(code(() => step(a, "propose", quickCourier, { deliveryPiastres: 20001, estimatedPurchasesPiastres: 10000 })))
      .toBe("400:invalid_delivery");
    expect(code(() => step(a, "propose", quickCourier, { deliveryPiastres: 3000, estimatedPurchasesPiastres: 100001 })))
      .toBe("400:invalid_estimate");
    expect(code(() => step(a, "propose", quickCourier, { deliveryPiastres: 30.5, estimatedPurchasesPiastres: 10000 })))
      .toBe("400:invalid_delivery");
  });
  it("limits the number of proposals", () => {
    let o = accepted();
    for (let i = 0; i < 3; i++) {
      o = step(o, "propose", quickCourier, { deliveryPiastres: 3000 + i, estimatedPurchasesPiastres: 10000 });
    }
    expect(code(() => step(o, "propose", quickCourier, { deliveryPiastres: 2000, estimatedPurchasesPiastres: 10000 })))
      .toBe("409:too_many_proposals");
  });
  it("customer approves only the current revision; courier cannot approve", () => {
    const p1 = step(accepted(), "propose", quickCourier, { deliveryPiastres: 3000, estimatedPurchasesPiastres: 10000 });
    const rev1 = (p1.quote as Record<string, unknown>).revision;
    const p2 = step(p1, "propose", quickCourier, { deliveryPiastres: 4000, estimatedPurchasesPiastres: 10000 });
    expect(code(() => step(p2, "approve", customer, { expectedRevision: rev1 }))).toBe("409:stale_quote");
    expect(code(() => step(p2, "approve", quickCourier, { expectedRevision: (p2.quote as Record<string, unknown>).revision })))
      .toBe("403:forbidden");
    const ok = step(p2, "approve", customer, { expectedRevision: (p2.quote as Record<string, unknown>).revision });
    expect((ok.quote as Record<string, unknown>).agreedDeliveryPiastres).toBe(4000);
  });
  it("cannot approve before any proposal", () => {
    const a = accepted();
    expect(code(() => step(a, "approve", customer, { expectedRevision: (a.quote as Record<string, unknown>).revision })))
      .toBe("409:invalid_state");
  });
});

describe("payment mode by the 200 EGP threshold", () => {
  it("up to 200 EGP (inclusive) is cash on delivery and goes straight to purchasing", () => {
    const o = agreed(20000);
    expect(o.paymentMode).toBe("cod");
    expect(o.status).toBe("purchasing");
  });
  it("above 200 EGP needs an advance confirmed by the courier before purchasing", () => {
    const o = agreed(20001);
    expect(o.paymentMode).toBe("advance");
    expect(o.status).toBe("awaiting_advance");
    expect(code(() => step(o, "receipt", quickCourier, { storeName: "x", amountPiastres: 100, imageUrl: receiptUrl() })))
      .toBe("409:invalid_state");
    expect(code(() => step(o, "advance-received", quickCourier, { amountPiastres: 30000 }))).toBe("409:invalid_state");
    const sent = step(o, "advance-sent", customer, { amountPiastres: 30000, reference: "VF-123" });
    expect(code(() => step(sent, "advance-received", otherQuickCourier, { amountPiastres: 30000 }))).toBe("403:forbidden");
    const confirmed = step(sent, "advance-received", quickCourier, { amountPiastres: 30000 });
    expect(confirmed.status).toBe("purchasing");
    expect(code(() => step(o, "advance-sent", customer, { amountPiastres: 100001 }))).toBe("400:invalid_advance");
  });
});

describe("receipts and totals", () => {
  it("accepts only receipt images uploaded for this order", () => {
    const o = agreed();
    const bad = [
      `https://res.cloudinary.com/g3n5pdfz/image/upload/quick_receipts/other_order_123456789/r.jpg`,
      `https://res.cloudinary.com/evil/image/upload/quick_receipts/${ID}/r.jpg`,
      `https://example.com/quick_receipts/${ID}/r.jpg`,
      `https://res.cloudinary.com/g3n5pdfz/image/upload/special_requests/${ID}/r.jpg`,
    ];
    for (const imageUrl of bad) {
      expect(code(() => step(o, "receipt", quickCourier, { storeName: "x", amountPiastres: 100, imageUrl })))
        .toBe("400:invalid_receipt_image");
    }
    expect(code(() => step(o, "receipt", customer, { storeName: "x", amountPiastres: 100, imageUrl: receiptUrl() })))
      .toBe("403:forbidden");
  });
  it("one service fee for all receipts; locked receipts cannot change", () => {
    let o = agreed(60000, 4000);
    // تقدير 600 جنيه > 200 → مقدم. نكمل التحويل الأول.
    o = step(o, "advance-sent", customer, { amountPiastres: 60000 });
    o = step(o, "advance-received", quickCourier, { amountPiastres: 60000 });
    o = step(o, "receipt", quickCourier, { storeName: "الخير", amountPiastres: 20000, imageUrl: receiptUrl(1) });
    o = step(o, "receipt", quickCourier, { storeName: "الجزار", amountPiastres: 40000, imageUrl: receiptUrl(2) });
    const locked = step(o, "lock-receipts", quickCourier);
    expect(locked.status).toBe("receipts_locked");
    expect(locked.totals).toEqual({ purchases: 60000, serviceFee: 1200, delivery: 4000, prepaid: 60000, due: 5200 });
    expect(code(() => step(locked, "receipt", quickCourier, { storeName: "x", amountPiastres: 1, imageUrl: receiptUrl(3) })))
      .toBe("409:invalid_state");
    expect(code(() => step(locked, "receipt-remove", quickCourier, { index: 0 }))).toBe("409:invalid_state");
  });
  it("negative due = courier refunds the customer; COD has no prepaid", () => {
    let adv = agreed(30000, 3000);
    adv = step(adv, "advance-sent", customer, { amountPiastres: 50000 });
    adv = step(adv, "advance-received", quickCourier, { amountPiastres: 50000 });
    adv = step(adv, "receipt", quickCourier, { storeName: "x", amountPiastres: 25000, imageUrl: receiptUrl() });
    expect(quickTotals(adv).due).toBe(25000 + 500 + 3000 - 50000);
    let cod = agreed(15000, 3000);
    cod = step(cod, "receipt", quickCourier, { storeName: "x", amountPiastres: 15000, imageUrl: receiptUrl() });
    expect(quickTotals(cod)).toEqual({ purchases: 15000, serviceFee: 500, delivery: 3000, prepaid: 0, due: 18500 });
  });
  it("records purchases over the agreed estimate for the admin (courier's risk)", () => {
    let o = agreed(15000, 3000);
    o = step(o, "receipt", quickCourier, { storeName: "x", amountPiastres: 18000, imageUrl: receiptUrl() });
    expect(step(o, "lock-receipts", quickCourier).overEstimatePiastres).toBe(3000);
    expect(code(() => step(agreed(), "lock-receipts", quickCourier))).toBe("409:no_receipts");
  });
  it("can remove a receipt before locking", () => {
    let o = agreed();
    o = step(o, "receipt", quickCourier, { storeName: "a", amountPiastres: 100, imageUrl: receiptUrl(1) });
    o = step(o, "receipt", quickCourier, { storeName: "b", amountPiastres: 200, imageUrl: receiptUrl(2) });
    o = step(o, "receipt-remove", quickCourier, { index: 0 });
    expect((o.receipts as Array<Record<string, unknown>>).map((r) => r.storeName)).toEqual(["b"]);
    expect(code(() => step(o, "receipt-remove", quickCourier, { index: 5 }))).toBe("400:invalid_index");
  });
});

describe("editing, cancelling and releasing", () => {
  it("customer edits freely before acceptance; after acceptance the quote resets", () => {
    const edited = step(fresh(), "edit", customer, { stores: [{ name: "", items: "عيش" }] });
    expect(edited.stores).toEqual([{ name: "", items: "عيش" }]);
    const p = step(accepted(), "propose", quickCourier, { deliveryPiastres: 3000, estimatedPurchasesPiastres: 10000 });
    const e2 = step(p, "edit", customer, { stores: [{ name: "", items: "عيش وجبنة" }] });
    const q = e2.quote as Record<string, unknown>;
    expect(q.proposedDeliveryPiastres).toBe(null);
    expect(q.courierId).toBe("cour1");
    expect(code(() => step(agreed(), "edit", customer, { stores: [{ name: "", items: "x" }] }))).toBe("409:invalid_state");
    expect(code(() => step(fresh(), "edit", quickCourier, { stores: [{ name: "", items: "x" }] }))).toBe("403:forbidden");
  });
  it("customer cancels before purchasing only; admin any time before delivery", () => {
    expect(step(fresh(), "cancel", customer).status).toBe("cancelled");
    expect(code(() => step(agreed(), "cancel", customer))).toBe("409:not_cancellable");
    expect(code(() => step(agreed(), "cancel", quickCourier))).toBe("403:forbidden");
    const byAdmin = step(agreed(), "cancel", admin, { reason: "مشكلة" });
    expect(byAdmin.cancelledBy).toBe("admin");
    expect(code(() => step(byAdmin, "edit", customer, { stores: [{ name: "", items: "x" }] }))).toBe("409:final");
  });
  it("flags a refund when the customer cancels after sending the advance", () => {
    const sent = step(agreed(30000), "advance-sent", customer, { amountPiastres: 30000 });
    expect(step(sent, "cancel", customer).advanceRefundDue).toBe(true);
    expect(step(fresh(), "cancel", customer).advanceRefundDue).toBe(false);
  });
  it("courier can release before the advance is sent; order reopens with a fresh quote", () => {
    const released = step(agreed(30000), "release", quickCourier);
    expect(released.status).toBe("open");
    expect(released.courierId).toBe("");
    expect((released.quote as Record<string, unknown>).agreedDeliveryPiastres).toBe(null);
    expect(step(released, "accept", otherQuickCourier).courierId).toBe("cour2");
    const sent = step(agreed(30000), "advance-sent", customer, { amountPiastres: 30000 });
    expect(code(() => step(sent, "release", quickCourier))).toBe("409:not_releasable");
    expect(code(() => step(agreed(), "release", quickCourier))).toBe("409:not_releasable");
  });
});

describe("delivery", () => {
  it("only after receipts are locked, by the assigned courier; fee is owed by the courier", () => {
    let o = agreed(15000, 3000);
    o = step(o, "receipt", quickCourier, { storeName: "x", amountPiastres: 15000, imageUrl: receiptUrl() });
    expect(quickDeliveryBlocker(o, "cour1")).not.toBe(null);
    const locked = step(o, "lock-receipts", quickCourier);
    expect(quickDeliveryBlocker(locked, "cour2")).not.toBe(null);
    expect(quickDeliveryBlocker(locked, "cour1")).toBe(null);
    const done = quickDeliveredPatch(locked, "cour1", now);
    expect(done.status).toBe("delivered");
    expect(done.courierOwedPiastres).toBe(500);
    expect(done.collectedPiastres).toBe(18500);
  });
  it("rejects unknown actions", () => {
    expect(code(() => step(fresh(), "hack", customer))).toBe("404:unknown_action");
  });
});
