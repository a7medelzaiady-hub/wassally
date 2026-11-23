import { describe, expect, it, vi } from "vitest";
import { verifyFirstOrderReferral } from "../src/referral_first_order";

const sv = (value: string) => ({ stringValue: value });
const iv = (value: number) => ({ integerValue: String(value) });
const policy = (channel: string, unit: string) => ({
  mapValue: { fields: {
    enabled: { booleanValue: true }, channel: sv(channel), unit: sv(unit), amount: iv(20),
  } },
});
const records: Record<string, Record<string, unknown>> = {
  "referral_attributions/invited": {
    invitedUid: sv("invited"), inviterUid: sv("inviter"), channel: sv("customer"), claimedAtMs: iv(100),
  },
  "orders/order1": { customerId: sv("invited"), status: sv("delivered"), deliveredAtMs: iv(200) },
  "app_info/referral_config": {
    version: iv(2),
    policies: { mapValue: { fields: {
      customer: policy("customer", "points"),
      marketer: policy("marketer", "cash_minor"),
      store_owner: policy("store_owner", "commission_discount_minor"),
    } } },
  },
};
const read = vi.fn(async (collection: string, id: string) => records[`${collection}/${id}`] ?? null);
const evidence = { invitedUid: "invited", firstOrderId: "order1", verifiedFirstOrder: true };

describe("canonical first-order referral verifier", () => {
  it("derives reward from server-owned attribution, order and policy", async () => {
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toEqual({
      grantId: "customer_invited", inviterUid: "inviter", invitedUid: "invited",
      sourceOrderId: "order1", amount: 20, unit: "points", policyVersion: 2,
    });
  });
  it("rejects unverified first-order status without reading anything", async () => {
    read.mockClear();
    await expect(verifyFirstOrderReferral(read, { ...evidence, verifiedFirstOrder: false }))
      .resolves.toBeNull();
    expect(read).not.toHaveBeenCalled();
  });
  it("rejects wrong customer, missing attribution and unfinished order", async () => {
    const original = records["orders/order1"]!;
    records["orders/order1"] = { ...original, customerId: sv("other") };
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    records["orders/order1"] = { ...original, status: sv("new") };
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    records["orders/order1"] = original;
    await expect(verifyFirstOrderReferral(read, { ...evidence, invitedUid: "unknown" }))
      .resolves.toBeNull();
  });
});
