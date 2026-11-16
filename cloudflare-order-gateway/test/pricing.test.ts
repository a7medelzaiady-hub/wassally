import { describe, expect, it } from "vitest";
import { calculateDiscount, catalogPriceMatches, effectiveCatalogPrice } from "../src/index";

describe("trusted catalog pricing", () => {
  it("calculates percentage discounts using the same floor-to-piastre rule as the app", () => {
    expect(calculateDiscount(123.45, 10)).toBe(12.34);
    expect(calculateDiscount(50, 50)).toBe(25);
    expect(calculateDiscount(20, 0)).toBe(0);
  });

  it("uses client prices only to detect a stale cart, never as the saved price", () => {
    expect(catalogPriceMatches(17.5, 17.5)).toBe(true);
    expect(catalogPriceMatches(17, 17.5)).toBe(false);
    expect(catalogPriceMatches(Number.NaN, 17.5)).toBe(false);
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

  it("ignores malformed string oldPrice values", () => {
    const now = Date.UTC(2026, 10, 16);
    expect(effectiveCatalogPrice({
      price: 12,
      oldPrice: "15",
      offerEndsAt: new Date(now - 1),
    }, now)).toBe(12);
  });

  it("rejects invalid catalog prices", () => {
    expect(() => effectiveCatalogPrice({ price: 0 })).toThrow();
    expect(() => effectiveCatalogPrice({ price: 20001 })).toThrow();
  });
});


describe("courier notification payload", () => {
  it("sends only a minimal new-order notice to the server-controlled couriers topic", async () => {
    const { courierTopicMessage } = await import("../src/index");
    const payload = courierTopicMessage("abcde_1234567890123456", "متجر تجريبي");
    expect(payload.message.topic).toBe("couriers");
    expect(payload.message.data).toEqual({
      type: "available_order",
      orderId: "abcde_1234567890123456",
    });
    expect(payload.message.notification.title).toContain("#ABCDE");
    expect(payload.message.notification.body).toContain("متجر تجريبي");
    expect(JSON.stringify(payload)).not.toContain("phone");
    expect(JSON.stringify(payload)).not.toContain("address");
  });
});
