import { awardVerifiedReferral } from "./referral_award";
import { verifyStoreReferral } from "./referral_store_verifier";
import type { FirestoreTransport } from "./referral_commit";
import { referralGrantId } from "./referrals";

/**
 * Trusted internal store-referral settlement entry point.
 * Caller must authorize the server-side delivery transition and maintain a
 * canonical first successful store order index. No public endpoint is added.
 */
export async function settleStoreReferral(
  projectId: string,
  oauthToken: string,
  evidence: { invitedStoreId: string; firstOrderId: string },
  transport: FirestoreTransport,
): Promise<"granted" | "already_granted" | "ineligible"> {
  const grantId = referralGrantId("store_owner", evidence.invitedStoreId);
  return awardVerifiedReferral(
    projectId, oauthToken, grantId,
    (read) => verifyStoreReferral(read, evidence),
    transport,
  );
}
