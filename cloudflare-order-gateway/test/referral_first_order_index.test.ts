import { describe, expect, it } from "vitest";
import { buildFirstCompletedOrderWrite } from "../src/referral_first_order_index";

const root = "projects/demo/databases/(default)/documents";
describe("first successful order immutable index", () => {
  it("creates a first-writer-wins record with atomic create-only precondition", () => {
    expect(buildFirstCompletedOrderWrite(root, {
      invitedUid: "user1", orderId: "order1", completedAtMs: 123,
    })).toEqual({
      update: {
        name: `${root}/referral_first_orders/user1`,
        fields: {
          invitedUid: { stringValue: "user1" },
          firstCompletedOrderId: { stringValue: "order1" },
          completedAtMs: { integerValue: "123" },
        },
      },
      currentDocument: { exists: false },
    });
  });
  it("rejects unsafe paths and timestamps", () => {
    expect(() => buildFirstCompletedOrderWrite(root, {
      invitedUid: "user/1", orderId: "order1", completedAtMs: 123,
    })).toThrow();
    expect(() => buildFirstCompletedOrderWrite(root, {
      invitedUid: "user1", orderId: "order1", completedAtMs: -1,
    })).toThrow();
    expect(() => buildFirstCompletedOrderWrite("wrong", {
      invitedUid: "user1", orderId: "order1", completedAtMs: 123,
    })).toThrow();
  });
});
