import { awardVerifiedReferral } from "./referral_award";
import { verifyFirstOrderReferral } from "./referral_first_order";
import { referralGrantId } from "./referrals";
import type { FirestoreTransport } from "./referral_commit";

/**
 * Internal-only entry point for customer/marketer rewards.
 * Call ONLY from an authenticated server-side completion workflow, after the
 * immutable first-order index has been atomically written with completion.
 * No public route or client-controlled eligibility flag is exposed.
 */
export async function settleFirstOrderReferral(
  projectId: string,
  oauthToken: string,
  invitedUid: string,
  firstOrderId: string,
  channel: "customer" | "marketer" | "store_customer",
  transport: FirestoreTransport,
): Promise<"granted" | "already_granted" | "ineligible"> {
  const grantId = referralGrantId(channel, invitedUid);
  return awardVerifiedReferral(
    projectId, oauthToken, grantId,
    (read) => verifyFirstOrderReferral(read, { invitedUid, firstOrderId }),
    transport,
  );
}
