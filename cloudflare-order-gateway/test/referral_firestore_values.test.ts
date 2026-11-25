import { describe, expect, it } from "vitest";
import { decodeFirestoreReferralFields } from "../src/referral_firestore_values";
import { parseReferralSettings } from "../src/referral_settings";

const policy = (channel: string, unit: string) => ({
  mapValue: { fields: {
    enabled: { booleanValue: true },
    channel: { stringValue: channel },
    unit: { stringValue: unit },
    amount: { integerValue: "50" },
    maxPerInviter: { integerValue: "20" },
  } },
});

describe("Firestore REST referral settings decoding", () => {
  it("decodes real Firestore value wrappers into validated admin policy", () => {
    const decoded = decodeFirestoreReferralFields({
      version: { integerValue: "3" },
      policies: { mapValue: { fields: {
        customer: policy("customer", "points"),
        marketer: policy("marketer", "cash_minor"),
        store_owner: policy("store_owner", "commission_discount_minor"),
      } } },
    });
    const parsed = parseReferralSettings(decoded);
    expect(parsed.version).toBe(3);
    expect(parsed.policies.store_owner.amount).toBe(50);
  });

  it.each([
    { integerValue: "9007199254740993" },
    { integerValue: "1.5" },
    { doubleValue: 12.5 },
    { stringValue: "x", integerValue: "1" },
    { mapValue: { fields: { "bad/key": { stringValue: "x" } } } },
  ])("fails closed on malformed values", (value) => {
    expect(() => decodeFirestoreReferralFields({ amount: value })).toThrow();
  });
});
