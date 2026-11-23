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
  "storeOwners/owner2": { storeId: sv("store1"), active: bv(true) },
  "storeOwners/owner1": { storeId: sv("originalStore"), active: bv(true) },
  "stores/store1": { active: bv(true), approved: bv(true), approvedAtMs: iv(110), activatedAtMs: iv(120) },
  "orders/order1": { storeId: sv("store1"), status: sv("delivered"), deliveredAt: { timestampValue: "1970-01-01T00:00:00.200Z" } },
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
  it("honors a per-channel cap using trusted store owner award count", async () => {
    const key = "referral_balances/owner1";
    const originalPolicy = docs["app_info/referral_config"]!;
    const originalBalance = docs[key];
    try {
      const policies = (originalPolicy.policies as { mapValue: { fields: Record<string, unknown> } }).mapValue.fields;
      const ownerPolicy = policies.store_owner as { mapValue: { fields: Record<string, unknown> } };
      docs["app_info/referral_config"] = {
        ...originalPolicy,
        policies: { mapValue: { fields: {
          ...policies,
          store_owner: { mapValue: { fields: { ...ownerPolicy.mapValue.fields, maxPerInviter: iv(1) } } },
        } } },
      };
      docs[key] = { storeOwnerAwardsCount: iv(1), customerAwardsCount: iv(0) };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      docs[key] = { storeOwnerAwardsCount: iv(0), customerAwardsCount: iv(100) };
      await expect(verifyStoreReferral(read, evidence)).resolves.toMatchObject({ grantId: "store_owner_store1" });
    } finally {
      docs["app_info/referral_config"] = originalPolicy;
      if (originalBalance) docs[key] = originalBalance; else delete docs[key];
    }
  });
  it("rejects store referral when invited account does not own the store", async () => {
    const original = docs["storeOwners/owner2"]!;
    try {
      docs["storeOwners/owner2"] = { storeId: sv("differentStore"), active: bv(true) };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      docs["storeOwners/owner2"] = { storeId: sv("store1"), active: bv(false) };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      docs["storeOwners/owner2"] = { storeId: sv("store1") };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      delete docs["storeOwners/owner2"];
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
    } finally { docs["storeOwners/owner2"] = original; }
  });
  it("rejects an inviter who is not an active store owner", async () => {
    const original = docs["storeOwners/owner1"]!;
    try {
      docs["storeOwners/owner1"] = { storeId: sv("originalStore"), active: bv(false) };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      docs["storeOwners/owner1"] = { storeId: sv("originalStore") };
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
      delete docs["storeOwners/owner1"];
      await expect(verifyStoreReferral(read, evidence)).resolves.toBeNull();
    } finally { docs["storeOwners/owner1"] = original; }
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
