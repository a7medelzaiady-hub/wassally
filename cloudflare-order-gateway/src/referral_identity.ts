/** Private, server-only identity used to deny repeat first-time referral awards.
 *
 * This is pseudonymous personal data: it can link two Wasally registrations.
 * Never log, expose to a client, or persist the Google subject, UID or email
 * in these records. Keep the HMAC key solely in Cloudflare Worker Secrets.
 */
export const REFERRAL_IDENTITY_RETENTION_DAYS = 365;
export const REFERRAL_IDENTITY_COLLECTION = "referral_deleted_identities";

export type GoogleProviderAccount = {
  providerId?: string;
  rawId?: string;
};

export function googleSubjectFromFirebaseLookup(
  providers: GoogleProviderAccount[] | undefined,
): string | null {
  const google = providers?.filter(p => p.providerId === "google.com") ?? [];
  if (google.length !== 1) return null;
  const subject = google[0].rawId;
  return typeof subject === "string" && /^[a-zA-Z0-9_-]{4,256}$/.test(subject)
    ? subject : null;
}

export function hasValidIdentitySecret(secret: string | undefined): boolean {
  return typeof secret === "string" && new TextEncoder().encode(secret).length >= 32;
}

export async function referralIdentityDocumentId(
  secret: string,
  googleSubject: string,
): Promise<string> {
  if (!hasValidIdentitySecret(secret)) throw new Error("missing identity HMAC secret");
  if (!/^[a-zA-Z0-9_-]{4,256}$/.test(googleSubject)) {
    throw new Error("invalid verified Google subject");
  }
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC", key, encoder.encode("wasally:referral:deleted:v1:" + googleSubject),
  );
  return Array.from(new Uint8Array(signature), b => b.toString(16).padStart(2, "0")).join("");
}

export function identityMarkerExpiresAt(now: Date): Date {
  return new Date(now.getTime() + REFERRAL_IDENTITY_RETENTION_DAYS * 86400000);
}

export function isActiveDeletedIdentity(
  record: { expiresAt?: unknown } | null,
  now: Date,
): boolean {
  // Invalid/absent expiry fails closed: corruption must never enable a reward.
  if (!record) return false;
  const expiry = record.expiresAt;
  const date = expiry instanceof Date ? expiry
    : typeof expiry === "string" ? new Date(expiry) : null;
  return !date || Number.isNaN(date.getTime()) || date.getTime() > now.getTime();
}
