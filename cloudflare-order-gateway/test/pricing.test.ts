import { describe, expect, it } from "vitest";
import { calculateDiscount, catalogPriceMatches, cloudinarySignature, detectImageContent, effectiveCatalogPrice, firstName, isRecentAuthTime } from "../src/index";

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


describe("customer name normalization", () => {
  it("uses the first whitespace-separated name consistently", () => {
    expect(firstName("  Ahmed   Mohamed  ")).toBe("Ahmed");
    expect(firstName("أحمد محمد")).toBe("أحمد");
    expect(firstName("Single")).toBe("Single");
    expect(firstName("   ")).toBe("");
    expect(firstName(null)).toBe("");
  });
});


describe("server-side image content validation", () => {
  it("accepts JPEG, PNG, and WEBP signatures", () => {
    expect(detectImageContent(new Uint8Array([0xff, 0xd8, 0xff, 0x00]))).toEqual({
      format: "jpg",
      mime: "image/jpeg",
    });
    expect(detectImageContent(new Uint8Array([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ]))).toEqual({
      format: "png",
      mime: "image/png",
    });
    expect(detectImageContent(new Uint8Array([
      0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
      0x57, 0x45, 0x42, 0x50,
    ]))).toEqual({
      format: "webp",
      mime: "image/webp",
    });
  });

  it("rejects extensions or MIME spoofing without a supported file signature", () => {
    expect(detectImageContent(new TextEncoder().encode("<svg></svg>"))).toBeNull();
    expect(detectImageContent(new Uint8Array([0x25, 0x50, 0x44, 0x46]))).toBeNull();
    expect(detectImageContent(new Uint8Array([]))).toBeNull();
  });
});

describe("Cloudinary upload signatures", () => {
  it("signs a canonical sorted parameter set and changes when the folder changes", async () => {
    const params = {
      timestamp: "1794850000",
      folder: "stores/store_1",
      public_id: "unique-image-id",
      allowed_formats: "jpg,jpeg,png,webp",
      overwrite: "false",
      unique_filename: "true",
      use_filename: "false",
    };
    const first = await cloudinarySignature(params, "test-secret");
    const same = await cloudinarySignature({
      use_filename: "false",
      folder: "stores/store_1",
      public_id: "unique-image-id",
      overwrite: "false",
      timestamp: "1794850000",
      unique_filename: "true",
      allowed_formats: "jpg,jpeg,png,webp",
    }, "test-secret");
    const otherFolder = await cloudinarySignature(
      { ...params, folder: "stores/store_2" },
      "test-secret",
    );
    expect(first).toMatch(/^[a-f0-9]{40}$/);
    expect(same).toBe(first);
    expect(otherFolder).not.toBe(first);
  });
});


describe("account deletion authentication freshness", () => {
  it("accepts only authentication performed within the last five minutes", () => {
    const now = 1_800_000_000;
    expect(isRecentAuthTime(now, now)).toBe(true);
    expect(isRecentAuthTime(now - 300, now)).toBe(true);
    expect(isRecentAuthTime(now - 301, now)).toBe(false);
    expect(isRecentAuthTime(now + 61, now)).toBe(false);
    expect(isRecentAuthTime(Number.NaN, now)).toBe(false);
    expect(isRecentAuthTime(0, now)).toBe(false);
  });
});
