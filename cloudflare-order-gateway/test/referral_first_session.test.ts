import { describe, expect, it } from "vitest";
import { isOriginalRegistrationSession } from "../src/referral_first_session";

describe("Firebase-authenticated first registration session", () => {
  const created = 1_800_000_000_000;
  it("accepts initial registration even if the dialog stays open", () => {
    expect(isOriginalRegistrationSession(created, created, created)).toBe(true);
    // No time limit is imposed on the code submission itself.
    expect(isOriginalRegistrationSession(created, created + 750, created + 800)).toBe(true);
  });
  it("rejects another Google login from an existing account", () => {
    expect(isOriginalRegistrationSession(created, created + 60_000, created + 60_000)).toBe(false);
  });
  it("rejects re-authentication even if the initial ID token is reused", () => {
    expect(isOriginalRegistrationSession(created, created + 60_000, created)).toBe(false);
  });
  it("fails closed on missing or malformed Firebase timestamps", () => {
    expect(isOriginalRegistrationSession(created, undefined, created)).toBe(false);
    expect(isOriginalRegistrationSession(0, 0, 0)).toBe(false);
    expect(isOriginalRegistrationSession(created, created, Number.NaN)).toBe(false);
  });
});
