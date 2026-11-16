import { describe, expect, it } from "vitest";
import { calculateDiscount, effectiveCatalogPrice } from "../src/index";

describe("trusted catalog pricing", () => {
  it("calculates percentage discounts using the same floor-to-piastre rule as the app", () => {
    expect(calculateDiscount(123.45, 10)).toBe(12.34);
    expect(calculateDiscount(50, 50)).toBe(25);
    expect(calculateDiscount(20, 0)).toBe(0);
  });

  it("uses the catalog price, not a client-supplied amount", () => {
    expect(effectiveCatalogPrice({ price: 17.5 })).toBe(17.5);
  });

  it("keeps an active offer and restores oldPrice after expiry", () => {
    const now = Date.UTC(2026, 10, 16);
    const active = { price: 12, oldPrice: 15, offerEndsAt: new Date(now + 60_000) };
    const expired = { price: 12, oldPrice: 15, offerEndsAt: new Date(now - 1) };
    expect(effectiveCatalogPrice(active, now)).toBe(12);
    expect(effectiveCatalogPrice(expired, now)).toBe(15);
  });

  it("rejects invalid catalog prices", () => {
    expect(() => effectiveCatalogPrice({ price: 0 })).toThrow();
    expect(() => effectiveCatalogPrice({ price: 20001 })).toThrow();
  });
});
