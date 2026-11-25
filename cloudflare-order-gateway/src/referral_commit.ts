import { buildReferralGrantWrites, type VerifiedReferralGrant } from "./referral_grants";

/**
 * A Firestore transaction adapter for referral awards.
 * The caller MUST read authoritative eligibility evidence using the same
 * transaction ID before invoking commitVerifiedReferralGrant.
 * This function never accepts a client-side status or an unverified grant.
 */
export interface ReferralCommitRequest {
  projectId: string;
  transaction: string;
  grant: VerifiedReferralGrant;
}

export interface ReferralCommitResult {
  committed: true;
}

export type FirestoreTransport = (
  url: string,
  init: { method: "POST"; headers: Record<string, string>; body: string },
) => Promise<{ ok: boolean; status: number; text(): Promise<string> }>;

export class ReferralCommitError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "ReferralCommitError";
  }
}

export async function commitVerifiedReferralGrant(
  request: ReferralCommitRequest,
  oauthAccessToken: string,
  transport: FirestoreTransport,
): Promise<ReferralCommitResult> {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(request.projectId)) {
    throw new Error("invalid project");
  }
  if (!request.transaction || !/^[A-Za-z0-9+/_=-]+$/.test(request.transaction)) {
    throw new Error("missing or invalid Firestore transaction");
  }
  if (!oauthAccessToken.trim()) throw new Error("missing OAuth token");
  const root = `projects/${request.projectId}/databases/(default)/documents`;
  const writes = buildReferralGrantWrites(root, request.grant);
  const response = await transport(
    `https://firestore.googleapis.com/v1/${root}:commit`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${oauthAccessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ transaction: request.transaction, writes }),
    },
  );
  if (!response.ok) {
    // Do not auto-retry: the caller must re-read the grant and eligibility
    // in a NEW transaction, especially after an ambiguous network failure.
    throw new ReferralCommitError(response.status, "referral commit rejected");
  }
  return { committed: true };
}
