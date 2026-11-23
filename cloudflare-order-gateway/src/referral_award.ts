import { beginReferralTransaction } from "./referral_transaction";
import { readReferralDocument } from "./referral_read";
import { commitVerifiedReferralGrant, type FirestoreTransport } from "./referral_commit";
import type { VerifiedReferralGrant } from "./referral_grants";

/**
 * Transactional referral award coordinator. Only a trusted Worker handler may
 * call this after authenticating the actor. Eligibility must be recomputed
 * from canonical records read within THIS transaction by verifyEligibility.
 *
 * No client-provided reward amount, order state or referral facts are trusted.
 * This module deliberately exposes no public HTTP endpoint.
 */
export async function awardVerifiedReferral(
  projectId: string,
  oauthToken: string,
  grantId: string,
  verifyEligibility: (
    read: (collection: string, id: string) => Promise<Record<string, unknown> | null>,
  ) => Promise<VerifiedReferralGrant | null>,
  transport: FirestoreTransport,
): Promise<"granted" | "already_granted" | "ineligible"> {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(grantId)) throw new Error("invalid grant ID");
  const transaction = await beginReferralTransaction(projectId, oauthToken, transport);
  const read = (collection: string, id: string) =>
    readReferralDocument(projectId, collection, id, transaction, oauthToken, transport);
  let committed = false;
  try {
    const existing = await read("referral_grants", grantId);
    if (existing !== null) return "already_granted";
    let canonicalReads = 0;
    const verifiedRead = async (collection: string, id: string) => {
      const document = await read(collection, id);
      canonicalReads++;
      return document;
    };
    const grant = await verifyEligibility(verifiedRead);
    if (!grant) return "ineligible";
    if (canonicalReads === 0) throw new Error("referral eligibility requires canonical Firestore reads");
    if (grant.grantId !== grantId) throw new Error("verified grant ID mismatch");
    await commitVerifiedReferralGrant({ projectId, transaction, grant }, oauthToken, transport);
    committed = true;
    return "granted";
  } finally {
    if (!committed) {
      const root = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
      await transport(`${root}:rollback`, {
        method: "POST",
        headers: { Authorization: `Bearer ${oauthToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({ transaction }),
      }).catch(() => undefined);
    }
  }
}
