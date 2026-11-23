/**
 * Referral eligibility policy (pure functions).
 * SECURITY: This module does not grant rewards or write to Firestore.
 * The Worker must fetch all facts from trusted documents, verify the
 * authenticated actor, and atomically reserve a unique grant document.
 */
export type ReferralChannel = "customer" | "marketer" | "store_owner";
export type RewardUnit = "points" | "cash_minor" | "commission_discount_minor";

export interface ReferralPolicy {
  enabled: boolean;
  channel: ReferralChannel;
  unit: RewardUnit;
  amount: number;
  maxPerInviter?: number;
}

export interface ReferralFacts {
  inviterUid: string;
  invitedUid: string;
  /** Required for store invitations: one award per store, not per owner account. */
  invitedStoreId?: string;
  channel: ReferralChannel;
  /** Set once on registration; never editable by the invited account. */
  attributedAt: number;
  /** Authoritative first successful order timestamp. */
  firstCompletedOrderAt?: number;
  /** For a newly invited store, admin approval and activation are mandatory. */
  storeApprovedAt?: number;
  storeActivatedAt?: number;
  /** Total already-awarded referrals, from trusted server-side records. */
  previousAwards: number;
}

export type ReferralDecision =
  | { eligible: true; grantId: string; amount: number; unit: RewardUnit }
  | { eligible: false; reason: string };

export function normalizeReferralCode(input: string): string {
  return input.trim().toUpperCase();
}

export function isReferralCode(input: string): boolean {
  return /^[A-Z0-9]{6,12}$/.test(input);
}

/** Stable idempotency key; not an authorization credential. */
export function referralGrantId(channel: ReferralChannel, invitedUid: string): string {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(invitedUid)) {
    throw new Error("invalid invited uid");
  }
  return `${channel}_${invitedUid}`;
}

export function decideReferralReward(
  policy: ReferralPolicy,
  facts: ReferralFacts,
): ReferralDecision {
  if (!policy.enabled) return { eligible: false, reason: "disabled" };
  if (policy.channel !== facts.channel) return { eligible: false, reason: "channel_mismatch" };
  const allowedUnits: Record<ReferralChannel, readonly RewardUnit[]> = {
    customer: ["points"],
    marketer: ["cash_minor"],
    store_owner: ["cash_minor", "commission_discount_minor"],
  };
  if (!allowedUnits[policy.channel]?.includes(policy.unit)) {
    return { eligible: false, reason: "invalid_reward_unit" };
  }
  if (!Number.isSafeInteger(policy.amount) || policy.amount <= 0) {
    return { eligible: false, reason: "invalid_amount" };
  }
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(facts.inviterUid) ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(facts.invitedUid) ||
      facts.inviterUid === facts.invitedUid) {
    return { eligible: false, reason: "self_or_missing" };
  }
  if (!Number.isSafeInteger(facts.attributedAt) || facts.attributedAt <= 0) {
    return { eligible: false, reason: "missing_attribution" };
  }
  if (!Number.isSafeInteger(facts.firstCompletedOrderAt) ||
      (facts.firstCompletedOrderAt ?? 0) < facts.attributedAt) {
    return { eligible: false, reason: "first_order_not_qualified" };
  }
  if (!Number.isSafeInteger(facts.previousAwards) || facts.previousAwards < 0) {
    return { eligible: false, reason: "invalid_award_count" };
  }
  if (policy.maxPerInviter !== undefined &&
      (!Number.isSafeInteger(policy.maxPerInviter) || policy.maxPerInviter < 0 ||
       facts.previousAwards >= policy.maxPerInviter)) {
    return { eligible: false, reason: "limit_reached" };
  }
  if (facts.channel === "store_owner") {
    if (!facts.invitedStoreId || !/^[A-Za-z0-9_-]{1,128}$/.test(facts.invitedStoreId)) {
      return { eligible: false, reason: "missing_store_identity" };
    }
    if (!Number.isSafeInteger(facts.storeApprovedAt) ||
        !Number.isSafeInteger(facts.storeActivatedAt) ||
        (facts.storeApprovedAt ?? 0) <= 0 || (facts.storeActivatedAt ?? 0) <= 0 ||
        (facts.firstCompletedOrderAt ?? 0) < (facts.storeActivatedAt ?? 0) ||
        (facts.firstCompletedOrderAt ?? 0) < (facts.storeApprovedAt ?? 0)) {
      return { eligible: false, reason: "store_not_qualified" };
    }
  }
  return {
    eligible: true,
    grantId: referralGrantId(facts.channel, facts.channel === "store_owner" ? facts.invitedStoreId ?? "" : facts.invitedUid),
    amount: policy.amount,
    unit: policy.unit,
  };
}
