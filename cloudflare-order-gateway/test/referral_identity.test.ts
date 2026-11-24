import { describe, expect, it } from "vitest";
import {
  REFERRAL_IDENTITY_COLLECTION,
  REFERRAL_IDENTITY_RETENTION_DAYS,
  googleSubjectFromFirebaseLookup,
  hasValidIdentitySecret,
  identityMarkerExpiresAt,
  isActiveDeletedIdentity,
  referralIdentityDocumentId,
  referralDeviceDocumentId,
  referralDeviceOwnerDigest,
  referralDeviceEligibility,
  isValidAndroidSsaid,
} from "../src/referral_identity";
import { pruneExpiredDeletedReferralIdentities } from "../src/referral_identity_prune";

const KEY = "fake-secret-for-automated-tests-only-0123456789";

describe("private anti-repeat-referral marker", () => {
  it("uses a stable Google provider subject, not a Firebase UID or email", async () => {
    const subject = "google-subject-1234";
    const previousUid = "firebase-old-uid";
    const rejoinedUid = "firebase-new-uid";
    expect(previousUid).not.toBe(rejoinedUid);
    const former = await referralIdentityDocumentId(KEY, subject);
    const rejoined = await referralIdentityDocumentId(KEY, subject);
    expect(former).toBe(rejoined);
    expect(former).toMatch(/^[a-f0-9]{64}$/);
    expect(former).not.toContain(subject);
    expect(former).not.toContain(previousUid);
    expect(former).not.toContain("@");
  });

  it("does not link different Google subjects or different secret versions", async () => {
    const original = await referralIdentityDocumentId(KEY, "google-subject-1234");
    expect(await referralIdentityDocumentId(KEY, "google-subject-5678")).not.toBe(original);
    expect(await referralIdentityDocumentId(KEY + "rotated", "google-subject-1234")).not.toBe(original);
    expect(hasValidIdentitySecret("too-short")).toBe(false);
    await expect(referralIdentityDocumentId("too-short", "google-subject-1234")).rejects.toThrow();
  });

  it("fails closed for missing or ambiguous Firebase Google provider credentials", () => {
    expect(googleSubjectFromFirebaseLookup([{ providerId: "google.com", rawId: "google-subject-1234" }]))
      .toBe("google-subject-1234");
    expect(googleSubjectFromFirebaseLookup([{ providerId: "password", rawId: "password-user" }]))
      .toBeNull();
    expect(googleSubjectFromFirebaseLookup(undefined)).toBeNull();
    expect(googleSubjectFromFirebaseLookup([
      { providerId: "google.com", rawId: "google-subject-1234" },
      { providerId: "google.com", rawId: "different-subject" },
    ])).toBeNull();
  });

  it("allows a marker to expire after the explicitly disclosed retention", () => {
    const now = new Date("2026-11-24T12:00:00Z");
    const expiresAt = identityMarkerExpiresAt(now);
    expect((expiresAt.getTime() - now.getTime()) / 86400000)
      .toBe(REFERRAL_IDENTITY_RETENTION_DAYS);
    expect(isActiveDeletedIdentity({ expiresAt }, now)).toBe(true);
    expect(isActiveDeletedIdentity({ expiresAt }, new Date(expiresAt.getTime() + 1)))
      .toBe(false);
    expect(isActiveDeletedIdentity({ expiresAt: "invalid" }, now)).toBe(true);
    expect(isActiveDeletedIdentity(null, now)).toBe(false);
  });
});

