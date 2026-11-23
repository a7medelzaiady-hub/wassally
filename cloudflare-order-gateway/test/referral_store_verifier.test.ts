import { describe, expect, it } from "vitest";
import { verifyStoreReferral } from "../src/referral_store_verifier";
const sv = (v: string) => ({ stringValue: v });
const iv = (v: number) => ({ integerValue: String(v) });
const bv = (v: boolean) => ({ booleanValue: v });
const policy = (channel: string, unit: string) => ({ mapValue: { fields: {
  enabled: bv(true), channel: sv(channel), unit: sv(unit), amount: iv(50),
} } });
const docs: Record<string, Record<string, unknown>> = {
  "referral_store_attributions/store1": {
    invitedStoreId: sv("store1"), invitedUid: sv("owner2"), inviterUid: sv("owner1"),
    channel: sv("store_owner"), claimedAtMs: iv(100),
  },
  "stores/store1": { active: bv(true), approved: bv(true), approvedAtMs: iv(110), activatedAtMs: iv(120) },
  "orders/order1": { storeId: sv("store1"), status: sv("delivered"), deliveredAt: iv(200) },
  "referral_store_first_orders/store1": {
    invitedStoreId: sv("store1"), firstCompletedOrderId: sv("order1"), completedAtMs: iv(200),
  },
  "app_info/referral_config": { version: iv(1), policies: { mapValue: { fields: {
    customer: policy("customer", "points"), marketer: policy("marketer", "cash_minor"),
    store_owner: policy("store_owner", "commission_discount_minor"),
  } } } },
};
const read = async (c: string, id: string) => docs[`${c}/${id}`] ?? null;
const evidence = { invitedStoreId: "store1", firstOrderId: "order1" };
describe("store referral verification", () => {
  it("credits commission discount only after approval, activation and first delivery", async () => {
    await expect(verifyStoreReferral(read, evidence)).resolves.toMatchObject({
      grantId: "store_owner_store1", inviterUid: "owner1", invitedUid: "owner2",
      unit: "commission_discount_minor", amount: 50,
    });
  });
  it("rejects unapproved or inactive stores", async () => {
    const original = docs["stores/store1"]!;
    try {
      docs["stores/store1"] = { ...original, approved: bv(false) };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      docs["stores/store1"] = { ...original, active: bv(false) };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
    } finally { docs["stores/store1"] = original; }
  });
  it("rejects missing or mismatched first store order", async () => {
    const original = docs["referral_store_first_orders/store1"]!;
    try {
      delete docs["referral_store_first_orders/store1"];
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      docs["referral_store_first_orders/store1"] = {
        ...original, firstCompletedOrderId: sv("other"),
      };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
    } finally { docs["referral_store_first_orders/store1"] = original; }
  });
});
