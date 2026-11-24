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

/** Android's SSAID is not a secret, and MUST be HMACed server-side only.
 * Android 8+ scopes it per signing key / Android user / physical device.
 * It is not tamper-proof; App Check is also required on protected routes.
 */
export function isValidAndroidSsaid(input: unknown): input is string {
  return typeof input === "string" && /^[a-fA-F0-9]{16}$/.test(input) &&
    input.toLowerCase() !== "9774d56d682e549c" &&
    input !== "0000000000000000";
}

export async function referralDeviceDocumentId(
  secret: string, androidSsaid: string,
): Promise<string> {
  if (!hasValidIdentitySecret(secret)) throw new Error("missing identity HMAC secret");
  if (!isValidAndroidSsaid(androidSsaid)) throw new Error("invalid Android device identifier");
  return hmacHex(secret, "wasally:referral:device:v1:" + androidSsaid.toLowerCase());
}

/** Does not reveal the raw Google subject or the deleted Firebase UID. */
export async function referralDeviceOwnerDigest(
  secret: string, googleSubject: string,
): Promise<string> {
  if (!hasValidIdentitySecret(secret)) throw new Error("missing identity HMAC secret");
  if (!/^[a-zA-Z0-9_-]{4,256}$/.test(googleSubject)) {
    throw new Error("invalid verified Google subject");
  }
  return hmacHex(secret, "wasally:referral:device-owner:v1:" + googleSubject);
}

async function hmacHex(secret: string, data: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const bytes = await crypto.subtle.sign("HMAC", key, encoder.encode(data));
  return Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, "0")).join("");
}

/** Returned for UI diagnostics only; never exposes a device or Google identifier. */
export function referralDeviceEligibility(
  existing: { googleOwnerDigest?: unknown; expiresAt?: unknown } | null,
  googleOwnerDigest: string,
  now: Date,
): "create" | "same" | "block" | "replace-expired" {
  if (!existing) return "create";
  const expiry = existing.expiresAt;
  const expiryDate = expiry instanceof Date ? expiry
    : typeof expiry === "string" ? new Date(expiry) : null;
  // Corrupt or missing expiry is treated as active: can't bypass by altering metadata.
  if (expiryDate && !Number.isNaN(expiryDate.getTime()) &&
      expiryDate.getTime() <= now.getTime()) return "replace-expired";
  return existing.googleOwnerDigest === googleOwnerDigest ? "same" : "block";
}
