import { describe, expect, it } from "vitest";
import { buildReferralCodeReservation } from "../src/referral_codes";

const root = "projects/wasally-test/databases/(default)/documents";
const issuer = {
  code: " abcd1234 ", inviterUid: "inviter", issuedByUid: "admin",
  channel: "marketer" as const, issuedAtMs: 1700000000000,
};

describe("server-owned unique referral code reservation", () => {
  it("creates a globally unique normalized code only if it does not exist", () => {
    const write = buildReferralCodeReservation(root, issuer);
    expect(write.update.name).toBe(`${root}/referral_codes/ABCD1234`);
    expect(write.currentDocument).toEqual({ exists: false });
    expect(write.update.fields.active).toEqual({ booleanValue: true });
    expect(write.update.fields.inviterUid).toEqual({ stringValue: "inviter" });
    expect(write.update.fields.issuedByUid).toEqual({ stringValue: "admin" });
  });

  it("rejects unsafe identifiers, invalid codes and invalid timestamps", () => {
    expect(() => buildReferralCodeReservation(root, { ...issuer, code: "AB-12" })).toThrow();
    expect(() => buildReferralCodeReservation(root, { ...issuer, inviterUid: "a/b" })).toThrow();
    expect(() => buildReferralCodeReservation(root, { ...issuer, issuedByUid: "" })).toThrow();
    expect(() => buildReferralCodeReservation(root, { ...issuer, issuedAtMs: 0 })).toThrow();
    expect(() => buildReferralCodeReservation("bad/root", issuer)).toThrow();
  });
});