describe("one Google account per scoped Android device for referral awards", () => {
  const device = "a1b2c3d4e5f60718";
  const now = new Date("2026-11-24T12:00:00Z");

  it("produces stable device HMACs while never persisting raw Android IDs", async () => {
    const id = await referralDeviceDocumentId(KEY, device);
    expect(id).toMatch(/^[a-f0-9]{64}$/);
    expect(id).not.toContain(device);
    expect(await referralDeviceDocumentId(KEY, device.toUpperCase())).toBe(id);
    expect(await referralDeviceDocumentId(KEY, "ffffffffffffffff")).not.toBe(id);
    expect(await referralDeviceOwnerDigest(KEY, "google-subject-first")).not.toBe(
      await referralDeviceOwnerDigest(KEY, "google-subject-second")
    );
    expect(isValidAndroidSsaid(device)).toBe(true);
    expect(isValidAndroidSsaid("0000000000000000")).toBe(false);
    expect(isValidAndroidSsaid("9774d56d682e549c")).toBe(false);
    expect(isValidAndroidSsaid("invalid")).toBe(false);
  });

  it("permits one Google owner and denies another on the same active device", () => {
    const first = "a".repeat(64), second = "b".repeat(64);
    const record = { googleOwnerDigest: first, expiresAt: identityMarkerExpiresAt(now) };
    expect(referralDeviceEligibility(null, first, now)).toBe("create");
    expect(referralDeviceEligibility(record, first, now)).toBe("same");
    expect(referralDeviceEligibility(record, second, now)).toBe("block");
    expect(referralDeviceEligibility({ googleOwnerDigest: first }, second, now)).toBe("block");
    expect(referralDeviceEligibility(
      { googleOwnerDigest: first, expiresAt: new Date(now.getTime() - 1000) },
      second, now)).toBe("replace-expired");
  });
});

describe("daily Spark-compatible marker retention cleanup", () => {
  const now = new Date("2027-11-24T12:00:00Z");
  const prefix = "projects/wasally-test/databases/(default)/documents/" + REFERRAL_IDENTITY_COLLECTION + "/";
  it("deletes expired digests only, in bounded writes", async () => {
    let commits = 0;
    let queries = 0;
    const valid = prefix + "a".repeat(64);
    const unrelated = "projects/wasally-test/databases/(default)/documents/users/someone";
    const requests: Array<{ url: string; body: unknown }> = [];
    const fake = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
      const url = String(input);
      const body = JSON.parse(String(init?.body));
      requests.push({ url, body });
      if (url.endsWith(":runQuery")) {
        queries++;
        return Response.json([{ document: { name: valid } }, { document: { name: unrelated } }]);
      }
      if (url.endsWith(":commit")) {
        commits++;
        expect(body.writes).toEqual([{ delete: valid }]);
        return Response.json({});
      }
      throw new Error("unexpected request");
    };
    await expect(pruneExpiredDeletedReferralIdentities(
      "wasally-test", "dummy-service-token", fake, now,
    )).resolves.toBe(1);
    expect(queries).toBe(1);
    expect(commits).toBe(1);
    const queryBody = requests[0].body as { structuredQuery: { where: {
      fieldFilter: { field: { fieldPath: string }; op: string; value: { timestampValue: string } };
    } } };
    expect(queryBody.structuredQuery.where.fieldFilter.field.fieldPath).toBe("expiresAt");
    expect(queryBody.structuredQuery.where.fieldFilter.op).toBe("LESS_THAN_OR_EQUAL");
    expect(queryBody.structuredQuery.where.fieldFilter.value.timestampValue).toBe(now.toISOString());
  });

  it("keeps markers when the delete commit fails, enabling retry", async () => {
    const valid = prefix + "b".repeat(64);
    const fake = async (input: RequestInfo | URL): Promise<Response> =>
      String(input).endsWith(":runQuery")
        ? Response.json([{ document: { name: valid } }])
        : new Response("", { status: 503 });
    await expect(pruneExpiredDeletedReferralIdentities(
      "wasally-test", "dummy-service-token", fake, now,
    )).rejects.toThrow("deletion failed");
  });

  it("does not commit anything if no markers have expired", async () => {
    let calls = 0;
    const fake = async (): Promise<Response> => {
      calls++;
      return Response.json([]);
    };
    expect(await pruneExpiredDeletedReferralIdentities(
      "wasally-test", "dummy-service-token", fake, now,
    )).toBe(0);
    expect(calls).toBe(1);
  });
});
