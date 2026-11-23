import { isReferralCode, normalizeReferralCode, type ReferralChannel } from "./referrals";

/**
 * Server-side first-registration attribution write plan.
 * The caller must authenticate the new account, resolve the code to a
 * server-owned active referral_codes document, and verify the inviter role.
 * Never use a client-supplied inviter UID.
 */
export interface VerifiedReferralClaim {
  invitedUid: string;
  inviterUid: string;
  code: string;
  channel: ReferralChannel;
  /** Milliseconds from server clock, not a client timestamp. */
  claimedAtMs: number;
}

const validId = (value: string) => /^[A-Za-z0-9_-]{1,128}$/.test(value);

export function buildReferralAttributionWrite(
  root: string,
  claim: VerifiedReferralClaim,
) {
  if (!/^projects\/[A-Za-z0-9_-]+\/databases\/\(default\)\/documents$/.test(root)) {
    throw new Error("invalid database root");
  }
  if (!validId(claim.invitedUid) || !validId(claim.inviterUid) ||
      claim.invitedUid === claim.inviterUid) {
    throw new Error("invalid referral actors");
  }
  if (!["customer", "marketer", "store_owner"].includes(claim.channel)) {
    throw new Error("invalid referral channel");
  }
  const code = normalizeReferralCode(claim.code);
  if (!isReferralCode(code)) throw new Error("invalid referral code");
  if (!Number.isSafeInteger(claim.claimedAtMs) || claim.claimedAtMs <= 0) {
    throw new Error("invalid server claim time");
  }
  return {
    update: {
      name: `${root}/referral_attributions/${claim.invitedUid}`,
      fields: {
        invitedUid: { stringValue: claim.invitedUid },
        inviterUid: { stringValue: claim.inviterUid },
        code: { stringValue: code },
        channel: { stringValue: claim.channel },
        claimedAtMs: { integerValue: String(claim.claimedAtMs) },
      },
    },
    currentDocument: { exists: false },
  };
}

/**
 * A separate immutable attribution per invited store. The same store cannot
 * generate multiple store-invitation claims from different owner accounts.
 */
export function buildStoreAttributionWrite(
  root: string,
  invitedStoreId: string,
  claim: VerifiedReferralClaim,
) {
  if (!validId(invitedStoreId) || claim.channel !== "store_owner") {
    throw new Error("invalid invited store");
  }
  const write = buildReferralAttributionWrite(root, claim);
  return {
    ...write,
    update: {
      ...write.update,
      name: `${root}/referral_store_attributions/${invitedStoreId}`,
      fields: {
        ...write.update.fields,
        invitedStoreId: { stringValue: invitedStoreId },
      },
    },
  };
}
