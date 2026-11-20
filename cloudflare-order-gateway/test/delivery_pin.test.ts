import { describe, expect, it } from "vitest";
import { equalHexDigest, generateDeliveryPin, hashDeliveryPin, isDeliveryPin } from "../src/delivery_pin";

describe("secure delivery PIN primitives", () => {
  it("generates exactly four digits, including possible leading zeros", () => {
    for (let i = 0; i < 100; i++) expect(generateDeliveryPin()).toMatch(/^[0-9]{4}$/);
  });
  it("rejects non-four-digit input", () => {
    for (const bad of ["123", "12345", "abcd", " 1234", 1234, null]) {
      expect(isDeliveryPin(bad)).toBe(false);
    }
    expect(isDeliveryPin("0007")).toBe(true);
  });
  it("binds digest to order, salt and server pepper", async () => {
    const digest = await hashDeliveryPin("0007", "order-a", "salt-a", "secret-pepper");
    expect(digest).toMatch(/^[0-9a-f]{64}$/);
    expect(equalHexDigest(digest, await hashDeliveryPin("0007", "order-a", "salt-a", "secret-pepper"))).toBe(true);
    expect(equalHexDigest(digest, await hashDeliveryPin("0008", "order-a", "salt-a", "secret-pepper"))).toBe(false);
    expect(equalHexDigest(digest, await hashDeliveryPin("0007", "order-b", "salt-a", "secret-pepper"))).toBe(false);
    expect(equalHexDigest(digest, await hashDeliveryPin("0007", "order-a", "salt-b", "secret-pepper"))).toBe(false);
    expect(equalHexDigest(digest, await hashDeliveryPin("0007", "order-a", "salt-a", "another-pepper"))).toBe(false);
    expect(equalHexDigest("invalid", digest)).toBe(false);
  });
});
