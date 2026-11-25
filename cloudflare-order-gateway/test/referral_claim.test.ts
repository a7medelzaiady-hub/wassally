import { describe, expect, it } from "vitest";
import { decideReferralClaim } from "../src/referral_claim";

const record = {
  code: "ABC12345", inviterUid: "owner-1", channel: "customer" as const, active: true,
};
const evidence = {
  invitedUid: "new-user", accountCreatedAtMs: 1000000,
  claimAtMs: 1000500, alreadyAttributed: false,
};

describe("trusted first-registration referral attribution", () => {
  it("accepts matching active code for eligible original signup", () => {
    expect(decideReferralClaim(" abc12345 ", record, evidence)).toEqual({
      allowed: true, code: "ABC12345", inviterUid: "owner-1", channel: "customer",
    });
  });

  it("does not apply an arbitrary minute-based expiry within the original session", () => {
    expect(decideReferralClaim("ABC12345", record, {
      ...evidence, claimAtMs: evidence.accountCreatedAtMs + 60 * 60 * 1000,
    }).allowed).toBe(true);
  });

  it.each([
    ["invalid code", "ABC-123", record, evidence, "invalid_code"],
    ["missing code", "ABC12345", null, evidence, "inactive_or_missing_code"],
    ["inactive code", "ABC12345", { ...record, active: false }, evidence, "inactive_or_missing_code"],
    ["missing active flag", "ABC12345", { ...record, active: undefined as unknown as boolean }, evidence, "inactive_or_missing_code"],
    ["wrong code", "ABC12345", { ...record, code: "ZZZ12345" }, evidence, "inactive_or_missing_code"],
    ["self referral", "ABC12345", record, { ...evidence, invitedUid: "owner-1" }, "invalid_actors"],
    ["existing attribution", "ABC12345", record, { ...evidence, alreadyAttributed: true }, "already_attributed"],
    ["future creation", "ABC12345", record, { ...evidence, claimAtMs: 999999 }, "not_first_registration"],
    ["zero creation timestamp", "ABC12345", record, { ...evidence, accountCreatedAtMs: 0 }, "not_first_registration"],
    ["fractional claim timestamp", "ABC12345", record, { ...evidence, claimAtMs: 1000000.5 }, "not_first_registration"],
  ] as const)("%s is rejected", (_name, code, owner, registration, reason) => {
    expect(decideReferralClaim(code, owner, registration))
      .toEqual({ allowed: false, reason });
  });
});
