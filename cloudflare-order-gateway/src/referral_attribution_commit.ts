import {
  buildReferralAttributionWrite, buildStoreAttributionWrite,
  type VerifiedReferralClaim,
} from "./referral_attribution";
import type { FirestoreTransport } from "./referral_commit";

/**
 * Writes an already verified first-registration attribution in the SAME
 * Firestore transaction used to read the canonical code and account.
 * Auth verification, code lookup and transaction reads belong to the caller.
 */
export async function commitVerifiedAttribution(
  projectId: string,
  transaction: string,
  claim: VerifiedReferralClaim,
  oauthToken: string,
  transport: FirestoreTransport,
  invitedStoreId?: string,
): Promise<void> {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(projectId)) throw new Error("invalid project");
  if (!/^[A-Za-z0-9+/_=-]+$/.test(transaction)) throw new Error("invalid transaction");
  if (!oauthToken.trim()) throw new Error("missing OAuth token");
  const root = `projects/${projectId}/databases/(default)/documents`;
  const write = invitedStoreId === undefined
    ? buildReferralAttributionWrite(root, claim)
    : buildStoreAttributionWrite(root, invitedStoreId, claim);
  const response = await transport(
    `https://firestore.googleapis.com/v1/${root}:commit`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${oauthToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ transaction, writes: [write] }),
    },
  );
  if (!response.ok) {
    // No automatic retries: caller must begin a fresh transaction and
    // re-check the code and immutable attribution document.
    throw new Error(`attribution commit rejected (${response.status})`);
  }
}
