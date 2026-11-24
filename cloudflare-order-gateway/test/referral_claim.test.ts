import { describe, expect, it } from "vitest";
import { decideReferralClaim, REFERRAL_REGISTRATION_WINDOW_MS } from "../src/referral_claim";

const record = {
  code: "ABC12345", inviterUid: "owner-1", channel: "customer" as const, active: true,
};
const evidence = {
  invitedUid: "new-user", accountCreatedAtMs: 1000000,
  claimAtMs: 1000500, alreadyAttributed: false, registrationWindowMs: 60000,
};

describe("server-verified first registration referral claims", () => {
  it("accepts a matching active code for a new user", () => {
    expect(decideReferralClaim(" abc12345 ", record, evidence)).toEqual({
      allowed: true, code: "ABC12345", inviterUid: "owner-1", channel: "customer",
    });
  });

  it("accepts a claim after ten minutes within the 24-hour grace period", () => {
    expect(decideReferralClaim("ABC12345", record, {
      ...evidence,
      registrationWindowMs: REFERRAL_REGISTRATION_WINDOW_MS,
      claimAtMs: evidence.accountCreatedAtMs + 10 * 60 * 1000,
    }).allowed).toBe(true);
  });

  it("accepts a claim exactly at the 24-hour window boundary", () => {
    expect(decideReferralClaim("ABC12345", record, {
      ...evidence,
      registrationWindowMs: REFERRAL_REGISTRATION_WINDOW_MS,
      claimAtMs: evidence.accountCreatedAtMs + REFERRAL_REGISTRATION_WINDOW_MS,
    }).allowed).toBe(true);
  });

  it("rejects a claim after 24 hours", () => {
    expect(decideReferralClaim("ABC12345", record, {
      ...evidence,
      registrationWindowMs: REFERRAL_REGISTRATION_WINDOW_MS,
      claimAtMs: evidence.accountCreatedAtMs + REFERRAL_REGISTRATION_WINDOW_MS + 1,
    })).toEqual({ allowed: false, reason: "not_first_registration" });
  });

  it.each([
    ["invalid code", "ABC-123", record, evidence, "invalid_code"],
    ["missing code", "ABC12345", null, evidence, "inactive_or_missing_code"],
    ["inactive code", "ABC12345", { ...record, active: false }, evidence, "inactive_or_missing_code"],
    ["missing active flag", "ABC12345", { ...record, active: undefined as unknown as boolean }, evidence, "inactive_or_missing_code"],
    ["string active flag", "ABC12345", { ...record, active: "true" as unknown as boolean }, evidence, "inactive_or_missing_code"],
    ["wrong code", "ABC12345", { ...record, code: "ZZZ12345" }, evidence, "inactive_or_missing_code"],
    ["self referral", "ABC12345", record, { ...evidence, invitedUid: "owner-1" }, "invalid_actors"],
    ["existing attribution", "ABC12345", record, { ...evidence, alreadyAttributed: true }, "already_attributed"],
    ["old account", "ABC12345", record, { ...evidence, claimAtMs: 1100000 }, "not_first_registration"],
    ["future creation", "ABC12345", record, { ...evidence, claimAtMs: 999999 }, "not_first_registration"],
    ["excessive window", "ABC12345", record, { ...evidence, registrationWindowMs: REFERRAL_REGISTRATION_WINDOW_MS + 1 }, "not_first_registration"],
    ["zero creation timestamp", "ABC12345", record, { ...evidence, accountCreatedAtMs: 0 }, "not_first_registration"],
    ["fractional claim timestamp", "ABC12345", record, { ...evidence, claimAtMs: 1000000.5 }, "not_first_registration"],
    ["negative registration window", "ABC12345", record, { ...evidence, registrationWindowMs: -1 }, "not_first_registration"],
    ["same inviter", "ABC12345", record, { ...evidence, invitedUid: "owner-1" }, "invalid_actors"],
  ] as const)("%s is rejected", (_name, code, owner, registration, reason) => {
    expect(decideReferralClaim(code, owner, registration))
      .toEqual({ allowed: false, reason });
  });
});
