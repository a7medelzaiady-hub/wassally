import { REFERRAL_IDENTITY_COLLECTION } from "./referral_identity";

type HttpTransport = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

const DIGEST = /^[a-f0-9]{64}$/;

/**
 * Bounded daily pruning on Cloudflare Cron, not Firebase paid TTL/Functions.
 * Firestore native single-field 'expiresAt' index is sufficient.
 */
export async function pruneExpiredDeletedReferralIdentities(
  projectId: string,
  bearerToken: string,
  transport: HttpTransport,
  now = new Date(),
  maxBatches = 10,
): Promise<number> {
  if (!/^[a-zA-Z0-9_-]+$/.test(projectId)) throw new Error("invalid Firebase project");
  const root = `projects/${projectId}/databases/(default)/documents`;
  const base = `https://firestore.googleapis.com/v1/${root}`;
  let total = 0;
  for (let batch = 0; batch < maxBatches; batch++) {
    const query = await transport(base + ":runQuery", {
      method: "POST",
      headers: { Authorization: `Bearer ${bearerToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: REFERRAL_IDENTITY_COLLECTION }],
          where: { fieldFilter: {
            field: { fieldPath: "expiresAt" },
            op: "LESS_THAN_OR_EQUAL",
            value: { timestampValue: now.toISOString() },
          } },
          limit: 100,
        },
      }),
    });
    if (!query.ok) throw new Error("referral marker retention query failed");
    const rows = await query.json() as Array<{ document?: { name?: string } }>;
    if (!Array.isArray(rows)) throw new Error("bad referral marker query response");
    const prefix = `${root}/${REFERRAL_IDENTITY_COLLECTION}/`;
    const paths = rows.flatMap(row => {
      const name = row.document?.name;
      return typeof name === "string" && name.startsWith(prefix) &&
        DIGEST.test(name.slice(prefix.length)) ? [name] : [];
    });
    if (!paths.length) return total;
    const deleted = await transport(base + ":commit", {
      method: "POST",
      headers: { Authorization: `Bearer ${bearerToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ writes: paths.map(name => ({ delete: name })) }),
    });
    if (!deleted.ok) throw new Error("referral marker retention deletion failed");
    total += paths.length;
    if (paths.length < 100) return total;
  }
  return total;
}
