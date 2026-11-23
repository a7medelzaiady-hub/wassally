import { describe, expect, it } from "vitest";
import { decideDeliveryPinVerification, canAttemptDeliveryPin, equalHexDigest, generateDeliveryPin, hashDeliveryPin, isDeliveryPin, nextDeliveryPinFailure } from "../src/delivery_pin";

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
  it("locks after five failures and never permits invalid attempt counts", () => {
    expect(canAttemptDeliveryPin(0, false)).toBe(true);
    expect(canAttemptDeliveryPin(4, false)).toBe(true);
    expect(canAttemptDeliveryPin(5, false)).toBe(false);
    expect(canAttemptDeliveryPin(0, true)).toBe(false);
    expect(canAttemptDeliveryPin(-1, false)).toBe(false);
    expect(canAttemptDeliveryPin(NaN, false)).toBe(false);
    expect(nextDeliveryPinFailure(3)).toEqual({ attempts: 4, locked: false });
    expect(nextDeliveryPinFailure(4)).toEqual({ attempts: 5, locked: true });
    expect(nextDeliveryPinFailure(5)).toEqual({ attempts: 5, locked: true });
  });
  it("accepts only a correct unconsumed digest and marks it consumed", async () => {
    const good = await hashDeliveryPin("1234", "order-1", "salt", "pepper");
    const wrong = await hashDeliveryPin("9999", "order-1", "salt", "pepper");
    expect(decideDeliveryPinVerification(good, good, 0, false, false)).toEqual({
      outcome: "accepted", attempts: 0, consumed: true, locked: false,
    });
    expect(decideDeliveryPinVerification(good, good, 0, false, true).outcome).toBe("unavailable");
    expect(decideDeliveryPinVerification(wrong, good, 4, false, false)).toEqual({
      outcome: "rejected", attempts: 5, consumed: false, locked: true,
    });
    expect(decideDeliveryPinVerification(good, good, 5, true, false).outcome).toBe("unavailable");
  });
  it("fails closed on corrupt counters and malformed digests", async () => {
    const good = await hashDeliveryPin("1234", "order-1", "salt", "pepper");
    for (const attempts of [-1, NaN, 1.5, Infinity]) {
      expect(decideDeliveryPinVerification(good, good, attempts, false, false).outcome).toBe("unavailable");
    }
    expect(decideDeliveryPinVerification("bad", good, 0, false, false).outcome).toBe("rejected");
    expect(decideDeliveryPinVerification(good, "bad", 0, false, false).outcome).toBe("rejected");
  });

});
