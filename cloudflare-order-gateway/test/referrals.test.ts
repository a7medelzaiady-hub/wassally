import { describe, expect, it } from "vitest";
import {
  decideReferralReward, isReferralCode, normalizeReferralCode,
  referralGrantId, type ReferralFacts, type ReferralPolicy,
} from "../src/referrals";

const policy: ReferralPolicy = {
  enabled: true, channel: "customer", unit: "points", amount: 100,
};
const facts: ReferralFacts = {
  inviterUid: "inviter", invitedUid: "invited", channel: "customer",
  attributedAt: 100, firstCompletedOrderAt: 200, previousAwards: 0,
};

describe("referral eligibility (no payout side effects)", () => {
  it("accepts only normalized code formats", () => {
    expect(normalizeReferralCode(" abcd12 ")).toBe("ABCD12");
    expect(isReferralCode("ABCD12")).toBe(true);
    expect(isReferralCode("abcd12")).toBe(false);
    expect(isReferralCode("ABC-12")).toBe(false);
  });

  it("permits a qualified first order", () => {
    expect(decideReferralReward(policy, facts)).toEqual({
      eligible: true, grantId: "customer_invited", amount: 100, unit: "points",
    });
  });

  it.each([
    [{ enabled: false }, {}, "disabled"],
    [{ amount: 0 }, {}, "invalid_amount"],
    [{ amount: 1.5 }, {}, "invalid_amount"],
    [{ unit: "cash_minor" as const }, {}, "invalid_reward_unit"],
    [{}, { inviterUid: "bad/id" }, "self_or_missing"],
    [{}, { invitedUid: "bad/id" }, "self_or_missing"],
    [{ channel: "marketer" as const }, {}, "channel_mismatch"],
    [{}, { inviterUid: "invited" }, "self_or_missing"],
    [{}, { firstCompletedOrderAt: undefined }, "first_order_not_qualified"],
    [{}, { firstCompletedOrderAt: 99 }, "first_order_not_qualified"],
    [{ maxPerInviter: 0 }, {}, "limit_reached"],
    [{ maxPerInviter: 1 }, { previousAwards: 1 }, "limit_reached"],
  ])("rejects invalid reward: %s / %s", (p, f, reason) => {
    expect(decideReferralReward({ ...policy, ...p }, { ...facts, ...f }))
      .toEqual({ eligible: false, reason });
  });

  it("requires store approval, activation, and a later first order", () => {
    const p: ReferralPolicy = {
      ...policy, channel: "store_owner", unit: "commission_discount_minor",
    };
    const f: ReferralFacts = { ...facts, channel: "store_owner", invitedStoreId: "store-001" };
    expect(decideReferralReward(p, { ...f, invitedStoreId: undefined })).toEqual({ eligible: false, reason: "missing_store_identity" });
    expect(decideReferralReward(p, f)).toEqual({
      eligible: false, reason: "store_not_qualified",
    });
    expect(decideReferralReward(p, {
      ...f, storeApprovedAt: 120, storeActivatedAt: 150,
    })).toEqual({ eligible: true, grantId: "store_owner_store-001", amount: 100, unit: "commission_discount_minor" });
    expect(decideReferralReward(p, {
      ...f, storeApprovedAt: 120, storeActivatedAt: 210,
    }).eligible).toBe(false);
    expect(decideReferralReward(p, {
      ...f, storeApprovedAt: 210, storeActivatedAt: 150,
    }).eligible).toBe(false);
  });

  it("uses stable grant identifiers and rejects path injection", () => {
    expect(referralGrantId("marketer", "uid_123")).toBe("marketer_uid_123");
    expect(() => referralGrantId("customer", "a/b")).toThrow();
    expect(() => referralGrantId("customer", "")).toThrow();
  });
});
