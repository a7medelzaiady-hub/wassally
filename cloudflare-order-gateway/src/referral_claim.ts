import { isReferralCode, normalizeReferralCode, type ReferralChannel } from "./referrals";

/**
 * Validates the server-owned code record and registration evidence before
 * creating an immutable attribution. All evidence must be fetched by the
 * Worker, not accepted from request JSON.
 */
export interface ReferralCodeRecord {
  code: string;
  inviterUid: string;
  channel: ReferralChannel;
  active: boolean;
}

export interface RegistrationEvidence {
  invitedUid: string;
  /** Verified Firebase Auth account creation timestamp in milliseconds. */
  accountCreatedAtMs: number;
  /** Server timestamp for this claim. */
  claimAtMs: number;
  /** Set by Worker from Auth/Firestore, not the app. */
  alreadyAttributed: boolean;
  /** This is a new registration claim, not a later login. */
  registrationWindowMs: number;
}

export type ReferralClaimDecision =
  | { allowed: true; code: string; inviterUid: string; channel: ReferralChannel }
  | { allowed: false; reason: string };

const validUid = (id: string) => /^[A-Za-z0-9_-]{1,128}$/.test(id);

export function decideReferralClaim(
  requestedCode: string,
  record: ReferralCodeRecord | null,
  evidence: RegistrationEvidence,
): ReferralClaimDecision {
  const code = normalizeReferralCode(requestedCode);
  if (!isReferralCode(code)) return { allowed: false, reason: "invalid_code" };
  if (!record || !record.active || normalizeReferralCode(record.code) !== code) {
    return { allowed: false, reason: "inactive_or_missing_code" };
  }
  if (!validUid(evidence.invitedUid) || !validUid(record.inviterUid) ||
      evidence.invitedUid === record.inviterUid) {
    return { allowed: false, reason: "invalid_actors" };
  }
  if (!["customer", "marketer", "store_owner"].includes(record.channel)) {
    return { allowed: false, reason: "invalid_channel" };
  }
  if (evidence.alreadyAttributed) return { allowed: false, reason: "already_attributed" };
  if (!Number.isSafeInteger(evidence.accountCreatedAtMs) ||
      !Number.isSafeInteger(evidence.claimAtMs) ||
      !Number.isSafeInteger(evidence.registrationWindowMs) ||
      evidence.accountCreatedAtMs <= 0 || evidence.registrationWindowMs <= 0 ||
      evidence.registrationWindowMs > 3600000 ||
      evidence.claimAtMs < evidence.accountCreatedAtMs ||
      evidence.claimAtMs - evidence.accountCreatedAtMs > evidence.registrationWindowMs) {
    return { allowed: false, reason: "not_first_registration" };
  }
  return { allowed: true, code, inviterUid: record.inviterUid, channel: record.channel };
}
