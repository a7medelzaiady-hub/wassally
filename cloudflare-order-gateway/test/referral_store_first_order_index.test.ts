import { describe, expect, it } from "vitest";
import { buildFirstStoreOrderWrite } from "../src/referral_store_first_order_index";
const root = "projects/test/databases/(default)/documents";
describe("first successful store order index", () => {
  it("uses create-only precondition for a stable store identity", () => {
    const write = buildFirstStoreOrderWrite(root, {
      invitedStoreId: "store1", orderId: "order1", completedAtMs: 500,
    });
    expect(write.currentDocument).toEqual({ exists: false });
    expect(write.update.name).toBe(`${root}/referral_store_first_orders/store1`);
    expect(write.update.fields.completedAtMs).toEqual({ integerValue: "500" });
  });
  it("rejects invalid identities and timestamps", () => {
    expect(() => buildFirstStoreOrderWrite(root, {
      invitedStoreId: "../store", orderId: "order1", completedAtMs: 500,
    })).toThrow();
    expect(() => buildFirstStoreOrderWrite(root, {
      invitedStoreId: "store1", orderId: "order1", completedAtMs: 0,
    })).toThrow();
  });
});
