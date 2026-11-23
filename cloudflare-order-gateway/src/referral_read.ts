import type { FirestoreTransport } from "./referral_commit";

/**
 * Reads a canonical Firestore document under the same transaction used for
 * referral eligibility and commit. A missing document is not an empty record.
 */
export async function readReferralDocument(
  projectId: string,
  collection: string,
  documentId: string,
  transaction: string,
  oauthAccessToken: string,
  transport: FirestoreTransport,
): Promise<Record<string, unknown> | null> {
  const validId = (value: string) => /^[A-Za-z0-9_-]{1,128}$/.test(value);
  if (![projectId, collection, documentId].every(validId)) {
    throw new Error("invalid Firestore document path");
  }
  if (!/^[A-Za-z0-9+/_=-]+$/.test(transaction)) throw new Error("invalid transaction");
  if (!oauthAccessToken.trim()) throw new Error("missing OAuth token");
  const root = `projects/${projectId}/databases/(default)/documents`;
  const response = await transport(
    `https://firestore.googleapis.com/v1/${root}:batchGet`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${oauthAccessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        documents: [`${root}/${collection}/${documentId}`],
        transaction,
      }),
    },
  );
  if (!response.ok) throw new Error("Firestore referral read failed");
  const lines = (await response.text()).trim().split("\n").filter(Boolean);
  if (lines.length !== 1) throw new Error("unexpected Firestore batchGet response");
  let value: unknown;
  try { value = JSON.parse(lines[0]!); }
  catch { throw new Error("invalid Firestore batchGet response"); }
  if (!value || typeof value !== "object") throw new Error("invalid Firestore response");
  const result = value as Record<string, unknown>;
  const expected = `${root}/${collection}/${documentId}`;
  if (result.missing === expected && !result.found) return null;
  const found = result.found as Record<string, unknown> | undefined;
  if (!found || found.name !== expected || !found.fields ||
      typeof found.fields !== "object" || Array.isArray(found.fields)) {
    throw new Error("unexpected Firestore document");
  }
  return found.fields as Record<string, unknown>;
}
