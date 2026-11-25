import { isReferralCode, normalizeReferralCode, type CodeReferralChannel } from "./referrals";

/**
 * Reserve a unique referral code with Firestore create-only precondition.
 * Worker MUST verify authenticated issuer and permissions for the channel.
 * Marketer codes MUST be issued by an admin; callers must not accept
 * inviterUid/channel from an untrusted request body.
 */
export interface VerifiedCodeIssuer {
  code: string;
  inviterUid: string;
  channel: CodeReferralChannel;
  issuedAtMs: number;
  issuedByUid: string;
  /** Verified admin status, resolved by Worker from trusted roles. */
  issuerIsAdmin: boolean;
}

const validId = (id: string) => /^[A-Za-z0-9_-]{1,128}$/.test(id);

export function buildReferralCodeReservation(root: string, issuer: VerifiedCodeIssuer) {
  if (!/^projects\/[A-Za-z0-9_-]+\/databases\/\(default\)\/documents$/.test(root)) {
    throw new Error("invalid database root");
  }
  const code = normalizeReferralCode(issuer.code);
  if (!isReferralCode(code)) throw new Error("invalid referral code");
  if (!validId(issuer.inviterUid) || !validId(issuer.issuedByUid)) {
    throw new Error("invalid issuer");
  }
  if (!["customer", "marketer", "store_owner"].includes(issuer.channel)) {
    throw new Error("invalid channel");
  }
  if (typeof issuer.issuerIsAdmin !== "boolean") throw new Error("invalid issuer role");
  if (issuer.channel === "marketer" && !issuer.issuerIsAdmin) {
    throw new Error("marketer codes require admin issuance");
  }
  if (issuer.channel !== "marketer" && !issuer.issuerIsAdmin &&
      issuer.issuedByUid !== issuer.inviterUid) {
    throw new Error("cannot issue code for another user");
  }
  if (!Number.isSafeInteger(issuer.issuedAtMs) || issuer.issuedAtMs <= 0) {
    throw new Error("invalid server timestamp");
  }
  return {
    update: {
      name: `${root}/referral_codes/${code}`,
      fields: {
        code: { stringValue: code },
        inviterUid: { stringValue: issuer.inviterUid },
        channel: { stringValue: issuer.channel },
        active: { booleanValue: true },
        issuedByUid: { stringValue: issuer.issuedByUid },
        issuedAtMs: { integerValue: String(issuer.issuedAtMs) },
      },
    },
    currentDocument: { exists: false },
  };
}
