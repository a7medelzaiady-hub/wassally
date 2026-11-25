import { describe, expect, it } from "vitest";
import { quoteReferralPoints } from "../src/referral_points";

const policy = { pointValueMinor: 25, maxDiscountMinor: 500 };

describe("referral points quote", () => {
  it("caps whole-point spending at the configured limit and available balance", () => {
    expect(quoteReferralPoints(policy, 100, 1900)).toEqual({ points: 20, discountMinor: 500 });
    expect(quoteReferralPoints(policy, 3, 1900)).toEqual({ points: 3, discountMinor: 75 });
  });

  it("caps eligible spend at merchandise value and leaves fees outside the quote", () => {
    expect(quoteReferralPoints(policy, 100, 49)).toEqual({ points: 1, discountMinor: 25 });
    expect(quoteReferralPoints(policy, 100, 0)).toEqual({ points: 0, discountMinor: 0 });
  });

  it("requires a configured redemption policy and rejects corrupt balances", () => {
    expect(quoteReferralPoints(undefined, 100, 1900)).toEqual({ points: 0, discountMinor: 0 });
    expect(() => quoteReferralPoints(policy, -1, 1900)).toThrow();
    expect(() => quoteReferralPoints(policy, 10, 1.5)).toThrow();
  });
});
