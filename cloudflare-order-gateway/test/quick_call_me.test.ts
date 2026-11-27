import { describe, expect, it } from "vitest";
import {
  QuickRuleError,
  applyQuickAction,
  isCallMeOrder,
  newQuickOrder,
  resolveQuickSettings,
  validateQuickStores,
  type QuickActor,
} from "../src/quick_orders";

const ID = "cust1_abcdefghijklmnop";
const ctx = { orderId: ID, now: new Date("2026-11-27T12:00:00Z"), cloudName: "g3n5pdfz" };
const customer: QuickActor = { uid: "cust1", role: "customer" };
const courier: QuickActor = { uid: "cour1", role: "courier", name: "Mido", quickEnabled: true };
type Doc = Record<string, unknown>;

function callMeOrder(stores = validateQuickStores([{ name: "", items: "" }], true)): Doc {
  return newQuickOrder({
    uid: "cust1",
    customerFirstName: "Ali",
    area: "وسط البلد",
    notes: "",
    stores,
    settings: resolveQuickSettings({ enabled: true }),
    callMe: true,
  });
}

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

describe("«كلّمني»", () => {
  it("بيتسجل على الطلب من غير أصناف، ومش بيتسجل على المشاوير", () => {
    const o = callMeOrder();
    expect(o.callMe).toBe(true);
    expect(isCallMeOrder(o)).toBe(true);
    const errand = newQuickOrder({
      uid: "cust1", customerFirstName: "Ali", area: "", notes: "",
      stores: [{ name: "", items: "استلام ورق من البنك" }],
      settings: resolveQuickSettings({ enabled: true }), kind: "errand", errandType: "documents", callMe: true,
    });
    expect(errand.callMe).toBeUndefined();
    const normal = newQuickOrder({
      uid: "cust1", customerFirstName: "Ali", area: "", notes: "",
      stores: [{ name: "", items: "رز" }], settings: resolveQuickSettings({ enabled: true }),
    });
    expect(normal.callMe).toBeUndefined();
  });

  it("المندوب لازم يكتب اللي اتفقوا عليه قبل الشراء، وبيظهر كطلب العميل", () => {
    const accepted = step(callMeOrder(), "accept", courier);
    expect(code(() => step(accepted, "start-purchase", courier, { estimatedPurchasesPiastres: 20000 })))
      .toBe("400:agreed_items_required");
    expect(code(() => step(accepted, "start-purchase", courier,
      { estimatedPurchasesPiastres: 20000, agreedItems: "  " }))).toBe("400:agreed_items_required");
    const started = step(accepted, "start-purchase", courier,
      { estimatedPurchasesPiastres: 20000, agreedItems: "2 كيلو طماطم، علبة زيت" });
    expect(started.status).toBe("purchasing");
    expect(started.stores).toEqual([{ name: "", items: "2 كيلو طماطم، علبة زيت" }]);
    expect(started.agreedItems).toBe("2 كيلو طماطم، علبة زيت");
  });

  it("لو العميل كتب حاجة كمان، الكتابة اختيارية وما بتمسحش طلبه", () => {
    const own = callMeOrder(validateQuickStores([{ name: "", items: "رز" }], true));
    const accepted = step(own, "accept", courier);
    const started = step(accepted, "start-purchase", courier, { estimatedPurchasesPiastres: 20000 });
    expect(started.stores).toEqual([{ name: "", items: "رز" }]);
    const withNote = step(accepted, "start-purchase", courier,
      { estimatedPurchasesPiastres: 20000, agreedItems: "رز وسكر" });
    expect(withNote.stores).toEqual([{ name: "", items: "رز" }]);
    expect(withNote.agreedItems).toBe("رز وسكر");
  });

  it("العميل يقدر يعدّل قبل القبول من غير ما يكتب أصناف", () => {
    const edited = step(callMeOrder(), "edit", customer, { stores: [], notes: "كلمني بعد العصر" });
    expect(edited.notes).toBe("كلمني بعد العصر");
  });

  it("الطلب العادي لسه بيرفض المحل الفاضي", () => {
    expect(code(() => validateQuickStores([{ name: "", items: "" }]))).toBe("400:invalid_stores");
  });
});
