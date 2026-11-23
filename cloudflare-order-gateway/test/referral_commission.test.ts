import { describe, expect, it } from "vitest";
import { commissionAmounts } from "../src/referral_commission";

describe("commission referral credit", () => {
  it("caps the credit at the recorded commission", () => {
    expect(commissionAmounts(4000, 5000)).toEqual({
      dueMinor: 4000, discountMinor: 4000, payableMinor: 0,
    });
  });

  it("leaves the uncovered amount payable", () => {
    expect(commissionAmounts(4000, 1000)).toEqual({
      dueMinor: 4000, discountMinor: 1000, payableMinor: 3000,
    });
  });

  it("supports balances created before commission rewards", () => {
    expect(commissionAmounts(4000, undefined).payableMinor).toBe(4000);
  });

  it("rejects invalid ledger amounts", () => {
    expect(() => commissionAmounts(0, 100)).toThrow();
    expect(() => commissionAmounts(100, -1)).toThrow();
    expect(() => commissionAmounts(100, 1.5)).toThrow();
  });
});
