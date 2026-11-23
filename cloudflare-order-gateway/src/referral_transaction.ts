import type { FirestoreTransport } from "./referral_commit";

/**
 * Opens a Firestore read-write transaction for the referral service.
 * The caller must use this token for canonical document reads and the
 * eventual create-only grant commit; it must never trust client-supplied IDs.
 */
export async function beginReferralTransaction(
  projectId: string,
  oauthAccessToken: string,
  transport: FirestoreTransport,
): Promise<string> {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(projectId)) throw new Error("invalid project");
  if (!oauthAccessToken.trim()) throw new Error("missing OAuth token");
  const root = `projects/${projectId}/databases/(default)/documents`;
  const response = await transport(
    `https://firestore.googleapis.com/v1/${root}:beginTransaction`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${oauthAccessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ options: { readWrite: {} } }),
    },
  );
  if (!response.ok) throw new Error("could not begin referral transaction");
  let result: unknown;
  try {
    result = JSON.parse(await response.text());
  } catch {
    throw new Error("invalid Firestore transaction response");
  }
  const token = (result as { transaction?: unknown } | null)?.transaction;
  if (typeof token !== "string" || !/^[A-Za-z0-9+/_=-]+$/.test(token)) {
    throw new Error("missing or invalid Firestore transaction token");
  }
  return token;
}
