import { describe, expect, it } from "vitest";
import { parseReferralSettings } from "../src/referral_settings";

const settings = () => ({
  version: 1,
  policies: {
    customer: { enabled: true, channel: "customer", unit: "points", amount: 100, maxPerInviter: 10 },
    marketer: { enabled: true, channel: "marketer", unit: "cash_minor", amount: 2500 },
    store_owner: { enabled: false, channel: "store_owner", unit: "commission_discount_minor", amount: 0 },
  },
});

describe("referral admin policy decoder", () => {
  it("parses the three permitted channels and their units", () => {
    const parsed = parseReferralSettings(settings());
    expect(parsed.version).toBe(1);
    expect(parsed.policies.customer.amount).toBe(100);
    expect(parsed.policies.store_owner.enabled).toBe(false);
  });

  it("keeps points redemption off for existing settings", () => {
    expect(parseReferralSettings(settings()).redemption).toBeUndefined();
  });

  it("validates the admin-managed point value and per-order cap", () => {
    const redemption = { pointValueMinor: 25, maxDiscountMinor: 500 };
    expect(parseReferralSettings({ ...settings(), redemption }).redemption)
      .toEqual(redemption);
    expect(() => parseReferralSettings({
      ...settings(), redemption: { ...redemption, maxDiscountMinor: 24 },
    })).toThrow();
    expect(() => parseReferralSettings({
      ...settings(), redemption: { ...redemption, pointValueMinor: 0 },
    })).toThrow();
  });

  it("rejects malformed or unsafe settings without fallback rewards", () => {
    expect(() => parseReferralSettings(null)).toThrow();
    expect(() => parseReferralSettings({ ...settings(), version: 0 })).toThrow();
    const missing = settings();
    delete (missing.policies as Record<string, unknown>).marketer;
    expect(() => parseReferralSettings(missing)).toThrow();
    const wrongUnit = settings();
    wrongUnit.policies.customer.unit = "cash_minor";
    expect(() => parseReferralSettings(wrongUnit)).toThrow();
    const zero = settings();
    zero.policies.marketer.amount = 0;
    expect(() => parseReferralSettings(zero)).toThrow();
    const negative = settings();
    negative.policies.customer.maxPerInviter = -1;
    expect(() => parseReferralSettings(negative)).toThrow();
  });
});
