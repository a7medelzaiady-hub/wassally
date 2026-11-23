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
  "orders/order1": { userId: sv("invited"), status: sv("delivered"), deliveredAt: { timestampValue: "1970-01-01T00:00:00.200Z" } },
  "referral_first_orders/invited": { invitedUid: sv("invited"), firstCompletedOrderId: sv("order1"), completedAtMs: iv(200) },
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
const evidence = { invitedUid: "invited", firstOrderId: "order1" };

describe("canonical first-order referral verifier", () => {
  it("derives reward from server-owned attribution, order and policy", async () => {
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toEqual({
      grantId: "customer_invited", inviterUid: "inviter", invitedUid: "invited",
      sourceOrderId: "order1", amount: 20, unit: "points", policyVersion: 2,
    });
  });
  it("enforces capped rewards using trusted award counter", async () => {
    const original = records["app_info/referral_config"]!;
    const policies = (original.policies as { mapValue: { fields: Record<string, unknown> } }).mapValue.fields;
    const customer = policies.customer as { mapValue: { fields: Record<string, unknown> } };
    const previous = customer.mapValue.fields.maxPerInviter;
    customer.mapValue.fields.maxPerInviter = iv(1);
    try {
      records["referral_balances/inviter"] = { customerAwardsCount: iv(1) };
      await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
      records["referral_balances/inviter"] = { customerAwardsCount: iv(0) };
      await expect(verifyFirstOrderReferral(read, evidence)).resolves.not.toBeNull();
    } finally {
      delete records["referral_balances/inviter"];
      if (previous === undefined) delete customer.mapValue.fields.maxPerInviter;
      else customer.mapValue.fields.maxPerInviter = previous;
    }
  });
  it("rejects an existing balance with no trusted award counter", async () => {
    records["referral_balances/inviter"] = { points: iv(500) };
    try {
      await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    } finally {
      delete records["referral_balances/inviter"];
    }
  });
  it("rejects missing or mismatched server-owned first order index", async () => {
    const original = records["referral_first_orders/invited"]!;
    delete records["referral_first_orders/invited"];
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    records["referral_first_orders/invited"] = {
      invitedUid: sv("invited"), firstCompletedOrderId: sv("another_order"), completedAtMs: iv(200),
    };
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    records["referral_first_orders/invited"] = original;
  });
  it("rejects a first-order index whose completion time disagrees with the order", async () => {
    const original = records["referral_first_orders/invited"]!;
    records["referral_first_orders/invited"] = {
      invitedUid: sv("invited"), firstCompletedOrderId: sv("order1"), completedAtMs: iv(201),
    };
    try {
      await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    } finally {
      records["referral_first_orders/invited"] = original;
    }
  });
  it("rejects wrong customer, missing attribution and unfinished order", async () => {
    const original = records["orders/order1"]!;
    records["orders/order1"] = { ...original, userId: sv("other") };
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    records["orders/order1"] = { ...original, status: sv("new") };
    await expect(verifyFirstOrderReferral(read, evidence)).resolves.toBeNull();
    records["orders/order1"] = original;
    await expect(verifyFirstOrderReferral(read, { ...evidence, invitedUid: "unknown" }))
      .resolves.toBeNull();
  });
});
