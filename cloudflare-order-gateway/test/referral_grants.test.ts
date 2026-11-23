import { describe, expect, it } from "vitest";
import { buildReferralGrantWrites, type VerifiedReferralGrant } from "../src/referral_grants";

const root = "projects/wasally-test/databases/(default)/documents";
const grant: VerifiedReferralGrant = {
  grantId: "customer_invited", inviterUid: "inviter", invitedUid: "invited",
  sourceOrderId: "order-1", amount: 100, unit: "points", policyVersion: 1,
};

describe("referral grant atomic write plan", () => {
  it("requires create-only grant and atomic balance increment", () => {
    const writes = buildReferralGrantWrites(root, grant);
    expect(writes).toHaveLength(2);
    expect(writes[0].currentDocument).toEqual({ exists: false });
    expect(writes[0].update?.name).toBe(`${root}/referral_grants/customer_invited`);
    expect(writes[1].transform?.document).toBe(`${root}/referral_balances/inviter`);
    expect(writes[1].transform?.fieldTransforms).toEqual([{
      fieldPath: "points", increment: { integerValue: "100" },
    }, {
      fieldPath: "customerAwardsCount", increment: { integerValue: "1" },
    }]);
  });

  it.each([
    ["cash_minor", "cashMinor"],
    ["commission_discount_minor", "commissionDiscountMinor"],
  ] as const)("maps %s into server-owned balance field", (unit, field) => {
    const channel = unit === "cash_minor" ? "marketer" : "store_owner";
    expect(buildReferralGrantWrites(root, { ...grant, grantId: `${channel}_invited`, unit })[1]
      .transform?.fieldTransforms[0].fieldPath).toBe(field);
  });

  it("rejects mismatched grant identity and channel reward units", () => {
    expect(() => buildReferralGrantWrites(root, { ...grant, grantId: "customer_other" })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, unit: "cash_minor" })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, grantId: "marketer_invited", unit: "points" })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, grantId: "store_owner_store1", unit: "points" })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, grantId: "store_owner_", unit: "cash_minor" })).toThrow("referral grant identity mismatch");
  });

  it("rejects unsafe IDs, invalid amounts, self referrals and invalid roots", () => {
    expect(() => buildReferralGrantWrites(root, { ...grant, grantId: "x/y" })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, inviterUid: "invited" })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, amount: 0 })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, amount: 1.5 })).toThrow();
    expect(() => buildReferralGrantWrites(root, { ...grant, policyVersion: 0 })).toThrow();
    expect(() => buildReferralGrantWrites("bad/root", grant)).toThrow();
  });
});
